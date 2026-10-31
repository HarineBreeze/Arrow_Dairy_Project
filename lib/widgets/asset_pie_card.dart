import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../utils/haptics.dart';

/// 资产全景页顶部的「数据看板」卡片堆叠。
///
/// ## 交互
/// - **堆叠**：顶层卡片完整显示，第二张整体向下平移 [kStackOffset] 并等比缩小
///   [kStackScale]，只从下面露出一条边（第三层再往下缩，形成层次）；
/// - **左右滑动**：在卡片上左右滑动切换。左滑 = 翻到下一张（[card2] 升到顶层，
///   原 [card1] 滑到最底部），右滑 = 回到上一张；
/// - **吸附 / 回弹**：松手后按拖动距离与速度决定「翻页」还是「弹回」。
///
/// ## 性能设计（这是「切换卡顿」的修复点）
/// 滑动与翻页涉及的**所有**变化（位移、缩放、层级、哪张卡在上层）都只存在于
/// 几个 [ValueNotifier] / [AnimationController] 里，逐帧重建的只有
/// [ValueListenableBuilder] 内层的 [Transform] 与 [Offstage]：
///
/// - 本组件与父级（列表）**全程不 setState**，卡片子树一次也不重建；
/// - 「换层」不是换 Stack 的 children 顺序，而是把两张卡按**固定顺序**
///   挂载，用 `_level` 决定谁在上、谁归位 —— 挂载点稳定，子树不会丢；
/// - 层级是两态量，靠 [Offstage] 切可见性，离屏那张不布局也不绘制；
/// - 背面的「露边」用固定底色的装饰盒，不再把整张饼图卡挂在底下。
class OverviewStack extends StatefulWidget {
  /// 第一张：净资产看板
  final Widget card1;

  /// 第二张：金额为正的资产细分饼图
  final Widget card2;

  /// 是否允许切到第二张（资产为空等场景下不显示堆叠）
  final bool hasSecond;

  /// 当前第几层（供外部同步其他入口，可选）
  final ValueChanged<int>? onPageChanged;

  const OverviewStack({
    Key? key,
    required this.card1,
    required this.card2,
    this.hasSecond = true,
    this.onPageChanged,
  }) : super(key: key);

  /// 下移距离（露出下沿的厚度）
  static const double kStackOffset = 16;

  /// 缩小比例
  static const double kStackScale = 0.955;

  /// 切换卡片的拖动位移门槛（超过即翻页）
  static const double kDragThreshold = 80;

  /// 翻页动画时长
  static const Duration kSettle = Duration(milliseconds: 380);

  /// 未达门槛时回弹的时长（比翻页短，避免「慢吞吞弹回去」）
  static const Duration kSnapBack = Duration(milliseconds: 240);

  @override
  State<OverviewStack> createState() => OverviewStackState();
}

class OverviewStackState extends State<OverviewStack>
    with TickerProviderStateMixin {
  /// 顶层是谁：0 = card1，1 = card2
  int _index = 0;

  /// 卡片所在宽度（拖动范围与背面卡尺寸都按它算）
  double _width = 0;

  /// 水平位移（正 = 往右拖）
  final ValueNotifier<double> _dx = ValueNotifier<double>(0);

  /// 两张卡各自的「瞬时层级」：0 = 被压在下面（露边），1 = 完全在顶层。
  /// 拖动/翻页途中连续变化，因此不会出现「瞬移换层」。
  final ValueNotifier<double> _levelA = ValueNotifier<double>(1);
  final ValueNotifier<double> _levelB = ValueNotifier<double>(0);

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: OverviewStack.kSettle,
  );
  double _fromDx = 0;
  double _toDx = 0;
  Curve _curve = Curves.easeOutCubic;
  VoidCallback? _animDone;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final t = _curve.transform(_anim.value);
      _dx.value = _fromDx + (_toDx - _fromDx) * t;
      _syncLevels();
    });
    _anim.addStatusListener((s) {
      if (s != AnimationStatus.completed) return;
      final cb = _animDone;
      _animDone = null;
      cb?.call();
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _dx.dispose();
    _levelA.dispose();
    _levelB.dispose();
    super.dispose();
  }

  bool get _topIsSecond => widget.hasSecond && _index == 1;

  double get _maxDrag => _width <= 0 ? 320 : _width.clamp(200.0, 900.0);

  void _animateTo(double target, Duration duration, Curve curve, [VoidCallback? done]) {
    _fromDx = _dx.value;
    _toDx = target;
    _curve = curve;
    _animDone = done;
    _anim.duration = duration;
    _anim.forward(from: 0);
  }

  // ---------- 拖动 ----------

  void _onDragStart(DragStartDetails d) {
    _anim.stop();
    _dx.value = 0;
    _syncLevels(progress: 0);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final raw = _dx.value + d.delta.dx;
    // 顶层是 card1 时只能左拉（负），顶层是 card2 时只能右拉（正）；
    // 反方向留一点点「橡皮筋」余量，避免手指一抖就整卡偏移。
    _dx.value = _index == 0
        ? raw.clamp(-_maxDrag, 40.0)
        : raw.clamp(-40.0, _maxDrag);
    _syncLevels();
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dx;
    final far = _dx.value.abs() > OverviewStack.kDragThreshold;
    final fling = _index == 0 ? v < -600 : v > 600;

    if (far || fling) {
      Haptics.light();
      _pageTo(_index == 0 ? 1 : 0);
    } else {
      _animateTo(0, OverviewStack.kSnapBack, Curves.easeOutCubic, () {
        _syncLevels(progress: 0);
      });
    }
  }

  /// 翻页：位移推到整卡宽（滑出去），到终点再一次性换层并归零。
  void _pageTo(int index) {
    final target = index == 1 ? -_maxDrag : _maxDrag;
    _animateTo(target, OverviewStack.kSettle, Curves.easeInOutCubic, () {
      // 终点：位移先归零，再在同一帧里固化新层级并换 index
      _dx.value = 0;
      setState(() {
        _index = index;
        _syncLevels(progress: 0);
        widget.onPageChanged?.call(index);
      });
    });
  }

  /// 程序化切换（外部按钮等）
  void jumpTo(int index) {
    if (index == _index || !widget.hasSecond) return;
    _pageTo(index);
  }

  /// 把「位移进度」同步成两张卡的层级：
  /// 拖动时目标卡的层级随进度从 0 升到 1（连续、无跳变）；
  /// 松手后由翻页动画继续把进度推到满格，到达终点后才真正换 [_index]。
  void _syncLevels({double? progress}) {
    final p = progress ?? (_dx.value.abs() / _maxDrag).clamp(0.0, 1.0);
    if (_topIsSecond) {
      _levelB.value = 1;
      _levelA.value = p;
    } else {
      _levelA.value = 1;
      _levelB.value = p;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = widget.hasSecond;
    return LayoutBuilder(
      builder: (context, c) {
        _width = c.maxWidth;
        return GestureDetector(
          // 只接管水平拖动：纵向仍交给外层列表滚动
          onHorizontalDragStart: allowed ? _onDragStart : null,
          onHorizontalDragUpdate: allowed ? _onDragUpdate : null,
          onHorizontalDragEnd: allowed ? _onDragEnd : null,
          behavior: HitTestBehavior.deferToChild,
          // 用 Stack 的默认「按最大非定位子节点定高」行为：
          // 当前在顶层的那张卡最高，Stack 高度就跟着它 ——
          // 第二张（饼图）比看板高时列表项自动长高，不会被裁掉。
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // —— 第三层：更小的一圈浅色边（纯装饰，最先绘制在最底下）——
              if (allowed) _buildGhost(),
              _CardRole(
                role: 0,
                level: _levelA,
                dx: _dx,
                maxDrag: _maxDrag,
                stack: this,
                child: widget.card1,
              ),
              if (allowed)
                _CardRole(
                  role: 1,
                  level: _levelB,
                  dx: _dx,
                  maxDrag: _maxDrag,
                  stack: this,
                  child: widget.card2,
                ),
            ],
          ),
        );
      },
    );
  }

  /// 更靠后的一圈底色：只为了「一叠」的层次感。
  ///
  /// 它同时是 Stack 的「撑高者」：真卡用 [Positioned.fill] 铺满，
  /// 尺寸由外层决定，所以必须有一个非定位子节点告诉 Stack 自己多高 ——
  /// 这里取「露边位置 + 底边」，不会被那 8~16px 的错位裁掉。
  Widget _buildGhost() {
    // 高度定死在「错位量 + 一小截」，既不会顶高 Stack，也不会被裁掉
    return IgnorePointer(
      child: SizedBox(
        height: OverviewStack.kStackOffset * 2 + 20,
        child: Align(
          alignment: Alignment.topCenter,
          child: Transform.translate(
            offset: const Offset(0, OverviewStack.kStackOffset * 2),
            child: Transform.scale(
              scale: OverviewStack.kStackScale * 0.985,
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 20,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE5F5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 一张卡在堆叠中的「角色」：把层级与位移翻译成 Transform。
///
/// 逐帧重建的只有这里最内层的 [Transform]；[child]（真实卡片）
/// 作为 `child` 参数缓存透传，element 与 render 对象都不会重建。
class _CardRole extends StatelessWidget {
  final int role; // 0 = card1，1 = card2
  final ValueNotifier<double> level;
  final ValueNotifier<double> dx;
  final double maxDrag;
  final OverviewStackState stack;
  final Widget child;

  const _CardRole({
    required this.role,
    required this.level,
    required this.dx,
    required this.maxDrag,
    required this.stack,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: level,
      child: child,
      builder: (context, lv, card) {
        // 完全压在底层 → 整卡离屏（不布局、不绘制），只留装饰露边
        if (lv < 0.001) {
          return const Offstage(offstage: true, child: SizedBox.shrink());
        }
        return RepaintBoundary(
          child: ValueListenableBuilder<double>(
            valueListenable: dx,
            child: card,
            builder: (context, d, childCard) => _body(lv, d, childCard!),
          ),
        );
      },
    );
  }

  Widget _body(double lv, double d, Widget card) {
    final p = (d.abs() / maxDrag).clamp(0.0, 1.0);
    final onTop = lv > 0.999;
    // 顶层跟手 1:1；背面反向跟随 + 随进度上浮放大
    final shift = onTop ? d : d * 0.55;
    final scale = onTop
        ? 1 - 0.04 * p
        : OverviewStack.kStackScale +
            (1 - OverviewStack.kStackScale) * p * lv.clamp(0.0, 1.0);
    return Transform.translate(
      offset: Offset(shift, onTop ? 0 : OverviewStack.kStackOffset * (1 - p)),
      child: Transform.scale(
        scale: scale,
        alignment: onTop ? Alignment.center : Alignment.topCenter,
        child: card,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 第二张卡：金额为正的资产细分饼图
// ---------------------------------------------------------------------------

/// 一块饼：类型 / 金额 / 占比 / 颜色
class AssetSlice {
  final String type;
  final double amount;
  final double ratio;
  final Color color;

  const AssetSlice({
    required this.type,
    required this.amount,
    required this.ratio,
    required this.color,
  });
}

/// 一组饼图配色（循环使用）。
const List<Color> kSlicePalette = [
  Color(0xFF3B6FE0),
  Color(0xFF2A9D5C),
  Color(0xFFF0A020),
  Color(0xFF9B6BE0),
  Color(0xFF20B2C4),
  Color(0xFFE0576A),
  Color(0xFF6C7CE0),
  Color(0xFFB0A84A),
];

/// 按资产类型汇总「金额为正」的部分，并计算占比。
///
/// 占比以**正资产总额**为分母（净资产为负时也不会出现 >100% 的怪数字）。
/// 结果按金额从大到小排列，便于图例对照。
List<AssetSlice> buildSlices(List<Asset> assets) {
  final byType = <String, double>{};
  for (final a in assets) {
    if (a.amount <= 0) continue;
    byType[a.type] = (byType[a.type] ?? 0) + a.amount;
  }
  final total = byType.values.fold<double>(0, (s, v) => s + v);
  if (total <= 0) return const [];

  final entries = byType.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return [
    for (var i = 0; i < entries.length; i++)
      AssetSlice(
        type: entries[i].key,
        amount: entries[i].value,
        ratio: entries[i].value / total,
        color: kSlicePalette[i % kSlicePalette.length],
      ),
  ];
}

/// 资产细分的金额饼图卡片（看板堆叠的第二张）。
class AssetPieCard extends StatefulWidget {
  final List<AssetSlice> slices;
  final bool hideNumbers;

  /// 数值格式化（与看板同一套）
  final String Function(double) money;

  /// 图例点按：按该类型筛选列表
  final ValueChanged<String>? onTapType;

  const AssetPieCard({
    Key? key,
    required this.slices,
    required this.money,
    this.hideNumbers = false,
    this.onTapType,
  }) : super(key: key);

  @override
  State<AssetPieCard> createState() => _AssetPieCardState();
}

class _AssetPieCardState extends State<AssetPieCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  /// 高亮某一块（点图例时扇区外扩 + 其余变淡）
  int? _active;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AssetPieCard old) {
    super.didUpdateWidget(old);
    if (old.slices.length != widget.slices.length) {
      _c.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.slices.fold<double>(0, (s, e) => s + e.amount);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F2A3B52),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.pie_chart_outline, size: 16, color: Color(0xFF3B6FE0)),
              SizedBox(width: 6),
              Text('资产细分',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A3B52))),
              Spacer(),
              Text('仅统计金额为正',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF9AA8BF))),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.slices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text('还没有金额为正的资产',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9AA8BF))),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 108,
                  height: 108,
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (_, __) => CustomPaint(
                        painter: _PiePainter(
                          slices: widget.slices,
                          progress: Curves.easeOutCubic.transform(_c.value),
                          active: _active,
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('正资产',
                                  style: TextStyle(
                                      fontSize: 9.5, color: Color(0xFF9AA8BF))),
                              const SizedBox(height: 1),
                              Text(
                                widget.hideNumbers ? '****' : _short(total),
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2A3B52)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = 0; i < widget.slices.length; i++)
                        _legendRow(i, widget.slices[i]),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legendRow(int i, AssetSlice s) {
    final on = _active == null || _active == i;
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() => _active = _active == i ? null : i);
        widget.onTapType?.call(s.type);
      },
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: on ? 1 : 0.4,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: s.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  s.type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF2A3B52)),
                ),
              ),
              Text(
                '${(s.ratio * 100).toStringAsFixed(s.ratio >= 0.1 ? 0 : 1)}%',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3B6FE0)),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 62,
                child: Text(
                  widget.hideNumbers ? '****' : _short(s.amount),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF9AA8BF)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 图例里的金额用紧凑写法：1.2万 / 3,456 / 88
  static String _short(double v) {
    final a = v.abs();
    if (a >= 10000) {
      final w = v / 10000;
      return '${w.toStringAsFixed(w.abs() >= 100 ? 0 : 1)}万';
    }
    if (a == a.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }
}

/// 圆环饼图：从 12 点方向顺时针依次绘制，带 0.5% 的间隙，
/// 高亮块向外扩 3px 且其余变淡。
class _PiePainter extends CustomPainter {
  final List<AssetSlice> slices;
  final double progress;
  final int? active;

  _PiePainter({
    required this.slices,
    required this.progress,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseR = math.min(size.width, size.height) / 2;
    final stroke = baseR * 0.34;
    final r = baseR - stroke / 2 - 4;
    var start = -math.pi / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    for (var i = 0; i < slices.length; i++) {
      final s = slices[i];
      final sweep = s.ratio * 2 * math.pi * progress;
      final isActive = active == i;
      final dim = active != null && !isActive;
      // 单一类型时不留缝，避免画成一个不闭合的圈
      final gap = slices.length > 1 ? 0.018 : 0.0;
      final rr = isActive ? r + 3 : r;
      paint.color = dim ? s.color.withOpacity(0.28) : s.color;
      paint.strokeWidth = isActive ? stroke + 2 : stroke;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: rr),
        start + gap / 2,
        math.max(sweep - gap, 0.001),
        false,
        paint,
      );
      start += s.ratio * 2 * math.pi * progress;
    }
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.progress != progress ||
      old.active != active ||
      old.slices.length != slices.length;
}
