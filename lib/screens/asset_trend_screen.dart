import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../models/asset_history.dart';
import '../services/asset_history_storage.dart';
import '../services/asset_storage.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
import '../utils/app_motion.dart';
import '../utils/haptics.dart';
import '../widgets/app_icons.dart';
import '../widgets/asset_trend_chart.dart';
import '../widgets/entry_icon.dart';

/// 资产趋势（VIP 权益）：按天快照的折线图 + 更新记录明细。
///
/// 入口在资产页设置里，由调用方做 VIP 判定；本页只负责展示与记录删除。
class AssetTrendScreen extends StatefulWidget {
  /// 仅供测试：注入历史记录加载（跳过 path_provider / dart:io）。
  final Future<List<AssetHistoryEntry>> Function()? loadHistoryOverride;

  /// 仅供测试：注入当前资产列表（用于历史为空时的基线种子）。
  final Future<List<Asset>> Function()? loadAssetsOverride;

  const AssetTrendScreen({
    Key? key,
    this.loadHistoryOverride,
    this.loadAssetsOverride,
  }) : super(key: key);

  @override
  State<AssetTrendScreen> createState() => _AssetTrendScreenState();
}

class _AssetTrendScreenState extends State<AssetTrendScreen> {
  List<AssetHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final assets = await (widget.loadAssetsOverride ?? AssetStorage.load)();
    // 历史为空且从未建过基线：用当前资产建立当日起点（折线图才有第一个点）。
    // 测试注入了历史/资产时跳过真实 seed（避免 dart:io），保持注入数据不变。
    if (widget.loadHistoryOverride == null && widget.loadAssetsOverride == null) {
      await AssetHistoryStorage.seedIfEmpty(assets);
    }
    final entries =
        await (widget.loadHistoryOverride ?? AssetHistoryStorage.load)();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  /// 按天分组（最新在前），同一天内保持存储顺序（最新在前）。
  List<_DayGroup> _groupByDay() {
    final groups = <_DayGroup>[];
    for (final e in _entries) {
      final key = '${e.time.year}-${e.time.month.toString().padLeft(2, '0')}-${e.time.day.toString().padLeft(2, '0')}';
      if (groups.isEmpty || groups.last.key != key) {
        groups.add(_DayGroup(key, [e]));
      } else {
        groups.last.entries.add(e);
      }
    }
    return groups;
  }

  /// 按天聚合：同一天多次调整只取「当天最后一次」快照打点。
  /// 用户要求「以天为纬度在折线图打点」，因此每天恰好一个点。
  List<TrendPoint> _chartPoints() {
    final seenDays = <String>{};
    final points = <TrendPoint>[];
    // _entries 最新在前：同一天遇到的第一条即当天最后一次调整。
    for (final e in _entries) {
      final key = '${e.time.year}-${e.time.month.toString().padLeft(2, '0')}-${e.time.day.toString().padLeft(2, '0')}';
      if (seenDays.contains(key)) continue;
      seenDays.add(key);
      points.add(TrendPoint(
        time: e.time,
        totalAssets: e.totalAssets,
        totalDebt: e.totalDebt,
      ));
    }
    // 图表需要时间升序。
    points.sort((a, b) => a.time.compareTo(b.time));
    return points;
  }

  /// 按条删除：点击/长按某一笔改动后确认删除。
  ///
  /// v5.0.17 修复：删除后先即时更新内存并 setState，让用户立刻看到结果；
  /// 不再调用含 seedIfEmpty 的 _load()（真机上若 seed 标记缺失会重新插回基线，
  /// 表现为「删了又出现」）。落盘失败也不影响本次 UI 反馈。
  Future<void> _deleteChange(AssetHistoryEntry e, int changeIndex) async {
    if (changeIndex < 0 || changeIndex >= e.changes.length) return;
    final change = e.changes[changeIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除这笔改动记录？'),
        content: Text('删除「${change.name}」这笔改动后，更新记录将同步更新。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFCB5C50))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Haptics.medium();

    // 单一删除源：由存储层按 e.id + changeIndex 删除并落盘。
    await AssetHistoryStorage.removeChange(e.id, changeIndex);

    // 直接重新读取刷新（不走 _load()：它含 seedIfEmpty，真机上若 seed 标记
    // 缺失会把刚删空的基线重新插回，表现为「删了又出现」）。
    final fresh = await (widget.loadHistoryOverride ?? AssetHistoryStorage.load)();
    if (!mounted) return;
    setState(() => _entries = fresh);
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    return Scaffold(
      backgroundColor: AppPalette.c(0xFFF5FAF7),
      appBar: AppBar(
        toolbarHeight: 48,
        backgroundColor: AppPalette.c(0xB33E8E6D),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('资产趋势'),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back),
          tooltip: '返回',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const SizedBox()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AssetTrendChart(points: _chartPoints()),
                  const SizedBox(height: 20),
                  _buildRecordsHeader(),
                  const SizedBox(height: 8),
                  if (_entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text('暂无更新记录',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppPalette.c(0xFF8FA09A))),
                      ),
                    )
                  else
                    ..._buildDayGroups(_groupByDay()),
                ],
              ),
            ),
    );
  }

  Widget _buildRecordsHeader() {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text('更新记录',
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppPalette.c(0xFF24382F))),
    );
  }

  List<Widget> _buildDayGroups(List<_DayGroup> groups) {
    final widgets = <Widget>[];
    for (final g in groups) {
      // 同一天内最新在前：索引 0 即当天最后一次调整后的净资产。
      widgets.add(_buildDayLabel(g.key, g.entries.first.netWorth));
      widgets.add(const SizedBox(height: 6));
      widgets.add(Container(
        decoration: BoxDecoration(
          color: AppPalette.c(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            for (var i = 0; i < g.entries.length; i++) ...[
              _buildEntryTile(g.entries[i]),
              if (i < g.entries.length - 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Divider(
                      height: 1, color: AppPalette.c(0xFFE6EDE9)),
                ),
            ],
          ],
        ),
      ));
      widgets.add(const SizedBox(height: 14));
    }
    return widgets;
  }

  Widget _buildDayLabel(String day, double netWorth) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppPalette.c(0xFFB7C9C0), width: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(day,
              style: TextStyle(
                  fontSize: 12, color: AppPalette.c(0xFF8FA09A))),
          const Spacer(),
          // v5.0.18：净资产显示改为与日期相同的灰色（原为红/深绿加粗）。
          Text('净资产 ${_money(netWorth)}',
              style: TextStyle(
                  fontSize: 12, color: AppPalette.c(0xFF8FA09A))),
        ],
      ),
    );
  }

  Widget _buildEntryTile(AssetHistoryEntry e) {
    // 一条记录可能含多张卡片的变更（基线种子时会有多条），逐条展开。
    // v5.0.16：删除粒度从「整条记录」改为「单笔改动」，每行独立删除。
    // v5.0.17：每行右侧新增显式删除按钮（长按也保留），解决真机长按不易触发。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < e.changes.length; i++) ...[
            _buildChangeRow(e.changes[i], onDelete: () => _deleteChange(e, i)),
            if (i < e.changes.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildChangeRow(AssetChange c, {required VoidCallback onDelete}) {
    final negative = c.amount < 0;
    final label = c.deleted ? '${c.name}（已删除）' : c.name;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // v5.0.18：长按弹出删除确认弹窗时同步震动（与全站「长按弹菜单」口径一致），
      // 先震后弹，避免部分 ROM 在 UI 切换后吞掉这次振动。
      onLongPress: () {
        Haptics.mediumNow();
        onDelete();
      },
      child: Row(
        children: [
          EntryIcon(Asset.defaultIconFor(c.type), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, color: AppPalette.c(0xFF24382F))),
                if (c.autoImported)
                  Text('自动导入',
                      style: TextStyle(
                          fontSize: 11, color: AppPalette.c(0xFF8FA09A))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(_money(c.amount),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: negative
                      ? const Color(0xFFCB5C50)
                      : AppPalette.c(0xFF24382F))),
          const SizedBox(width: 2),
          // v5.0.17：显式删除按钮，解决真机长按被滚动吞掉/无视觉提示的问题。
          InkWell(
            key: const Key('asset_trend_delete_change'),
            onTap: onDelete,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: AppIcon(AppIcons.delete,
                  size: 15, color: AppPalette.c(0xFFB2C4BA)),
            ),
          ),
        ],
      ),
    );
  }

  static String _money(double v) {
    final neg = v < 0;
    final digits = v.abs().round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '${neg ? '-' : ''}$buf';
  }
}

class _DayGroup {
  final String key;
  final List<AssetHistoryEntry> entries;
  _DayGroup(this.key, this.entries);
}
