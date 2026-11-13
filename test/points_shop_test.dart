import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/points_shop_screen.dart';
import 'package:ayodiray/screens/profile_edit_screen.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/services/user_storage.dart';

/// 身份牌切换 / 积分商城 / 活动分组文案的回归测试。
class _FakePathProvider extends PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory('/tmp/shop_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
    UserStorage.revision.value = 0;
  });

  void writeProfile(UserProfile p) {
    File('${dir.path}/user_profile.json')
        .writeAsStringSync(jsonEncode(p.toJson()));
  }

  group('积分商城兑换', () {
    test('积分充足：扣 50 分 → 加入已拥有 → 立即佩戴', () async {
      writeProfile(UserProfile(points: 120));
      final r = await RewardService.buyBadge(UserProfile.badgeBirthday);
      expect(r.ok, isTrue);
      expect(r.message, contains('诞生日'));

      final p = await UserStorage.load();
      expect(p.points, 70);
      expect(p.badge, UserProfile.badgeBirthday);
      expect(p.owns(UserProfile.badgeBirthday), isTrue);
    });

    test('积分不足：不扣分、不发放', () async {
      writeProfile(UserProfile(points: 30));
      final r = await RewardService.buyBadge(UserProfile.badgeBirthday);
      expect(r.ok, isFalse);
      expect(r.message, contains('积分不足'));

      final p = await UserStorage.load();
      expect(p.points, 30);
      expect(p.owns(UserProfile.badgeBirthday), isFalse);
    });

    test('已拥有：不重复扣分', () async {
      writeProfile(UserProfile(
        points: 100,
        badge: UserProfile.badgeBirthday,
        ownedBadges: [UserProfile.badgeBirthday],
      ));
      final r = await RewardService.buyBadge(UserProfile.badgeBirthday);
      expect(r.ok, isFalse);
      expect(r.message, '已拥有该身份牌');
      expect((await UserStorage.load()).points, 100);
    });

    test('商品不在售：拒绝', () async {
      final r = await RewardService.buyBadge('not-a-badge');
      expect(r.ok, isFalse);
      expect(r.message, '商品不存在');
    });
  });

  group('身份牌切换', () {
    test('已拥有：可来回切换（诞生日 → 普通版）', () async {
      writeProfile(UserProfile(
        points: 70,
        badge: UserProfile.badgeBirthday,
        ownedBadges: [UserProfile.badgeBirthday],
      ));

      final back = await RewardService.wearBadge(UserProfile.badgeNormal);
      expect(back.ok, isTrue);
      expect((await UserStorage.load()).badge, UserProfile.badgeNormal);

      final again = await RewardService.wearBadge(UserProfile.badgeBirthday);
      expect(again.ok, isTrue);
      expect((await UserStorage.load()).badge, UserProfile.badgeBirthday);
    });

    test('未拥有：拒绝', () async {
      writeProfile(UserProfile());
      final r = await RewardService.wearBadge(UserProfile.badgeVip);
      expect(r.ok, isFalse);
      expect(r.message, '尚未拥有该身份牌');
    });

    test('已是当前牌：提示无需切换', () async {
      writeProfile(UserProfile(badge: UserProfile.badgeNormal));
      final r = await RewardService.wearBadge(UserProfile.badgeNormal);
      expect(r.ok, isFalse);
      expect(r.message, '已是当前身份牌');
    });
  });

  group('设置页活动分组', () {
    testWidgets('标题为「活动」，兑换码副标题为「参与活动获得兑换码」', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();

      expect(find.text('活动'), findsOneWidget);
      expect(find.text('兑换与积分'), findsNothing);
      expect(find.text('参与活动获得兑换码'), findsOneWidget);
      expect(find.text('兑换码'), findsOneWidget);
    });
  });

  group('积分商城页面', () {
    testWidgets('显示余额与商品价格', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(points: 120),
        ),
      ));
      await tester.pump();

      expect(find.text('积分商城'), findsOneWidget);
      expect(find.text('我的积分'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('诞生日'), findsOneWidget);
      expect(find.text('50 积分'), findsOneWidget);
      expect(find.text('兑换'), findsOneWidget);
    });

    testWidgets('积分不足时按钮为「积分不足」且不可点', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var bought = 0;
      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(points: 10),
          buyOverride: (id) async {
            bought++;
            return const RedeemOutcome(true, 'ok');
          },
        ),
      ));
      await tester.pump();

      expect(find.text('积分不足'), findsOneWidget);
      await tester.tap(find.text('积分不足'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(bought, 0);
    });

    testWidgets('已拥有时显示「已拥有」', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(
            points: 70,
            badge: UserProfile.badgeBirthday,
            ownedBadges: [UserProfile.badgeBirthday],
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('已拥有'), findsOneWidget);
      expect(find.text('兑换'), findsNothing);
    });

    testWidgets('确认兑换：调起对话 → 扣分并刷新余额', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var profile = UserProfile(points: 120);
      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => profile,
          buyOverride: (id) async {
            profile = UserProfile(
              points: 70,
              badge: id,
              ownedBadges: [id],
            );
            return const RedeemOutcome(true, '兑换成功，已佩戴「诞生日」身份牌');
          },
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('兑换'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('兑换身份牌'), findsOneWidget);
      expect(find.textContaining('剩余 70'), findsOneWidget);

      await tester.tap(find.text('确认兑换'));
      await _settle(tester);

      expect(find.text('70'), findsOneWidget, reason: '余额应刷新为 70');
      expect(find.text('已拥有'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2)); // 排空 toast 定时器
    });
  });

  group('个人信息页身份牌', () {
    testWidgets('点「身份牌」弹出选项，可在普通版与已有牌之间切换', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(600, 1200);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

      String? worn;
      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(
          profile: UserProfile(
            badge: UserProfile.badgeVip,
            ownedBadges: [UserProfile.badgeVip],
          ),
          wearOverride: (id) async {
            worn = id;
            return const RedeemOutcome(true, '已切换为「普通版」');
          },
        ),
      ));
      await tester.pump();
      expect(find.text('VIP'), findsOneWidget);
      expect(find.text('普通版'), findsNothing, reason: '当前佩戴 VIP，页面只显示 VIP');

      await tester.tap(find.text('身份牌'));
      await tester.pump(); // route 入栈
      await tester.pump(const Duration(milliseconds: 400)); // 弹层滑入
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('选择身份牌'), findsOneWidget);
      // 选项：普通版恒在 + 已拥有的 VIP
      expect(find.byKey(const ValueKey('badge_option_normal')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge_option_vip')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('badge_option_normal')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // 弹层滑出
      await tester.pump(const Duration(milliseconds: 400));

      expect(worn, UserProfile.badgeNormal);
      expect(find.text('选择身份牌'), findsNothing, reason: '选完应关闭选项');
      expect(find.text('普通版'), findsOneWidget, reason: '页面应显示已切换的普通版');
      await tester.pump(const Duration(seconds: 2)); // 排空 toast 定时器
    });

    testWidgets('点「积分」进入积分商城', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(
          profile: UserProfile(points: 60),
          loadOverride: () async => UserProfile(points: 60),
          shopBuilder: () => const Scaffold(
            body: Center(child: Text('积分商城页')),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('积分'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('积分商城页'), findsOneWidget);
    });
  });
}
