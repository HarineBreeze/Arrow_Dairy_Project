import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../theme/app_palette.dart';
import 'app_icons.dart';

/// v4.9.37 未来信件「到期开封」App 内上方横幅。
///
/// 视觉与事件提醒横幅（CountdownBannerHost）同款：从屏幕上方约 1/10 处滑出，
/// 上滑关闭、点击进入该笔记。作为独立 host 叠加在首页 Stack 顶层，
/// 与事件横幅互不干扰（开封提醒只针对未来信件）。
class FutureLetterBannerHost extends StatefulWidget {
  /// 点击横幅 → 打开该封未来信件
  final ValueChanged<DiaryEntry> onOpenLetter;
  final Widget child;

  const FutureLetterBannerHost({
    Key? key,
    required this.onOpenLetter,
    required this.child,
  }) : super(key: key);

  @override
  State<FutureLetterBannerHost> createState() => FutureLetterBannerHostState();
}

class FutureLetterBannerHostState extends State<FutureLetterBannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  DiaryEntry? _entry;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 由外部在数据加载完成后调用；同一次启动只展示一次（去重在调用方也有）。
  void showFor(DiaryEntry e) {
    if (_shown) return;
    _shown = true;
    setState(() => _entry = e);
    _ctrl.forward();
  }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _entry = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final top = screenH * 0.1;
    final topPadding = MediaQuery.of(context).padding.top;
    final slideFrom = -(top + topPadding + 90);

    return Stack(
      children: [
        widget.child,
        if (_entry != null)
          Positioned(
            top: top,
            left: 14,
            right: 14,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                final v =
                    Curves.easeOutCubic.transform(_ctrl.value.clamp(0.0, 1.0));
                return Transform.translate(
                  offset: Offset(0, slideFrom * (1 - v)),
                  child: Opacity(opacity: v, child: child),
                );
              },
              child: GestureDetector(
                onTap: () {
                  final e = _entry!;
                  _dismiss();
                  widget.onOpenLetter(e);
                },
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < -180) _dismiss();
                },
                child: _buildBannerCard(_entry!),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBannerCard(DiaryEntry e) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(16),
      color: AppPalette.c(0xFFFFFFFF),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.c(0xFFE8EDF5)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.c(0xFFFDEEF3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('💌', style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '你给未来写的信到啦',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.c(0xFF24382F)),
                  ),
                  const SizedBox(height: 2),
                  Text('点击查看这封来自过去的信～',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppIcon(AppIcons.chevR, size: 20, color: AppPalette.c(0xFFC6D6CD)),
          ],
        ),
      ),
    );
  }
}
