import 'package:flutter/material.dart';
import '../theme.dart';
import '../scaffold.dart';

/// 物资清单主页骨架：统计条 → 筛选胶囊 → 双列物品卡
class UiItemsPage extends StatelessWidget {
  final UiTheme theme;
  final VoidCallback onOpenMenu;

  const UiItemsPage({Key? key, required this.theme, required this.onOpenMenu})
      : super(key: key);

  static const _items = [
    _Item('📱', 'iPhone 13', '数码设备', '¥5,999', '日均 ¥4.8', 0.72),
    _Item('💻', 'MacBook Air', '数码设备', '¥8,999', '日均 ¥8.2', 0.58),
    _Item('🎧', 'AirPods Pro', '数码设备', '¥1,899', '日均 ¥1.4', 0.86),
    _Item('⌚️', 'Apple Watch', '数码设备', '¥3,199', '日均 ¥2.6', 0.64),
    _Item('🚲', '折叠自行车', '出行', '¥2,400', '日均 ¥1.9', 0.43),
    _Item('☕️', '手冲咖啡壶', '生活', '¥398', '日均 ¥0.5', 0.91),
  ];

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      theme: theme,
      title: '物资清单',
      subtitle: 'ITEMS',
      onOpenMenu: onOpenMenu,
      actions: const [UiHeaderAction(icon: Icons.search_rounded)],
      statsBar: UiStatsBar(theme: theme, stats: const [
        UiStat('物品数', '36'),
        UiStat('总价值', '¥61,240'),
        UiStat('日均成本', '¥19.4'),
      ]),
      filterBar: SizedBox(
        height: 32,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final f in ['全部', '在役', '已遗失', '愿望单'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: UiChip(
                  theme: theme,
                  label: f,
                  selected: f == '全部',
                  onTap: () {},
                ),
              ),
          ],
        ),
      ),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.80,
          crossAxisSpacing: 11,
          mainAxisSpacing: 11,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) => _buildCard(_items[i]),
      ),
    );
  }

  Widget _buildCard(_Item it) {
    return UiCard(
      theme: theme,
      padding: const EdgeInsets.all(11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.accent.withOpacity(theme.isDark ? 0.20 : 0.08),
                  borderRadius: BorderRadius.circular(theme.cardRadius - 4),
                ),
                alignment: Alignment.center,
                child: Text(it.icon, style: const TextStyle(fontSize: 18)),
              ),
              const Spacer(),
              Icon(Icons.more_horiz, size: 16, color: theme.textTertiary),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            it.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${it.category} · ${it.price}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: theme.textTertiary),
          ),
          const SizedBox(height: 9),
          // 攒钱 / 成本进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5,
              child: Row(
                children: [
                  Expanded(
                    flex: (it.progress * 100).round(),
                    child: ColoredBox(color: theme.accent),
                  ),
                  Expanded(
                    flex: 100 - (it.progress * 100).round(),
                    child: ColoredBox(
                      color: theme.accent.withOpacity(theme.isDark ? 0.18 : 0.10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            it.unit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: theme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final String icon;
  final String name;
  final String category;
  final String price;
  final String unit;
  final double progress;
  const _Item(
      this.icon, this.name, this.category, this.price, this.unit, this.progress);
}
