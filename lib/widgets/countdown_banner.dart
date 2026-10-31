import 'package:flutter/material.dart';
import '../models/countdown_event.dart';

/// 当天有事件到期时，在任意主页顶部滑出的一次性横幅。
/// 动画：从屏幕上方平滑滑出，停在距顶部约 1/10 屏高处。
/// 交互：上滑关闭、点击进入该事件编辑页。
class CountdownBannerHost extends StatefulWidget {
  final ValueChanged<String> onOpenEvent; // 点击横幅 → 打开该事件
  final Widget child;
  const CountdownBannerHost({
    Key? key,
    required this.onOpenEvent,
    required this.child,
  }) : super(key: key);

  @override
  State<CountdownBannerHost> createState() => CountdownBannerHostState();
}

class CountdownBannerHostState extends State<CountdownBannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  CountdownEvent? _event;
  bool _shown = false; // 同一次启动只展示一次

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

  /// 由外部在数据加载完成后调用
  void showFor(CountdownEvent e) {
    if (_shown) return;
    _shown = true;
    setState(() => _event = e);
    _ctrl.forward();
  }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _event = null);
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
        if (_event != null)
          Positioned(
            top: top,
            left: 14,
            right: 14,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                final v = Curves.easeOutCubic.transform(
                    _ctrl.value.clamp(0.0, 1.0));
                return Transform.translate(
                  offset: Offset(0, slideFrom * (1 - v)),
                  child: Opacity(opacity: v, child: child),
                );
              },
              child: GestureDetector(
                onTap: () {
                  final id = _event!.id;
                  _dismiss();
                  widget.onOpenEvent(id);
                },
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < -180) _dismiss();
                },
                child: _buildBannerCard(_event!),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBannerCard(CountdownEvent e) {
    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(18),
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8EDF5)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFDEEF3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(e.icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2A3B52))),
                  const SizedBox(height: 2),
                  const Text('不要忘记重要的日子哦～',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: Color(0xFF9AA8BF))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFFC4CEDD)),
          ],
        ),
      ),
    );
  }
}
