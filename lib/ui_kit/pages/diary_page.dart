import 'package:flutter/material.dart';
import '../theme.dart';
import '../scaffold.dart';

/// 笔记主页骨架：置顶横滑卡带 → 分组列表（时间分组 + 笔记卡）
class UiDiaryPage extends StatelessWidget {
  final UiTheme theme;
  final VoidCallback onOpenMenu;

  const UiDiaryPage({Key? key, required this.theme, required this.onOpenMenu})
      : super(key: key);

  static const _pinned = [
    _Note('结婚纪念日', '今天去把戒指取回来，顺便吃顿好的。', '10-12', true),
    _Note('生日愿望清单', '想去看一次极光，攒钱中。', '10-08', false),
    _Note('搬家清单', '书桌、台灯、地毯…慢慢来。', '09-30', false),
  ];

  static const _groups = <String, List<_Note>>{
    '今天': [
      _Note('今天的小事', '早上起得早，路上有雾，像一层薄纱。', '07:40', false),
      _Note('读到一句话', '「把日子过成自己喜欢的形状。」', '01:12', false),
    ],
    '昨天': [
      _Note('关于攒钱的一点想法', '每次滑一下就存一点，比强迫自己记账轻松。', '22:10', false),
      _Note('晚饭', '楼下那家面，加了个蛋。', '19:30', false),
    ],
    '本周': [
      _Note('周末计划', '整理房间、看部电影、去公园走走。', '10-26', false),
    ],
  };

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      theme: theme,
      title: '笔记',
      subtitle: 'DIARY',
      onOpenMenu: onOpenMenu,
      actions: const [
        UiHeaderAction(icon: Icons.search_rounded),
        UiHeaderAction(icon: Icons.tune_rounded),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 100),
        children: [
          _buildPinnedRail(),
          const SizedBox(height: 8),
          for (final g in _groups.entries) ..._buildGroup(g.key, g.value),
        ],
      ),
    );
  }

  Widget _buildPinnedRail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
          child: Row(
            children: [
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                  color: theme.danger,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '置顶 ${_pinned.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '左右滑动',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: theme.textTertiary),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            itemCount: _pinned.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final n = _pinned[i];
              return Container(
                width: 176,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardBg,
                  borderRadius: BorderRadius.circular(theme.cardRadius),
                  border: Border.all(
                    color: n.encrypted
                        ? theme.danger.withOpacity(0.45)
                        : (theme.cardBorder ?? theme.divider),
                  ),
                  boxShadow: theme.isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          n.encrypted ? Icons.lock_outline : Icons.push_pin_outlined,
                          size: 13,
                          color: n.encrypted ? theme.danger : theme.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            n.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Text(
                        n.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: theme.textTertiary,
                        ),
                      ),
                    ),
                    Text(
                      n.time,
                      style: TextStyle(fontSize: 10, color: theme.textTertiary),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildGroup(String title, List<_Note> notes) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
        child: UiSectionHeader(
          theme: theme,
          title: title,
          count: notes.length,
          dotColor: theme.accent,
        ),
      ),
      for (final n in notes)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
          child: UiCard(
            theme: theme,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: theme.accent.withOpacity(theme.isDark ? 0.20 : 0.09),
                    borderRadius: BorderRadius.circular(theme.cardRadius - 4),
                  ),
                  alignment: Alignment.center,
                  child: Text('📝', style: const TextStyle(fontSize: 16)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                                color: theme.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // 窄卡片下先压缩时间，标题保底可见
                          Flexible(
                            child: Text(
                              n.time,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        n.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: theme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}

class _Note {
  final String title;
  final String excerpt;
  final String time;
  final bool encrypted;
  const _Note(this.title, this.excerpt, this.time, this.encrypted);
}
