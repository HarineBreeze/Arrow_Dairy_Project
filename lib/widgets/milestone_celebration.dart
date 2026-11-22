import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../utils/app_motion.dart';
import '../utils/haptics.dart';
import 'pressable.dart';

/// 弹出「写作里程碑达成」庆祝层。
///
/// 由 home_screen 在新建日记成功后调用：日记总数首次跨过某个里程碑节点
/// （7/30/100/…）时弹出。奖励灵感已由 RewardService 落盘，这里只负责呈现。
///
/// 点遮罩或「太棒了」按钮均可关闭；关闭后调用方继续后续提示。
Future<void> showMilestoneCelebration(
  BuildContext context, {
  required int milestone,
  required int points,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0x99000000),
    builder: (_) => MilestoneCelebration(milestone: milestone, points: points),
  );
}

/// 里程碑庆祝弹层：主题色圆形徽章 + 粒子迸发 + 奖励文案。
///
/// UI 全部走 [AppPalette]（不写深浅判断、不写死绿色），动效走 [AppMotion]
/// 时长与曲线，按钮走 [Pressable]，达成瞬间走 [Haptics.medium]。
class MilestoneCelebration extends StatefulWidget {
  /// 达成的里程碑篇数（如 7 / 100）
  final int milestone;

  /// 本次获得的灵感点数（一次跨多节点时为各节点之和）
  final int points;

  const MilestoneCelebration({
    Key? key,
    required this.milestone,
    required this.points,
  }) : super(key: key);

  @override
  State<MilestoneCelebration> createState() => _MilestoneCelebrationState();
}

class _MilestoneCelebrationState extends State<MilestoneCelebration>
    with TickerProviderStateMixin {
  /// 卡片入场：缩放 + 淡入，时长与曲线复用全局动效常量
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: AppMotion.pageDuration,
  );

  /// 粒子迸发：入场后播一次
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
    final accent = AppPalette.accentColor;
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
                key: const ValueKey('milestone-celebration'),
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
                    // 徽章 + 粒子
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
                              painter: _CelebrationBurst(
                                progress: _burst.value,
                                color: accent,
                              ),
                            ),
                            Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '${widget.milestone}',
                                key: const ValueKey('milestone-number'),
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '第 ${widget.milestone} 篇',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '写作里程碑达成',
                      style: TextStyle(fontSize: 15, color: titleColor),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppPalette.c(0xFFE4F2EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '+${widget.points} 灵感',
                        key: const ValueKey('milestone-points'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Pressable(
                        child: Material(
                          color: accent,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: const ValueKey('milestone-confirm'),
                            onTap: _close,
                            child: const Center(
                              child: Text(
                                '太棒了',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
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

/// 庆祝粒子：一圈小圆点从中心向外扩散并淡出，角度带固定错位避免机械感。
/// 固定随机种子保证每次播放轨迹一致，不会闪烁抖动。
class _CelebrationBurst extends CustomPainter {
  final double progress;
  final Color color;

  static const int _count = 12;

  _CelebrationBurst({required this.progress, required this.color});

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
  bool shouldRepaint(_CelebrationBurst old) =>
      old.progress != progress || old.color != color;
}
