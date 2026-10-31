import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_toast.dart';
import '../utils/haptics.dart';
import 'pressable.dart';

/// 编辑页底部「完成」按钮：点击后收缩成圆形、对勾描边绘出、粒子迸发，
/// 停留片刻再回调 [onDone]（由调用方负责 pop / 保存）。
///
/// 与 [AnimatedContainer] 不同，这里的收缩是**宽度驱动的**：圆形直径 = 按钮高度，
/// 因此无论在窄屏（半宽约 150）还是宽屏上，收缩终点始终是一个正圆。
///
/// 时序（总时长 [kTotal] ≈ 1.0s）：
///   |-- 0.30s 收缩 + 取消按钮淡出 --|-- 0.24s 对勾描边 --|-- 0.16s 粒子 --| 停留 0.25s
class SaveDoneButton extends StatefulWidget {
  /// 点击时的**校验**回调：返回 null 表示可以保存，返回文案则提示并中止。
  ///
  /// 校验必须是同步的（弹 SnackBar / 判断空值都是同步的），这样点击后
  /// 能立刻起动画，不用等异步落盘，避免「点了没反应」的等待感。
  final String? Function()? validate;

  /// 校验通过后立刻回调（同步起步，异步落盘由调用方自己安排）。
  /// 落盘完成后再调用 [SaveDoneButtonState.finish] 触发「打勾 + 粒子」。
  final VoidCallback? onTap;

  /// 动画播完、停留结束后回调，调用方在这里 pop 返回上一页
  final VoidCallback onDone;

  final Color color;
  final double height;
  final double radius;

  /// 收缩成圆形 / 对勾 / 粒子的总色调，默认白色（深色实心按钮上）
  final Color foreground;

  const SaveDoneButton({
    Key? key,
    this.validate,
    this.onTap,
    required this.onDone,
    required this.color,
    this.height = 48,
    this.radius = 12,
    this.foreground = Colors.white,
  }) : super(key: key);

  /// 收缩时长
  static const Duration kCollapse = Duration(milliseconds: 300);

  /// 对勾描边时长
  static const Duration kCheck = Duration(milliseconds: 240);

  /// 粒子迸发时长
  static const Duration kBurst = Duration(milliseconds: 160);

  /// 动画播完后的停留，让用户看清「完成了」
  static const Duration kHold = Duration(milliseconds: 250);

  static Duration get kTotal =>
      kCollapse + kCheck + kBurst + kHold;

  @override
  State<SaveDoneButton> createState() => SaveDoneButtonState();
}

class SaveDoneButtonState extends State<SaveDoneButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: SaveDoneButton.kTotal,
  );

  /// 0 → 1：0~0.30 收缩，0.30~0.54 描边，0.54~0.70 粒子，之后停留
  late final Animation<double> _collapse = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.30, curve: Curves.easeInOutCubic),
  );
  late final Animation<double> _check = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.30, 0.54, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _burst = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.52, 0.70, curve: Curves.easeOutCubic),
  );

  /// 收缩进度 0→1，供外部（如「取消」按钮淡出）联动
  Animation<double> get collapse => _collapse;

  /// 动画是否进行中（用于拦截连点与手势）
  bool get isPlaying => _c.isAnimating || _c.value > 0;

  /// 按钮此刻是否可点：动画一开始就锁定，直到 finish()/reset() 才解锁。
  ///
  /// 不能只用 `_c.value` 判断 —— 点击后动画首帧还没推进时 value 仍是 0，
  /// 连点第二下会漏进来。
  bool get canTap => !_busy;

  bool _busy = false;

  /// 是否已经播完并回调过 onDone（防止重复返回）
  bool _finished = false;

  /// 按压缩放：与列表卡片、单选按钮同一套参数（按下 90%，松手弹簧回弹）。
  ///
  /// 用 [PressableHandle] 由本组件自己驱动：按钮的点击已经挂在
  /// [GestureDetector] 上，再套一层 Listener 只会多一份冗余监听；
  /// 交给句柄在 onTapDown / onTapCancel 里通知最省事，也最准确。
  final PressableHandle _press = PressableHandle();

  void _toPress() {
    if (!canTap) return;
    _press.press();
  }

  void _toRelease() => _press.release();

  /// 点击：同步校验 → 收缩 → 交给外部落盘
  void _onTap() {
    if (_busy || _finished) return;
    final err = widget.validate?.call();
    if (err != null) {
      _press.release();
      Haptics.lightNow();
      _toast(err);
      return;
    }
    _busy = true;
    setState(() {});
    // 先进入收缩阶段（0 → 0.54），落盘完成后由 finish() 续播对勾 + 粒子
    _c.animateTo(0.54,
        duration: SaveDoneButton.kCollapse + SaveDoneButton.kCheck,
        curve: Curves.linear);
    widget.onTap?.call();
  }

  /// 中止并复位（校验失败 / 保存失败时由外部调用）
  void reset() {
    _busy = false;
    _finished = false;
    _press.reset();
    _c.value = 0;
    if (mounted) setState(() {});
  }

  /// 校验失败提示：走 [AppToast] 去重。
  ///
  /// 之前直接 `showSnackBar`，用户连点「完成」会一条接一条地弹
  /// （同一句「请填写事件名称」反复刷屏）。现在同一句提示在展示期内
  /// 只弹一次，只有提示内容变了才会立刻换成新的那条。
  void _toast(String msg) {
    AppToast.show(context, msg);
  }

  /// 落盘完成：续播「对勾 → 粒子 → 停留 → onDone」
  Future<void> finish() async {
    if (_finished) return;
    _finished = true;
    _busy = true;
    if (mounted) setState(() {});
    Haptics.mediumNow();
    await _c.forward(from: _c.value);
    if (!mounted) return;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _collapse.value;
        return LayoutBuilder(
          builder: (context, constraints) {
            final full = constraints.maxWidth;
            // 宽度从整条收缩到 h（正圆），圆角同步从 radius 收到 h/2
            final w = full + (h - full) * t;
            final r = widget.radius + (h / 2 - widget.radius) * t;
            return SizedBox(
              width: double.infinity,
              height: h,
              child: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: GestureDetector(
                    // 用 GestureDetector 而不是叠两层 InkWell：
                    // 父级 InkWell 会吃掉子级的点击，导致 onTap 永不触发
                    behavior: HitTestBehavior.opaque,
                    onTap: canTap ? _onTap : null,
                    // 按压回弹：按下缩到 90%，松手弹簧回弹（参数与其它按钮一致）
                    onTapDown: canTap ? (_) => _toPress() : null,
                    onTapUp: (_) => _toRelease(),
                    onTapCancel: _toRelease,
                    child: Pressable(
                      enabled: canTap,
                      external: true,
                      handle: _press,
                      child: Material(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(r),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 「完成」文字：随收缩淡出
                          Opacity(
                            opacity: (1 - t * 2.2).clamp(0.0, 1.0),
                            child: const Text('完成',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.white)),
                          ),
                          // 对勾：描边逐段绘出
                          if (_c.value > 0)
                            CustomPaint(
                              size: Size.square(h * 0.52),
                              painter: _CheckPainter(
                                progress: _check.value,
                                color: widget.foreground,
                                strokeWidth: 2.6,
                              ),
                            ),
                          // 粒子：沿圆形外缘迸发
                          if (_burst.value > 0)
                            IgnorePointer(
                              child: CustomPaint(
                                size: Size.square(h * 2.1),
                                painter: _BurstPainter(
                                  progress: _burst.value,
                                  color: widget.foreground,
                                  radius: h / 2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// 对勾描边：两段直线按 progress 依次绘出（下笔 → 长撇 → 提笔），
/// 用短小的圆头线帽模拟「笔尖」。
class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _CheckPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final w = size.width, h = size.height;
    // 归一化到 24 网格再缩放，保证不同尺寸下形状一致
    Offset p(double x, double y) => Offset(x / 24 * w, y / 24 * h);
    final start = p(4.5, 12.5);
    final elbow = p(9.8, 17.8);
    final end = p(19.5, 7.2);

    final l1 = (elbow - start).distance;
    final l2 = (end - elbow).distance;
    final total = l1 + l2;
    final drawn = total * progress.clamp(0.0, 1.0);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()..moveTo(start.dx, start.dy);
    if (drawn <= l1) {
      final t = drawn / l1;
      path.lineTo(
        start.dx + (elbow.dx - start.dx) * t,
        start.dy + (elbow.dy - start.dy) * t,
      );
    } else {
      path.lineTo(elbow.dx, elbow.dy);
      final t = ((drawn - l1) / l2).clamp(0.0, 1.0);
      path.lineTo(
        elbow.dx + (end.dx - elbow.dx) * t,
        elbow.dy + (end.dy - elbow.dy) * t,
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color;
}

/// 粒子迸发：一圈小圆点从圆按钮外缘向外扩散并淡出，
/// 角度做一点错位，避免排列过于机械。
class _BurstPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double radius;

  static const int _count = 10;

  _BurstPainter({
    required this.progress,
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < _count; i++) {
      // 固定种子：每次播放轨迹一致，不会闪烁抖动
      final rnd = math.Random(i * 31 + 7);
      final angle = (i / _count) * math.pi * 2 + rnd.nextDouble() * 0.22;
      final spread = radius + (10 + rnd.nextDouble() * 9) * t;
      final dotR = (1.9 + rnd.nextDouble() * 1.1) * (1 - t).clamp(0.25, 1.0);
      paint.color = color.withOpacity((1 - t).clamp(0.0, 1.0) * 0.9);
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * spread,
        dotR,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}
