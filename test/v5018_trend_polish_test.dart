import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/asset.dart';
import 'package:ayodiray/models/asset_history.dart';
import 'package:ayodiray/screens/asset_trend_screen.dart';
import 'package:ayodiray/services/asset_history_storage.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/widgets/asset_pie_card.dart';

AssetHistoryEntry _entry({
  required String id,
  required DateTime time,
  required double assets,
  required double debt,
}) =>
    AssetHistoryEntry(
      id: id,
      time: time,
      changes: [
        AssetChange(name: '微信', type: '银行储蓄', amount: assets),
      ],
      totalAssets: assets,
      totalDebt: debt,
      netWorth: assets + debt,
    );

void main() {
  setUp(() => AssetHistoryStorage.resetForTest());
  tearDown(() => AssetHistoryStorage.resetForTest());

  final root = Directory.current.path;
  final trendSrc =
      File('$root/lib/screens/asset_trend_screen.dart').readAsStringSync();
  final chartSrc =
      File('$root/lib/widgets/asset_trend_chart.dart').readAsStringSync();
  final assetSrc =
      File('$root/lib/screens/asset_screen.dart').readAsStringSync();
  final pieSrc =
      File('$root/lib/widgets/asset_pie_card.dart').readAsStringSync();

  group('v5.0.18 ① 日期栏净资产改灰色', () {
    testWidgets('日期行净资产文字颜色与日期相同（灰色 0xFF8FA09A）', (tester) async {
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

      // 找到净资产那一行的 Text，断言其颜色为与日期一致的灰色。
      final netText = tester.widget<Text>(find.text('净资产 37,534').first);
      expect(netText.style?.color, AppPalette.c(0xFF8FA09A),
          reason: '净资产显示应改为和日期相同的灰色');
      // 日期文字本身也是该灰色，二者一致。
      final dayText = tester.widget<Text>(
          find.text('${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'));
      expect(dayText.style?.color, netText.style?.color);
    });

    test('源码：日期栏净资产不再用红色/加粗', () {
      // _buildDayLabel 内不应再出现 negative 判断与红色常量。
      final dayLabel = trendSrc.substring(
          trendSrc.indexOf('Widget _buildDayLabel'),
          trendSrc.indexOf('Widget _buildEntryTile'));
      expect(dayLabel, isNot(contains('negative')),
          reason: '净资产不应再按正负着色');
      expect(dayLabel, isNot(contains('FontWeight.w600')),
          reason: '净资产不应再加粗');
      expect(dayLabel, isNot(contains('0xFFCB5C50')),
          reason: '净资产不应再用红色');
    });
  });

  group('v5.0.18 ② 移除底部提示语', () {
    test('源码：底部提示语已移除', () {
      expect(trendSrc, isNot(contains('本页面包含手工录入数据')),
          reason: '资产趋势页底部提示语应移除');
      expect(trendSrc, isNot(contains('_buildTipText')),
          reason: '提示语构建方法应一并删除');
    });

    testWidgets('页面不再渲染旧底部提示语', (tester) async {
      AssetHistoryStorage.loadOverride = [
        _entry(id: 'a', time: DateTime.now(), assets: 100, debt: 0),
      ];
      await tester.pumpWidget(MaterialApp(
        home: AssetTrendScreen(
          loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
          loadAssetsOverride: () async => [],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('本页面包含手工录入数据，不作为对账凭证。'), findsNothing);
    });
  });

  group('v5.0.18 ③ 全资产/负债改虚线', () {
    test('源码：全资产与负债线 dashed=true，净资产仍实线', () {
      // 两处虚线：全资产(totalAssets) 与 负债(totalDebt.abs())
      final dashedCount = '(p) => p.totalAssets, dashed: true'.allMatches(chartSrc).length +
          '(p) => p.totalDebt.abs(), dashed: true'.allMatches(chartSrc).length;
      expect(dashedCount, 2, reason: '全资产与负债两条线应改为虚线');
      // 净资产线不带 dashed 参数，保持实线
      expect(chartSrc, contains('(p) => p.netWorth);'),
          reason: '净资产线应保持实线');
      // painter 支持 dashed 参数并有虚线路径绘制
      expect(chartSrc, contains('bool dashed = false'),
          reason: '_drawStepLine 应支持虚线开关');
      expect(chartSrc, contains('computeMetrics()'),
          reason: '虚线应通过 path 度量逐段绘制');
    });
  });

  group('v5.0.18 ⑤ 最新资产节点放最右侧', () {
    test('源码：painter 与两处定位口径单点时取 right', () {
      // xOf / _nearestIndex / _tooltipLeft 三处均应把 span<=0 的 x 取 right
      final rightFallback = '? right'.allMatches(chartSrc).length;
      expect(rightFallback, greaterThanOrEqualTo(3),
          reason: 'painter/点击定位/tooltip 定位都应在单点时取最右侧');
      expect(chartSrc, isNot(contains('? left\n        : left + t.difference(first)')),
          reason: 'xOf 不应再把单点节点放最左');
    });
  });

  group('v5.0.18 ⑥ 长按弹窗加震动', () {
    test('源码：onLongPress 内先 mediumNow 再 onDelete', () {
      expect(trendSrc, contains('Haptics.mediumNow();'),
          reason: '长按弹窗应同步触发震动');
      expect(trendSrc, contains('onLongPress: () {\n        Haptics.mediumNow();\n        onDelete();\n      }'),
          reason: '震动应绑定在长按回调里、弹窗之前');
    });

    testWidgets('长按记录仍可弹出删除确认框', (tester) async {
      AssetHistoryStorage.loadOverride = [
        _entry(id: 'a', time: DateTime.now(), assets: 100, debt: -20),
      ];
      await tester.pumpWidget(MaterialApp(
        home: AssetTrendScreen(
          loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
          loadAssetsOverride: () async => [],
        ),
      ));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('微信'));
      await tester.pumpAndSettle();
      expect(find.text('删除这笔改动记录？'), findsOneWidget,
          reason: '加震动后长按仍应正常弹确认框');
    });
  });

  group('v5.0.18 ④ 设置抽屉描述文案', () {
    test('源码：资产趋势副标题改为「查看资产变化趋势」', () {
      expect(assetSrc, contains("Text('查看资产变化趋势'"),
          reason: '资产趋势下方描述应改为「查看资产变化趋势」');
      expect(assetSrc, isNot(contains('按天记录每次金额调整，查看资产走势')),
          reason: '旧描述文案应移除');
    });
  });

  group('v5.0.18 ⑦ 饼图卡移除标题并居中', () {
    test('源码：标题移除、垂直居中、上下左右边距各自相等', () {
      expect(pieSrc, isNot(contains("Text('资产细分'")),
          reason: '饼图卡应移除左上角「资产细分」标题');
      expect(pieSrc, contains('EdgeInsets.symmetric(horizontal: 16, vertical: 12)'),
          reason: '左右边距相等(16)、上下边距相等(12)');
      expect(pieSrc, contains('mainAxisAlignment: MainAxisAlignment.center'),
          reason: '内容列应垂直居中，图表与文字顺位上移');
    });

    testWidgets('饼图卡不再渲染「资产细分」标题，仍有饼图内容', (tester) async {
      final slices = buildSlices([
        Asset(id: '1', type: '银行储蓄', amount: 2000),
        Asset(id: '2', type: '基金', amount: 3000),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AssetPieCard(
            slices: slices,
            money: (v) => v.toStringAsFixed(0),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('资产细分'), findsNothing,
          reason: '左上角标题应移除');
      expect(find.text('正资产'), findsOneWidget,
          reason: '饼图中心文字仍应显示');
    });
  });
}
