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
          _buildTab(
            icon: Icons.book_outlined,
            label: '日记',
            selected: currentTab == 'diary',
            onTap: onOpenDiary,
          ),
          const SizedBox(height: 4),
          _buildTab(
            icon: Icons.inventory_2_outlined,
            label: '物资清单',
            selected: currentTab == 'items',
            onTap: onOpenItems,
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? const Color(0xB33B6FE0) : Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: selected ? Colors.white : const Color(0xFF3B6FE0),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: selected ? Colors.white : const Color(0xFF2A3B52),
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
