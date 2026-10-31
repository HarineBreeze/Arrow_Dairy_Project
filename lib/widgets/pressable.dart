import 'package:flutter/material.dart';

/// 按压回弹（Press & Bounce）动效。
///
/// 手势：按下缩到 96%，松手用弹簧动画先冲到约 102%，再回落 100%。
///
/// 实现要点：
/// · 只用 [Transform.scale] 做纯绘制变换，不参与布局与命中测试，
///   所以缩放过程中手指不会「脱离」目标，点击不会被意外取消。
/// · 用 [Listener]（原始指针事件）而不是 GestureDetector 识别按压，
///   Listener 不参与手势竞技场，可以从外层「套住」已有的
///   InkWell / GestureDetector / 拖拽监听，叠加缩放而不抢它们的点击与长按。
/// · 必须用 [AnimationController.unbounded]：Flutter 每帧都会把 `value`
///   钳制在 `[lowerBound, upperBound]` 内（见 `AnimationController._tick`），
///   默认的 `[0, 1]` 会把弹簧曲线的过冲直接夹掉 —— 实测动画变成「匀速回弹」，
///   完全看不出弹性。用不受限的控制器让过冲值越过 0 保留下来。
class Pressable extends StatefulWidget {
  /// 被压缩的内容
  final Widget child;

  /// 是否启用（禁用态按钮不收缩）
  final bool enabled;

  /// 按压缩小比例
  final double pressedScale;

  /// 由外层驱动按压（true = 不自己监听指针）。
  ///
  /// 有些卡片本来就挂着指针监听（如资产卡的长按/拖拽判定），
  /// 再套一层 Listener 既多余、也可能干扰滑动语义。
  /// 此时把 external 设为 true，再由外层通过 [PressableHandle] 通知按下/松手。
  final bool external;

  /// 外层驱动用的句柄（仅 [external] 为 true 时需要）
  final PressableHandle? handle;

  const Pressable({
    Key? key,
    required this.child,
    this.enabled = true,
    this.pressedScale = kDefaultPressedScale,
    this.external = false,
    this.handle,
  }) : super(key: key);

  /// 默认按压缩放比例
  static const double kDefaultPressedScale = 0.96;

  /// 按下收缩时长（要干脆）
  static const Duration kPressIn = Duration(milliseconds: 90);

  /// 回弹时长（弹簧要有余韵）
  static const Duration kRelease = Duration(milliseconds: 420);

  /// 回弹最高点超出量：1.00 → 1.02 → 1.00
  static const double kOvershoot = 0.02;

  /// 回弹曲线：先冲过目标再回落（≈ 弹簧）。
  ///
  /// 峰值约 1.09（t≈0.55）。配合从 `-1` 到 `0` 的动画，值会短暂越过 0 到
  /// 约 `+0.09`，再回落 —— 越过 0 的那段即「弹过头」。
  static const Curve kReleaseCurve = Cubic(0.34, 1.56, 0.64, 1.0);

  /// 曲线越过 0 的幅度（归一化用），`Cubic(0.34,1.56,0.64,1.0)` 实测约 0.088。
  static const double kCurveOvershoot = 0.088;

  /// 把动画进度 v 映射为缩放值。
  ///
  /// 约定：v == 0 落定；v == -1 按到底；v > 0 表示弹簧过冲。
  ///
  /// 为什么过冲是正值：控制器从 `-1` 回到 `0`，Flutter 按
  /// `x = begin + (end-begin) * curve(t)` 取值，即 `x = -1 + curve(t)`。
  /// 曲线在 t≈0.55 处冲到 1.09，于是 `x` 短暂变成 `+0.09` —— 这正是
  /// 「弹过头」的瞬间，随后回落到 0。
  static double scaleFor(double v, double pressedScale) {
    final amp = 1 - pressedScale; // 0.04
    if (v <= -1) return pressedScale; // 按到底
    if (v < 0) return 1 + amp * v; // 由 96% 回到 100%
    // v > 0：弹簧过冲，按曲线峰值归一化后外扩，最多 kOvershoot
    final over = (v / kCurveOvershoot) * kOvershoot;
    return 1 + over.clamp(0.0, kOvershoot);
  }

  @override
  State<Pressable> createState() => _PressableState();
}

/// 外部驱动 [Pressable] 的句柄
class PressableHandle {
  _PressableState? _state;

  void press() => _state?.press();
  void release() => _state?.release();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  /// 约定取值：`0` = 落定，`-1` = 按到底，`> 0` = 弹簧过冲。
  ///
  /// 必须用 unbounded：默认控制器的 `_tick` 会把 value 钳制到 `[0, 1]`，
  /// 弹簧曲线越过终点的部分会被夹掉，动画看起来就是「匀速回弹」，没有弹性。
  late final AnimationController _ctrl = AnimationController.unbounded(
    vsync: this,
    duration: Pressable.kRelease,
    debugLabel: 'Pressable',
  );

  bool _down = false;

  @override
  void initState() {
    super.initState();
    if (widget.external) widget.handle?._state = this;
  }

  @override
  void dispose() {
    if (widget.external && identical(widget.handle?._state, this)) {
      widget.handle?._state = null;
    }
    _ctrl.dispose();
    super.dispose();
  }

  void press() {
    if (!widget.enabled || _down) return;
    _down = true;
    _ctrl.animateTo(-1, duration: Pressable.kPressIn, curve: Curves.easeOut);
  }

  void release() {
    if (!_down) return;
    _down = false;
    // 从 -1 回到 0：曲线中段超过 1，x = -1 + curve(t) 会短暂 > 0，
    // 即越过原尺寸一点点，形成回弹
    _ctrl.animateTo(0,
        duration: Pressable.kRelease, curve: Pressable.kReleaseCurve);
  }

  @override
  Widget build(BuildContext context) {
    final scaled = AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.scale(
        scale: Pressable.scaleFor(_ctrl.value, widget.pressedScale),
        child: child,
      ),
      child: widget.child,
    );
    if (widget.external) return scaled;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => press(),
      onPointerUp: (_) => release(),
      onPointerCancel: (_) => release(),
      child: scaled,
    );
  }
}
