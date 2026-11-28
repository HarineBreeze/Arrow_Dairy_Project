import 'app_icons.dart';
import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../theme/app_palette.dart';

/// v5.0.21 负资产还款到期时，在任意主页顶部滑出的一次性横幅。
/// 动画与交互与 CountdownBannerHost 一致：上方滑出、上滑关闭、点击进入资产编辑。
class AssetRepayBannerHost extends StatefulWidget {
  final ValueChanged<String> onOpenAsset;
  final Widget child;
  const AssetRepayBannerHost({
    Key? key,
    required this.onOpenAsset,
    required this.child,
  }) : super(key: key);

  @override
  State<AssetRepayBannerHost> createState() => AssetRepayBannerHostState();
}

class AssetRepayBannerHostState extends State<AssetRepayBannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Asset? _asset;
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

  void showFor(Asset a) {
    if (_shown) return;
    _shown = true;
    setState(() => _asset = a);
    _ctrl.forward();
  }

  void _dismiss() {
    _ctrl.reverse().then((_) {
      if (mounted) setState(() => _asset = null);
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
        if (_asset != null)
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
                  final id = _asset!.id;
                  _dismiss();
                  widget.onOpenAsset(id);
                },
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < -180) _dismiss();
                },
                child: _buildBannerCard(_asset!),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBannerCard(Asset a) {
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
                color: AppPalette.c(0xFFE4F2EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(a.icon, style: const TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${a.owner}的${a.type}该还款啦',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.c(0xFF24382F))),
                  const SizedBox(height: 2),
                  Text('今天别忘了处理哦～',
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
