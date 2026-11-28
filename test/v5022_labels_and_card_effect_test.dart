import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/screens/asset_edit_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';

void main() {
  final root = Directory.current.path;
  String src(String rel) => File('$root/$rel').readAsStringSync();

  final assetEditSrc = src('lib/screens/asset_edit_screen.dart');
  final itemEditSrc = src('lib/screens/item_edit_screen.dart');
  final itemListSrc = src('lib/screens/item_list_screen.dart');
  final convertSrc = src('lib/widgets/wishlist_convert_celebration.dart');
  final profileSrc = src('lib/screens/profile_edit_screen.dart');

  Future<void> settle(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
  }

  group('v5.0.22 ① 资产归属 + 顺序 + 还款时间 bug', () {
    testWidgets('资产归属更名、金额在上、还款时间在下、无选择还款日期占位', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
      await settle(tester);

      expect(find.text('资产归属'), findsOneWidget);
      expect(find.text('资产所有人'), findsNothing);
      expect(find.text('还款时间'), findsOneWidget);
      expect(find.text('选择还款日期'), findsNothing);

      // 资产金额 → 资产归属 → 还款时间 的垂直顺序
      final amountTop = tester.getTopLeft(find.text('资产金额')).dy;
      final ownerTop = tester.getTopLeft(find.text('资产归属')).dy;
      final repayTop = tester.getTopLeft(find.text('还款时间')).dy;
      expect(amountTop, lessThan(ownerTop), reason: '资产金额行应位于资产归属之上');
      expect(ownerTop, lessThan(repayTop), reason: '资产归属应位于还款时间之上');
    });

    test('源码：还款时间标题不换行、VIP 徽章 0.85 常驻、移除占位文案', () {
      expect(assetEditSrc, contains("Text('还款时间',\n                                maxLines: 1"));
      expect(assetEditSrc, contains('overflow: TextOverflow.clip'));
      expect(assetEditSrc,
          contains('badge: UserProfile.badgeVip, scale: 0.85'));
      expect(assetEditSrc, isNot(contains("'选择还款日期'")));
    });
  });

  group('v5.0.22 ② 愿望单转正特效作用在卡片上', () {
    test('源码：卡片层包 WishlistConvertEffect，按 id 集合锚定', () {
      expect(itemListSrc, contains('WishlistConvertEffect('));
      expect(itemListSrc, contains('final Set<String> _celebratingIds'));
      expect(itemListSrc, contains('celebrate: _celebratingIds.contains(it.id)'));
      expect(itemListSrc, contains('onCelebrateDone:'));
      // 转正后不再弹窗
      expect(itemListSrc, isNot(contains('showWishlistConvertCelebration')));
    });

    test('源码：组件为翻转 + 粒子，无 Dialog / 无弹窗文案', () {
      expect(convertSrc, contains('rotateY'));
      expect(convertSrc, contains('CustomPaint'));
      expect(convertSrc, contains('class _ConvertBurst extends CustomPainter'));
      expect(convertSrc, isNot(contains('showDialog')));
      expect(convertSrc, isNot(contains('愿望成真')));
      expect(convertSrc, isNot(contains('太棒了')));
      // 状态在卡片内随 ValueKey 复用，换物理位置不丢
      expect(itemListSrc, contains('key: ValueKey(it.id)'));
    });
  });

  group('v5.0.22 ③ 物品编辑三字段行改为档案昵称行样式', () {
    testWidgets('三行显示左标签 + 右输入，提示语不变', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
      await settle(tester);

      for (final label in ['物品名', '物品价格', '附加价格']) {
        expect(find.text(label), findsOneWidget, reason: '$label 行标签应存在');
      }
      expect(find.text('输入物品名'), findsOneWidget);
      expect(find.text('输入物品价格'), findsOneWidget);
      expect(find.text('如卖出/折扣（选填）'), findsOneWidget);
    });

    test('源码：三行统一走 _buildLabeledField，标签列宽 76，与档案昵称一致', () {
      final builderStart = itemEditSrc.indexOf('Widget _buildLabeledField(');
      final builderEnd = itemEditSrc.indexOf('Widget _buildNameField()', builderStart);
      final builder = itemEditSrc.substring(builderStart, builderEnd);
      expect(builder, contains('width: 76'));
      expect(builder, contains('crossAxisAlignment: CrossAxisAlignment.center'));

      for (final method in [
        'Widget _buildNameField()',
        'Widget _buildPriceField()',
        'Widget _buildExtraPriceField()',
      ]) {
        final start = itemEditSrc.indexOf(method);
        final next = itemEditSrc.indexOf('\n  }', start);
        expect(itemEditSrc.substring(start, next), contains('_buildLabeledField('),
            reason: '$method 应复用昵称行同款布局');
      }

      // 与档案昵称行同款：76 宽标签列
      expect(profileSrc, contains('width: 76'));
    });

    test('源码：三处 hintText 保持原样（不改变待输入提示语）', () {
      expect(itemEditSrc, contains("hintText: '输入物品名'"));
      expect(itemEditSrc, contains("hintText: '输入物品价格'"));
      expect(itemEditSrc, contains("hintText: '如卖出/折扣（选填）'"));
    });
  });
}
