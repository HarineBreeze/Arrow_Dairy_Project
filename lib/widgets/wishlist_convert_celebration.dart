import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../utils/app_motion.dart';
import '../utils/haptics.dart';
import 'pressable.dart';

/// v5.0.21 愿望单物品攒满「转正」为已拥有时的庆祝层。
/// 粉色主题（愿望单色）+ 对勾徽章 + 粒子迸发，主题色随 AppPalette 自适应。
Future<void> showWishlistConvertCelebration(
  BuildContext context, {
  required String name,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0x99000000),
    builder: (_) => WishlistConvertCelebration(name: name),
  );
}

class WishlistConvertCelebration extends StatefulWidget {
  final String name;
  const WishlistConvertCelebration({Key? key, required this.name})
      : super(key: key);

  @override
  State<WishlistConvertCelebration> createState() =>
      _WishlistConvertCelebrationState();
}

class _WishlistConvertCelebrationState extends State<WishlistConvertCelebration>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: AppMotion.pageDuration,
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  @override
  void initState() {
    super.initState();
    Haptics.medium();
    _enter.forward();
    _burst.forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _close() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    // 愿望单粉（沿用 item_edit 的 0xFFE58BA0），文字/底纹走 AppPalette 适配
    const pink = Color(0xFFE58BA0);
    final titleColor = AppPalette.c(0xFF24382F);

    return FadeTransition(
      opacity: _enter,
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _enter, curve: AppMotion.pageCurve),
        child: Center(
          child: SingleChildScrollView(
            child: Material(
              color: Colors.transparent,
              child: Container(
                key: const ValueKey('wishlist-convert-celebration'),
                width: 300,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: AnimatedBuilder(
                        animation: _burst,
                        builder: (_, child) => Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size.square(120),
                              painter: _ConvertBurst(
                                progress: _burst.value,
                                color: pink,
                              ),
                            ),
                            Container(
                              width: 92,
                              height: 92,
                              decoration: const BoxDecoration(
                                color: pink,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(Icons.check,
                                  key: ValueKey('wishlist-convert-check'),
                                  size: 48,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('愿望成真！',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            color: titleColor)),
                    const SizedBox(height: 12),
                    Text(
                      '「${widget.name}」已加入拥有中',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: titleColor),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Pressable(
                        child: Material(
                          color: pink,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: const ValueKey('wishlist-convert-confirm'),
                            onTap: _close,
                            child: const Center(
                              child: Text('太棒了',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white)),
                            ),
                          ),
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
  }
}

/// 转正粒子：一圈小圆点从中心向外扩散并淡出（固定种子，轨迹稳定）。
class _ConvertBurst extends CustomPainter {
  final double progress;
  final Color color;
  static const int _count = 12;

  _ConvertBurst({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final center = size.center(Offset.zero);
    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < _count; i++) {
      final rnd = math.Random(i * 31 + 7);
      final angle = (i / _count) * math.pi * 2 + rnd.nextDouble() * 0.22;
      final spread = 40 + (18 + rnd.nextDouble() * 14) * t;
      final dotR = (2.2 + rnd.nextDouble() * 1.4) * (1 - t).clamp(0.25, 1.0);
      paint.color = color.withOpacity((1 - t).clamp(0.0, 1.0) * 0.9);
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * spread,
        dotR,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ConvertBurst old) =>
      old.progress != progress || old.color != color;
}
