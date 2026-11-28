import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../utils/haptics.dart';

/// v5.0.22 愿望单物品攒满「转正」时的庆祝特效。
///
/// 与 v5.0.21 的差别：不再弹一个独立对话框，而是把**翻转 + 粒子**直接
/// 作用在被转正的那张卡片本身。卡片用物品 id 作 ValueKey，转正后即使
/// 因排序变化被移动到别的物理位置，State（及动画）也会随卡片一起走，
/// 不会出现「卡片换位置特效就丢」的情况。
///
/// 用法：
/// ```dart
/// WishlistConvertEffect(
///   celebrate: _celebratingIds.contains(item.id),
///   onDone: () => _celebratingIds.remove(item.id),
///   child: card,
/// )
/// ```
class WishlistConvertEffect extends StatefulWidget {
  /// false → true 的跳变触发一次特效
  final bool celebrate;

  /// 特效播完回调（调用方据此清掉 celebrating 标记）
  final VoidCallback? onDone;

  /// 被作用的目标卡片
  final Widget child;

  const WishlistConvertEffect({
    Key? key,
    required this.celebrate,
    this.onDone,
    required this.child,
  }) : super(key: key);

  @override
  State<WishlistConvertEffect> createState() => _WishlistConvertEffectState();
}

class _WishlistConvertEffectState extends State<WishlistConvertEffect>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    // v5.0.24：单次翻转一整圈（360°），翻过去即从「愿望单」变成「已拥有」，
    // 停在正面；不再来回 reverse（v5.0.23 的「翻过去又翻回来」已废弃）。
    duration: const Duration(milliseconds: 720),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // 翻完一整圈直接结束，卡片已是「已拥有」内容且正面朝上
        widget.onDone?.call();
      }
    });

  @override
  void initState() {
    super.initState();
    if (widget.celebrate) _start();
  }

  @override
  void didUpdateWidget(WishlistConvertEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.celebrate && !oldWidget.celebrate) _start();
  }

  void _start() {
    Haptics.medium();
    if (mounted) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      child: widget.child,
      builder: (context, child) {
        final t = _ctrl.value;
        // v5.0.24：绕 Y 轴单向翻转一整圈（2π），翻过去即从愿望单变成已拥有，
        // 停在正面（内容可读）；不再 reverse 翻回来。
        final angle = t * math.pi * 2;
        final scale = 1 + 0.06 * math.sin(t * math.pi);
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0018) // 透视，避免翻转像纸片平移
                ..rotateY(angle)
                ..scale(scale),
              child: child,
            ),
            if (t > 0 && t < 1)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ConvertBurst(progress: t),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 转正粒子：一圈小圆点从卡片中心向外扩散并淡出（固定种子，轨迹稳定）。
/// 半径随卡片尺寸自适应，正方形物品卡上呈现为环绕卡片的一圈点缀。
class _ConvertBurst extends CustomPainter {
  final double progress;
  static const int _count = 14;

  _ConvertBurst({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final base = size.shortestSide * 0.34;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < _count; i++) {
      final rnd = math.Random(i * 31 + 7);
      final angle = (i / _count) * math.pi * 2 + rnd.nextDouble() * 0.22;
      final spread = base + (18 + rnd.nextDouble() * 14) * t;
      final dotR =
          (2.6 + rnd.nextDouble() * 1.6) * (1 - t).clamp(0.25, 1.0);
      // 愿望单粉走主题色板（与 item_edit 的 0xFFE58BA0 语义一致）
      paint.color = AppPalette.c(0xFFE58BA0)
          .withOpacity((1 - t).clamp(0.0, 1.0) * 0.9);
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * spread,
        dotR,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ConvertBurst old) => old.progress != progress;
}
