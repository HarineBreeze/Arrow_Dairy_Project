import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/asset.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/utils/app_toast.dart';
import 'package:ayodiray/widgets/app_icons.dart';

import 'package:ayodiray/widgets/asset_sankey_card.dart';
import 'package:ayodiray/widgets/identity_badge.dart';

Asset _a(String type, double amount) => Asset(id: type, type: type, amount: amount);

SankeyData _data() => buildSankeyData([
      _a('银行储蓄', 2000),
      _a('基金', 3000),
      _a('信用卡', -800),
    ]);

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// 找 path 为锁图标的 AppIcon（AppIcons.lock 是 SVG path 字符串，非 IconData）
Finder _lockIcons() => find.byWidgetPredicate(
      (w) => w is AppIcon && w.path == AppIcons.lock,
    );

void main() {
  setUp(() => AppToast.resetForTest());
  tearDown(() => AppToast.resetForTest());

  group('VIP 提示语统一口径', () {
    test('vipRequiredMessage 格式正确', () {
      expect(AppToast.vipRequiredMessage('桑基图'),
          '桑基图是VIP专属权益，请充值后重试～');
      expect(AppToast.vipRequiredMessage('未来信件'),
          '未来信件是VIP专属权益，请充值后重试～');
    });

    test('VIP 权益判断复用 hasVipPrivilege', () {
      expect(RewardService.hasVipPrivilege(UserProfile()), isFalse);
      expect(
          RewardService.hasVipPrivilege(UserProfile(
              ownedBadges: [UserProfile.badgeNormal, UserProfile.badgeVip])),
          isTrue);
      expect(
          RewardService.hasVipPrivilege(UserProfile(
              ownedBadges: [UserProfile.badgeNormal, UserProfile.badgeBeta])),
          isTrue);
    });
  });

  group('资产构成卡 VIP 锁态', () {
    testWidgets('已解锁：正常显示图表，无锁图标/VIP 标识', (tester) async {
      await tester.pumpWidget(_host(AssetSankeyCard(
        data: _data(),
        money: (v) => '¥${v.toStringAsFixed(0)}',
        unlocked: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('资产构成'), findsOneWidget);
      expect(find.text('1项金融资产'), findsOneWidget);
      // 标题行不带小锁（锁图标只在未解锁时出现）
      expect(_lockIcons(), findsNothing);
      expect(find.byType(IdentityBadge), findsNothing);
    });

    testWidgets('未解锁：毛玻璃蒙版 + 锁图标 + VIP 标识', (tester) async {
      await tester.pumpWidget(_host(AssetSankeyCard(
        data: _data(),
        money: (v) => '¥${v.toStringAsFixed(0)}',
        unlocked: false,
      )));
      await tester.pumpAndSettle();

      // 标题行小锁 + 蒙版居中大锁，共两处锁图标
      expect(_lockIcons(), findsNWidgets(2));
      // VIP 标识（IdentityBadge 渲染文本 VIP）
      expect(find.text('VIP'), findsOneWidget);
      // 底层图表标签仍在（毛玻璃只是覆盖，不是移除）
      expect(find.text('1项金融资产'), findsOneWidget);
    });

    testWidgets('未解锁：单击卡片触发统一 VIP 提示', (tester) async {
      await tester.pumpWidget(_host(AssetSankeyCard(
        data: _data(),
        money: (v) => '¥${v.toStringAsFixed(0)}',
        unlocked: false,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('资产构成'));
      await tester.pumpAndSettle();

      expect(find.text('桑基图是VIP专属权益，请充值后重试～'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('未解锁：传入 onLockedTap 时走自定义回调', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(AssetSankeyCard(
        data: _data(),
        money: (v) => '¥${v.toStringAsFixed(0)}',
        unlocked: false,
        onLockedTap: () => tapped++,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('资产构成'));
      await tester.pumpAndSettle();

      expect(tapped, 1);
      expect(find.text('桑基图是VIP专属权益，请充值后重试～'), findsNothing);
    });

    testWidgets('已解锁：单击卡片不弹提示', (tester) async {
      await tester.pumpWidget(_host(AssetSankeyCard(
        data: _data(),
        money: (v) => '¥${v.toStringAsFixed(0)}',
        unlocked: true,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('资产构成'));
      await tester.pumpAndSettle();

      expect(find.textContaining('VIP专属权益'), findsNothing);
    });
  });
}
