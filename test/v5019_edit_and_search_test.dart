import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/screens/asset_edit_screen.dart';
import 'package:ayodiray/screens/countdown_edit_screen.dart';
import 'package:ayodiray/screens/global_search_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';

void main() {
  final root = Directory.current.path;
  final itemSrc =
      File('$root/lib/screens/item_edit_screen.dart').readAsStringSync();
  final eventSrc =
      File('$root/lib/screens/countdown_edit_screen.dart').readAsStringSync();
  final assetSrc =
      File('$root/lib/screens/asset_edit_screen.dart').readAsStringSync();
  final searchSrc =
      File('$root/lib/screens/global_search_screen.dart').readAsStringSync();

  Future<void> settle(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
  }

  group('v5.0.19 ① 物品编辑页', () {
    testWidgets('4 个节标题移除，占位文案改为新文案', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
      await tester.pumpAndSettle();

      // v5.0.19 移除的四个节标题中，「物品名称」全称与「日期」仍不存在；
      // 「物品价格」「附加价格」在 v5.0.22 作为档案昵称行同款的行标签回归，
      // 不再是节标题（位于输入框左侧同一白卡内）。
      for (final label in ['物品名称', '日期']) {
        expect(find.text(label), findsNothing, reason: '$label 节标题应移除');
      }
      for (final label in ['物品价格', '附加价格']) {
        expect(find.text(label), findsOneWidget, reason: '$label 行标签应存在');
      }
      expect(find.text('输入物品名'), findsOneWidget);
      expect(find.text('输入物品价格'), findsOneWidget);
      expect(find.text('如卖出/折扣（选填）'), findsOneWidget);
      expect(find.text('请输入物品名'), findsNothing);
      expect(find.text('请输入物品价格'), findsNothing);
      expect(find.text('¥ 0.00'), findsNothing);
      expect(find.text('¥ 可为负数（选填）'), findsNothing);
    });

    test('源码：4 处 _sectionLabel 调用已移除', () {
      expect(itemSrc, isNot(contains("_sectionLabel('物品名称')")));
      expect(itemSrc, isNot(contains("_sectionLabel('物品价格')")));
      expect(itemSrc, isNot(contains("_sectionLabel('附加价格')")));
      expect(itemSrc, isNot(contains("_sectionLabel('日期')")));
    });
  });

  group('v5.0.19 ② 事件编辑页', () {
    testWidgets('3 个节标题移除，备注占位/日期时间占位改为新文案', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: CountdownEditScreen()));
      await tester.pumpAndSettle();

      // v5.0.23：事件名称/事件备注改为档案昵称行同款的行标签（左侧 76px）
      for (final label in ['事件名称', '事件备注']) {
        expect(find.text(label), findsOneWidget, reason: '$label 行标签应存在');
      }
      expect(find.text('纪念日/生日/表白日/节日...'), findsOneWidget);
      expect(find.text('奖励一顿火锅?'), findsOneWidget,
          reason: '备注待输入占位文案保持不变');
      expect(find.text('写点什么…（选填）'), findsNothing);
      // 「事件日期」原为节标题，v5.0.19 移除标题后改用同名占位文字承担字段说明，
      // 因此此处恰好一处（即日期块空态占位），不再有独立标题。
      expect(find.text('事件日期'), findsOneWidget,
          reason: '日期块空态占位应为「事件日期」（标题已移除）');
      expect(find.text('发生时间'), findsOneWidget,
          reason: '时间块空态占位应为「发生时间」');
      expect(find.text('选择日期'), findsNothing);
      expect(find.text('选择时间'), findsNothing);
    });

    test('源码：滚轮弹窗标题仍为选择日期/选择时间（仅编辑页占位改动）', () {
      expect(eventSrc, contains("title: '选择日期'"));
      expect(eventSrc, contains("title: '选择时间'"));
      expect(eventSrc, isNot(contains("_sectionLabel('事件名称')")));
      expect(eventSrc, isNot(contains("_sectionLabel('事件备注')")));
      expect(eventSrc, isNot(contains("_sectionLabel('事件日期')")));
    });
  });

  group('v5.0.19 ③ 资产编辑页', () {
    testWidgets('3 个节标题移除，金额列无¥符号、不加粗、提示语格式统一', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
      await tester.pumpAndSettle();

      // 资产类型仍为节标题移除后无独立标签；资产备注/资产金额在 v5.0.23
      // 改为档案昵称行同款的行标签（左侧 76px）
      expect(find.text('资产类型'), findsNothing, reason: '资产类型节标题应移除');
      for (final label in ['资产备注', '资产金额']) {
        expect(find.text(label), findsOneWidget, reason: '$label 行标签应存在');
      }
      expect(find.text(' *'), findsNothing, reason: '必填星号随标题移除');
      // v5.0.23：金额提示语改为「输入金额」，备注为「工资卡、应急金、养老金...」
      expect(find.text('输入金额'), findsOneWidget);
      expect(find.text('工资卡、应急金、养老金...'), findsOneWidget);
    });

    test('源码：金额列移除 Text(¥) 与 w600 加粗', () {
      // 金额区块内不应再有独立的 ¥ 符号 Text 与 fontSize:17 加粗样式
      final amountBlock = assetSrc.substring(
          assetSrc.indexOf('资产金额（必填）'),
          assetSrc.indexOf('const SizedBox(height: 28)'));
      expect(amountBlock, isNot(contains("Text('¥'")),
          reason: '金额列应移除金钱符号');
      expect(amountBlock, isNot(contains('FontWeight.w600')),
          reason: '金额输入文字应取消加粗');
      expect(amountBlock, contains('const TextStyle(fontSize: 15)'),
          reason: '金额输入文字应与正文同格式');
      expect(amountBlock, contains('hintStyle:'),
          reason: '提示语应保留统一的 hintStyle 格式');
    });
  });

  group('v5.0.19 ④ 搜索结果分区标题对齐（v5.0.20 改为对齐「全部」）', () {
    test('源码：分区标题/卡片标题/副标题统一用动态 allLeft 对齐筛选栏「全部」', () {
      // v5.0.20：三者左边缘不再写死 14，而是统一用 LayoutBuilder 算出的
      // allLeft（= 筛选栏「全部」文字左边缘），保证与筛选栏左对齐。
      expect(searchSrc, contains('final allLeft = (cellW - 26) / 2'),
          reason: '应按「全部」2 字 13px 计算文字左边缘');
      expect(searchSrc, contains('EdgeInsets.only(left: allLeft, bottom: 7)'),
          reason: '分区标题应改用动态 allLeft');
      expect(searchSrc, contains('EdgeInsets.fromLTRB(allLeft, 11, 14, 11)'),
          reason: '卡片标题/副标题应改用动态 allLeft');
      expect(searchSrc, isNot(contains('EdgeInsets.only(left: 2, bottom: 7)')),
          reason: '旧的 left:2 应移除');
      expect(searchSrc,
          isNot(contains('EdgeInsets.symmetric(horizontal: 14, vertical: 11)')),
          reason: '旧的写死 14 基线应移除');
    });
  });
}
