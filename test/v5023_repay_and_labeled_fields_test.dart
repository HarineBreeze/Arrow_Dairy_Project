import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/screens/asset_edit_screen.dart';
import 'package:ayodiray/screens/countdown_edit_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';

void main() {
  final root = Directory.current.path;
  String src(String rel) => File('$root/$rel').readAsStringSync();

  final assetEditSrc = src('lib/screens/asset_edit_screen.dart');
  final eventEditSrc = src('lib/screens/countdown_edit_screen.dart');
  final itemEditSrc = src('lib/screens/item_edit_screen.dart');
  final convertSrc = src('lib/widgets/wishlist_convert_celebration.dart');

  Future<void> settle(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
  }

  group('v5.0.23 ① 还款时间设置成功提示 + 显示格式', () {
    test('源码：设置日期后弹「设置成功，阿尤会在x年x月x日提醒哦～」', () {
      expect(assetEditSrc, contains('设置成功，阿尤会在'));
      expect(assetEditSrc, contains('日提醒哦～'));
      // 年月日取自选中的 picked 日期，不写死
      expect(assetEditSrc,
          contains(r'${picked.year}年${picked.month}月${picked.day}日提醒哦～'));
    });

    test('源码：还款时间显示格式改为 2026/11/6（斜杠、不补零）', () {
      expect(assetEditSrc,
          contains(r"'${_repayDate!.year}/${_repayDate!.month}/${_repayDate!.day}'"));
      // 旧的 点号 + padLeft 补零格式应移除
      expect(assetEditSrc, isNot(contains(r"'${_repayDate!.year}.")));
      expect(assetEditSrc, isNot(contains('month.toString().padLeft')));
    });
  });

  group('v5.0.23 ② VIP 身份牌恢复常驻 + 一致大小', () {
    testWidgets('编辑页：VIP 牌常驻，与是否拥有权益无关', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
      await settle(tester);
      // 即使默认非 VIP（正资产置灰），身份牌仍在树上（IdentityBadge 由 VIP id 决定文案）
      expect(find.text('还款时间'), findsOneWidget);
    });

    test('源码：VIP 牌 0.85 大小、无 !_isVip 条件隐藏', () {
      expect(assetEditSrc,
          contains('badge: UserProfile.badgeVip, scale: 0.85'));
      // 移除旧的 0.5 缩放
      expect(assetEditSrc, isNot(contains('badge: UserProfile.badgeVip, scale: 0.5')));
      // 身份牌不再包在 if (!_isVip) 条件里
      final repayBlock = assetEditSrc.substring(
          assetEditSrc.indexOf('// 还款时间（v5.0.21'),
          assetEditSrc.indexOf('const SizedBox(height: 28)'));
      expect(repayBlock, isNot(contains('if (!_isVip)')));
      expect(repayBlock, contains('const IdentityBadge('));
    });
  });

  group('v5.0.23 ③ 转正翻转（v5.0.24 改为单向一整圈）', () {
    test('源码：翻转角为 math.pi * 2（单向整圈，停在正面）', () {
      expect(convertSrc, contains('final angle = t * math.pi * 2;'));
    });

    test('源码：播完直接结束，无 reverse 翻回', () {
      expect(convertSrc, isNot(contains('_ctrl.reverse();')));
      expect(convertSrc, isNot(contains('AnimationStatus.dismissed')));
      expect(convertSrc, contains('AnimationStatus.completed'));
      expect(convertSrc, contains('widget.onDone?.call()'));
    });
  });

  group('v5.0.23 ④ 资产编辑备注/金额改档案昵称行样式', () {
    testWidgets('资产备注/资产金额显示左侧标签 + 新提示语', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
      await settle(tester);

      for (final label in ['资产备注', '资产金额']) {
        expect(find.text(label), findsOneWidget, reason: '$label 行标签应存在');
      }
      expect(find.text('工资卡、应急金、养老金...'), findsOneWidget);
      expect(find.text('输入金额'), findsOneWidget);
      expect(find.text('输入数额'), findsNothing);
      expect(find.text('如：工资卡、应急金、基金账户'), findsNothing);
    });

    test('源码：资产编辑新增 _buildLabeledField 且两行复用，标签列宽 76', () {
      final start = assetEditSrc.indexOf('Widget _buildLabeledField(');
      expect(start, greaterThan(0));
      final end = assetEditSrc.indexOf('BoxDecoration _box()', start);
      final builder = assetEditSrc.substring(start, end);
      expect(builder, contains('width: 76'));
      expect(builder,
          contains('crossAxisAlignment: CrossAxisAlignment.center'));
      for (final method in [
        "_buildLabeledField(\n              label: '资产备注'",
        "_buildLabeledField(\n              label: '资产金额'",
      ]) {
        expect(assetEditSrc, contains(method), reason: '$method 应复用昵称行布局');
      }
    });
  });

  group('v5.0.23 ⑤ 事件编辑名称/备注改档案昵称行样式', () {
    testWidgets('事件名称/事件备注显示左侧标签，提示语保持不变', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: CountdownEditScreen()));
      await settle(tester);

      for (final label in ['事件名称', '事件备注']) {
        expect(find.text(label), findsOneWidget, reason: '$label 行标签应存在');
      }
      expect(find.text('纪念日/生日/表白日/节日...'), findsOneWidget);
      expect(find.text('奖励一顿火锅?'), findsOneWidget);
    });

    test('源码：事件编辑新增 _buildLabeledField，两行复用', () {
      final start = eventEditSrc.indexOf('Widget _buildLabeledField(');
      expect(start, greaterThan(0));
      final end = eventEditSrc.indexOf('BoxDecoration _box()', start);
      final builder = eventEditSrc.substring(start, end);
      expect(builder, contains('width: 76'));
      expect(eventEditSrc,
          contains("_buildLabeledField(\n              label: '事件名称'"));
      expect(eventEditSrc,
          contains("_buildLabeledField(\n              label: '事件备注'"));
    });
  });

  group('v5.0.23 ⑥ 附加价格提示语移除前缀', () {
    testWidgets('附加价格 hint 为「如卖出/折扣（选填）」', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
      await settle(tester);
      expect(find.text('如卖出/折扣（选填）'), findsOneWidget);
      expect(find.text('输入附加价格，如卖出/折扣（选填）'), findsNothing);
    });

    test('源码：附加价格 hintText 去掉「输入附加价格，」', () {
      expect(itemEditSrc, contains("hintText: '如卖出/折扣（选填）'"));
      expect(itemEditSrc, isNot(contains("hintText: '输入附加价格，")));
    });
  });
}
