import 'package:flutter/material.dart';
import 'theme.dart';

/// 侧边栏骨架：四套方案统一布局（头像区 → 分隔 → 导航列表 → 底部设置），
/// 仅视觉语言不同：选中态表达、配色、分隔形态。
class UiSideBar extends StatelessWidget {
  final UiTheme theme;
  final String nickname;
  final String uid;
  final String currentTab;
  final ValueChanged<String> onSelectTab;
  final VoidCallback onTapProfile;
  final VoidCallback onOpenSettings;

  const UiSideBar({
    Key? key,
    required this.theme,
    required this.nickname,
    required this.uid,
    required this.currentTab,
    required this.onSelectTab,
    required this.onTapProfile,
    required this.onOpenSettings,
  }) : super(key: key);

  static const tabs = <_TabSpec>[
    _TabSpec('diary', Icons.edit_note_rounded, '写日记', '记录今天'),
    _TabSpec('items', Icons.inventory_2_outlined, '物资清单', '物品与攒钱'),
    _TabSpec('countdown', Icons.event_available_outlined, '倒数日', '纪念与资产日'),
    _TabSpec('assets', Icons.account_balance_outlined, '资产全景', '正负资产总览'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.menuBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 34),
          _buildProfile(),
          const SizedBox(height: 26),
          _divider(),
          const SizedBox(height: 10),
          for (final t in tabs) Flexible(child: _buildTabItem(t)),
          const Spacer(),
          _divider(),
          _buildSettings(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 18),
        color: theme.divider,
      );

  Widget _buildProfile() {
    return InkWell(
      onTap: onTapProfile,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: theme.headerGradient,
                borderRadius: BorderRadius.circular(theme.cardRadius + 4),
              ),
              alignment: Alignment.center,
              child: const Text(
                '矢',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    uid,
                    style: TextStyle(fontSize: 11.5, color: theme.textTertiary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: theme.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(_TabSpec t) {
    final selected = currentTab == t.id;
    final fg = selected ? theme.accent : theme.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? theme.accent.withOpacity(theme.isDark ? 0.20 : 0.09) : Colors.transparent,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        child: InkWell(
          onTap: () => onSelectTab(t.id),
          borderRadius: BorderRadius.circular(theme.cardRadius),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // 选中标记：左侧竖条（A/B）或圆点（C/D 由 isDark 控制）
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 3,
                  height: selected ? 20 : 0,
                  margin: const EdgeInsets.only(right: 11),
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(t.icon, size: 21, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? theme.textPrimary : theme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: theme.textTertiary),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_rounded, size: 16, color: theme.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return InkWell(
      onTap: onOpenSettings,
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            const SizedBox(width: 24),
            Icon(Icons.settings_outlined, size: 20, color: theme.textSecondary),
            const SizedBox(width: 12),
            Text(
              '设置',
              style: TextStyle(fontSize: 14, color: theme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSpec {
  final String id;
  final IconData icon;
  final String label;
  final String sub;
  const _TabSpec(this.id, this.icon, this.label, this.sub);
}
