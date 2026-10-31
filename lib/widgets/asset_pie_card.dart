import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
  static const Duration kSettle = Duration(milliseconds: 320);

  /// 翻页时顶层卡滑出的距离（相对卡宽的倍数）。
  /// 不必滑到整屏 —— 配合淡出，滑出 78% 时已经「看不见了」，
  /// 位移越短、动画越短，观感越干脆。
  static const double kExitFraction = 0.78;

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

  /// 轮盘高度锁：一旦量到就固定，翻页、切卡、转场都不再变（见 [_stackHeight]）
  double? _heightLocked;

  /// 上一次参与定高的可用宽度 —— 宽度变了（旋转屏 / 分屏）才允许重新定高
  double _lockedAtWidth = 0;

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

  /// 翻页终点的位移：不必滑满一整卡宽
  double get _exitDistance => _maxDrag * OverviewStack.kExitFraction;

  /// 轮盘高度 = **固定的一块专属区域**，一旦量到就锁死，与「当前停在哪张卡」无关。
  ///
  /// 这里是「切换卡片时下方资产卡跟着一上一下」的修复点。
  ///
  /// 旧实现的定高跟着「当前顶层卡」走：切到饼图的那一帧 `_index` 变了，
  /// 高度跟着从净资产卡的高度跳到饼图卡的高度，[SizedBox] 尺寸一变，
  /// 紧跟在看板后面的资产卡片就被整体推下 / 推上一截 —— 即「跟随移动」。
  ///
  /// 现在：
  /// - 高度只由**占位卡（card1）**的实测内容高度决定，跟 `_index` 完全无关；
  /// - 量到一次后写进 [_heightLocked] 并保持不动，翻页动画期间也一样；
  /// - 另一张卡（饼图）即使更高，超出部分由 `clipBehavior: Clip.none`
  ///   溢出绘制（会被下方的卡盖住），不参与布局，不会撑开高度。
  ///
  /// 于是顶部数据栏有了稳定、专属的位置，下方列表里的卡片 y 坐标永远不变。
  double get _stackHeight => _heightLocked ?? _fallbackHeight;

  /// 每张卡的内容高度变化时调用（在布局完成后回传）。
  ///
  /// 只有占位卡（role 0）参与定高；另一张卡怎么长都不影响布局。
  void _onMeasure(int role, double h) {
    if (role != 0) return; // 只有占位卡定高
    if (h <= 0) return;
    final locked = _heightLocked;
    if (locked != null && (locked - h).abs() < 0.5) return;
    _heightLocked = h;
    // 高度在布局后才拿到，推到帧后重建一次
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  /// 只允许在「布局口径变了」时重新定高：可用宽度变化（旋转屏 / 分屏 / 字号）。
  /// 卡片自己切换、翻页、动效都不算，因此不会带来跳动。
  void _onWidthChanged(double w) {
    if ((_lockedAtWidth - w).abs() < 0.5) return;
    final firstLayout = _lockedAtWidth == 0;
    _lockedAtWidth = w;
    if (firstLayout) return; // 首次布局，正常走测量流程
    // 宽度变了：旧高度不再适用，放开锁重新量一帧
    _heightLocked = null;
  }

  /// 首帧还没有测量结果时的保底高度（净资产卡大约就这么高）
  static const double _fallbackHeight = 200;

  void _animateTo(double target, Duration duration, Curve curve, [VoidCallback? done]) {
    _fromDx = _dx.value;
    _toDx = target;
    _curve = curve;
    _animDone = done;
    _anim.duration = duration;
    _anim.forward(from: 0);
  }

  // ---------- 拖动 ----------

  /// 拖动时被「抽出来」的那张卡（层级为 0 的那张）。
  /// 必须让它上屏，否则下面的卡接位时没有内容可看。
  final ValueNotifier<int?> _peekRole = ValueNotifier<int?>(null);

  void _onDragStart(DragStartDetails d) {
    _anim.stop();
    _dx.value = 0;
    _syncLevels(progress: 0);
  }

  /// 轮换型的拖动：两个方向都能拖，都能翻页。
  ///
  /// - **左滑**：当前卡向左滑出，下面那张升上来（一直往后翻）；
  /// - **右滑**：当前卡向右滑出，上一张从左侧滑进来（回到前一张）。
  ///
  /// 只有两张卡时两种手势结果相同（互相切换），但手感一致 ——
  /// 不再有「某个方向拖不动」的死区。
  void _onDragUpdate(DragUpdateDetails d) {
    _dx.value = (_dx.value + d.delta.dx).clamp(-_maxDrag, _maxDrag);
    _syncLevels();
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dx;
    // 无论往哪边拉，只要拉得够远 / 甩得够快就切换
    final far = _dx.value.abs() > OverviewStack.kDragThreshold;
    final fling = v.abs() > 550;

    if (far || fling) {
      Haptics.light();
      _pageTo(1 - _index);
    } else {
      _animateTo(0, OverviewStack.kSnapBack, Curves.easeOutCubic, () {
        _syncLevels(progress: 0);
      });
    }
  }

  /// 翻页：位移推到 [_exitDistance]（配合淡出，已足够「滑出去」），
  /// 到终点再一次性换层并归零。
  void _pageTo(int index) {
    final target =
        _dx.value < 0 ? -_exitDistance : _exitDistance;
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
    // 有位移就露出背面那张（它的内容要一起参与接位动画）
    final peeking = p > 0.0001;
    final wantRole = peeking ? (widget.hasSecond && _index == 1 ? 0 : 1) : null;
    if (wantRole != _peekRole.value) _peekRole.value = wantRole;
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
        _onWidthChanged(c.maxWidth);
        return GestureDetector(
          // 只接管水平拖动：纵向仍交给外层列表滚动
          onHorizontalDragStart: allowed ? _onDragStart : null,
          onHorizontalDragUpdate: allowed ? _onDragUpdate : null,
          onHorizontalDragEnd: allowed ? _onDragEnd : null,
          behavior: HitTestBehavior.deferToChild,
          child: SizedBox(
            // 高度是**锁定的常数**：只在首次量到 card1 时定一次，
            // 之后无论怎么翻页、切卡、转场都保持不动，
            // 下方列表里的卡片因此不会被推上推下。
            height: _stackHeight,
            child: ValueListenableBuilder<int?>(
              valueListenable: _peekRole,
              builder: (context, peek, _) => Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // —— 第三层：更小的一圈浅色边（纯装饰，最先绘制在最底下）——
                  if (allowed) _buildGhost(),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: _CardRole(
                      role: 0,
                      level: _levelA,
                      dx: _dx,
                      maxDrag: _maxDrag,
                      stack: this,
                      peeking: peek == 0,
                      child: widget.card1,
                      onHeight: (h) => _onMeasure(0, h),
                    ),
                  ),
                  if (allowed)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: _CardRole(
                        role: 1,
                        level: _levelB,
                        dx: _dx,
                        maxDrag: _maxDrag,
                        stack: this,
                        peeking: peek == 1,
                        child: widget.card2,
                        onHeight: (h) => _onMeasure(1, h),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 更靠后的一圈底色：只为了「一叠」的层次感。
  Widget _buildGhost() {
    return IgnorePointer(
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

  /// 拖动/翻页途中被抽出来接位的那张（层级仍为 0，但要让内容可见）
  final bool peeking;

  /// 卡片内容高度的实测回调（用于给轮盘定高）
  final ValueChanged<double> onHeight;

  const _CardRole({
    required this.role,
    required this.level,
    required this.dx,
    required this.maxDrag,
    required this.stack,
    required this.child,
    required this.peeking,
    required this.onHeight,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: level,
      child: child,
      builder: (context, lv, card) {
        // 平时只画顶层那张；一旦开始拖动，背面那张也要上屏参与接位动画，
        // 否则会看到「一张空卡」升上来（上一版切不过去就是这个原因）。
        //
        // 用 Visibility 而不是 Offstage —— 这是「切换时闪白」的根因修复：
        // · Offstage 会把整棵子树从布局/绘制里摘掉，再次上屏时要做一次
        //   完整的布局 + 首次绘制（饼图的圆环、文字都要重新栅格化），
        //   那一帧就是一道白；而且它同时会冻住饼图自己的渐显动画。
        // · Visibility 只把绘制跳过（maintainSize 保留布局与测量），
        //   子树、动画、图层都在，上屏时直接拿现成的缓存，不会闪。
        final visible = lv > 0.001 || peeking;
        return Visibility(
          visible: visible,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          maintainSemantics: false,
          child: RepaintBoundary(
            child: ValueListenableBuilder<double>(
              valueListenable: dx,
              child: card,
              builder: (context, d, childCard) => _body(lv, d, childCard!),
            ),
          ),
        );
      },
    );
  }

  Widget _body(double lv, double d, Widget card) {
    final p = (d.abs() / maxDrag).clamp(0.0, 1.0);
    final onTop = lv > 0.999;
    // 只有顶层卡跟手移动；背面卡上浮放大、错位归零，接位时正好对齐。
    // 左滑：顶层卡向左滑出；右滑：顶层卡向右滑出 —— 两个方向都成立。
    final shift = onTop ? d : 0.0;
    final dy = onTop ? 0.0 : OverviewStack.kStackOffset * (1 - p);
    final scale = onTop
        ? 1 - 0.04 * p
        : OverviewStack.kStackScale + (1 - OverviewStack.kStackScale) * p;
    // 滑出去的那张同步淡出：拖到一半就开始变淡，收尾时早已「看不见」，
    // 于是换层的瞬间不会出现「卡片突然消失 / 白底露出一块」的观感。
    final fade = onTop ? (1 - 0.85 * p).clamp(0.15, 1.0) : 1.0;

    return Transform.translate(
      offset: Offset(shift, dy),
      child: _Measure(
        onHeight: onHeight,
        child: Opacity(
          opacity: fade,
          child: Transform.scale(
            scale: scale,
            alignment: onTop ? Alignment.center : Alignment.topCenter,
            child: card,
          ),
        ),
      ),
    );
  }
}

/// 量出卡片内容高度并回传（只在变化超过 0.5px 时触发）。
class _Measure extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;

  const _Measure({required this.onHeight, Widget? child}) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasure(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasure ro) {
    ro.onHeight = onHeight;
  }
}

class _RenderMeasure extends RenderProxyBox {
  ValueChanged<double> onHeight;

  _RenderMeasure(this.onHeight);

  double _last = -1;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if ((_last - h).abs() > 0.5) {
      _last = h;
      final cb = onHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) => cb(h));
    }
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
