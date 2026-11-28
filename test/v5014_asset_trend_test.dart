import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/asset_history.dart';
import 'package:ayodiray/screens/asset_trend_screen.dart';
import 'package:ayodiray/services/asset_history_storage.dart';
import 'package:ayodiray/widgets/asset_trend_chart.dart';

AssetHistoryEntry _entry({
  required String id,
  required DateTime time,
  required double assets,
  required double debt,
  String name = '微信',
}) =>
    AssetHistoryEntry(
      id: id,
      time: time,
      changes: [
        AssetChange(name: name, type: '银行储蓄', amount: assets > 0 ? assets : debt)
      ],
      totalAssets: assets,
      totalDebt: debt,
      netWorth: assets + debt,
    );

void main() {
  setUp(() => AssetHistoryStorage.resetForTest());
  tearDown(() => AssetHistoryStorage.resetForTest());

  test('按天快照：storage 追加后最新在前', () async {
    AssetHistoryStorage.loadOverride = [];
    final now = DateTime.now();
    await AssetHistoryStorage.append(
        _entry(id: 'a', time: now, assets: 100, debt: 0));
    await AssetHistoryStorage.append(
        _entry(id: 'b', time: now.add(const Duration(seconds: 1)),
            assets: 200, debt: -50));
    final list = AssetHistoryStorage.loadOverride!;
    expect(list.first.id, 'b');
    expect(list.first.totalAssets, 200);
    expect(list.first.totalDebt, -50);
  });

  test('长按删除：removeById 只移除指定记录', () async {
    AssetHistoryStorage.loadOverride = [
      _entry(id: 'a', time: DateTime.now(), assets: 100, debt: 0),
      _entry(id: 'b', time: DateTime.now(), assets: 200, debt: 0),
    ];
    await AssetHistoryStorage.removeById('a');
    expect(AssetHistoryStorage.loadOverride!.length, 1);
    expect(AssetHistoryStorage.loadOverride!.first.id, 'b');
  });

  test('TrendRange 时间范围口径', () {
    final now = DateTime(2026, 11, 28);
    expect(TrendRange.threeMonths.cutoff(now),
        now.subtract(const Duration(days: 90)));
    expect(TrendRange.thisYear.cutoff(now), DateTime(2026, 1, 1));
  });

  testWidgets('趋势页渲染：折线图 + 更新记录 + 底部说明', (tester) async {
    final now = DateTime.now();
    AssetHistoryStorage.loadOverride = [
      _entry(id: 'a', time: now, assets: 38609, debt: -1075),
      _entry(id: 'b', time: now.subtract(const Duration(days: 5)),
          assets: 28000, debt: -921),
    ];
    await tester.pumpWidget(MaterialApp(
      home: AssetTrendScreen(
        loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
        loadAssetsOverride: () async => [],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('资产趋势'), findsOneWidget);
    expect(find.text('更新记录'), findsOneWidget);
    expect(find.textContaining('全资产'), findsWidgets);
    expect(find.textContaining('负债'), findsWidgets);
    expect(find.text('本页面包含手工录入数据，不作为对账凭证。'), findsOneWidget);
    // 时间范围四个标签
    for (final label in ['近3月', '近6月', '今年', '近1年']) {
      expect(find.text(label), findsOneWidget);
    }
    // 两条金额记录（千分位）；负债金额出现在 info bar 拼接文本中
    expect(find.text('38,609'), findsWidgets);
    expect(find.textContaining('-1,075'), findsWidgets);
  });

  testWidgets('空历史且无资产：显示空态，不报错', (tester) async {
    AssetHistoryStorage.loadOverride = [];
    await tester.pumpWidget(MaterialApp(
      home: AssetTrendScreen(
        loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
        loadAssetsOverride: () async => [],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('暂无更新记录'), findsOneWidget);
    expect(find.text('该时间段暂无资产变动记录'), findsOneWidget);
  });

  testWidgets('切换时间范围：点击近3月后选中态变化', (tester) async {
    final now = DateTime.now();
    AssetHistoryStorage.loadOverride = [
      _entry(id: 'a', time: now, assets: 1000, debt: 0),
    ];
    await tester.pumpWidget(MaterialApp(
      home: AssetTrendScreen(
        loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
        loadAssetsOverride: () async => [],
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('近3月'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  /// v5.0.14 资产页集成点：设置入口 + VIP 门控 + 变更记录注入。
  /// 项目惯例：用源码静态断言，避免启动整个 AssetScreen（依赖 dart:io 存储）。
  group('v5.0.14 资产页集成点', () {
  final root = Directory.current.path;
  final assetSrc =
      File('$root/lib/screens/asset_screen.dart').readAsStringSync();

  test('设置弹层含「资产趋势」VIP 入口', () {
    expect(assetSrc, contains("Text('资产趋势'"),
        reason: '设置弹层应有资产趋势入口标题');
    expect(assetSrc, contains('badge: UserProfile.badgeVip'),
        reason: '入口应带 VIP 标识');
  });

  test('VIP 未解锁走统一提示', () {
    expect(assetSrc, contains("AppToast.vipRequired(context, '资产趋势')"),
        reason: '非 VIP 点击应弹统一权益提示');
  });

  test('三处资产变更均注入历史记录', () {
    // openNewAsset / _openEditor / 长按删除 三个落盘点
    expect(assetSrc, contains('_recordAssetChange'),
        reason: '应有统一变更记录辅助方法');
    final count = '_recordAssetChange('.allMatches(assetSrc).length;
    expect(count, greaterThanOrEqualTo(3),
        reason: '新增/编辑/删除三处都应记录变更，实际 $count 处');
  });
  });
}
