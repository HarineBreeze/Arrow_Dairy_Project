import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/asset.dart';
import '../utils/haptics.dart';

/// 资产全景页顶部的「数据看板」卡片堆叠。
///
/// ## 交互
/// - **堆叠**：顶层卡片完整显示，第二张整体向下平移 [kStackOffset] 并等比缩小
///   [kStackScale]，只从下面露出一条边（第三张继续往下缩，形成层次）；
/// - **左右滑动**：拖动进行两张卡片之间的切换。向右滑 = 下一张（[card2] 升到顶层，
///   原 [card1] 会依次滑到最底部）；向左滑 = 上一张；
/// - **吸附 / 回弹**：松手后按拖动距离与速度决定「翻页」还是「弹回」，
///   用弹簧曲线回弹，和列表卡片的按压回弹手感一致。
///
/// ## 为什么不直接堆三张卡
/// 第二张（饼图）高度是动态的（图例条目多就高）。若把三张都做在 Stack 里，
/// 必须给一个固定高度，内容一多就被裁掉。这里用「顶层卡 + 背后一层假边」
/// 的方案：假边的高度只是 `卡1高 - offset`，第二张卡在翻页时才真正参与布局，
/// 于是不需要任何固定高度。
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

  @override
  State<OverviewStack> createState() => OverviewStackState();
}

class OverviewStackState extends State<OverviewStack>
    with SingleTickerProviderStateMixin {
  /// 0 = 顶层是 card1；1 = 顶层是 card2
  int _index = 0;

  /// 当前水平拖动位移（像素，未吸附）
  double _drag = 0;

  bool _dragging = false;

  /// 第一张卡的实测高度，用于给背后那层「露边」定高度
  double _card1Height = 0;

  late final AnimationController _settle = AnimationController.unbounded(
    vsync: this,
    duration: OverviewStack.kSettle,
  );
  double _settleTo = 0;
  VoidCallback? _onSettleDone;

  double get currentIndex => _index.toDouble();

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _animateTo(double target, Curve curve, [VoidCallback? done]) {
    _settleTo = target;
    _onSettleDone = done;
    _settle.value = 0;
    // 动画本身只负责「通知重绘」，位移仍在 _drag 里算，
    // 因此每帧只重跑 build 里的 Transform，不重建卡片子树。
    _settle.animateTo(1, duration: OverviewStack.kSettle, curve: curve)
        .whenComplete(() {
      _drag = _settleTo;
      final cb = _onSettleDone;
      _onSettleDone = null;
      if (!mounted) return;
      _settle.value = 0;
      setState(() {}); // 落定：一次性把 _drag 归位并重建
      cb?.call();
    });
  }

  void _onDragStart(DragStartDetails d) {
    _settle.stop();
    _drag = 0;
    _dragging = true;
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_dragging) {
      _dragging = true;
    }
    // 顶层是卡 1：只能往左拉（负位移）把卡 2 拉上来；
    // 顶层是卡 2：只能往右拉（正位移）回到卡 1。
    final dx = d.delta.dx;
    if (_index == 0) {
      _drag = (_drag + dx).clamp(-400.0, 40.0);
    } else {
      _drag = (_drag + dx).clamp(-40.0, 400.0);
    }
    setState(() {});
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    final v = d.velocity.pixelsPerSecond.dx;
    if (_index == 0) {
      // 右滑距离/速度够 → 翻到卡 2
      if (_drag.abs() > OverviewStack.kDragThreshold || v > 600) {
        Haptics.light();
        _flipTo(1);
      } else {
        _animateTo(0, Curves.easeOutCubic, () => setState(() {}));
      }
    } else {
      if (_drag.abs() > OverviewStack.kDragThreshold || v < -600) {
        Haptics.light();
        _flipTo(0);
      } else {
        _animateTo(0, Curves.easeOutCubic, () => setState(() {}));
      }
    }
  }

  /// 完成一次翻页：用弹簧曲线把位移推到「整屏宽」再瞬间归零换层，
  /// 这样观感是「滑出去了」，而不是「弹回去」。
  void _flipTo(int index) {
    final w = MediaQuery.of(context).size.width;
    final target = index == 1 ? -w : w;
    _animateTo(target, Curves.easeInOutCubic, () {
      setState(() {
        _index = index;
        _drag = 0;
      });
      widget.onPageChanged?.call(index);
    });
  }

  /// 程序化切换（点击指示点）
  void jumpTo(int index) {
    if (index == _index) return;
    _flipTo(index);
  }

  @override
  Widget build(BuildContext context) {
    // 注意：拖动过程只更新 _drag 并重建**本组件内部**的 Transform，
    // 不通过父级 setState —— 否则父级每帧重建会毁掉卡片的子树
    // （饼图卡的动画控制器随之重建，尺寸也要重新测量）。
    final topIsSecond = widget.hasSecond && _index == 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          // 只接管水平拖动：纵向仍然让给外层列表滚动
          onHorizontalDragStart: widget.hasSecond ? _onDragStart : null,
          onHorizontalDragUpdate: widget.hasSecond ? _onDragUpdate : null,
          onHorizontalDragEnd: widget.hasSecond ? _onDragEnd : null,
          behavior: HitTestBehavior.deferToChild,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // —— 背面（第二层）：默认只露出一条边 ——
              if (widget.hasSecond)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    // 没翻页时它只露边，不该吃点击
                    ignoring: !topIsSecond,
                    child: AnimatedBuilder(
                      animation: _settle,
                      builder: (_, __) => _buildBack(),
                    ),
                  ),
                ),
              // —— 顶层：完整卡片，跟手位移 ——
              AnimatedBuilder(
                animation: _settle,
                builder: (_, __) => _buildTop(topIsSecond),
                child: topIsSecond ? widget.card2 : widget.card1,
              ),
              // —— 第三层：更小的一圈，增强「一叠卡」的层次 ——
              if (widget.hasSecond)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: IgnorePointer(child: _buildGhost()),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 顶层卡片（child 由外部传入并保持稳定，这里只做位移与缩放）
  Widget _buildTop(bool topIsSecond) {
    final maxDrag = (MediaQuery.of(context).size.width * 0.9).clamp(200.0, 520.0);
    final progress = (_drag.abs() / maxDrag).clamp(0.0, 1.0);
    return Transform.translate(
      offset: Offset(_drag, 0),
      child: Transform.scale(
        // 往外拉时顶层略缩，像被抽走
        scale: 1 - 0.04 * progress,
        alignment: Alignment.center,
        child: topIsSecond ? widget.card2 : widget.card1,
      ),
    );
  }

  /// 背面卡：按「卡1 高 - 露边」定高，底边从顶层下方露出来；
  /// 拖动过程中它上浮、放大、反向平移，翻页瞬间成为新的顶层。
  Widget _buildBack() {
    final topIsSecond = widget.hasSecond && _index == 1;
    final maxDrag = (MediaQuery.of(context).size.width * 0.9).clamp(200.0, 520.0);
    final progress = (_drag.abs() / maxDrag).clamp(0.0, 1.0);
    final behind = topIsSecond ? widget.card1 : widget.card2;

    return Transform.translate(
      offset: Offset(
        // 反向跟随：翻页时把即将上位的卡从屏幕外拉回来
        topIsSecond ? -_drag * 0.35 : _drag * 0.55,
        OverviewStack.kStackOffset * (1 - progress),
      ),
      child: Transform.scale(
        scale: OverviewStack.kStackScale +
            (1 - OverviewStack.kStackScale) * progress,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            // 只露出上面一部分：高度 = 顶层卡高 - 露边
            child: _StackHeightProbe(
              onHeight: (h) {
                if ((h - _card1Height).abs() > 0.5) {
                  _card1Height = h;
                }
              },
              child: behind,
            ),
          ),
        ),
      ),
    );
  }

  /// 更靠后的那圈阴影/底色：只为了「一叠」的层次感
  Widget _buildGhost() {
    return Transform.translate(
      offset: const Offset(0, OverviewStack.kStackOffset * 2),
      child: Transform.scale(
        scale: OverviewStack.kStackScale * 0.985,
        alignment: Alignment.topCenter,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFDCE5F5),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
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
              Icon(Icons.pie_chart_outline,
                  size: 16, color: Color(0xFF3B6FE0)),
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
                    style:
                        TextStyle(fontSize: 13, color: Color(0xFF9AA8BF))),
              ),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 108,
                  height: 108,
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
                                    fontSize: 9.5,
                                    color: Color(0xFF9AA8BF))),
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
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF2A3B52)),
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
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9AA8BF)),
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

/// 高度探针：把子树的实测高度回传给外层（用于背面卡的定高）。
class _StackHeightProbe extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;

  const _StackHeightProbe({required this.onHeight, Widget? child})
      : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightProbe(onHeight);

  @override
  void updateRenderObject(
      BuildContext context, _RenderHeightProbe renderObject) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderHeightProbe extends RenderProxyBox {
  ValueChanged<double> onHeight;

  _RenderHeightProbe(this.onHeight);

  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (_last == null || (_last!.height - h).abs() > 0.5) {
      _last = size;
      // 布局阶段不能直接 setState，推到帧后
      final cb = onHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) => cb(size.height));
    }
  }
}
