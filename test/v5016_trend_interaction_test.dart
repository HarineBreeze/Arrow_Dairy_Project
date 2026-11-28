import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/asset_history.dart';
import 'package:ayodiray/screens/asset_trend_screen.dart';
import 'package:ayodiray/services/asset_history_storage.dart';

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
        AssetChange(name: name, type: '银行储蓄', amount: assets > 0 ? assets : debt),
        AssetChange(name: '支付宝', type: '银行储蓄', amount: -debt),
      ],
      totalAssets: assets,
      totalDebt: debt,
      netWorth: assets + debt,
    );

void main() {
  setUp(() => AssetHistoryStorage.resetForTest());
  tearDown(() => AssetHistoryStorage.resetForTest());

  group('v5.0.16 图例去金额 + 点击点小窗', () {
    testWidgets('图例只有类型名无金额；点击折线图弹小窗显示三项金额', (tester) async {
      final now = DateTime.now();
      AssetHistoryStorage.loadOverride = [
        _entry(id: 'a', time: now, assets: 38609, debt: -1075),
      ];
      await tester.pumpWidget(MaterialApp(
        home: AssetTrendScreen(
          loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
          loadAssetsOverride: () async => [],
        ),
      ));
      await tester.pumpAndSettle();

      // 三个类型名图例各一处；图例区无金额（负债金额此时不应出现）
      expect(find.textContaining('全资产'), findsWidgets);
      expect(find.textContaining('净资产'), findsWidgets);
      expect(find.textContaining('负债'), findsWidgets);
      expect(find.textContaining('-1,075'), findsNothing,
          reason: '图例不再显示金额，负债金额应只在点击后的小窗出现');

      // 点击折线图区域 → 弹小窗
      await tester.tap(find.byKey(const Key('asset_trend_chart_tap')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 小窗里现在有负债金额
      expect(find.textContaining('-1,075'), findsWidgets,
          reason: '点击某日点后小窗应显示该日三项金额');
    });

    test('源码：汇总条图例不含金额拼接，tooltip 含三项金额', () {
      final root = Directory.current.path;
      final src =
          File('$root/lib/widgets/asset_trend_chart.dart').readAsStringSync();
      expect(src, contains('_legendLabel(_kAssetColor'),
          reason: '图例改为仅类型名');
      expect(src, contains('Widget _buildTooltip(TrendPoint p)'),
          reason: '应有点击点小窗构建方法');
      expect(src, contains('_tipRow(_kDebtColor'),
          reason: '小窗应显示负债金额');
    });
  });

  group('v5.0.16 日期栏净资产', () {
    testWidgets('日期行右侧显示当日调整后净资产', (tester) async {
      final now = DateTime.now();
      AssetHistoryStorage.loadOverride = [
        _entry(id: 'a', time: now, assets: 38609, debt: -1075),
      ];
      await tester.pumpWidget(MaterialApp(
        home: AssetTrendScreen(
          loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
          loadAssetsOverride: () async => [],
        ),
      ));
      await tester.pumpAndSettle();
      // 净资产 = 38609 - 1075 = 37534
      expect(find.textContaining('37,534'), findsWidgets,
          reason: '日期栏应显示当日调整后净资产');
    });
  });

  group('v5.0.16 按条删除', () {
    test('removeChange：只删指定笔，删空则移除整条，不重算快照', () async {
      final now = DateTime.now();
      AssetHistoryStorage.loadOverride = [_entry(id: 'a', time: now, assets: 100, debt: 0)];
      // 该 entry 有 2 笔 change（微信 100 / 支付宝 0）
      expect(AssetHistoryStorage.loadOverride!.first.changes.length, 2);

      await AssetHistoryStorage.removeChange('a', 0);
      expect(AssetHistoryStorage.loadOverride!.length, 1);
      expect(AssetHistoryStorage.loadOverride!.first.changes.length, 1);
      expect(AssetHistoryStorage.loadOverride!.first.changes.first.name, '支付宝');
      // 快照不重算
      expect(AssetHistoryStorage.loadOverride!.first.netWorth, 100);

      await AssetHistoryStorage.removeChange('a', 0);
      expect(AssetHistoryStorage.loadOverride, isEmpty,
          reason: 'changes 删空后整条移除');
    });

    test('源码：确认文案改为按条删除，长按绑定在单行', () {
      final root = Directory.current.path;
      final src = File('$root/lib/screens/asset_trend_screen.dart')
          .readAsStringSync();
      expect(src, contains("const Text('删除这笔改动记录？')"),
          reason: '确认文案应改为按条删除');
      expect(src, contains('removeChange(e.id, changeIndex)'),
          reason: '应调用按条删除');
    });
  });
}
