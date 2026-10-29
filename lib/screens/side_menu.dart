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
  final String currentTab; // 'diary' | 'items' | 'assets' | 'countdown'

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
    required this.currentTab,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final nickname = profile.nickname.isEmpty ? '未设置昵称' : profile.nickname;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          // 头像 / 昵称 / UID 统一左对齐，与下方导航项左边缘对齐
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
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
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFE8EDF5)),
          const SizedBox(height: 8),
          _buildGlobalSearchButton(),
          const SizedBox(height: 4),
          _buildTabSwitcher(),
          const Spacer(),
          const Divider(height: 1, color: Color(0xFFE8EDF5)),
          _buildSettingsButton(),
        ],
      ),
    );
  }

  Widget _buildGlobalSearchButton() {
    // 与导航选项卡同款排版：同宽度（horizontal 12）、同高度 52、同圆角 10
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenGlobalSearch,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.search_rounded,
                    size: 22, color: Color(0xFF5A6B82)),
                const SizedBox(width: 12),
                const Text(
                  '全局搜索',
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
      ),
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

  Widget _buildTabSwitcher() {
    const tabHeight = 52.0;
    const gap = 8.0;
    const tabs = ['diary', 'items', 'countdown', 'assets'];
    final selectedIndex = tabs.indexOf(currentTab).clamp(0, 3);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: tabHeight * 4 + gap * 3,
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
                _buildTabItem(
                  icon: Icons.book_outlined,
                  label: '写日记',
                  selected: currentTab == 'diary',
                  onTap: onOpenDiary,
                  height: tabHeight,
                ),
                const SizedBox(height: gap),
                _buildTabItem(
                  icon: Icons.inventory_2_outlined,
                  label: '物品清单',
                  selected: currentTab == 'items',
                  onTap: onOpenItems,
                  height: tabHeight,
                ),
                const SizedBox(height: gap),
                _buildTabItem(
                  icon: Icons.event_available_outlined,
                  label: '重要事件',
                  selected: currentTab == 'countdown',
                  onTap: onOpenCountdown,
                  height: tabHeight,
                ),
                const SizedBox(height: gap),
                _buildTabItem(
                  icon: Icons.account_balance_outlined,
                  label: '资产全景',
                  selected: currentTab == 'assets',
                  onTap: onOpenAssets,
                  height: tabHeight,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem({
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
}
