import 'package:flutter/material.dart';
import '../theme.dart';
import '../scaffold.dart';

/// 倒数日主页骨架：分组头 + 日期大数字卡片
class UiCountdownPage extends StatelessWidget {
  final UiTheme theme;
  final VoidCallback onOpenMenu;

  const UiCountdownPage(
      {Key? key, required this.theme, required this.onOpenMenu})
      : super(key: key);

  static const _groups = <String, List<_Event>>{
    '置顶': [
      _Event('💍', '结婚纪念日', '距离一周年还有', 42, '2026-12-09', true),
    ],
    '纪念日': [
      _Event('🎓', '毕业日', '已经过去', 1380, '2022-02-18', false),
      _Event('🎂', '我的生日', '距离下次生日还有', 27, '2026-11-23', false),
    ],
    '资产日': [
      _Event('🏠', '买房日', '已经过去', 210, '2026-04-01', false),
      _Event('💰', '发工资', '距离下次还有', 5, '2026-11-01', false),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      theme: theme,
      title: '倒数日',
      subtitle: 'COUNTDOWN',
      onOpenMenu: onOpenMenu,
      actions: const [
        UiHeaderAction(icon: Icons.calendar_today_rounded),
        UiHeaderAction(icon: Icons.search_rounded),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          for (final g in _groups.entries) ...[
            UiSectionHeader(
              theme: theme,
              title: g.key,
              count: g.value.length,
              dotColor: g.key == '置顶'
                  ? const Color(0xFFF2A0C0)
                  : (g.key == '资产日'
                      ? const Color(0xFF9BC2F0)
                      : const Color(0xFFA9D8B8)),
            ),
            for (final e in g.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildCard(e),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(_Event e) {
    return UiCard(
      theme: theme,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.accent.withOpacity(theme.isDark ? 0.20 : 0.08),
              borderRadius: BorderRadius.circular(theme.cardRadius - 2),
            ),
            alignment: Alignment.center,
            child: Text(e.icon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: theme.textPrimary,
                        ),
                      ),
                    ),
                    if (e.pinned)
                      Icon(Icons.push_pin_outlined,
                          size: 13, color: theme.danger),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${e.prefix} · ${e.date}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: theme.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧天数固定最大宽度：数字过大时整体缩放，避免把卡片撑破。
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 62),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${e.days}',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 26,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: theme.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text('天',
                    maxLines: 1,
                    style:
                        TextStyle(fontSize: 10.5, color: theme.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Event {
  final String icon;
  final String name;
  final String prefix;
  final int days;
  final String date;
  final bool pinned;
  const _Event(
      this.icon, this.name, this.prefix, this.days, this.date, this.pinned);
}
