import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../widgets/avatar.dart';

class SideMenu extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onClose;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenDiary;
  final VoidCallback onOpenItems;
  final String currentTab; // 'diary' | 'items'

  const SideMenu({
    Key? key,
    required this.profile,
    required this.onClose,
    required this.onOpenProfile,
    required this.onOpenDiary,
    required this.onOpenItems,
    required this.currentTab,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final nickname =
        profile.nickname.isEmpty ? '未设置昵称' : profile.nickname;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          Center(
            child: GestureDetector(
              onTap: onOpenProfile,
              child: buildAppAvatar(profile, radius: 42),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              nickname,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2A3B52),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFE8EDF5)),
          const SizedBox(height: 8),
          _buildTabSwitcher(),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    const tabHeight = 52.0;
    const gap = 8.0;
    final selectedIndex = currentTab == 'diary' ? 0 : 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: tabHeight * 2 + gap,
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
                  label: '日记',
                  selected: currentTab == 'diary',
                  onTap: onOpenDiary,
                  height: tabHeight,
                ),
                const SizedBox(height: gap),
                _buildTabItem(
                  icon: Icons.inventory_2_outlined,
                  label: '物资清单',
                  selected: currentTab == 'items',
                  onTap: onOpenItems,
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
        final iconColor =
            Color.lerp(const Color(0xFF3B6FE0), Colors.white, t)!;
        final textColor =
            Color.lerp(const Color(0xFF2A3B52), Colors.white, t)!;
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
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
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
