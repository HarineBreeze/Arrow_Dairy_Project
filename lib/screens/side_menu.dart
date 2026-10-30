import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../utils/app_version.dart';
import '../widgets/avatar.dart';

class SideMenu extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onClose;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenDiary;
  final VoidCallback onOpenItems;
  final VoidCallback onOpenAssets;
  final VoidCallback onOpenCountdown;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenGlobalSearch;
  final VoidCallback onOpenTrash;
  final String currentTab; // 'search' | 'diary' | 'items' | 'countdown' | 'assets' | 'trash'

  const SideMenu({
    Key? key,
    required this.profile,
    required this.onClose,
    required this.onOpenProfile,
    required this.onOpenDiary,
    required this.onOpenItems,
    required this.onOpenAssets,
    required this.onOpenCountdown,
    required this.onOpenSettings,
    required this.onOpenGlobalSearch,
    required this.onOpenTrash,
    required this.currentTab,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final nickname = profile.nickname.isEmpty ? '未设置昵称' : profile.nickname;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：头像 / 昵称 / UID（固定不滚动）
          _buildHeader(nickname),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE8EDF5)),
          const SizedBox(height: 8),
          // 导航区：条目较多（全局搜索 + 4 个主页 + 回收站），
          // 小屏或大字体下可滚动，避免纵向溢出
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: _buildNavStack(),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EDF5)),
          _buildSettingsButton(),
        ],
      ),
    );
  }

  /// 头像 / 昵称（含内测版铭牌）/ UID，统一左对齐
  Widget _buildHeader(String nickname) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onOpenProfile,
          child: Padding(
            padding: const EdgeInsets.only(left: 28),
            child: buildAppAvatar(profile, radius: 42),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 28, right: 20),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2A3B52),
                  ),
                ),
              ),
              if (AppVersion.isBeta) ...[
                const SizedBox(width: 6),
                // 内测版铭牌：橙色底纹 + 白字，紧跟昵称之后
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF08C3A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '内测版',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 用户 ID：暂用固定值，后续接入服务器后再按规则生成
        const Padding(
          padding: EdgeInsets.only(left: 28, right: 20),
          child: Text(
            'ID：10001',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF9AA8BF),
            ),
          ),
        ),
      ],
    );
  }

  /// 侧栏导航整体（全局搜索 + 4 个主页 + 回收站）：
  /// 高亮底纹共用一个 AnimatedPositioned 块，点击任意项时
  /// 底纹从当前块平滑滑动到目标块。
  Widget _buildNavStack() {
    const tabHeight = 52.0;
    const gap = 8.0;
    final items = <_NavItem>[
      _NavItem(Icons.search_rounded, '全局搜索', 'search', onOpenGlobalSearch),
      _NavItem(Icons.book_outlined, '写日记', 'diary', onOpenDiary),
      _NavItem(Icons.inventory_2_outlined, '物品清单', 'items', onOpenItems),
      _NavItem(Icons.event_available_outlined, '重要事件', 'countdown',
          onOpenCountdown),
      _NavItem(Icons.account_balance_outlined, '资产全景', 'assets',
          onOpenAssets),
      _NavItem(Icons.delete_outline, '回收站', 'trash', onOpenTrash),
    ];
    final selectedIndex =
        items.indexWhere((n) => n.key == currentTab).clamp(0, items.length - 1);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: tabHeight * items.length + gap * (items.length - 1),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              top: selectedIndex * (tabHeight + gap),
              left: 0,
              right: 0,
              height: tabHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xB33B6FE0),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: gap),
                  _buildNavItem(
                    icon: items[i].icon,
                    label: items[i].label,
                    selected: i == selectedIndex,
                    onTap: items[i].onTap,
                    height: tabHeight,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required double height,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final iconColor = Color.lerp(const Color(0xFF3B6FE0), Colors.white, t)!;
        final textColor = Color.lerp(const Color(0xFF2A3B52), Colors.white, t)!;
        return SizedBox(
          height: height,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(icon, color: iconColor, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      color: textColor,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

  Widget _buildSettingsButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpenSettings,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              const SizedBox(width: 16),
              const Icon(Icons.settings_outlined,
                  size: 22, color: Color(0xFF5A6B82)),
              const SizedBox(width: 12),
              const Text(
                '设置',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF2A3B52),
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFFC4CEDD)),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// 侧栏导航项数据（全局搜索 + 主页 + 回收站统一结构）
class _NavItem {
  final IconData icon;
  final String label;
  final String key;
  final VoidCallback onTap;
  const _NavItem(this.icon, this.label, this.key, this.onTap);
}
