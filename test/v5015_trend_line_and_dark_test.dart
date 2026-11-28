import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/asset_history.dart';
import 'package:ayodiray/screens/asset_trend_screen.dart';
import 'package:ayodiray/services/asset_history_storage.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/widgets/asset_trend_chart.dart';

AssetHistoryEntry _entry({
  required String id,
  required DateTime time,
  required double assets,
  required double debt,
}) =>
    AssetHistoryEntry(
      id: id,
      time: time,
      changes: [AssetChange(name: '微信', type: '银行储蓄', amount: assets)],
      totalAssets: assets,
      totalDebt: debt,
      netWorth: assets + debt,
    );

void main() {
  setUp(() => AssetHistoryStorage.resetForTest());
  tearDown(() => AssetHistoryStorage.resetForTest());

  group('v5.0.15 净资产线', () {
    test('TrendPoint.netWorth = 总资产 - 负债绝对值', () {
      // 负债为带符号负数（快照口径），净资产 = 总资产 + 负债 = 总资产 - |负债|
      final p = TrendPoint(
          time: DateTime(2026, 11, 28), totalAssets: 38609, totalDebt: -1075);
      expect(p.netWorth, 38609 - 1075);
      // 无负债时净资产 = 总资产
      final p2 = TrendPoint(
          time: DateTime(2026, 11, 28), totalAssets: 5000, totalDebt: 0);
      expect(p2.netWorth, 5000);
    });

    test('净资产红线 / 负债绿线配色常量', () {
      final root = Directory.current.path;
      final src =
          File('$root/lib/widgets/asset_trend_chart.dart').readAsStringSync();
      // 净资产用红色 0xFFE05252，负债用绿色 0xFF3FA96F
      expect(src, contains('_kNetWorthColor = Color(0xFFE05252)'),
          reason: '净资产线应为红色');
      expect(src, contains('_kDebtColor = Color(0xFF3FA96F)'),
          reason: '负债线应为绿色');
      // painter 画了三条线：netWorth 参与绘制
      expect(src, contains('(p) => p.netWorth'),
          reason: '净资产线应实际绘制');
    });

    testWidgets('汇总条显示全资产/净资产/负债三项', (tester) async {
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
      // 汇总条三项：净资产 = 38609 - 1075 = 37534
      expect(find.textContaining('全资产'), findsWidgets);
      expect(find.textContaining('净资产'), findsWidgets);
      expect(find.textContaining('负债'), findsWidgets);
    });
  });

  group('v5.0.15 深色底纹修复', () {
    test('资产趋势两个新底纹色已登记进 darkMap', () {
      // 深色下 AppPalette.c 必须把这两个底纹翻成深色，否则浅底+浅字看不清
      AppPalette.dark = true;
      final infoBg = AppPalette.c(0xFFEDF3FD);
      final chipBg = AppPalette.c(0xFFE4E8EB);
      expect(infoBg, isNot(const Color(0xFFEDF3FD)),
          reason: '汇总条底纹在深色下应翻转');
      expect(chipBg, isNot(const Color(0xFFE4E8EB)),
          reason: '选中胶囊底纹在深色下应翻转');
      AppPalette.dark = false;
    });

    test('源码：darkMap 含两条 v5.0.15 登记', () {
      final root = Directory.current.path;
      final src = File('$root/lib/theme/app_palette.dart').readAsStringSync();
      expect(src, contains('0xFFEDF3FD: 0xFF212A33'),
          reason: '汇总条底纹需登记深色映射');
      expect(src, contains('0xFFE4E8EB: 0xFF2B3530'),
          reason: '胶囊选中底纹需登记深色映射');
    });
  });

  group('v5.0.15 设置入口置灰', () {
    test('资产趋势入口按 _isVip 置灰图标/文字/箭头', () {
      final root = Directory.current.path;
      final src =
          File('$root/lib/screens/asset_screen.dart').readAsStringSync();
      // 入口 title 文字应按 _isVip 分支着色
      expect(src, contains('color: _isVip\n                              ? AppPalette.c(0xFF24382F)\n                              : AppPalette.c(0xFFB2C4BA)'),
          reason: '资产趋势入口文字未解锁应置灰');
    });
  });

  group('v5.0.15 设置抽屉图标右下偏移', () {
    test('设置抽屉 4 个图标均用 _shiftedIcon 包裹', () {
      final root = Directory.current.path;
      final src =
          File('$root/lib/screens/asset_screen.dart').readAsStringSync();
      // 辅助方法用 Transform.translate 做纯视觉位移
      expect(src, contains('Transform.translate'),
          reason: '应有 Transform 位移辅助方法');
      expect(src, contains('offset: const Offset(3, 3)'),
          reason: '图标应向右下小幅移动 3px');
      // leading(资产趋势) + trailing(箭头) + leading(加密) + leading(改密) 共 4 处
      final count = '_shiftedIcon(AppIcon'.allMatches(src).length;
      expect(count, 4,
          reason: '设置抽屉 4 个图标都应包裹位移，实际 $count 处');
    });
  });
}
