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
    testWidgets('显示余额与商品价格（诞生日 + VIP日卡）', (tester) async {
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
      expect(find.text('VIP日卡'), findsOneWidget);
      expect(find.text('200 积分'), findsOneWidget);
      // 120 分够买诞生日、不够买 VIP日卡
      expect(find.text('兑换'), findsOneWidget);
      expect(find.text('积分不足'), findsOneWidget);
    });

    testWidgets('旧提示语已移除', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(points: 120),
        ),
      ));
      await tester.pump();

      expect(find.text('佩戴后显示在昵称旁'), findsNothing);
      expect(find.textContaining('兑换后会立即佩戴'), findsNothing);
      expect(find.text('积分可通过每日首次发布笔记、参与活动获得。'),
          findsOneWidget);
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

      expect(find.text('积分不足'), findsNWidgets(2));
      await tester.tap(find.text('积分不足').first);
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

  group('VIP日卡', () {
    test('兑换：扣 200 分 → 计次数 → 立即佩戴且 24 小时内生效', () async {
      writeProfile(UserProfile(points: 260));
      final r = await RewardService.buyVipCard(UserProfile.badgeVip);
      expect(r.ok, isTrue);
      expect(r.message, contains('24小时'));

      final p = await UserStorage.load();
      expect(p.points, 60);
      expect(p.vipCardCount, 1);
      expect(p.badge, UserProfile.badgeVip);
      expect(p.vipCardActive, isTrue);
      expect(p.owns(UserProfile.badgeVip), isFalse,
          reason: '日卡 VIP 不是永久拥有');
      // 到期时间应在 24 小时内（留 1 分钟时钟误差）
      final left = p.vipCardExpireTime!.difference(DateTime.now());
      expect(left.inMinutes, inInclusiveRange(23 * 60, 24 * 60));
    });

    test('积分不足：不扣分、不计次', () async {
      writeProfile(UserProfile(points: 199));
      final r = await RewardService.buyVipCard(UserProfile.badgeVip);
      expect(r.ok, isFalse);
      expect(r.message, contains('积分不足'));

      final p = await UserStorage.load();
      expect(p.points, 199);
      expect(p.vipCardCount, 0);
    });

    test('单用户上限 30 次：达到后拒绝兑换', () async {
      writeProfile(UserProfile(points: 9999, vipCardCount: 30));
      final r = await RewardService.buyVipCard(UserProfile.badgeVip);
      expect(r.ok, isFalse);
      expect(r.message, contains('兑换上限'));

      final p = await UserStorage.load();
      expect(p.points, 9999, reason: '达到上限后不扣分');
      expect(p.vipCardCount, 30);
    });

    test('日卡生效期间可切换佩戴（非永久拥有也能戴）', () async {
      writeProfile(UserProfile(
        points: 0,
        badge: UserProfile.badgeNormal,
        vipCardCount: 1,
        vipCardExpireAt:
            DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
      ));
      final r = await RewardService.wearBadge(UserProfile.badgeVip);
      expect(r.ok, isTrue);
      expect((await UserStorage.load()).badge, UserProfile.badgeVip);
    });

    test('日卡生效期间可切走，切走后还能切回 VIP', () async {
      writeProfile(UserProfile(
        badge: UserProfile.badgeVip,
        vipCardCount: 1,
        vipCardExpireAt:
            DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      ));
      final away = await RewardService.wearBadge(UserProfile.badgeNormal);
      expect(away.ok, isTrue);

      final back = await RewardService.wearBadge(UserProfile.badgeVip);
      expect(back.ok, isTrue);
      expect((await UserStorage.load()).badge, UserProfile.badgeVip);
    });

    test('到期后读档自动摘牌换回普通版', () async {
      final json = UserProfile(badge: UserProfile.badgeNormal).toJson();
      json['badge'] = 'vip';
      json['vipCardCount'] = 1;
      json['vipCardExpireAt'] =
          DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String();
      File('${dir.path}/user_profile.json')
          .writeAsStringSync(jsonEncode(json));

      final p = await UserStorage.load();
      expect(p.badge, UserProfile.badgeNormal, reason: '过期日卡应摘牌');
      expect(p.owns(UserProfile.badgeVip), isFalse);
    });

    test('生效中的日卡读档不摘牌', () async {
      final json = UserProfile(badge: UserProfile.badgeNormal).toJson();
      json['badge'] = 'vip';
      json['vipCardCount'] = 1;
      json['vipCardExpireAt'] =
          DateTime.now().add(const Duration(hours: 3)).toIso8601String();
      File('${dir.path}/user_profile.json')
          .writeAsStringSync(jsonEncode(json));

      final p = await UserStorage.load();
      expect(p.badge, UserProfile.badgeVip);
      expect(p.vipCardActive, isTrue);
    });

    test('旧档案遗留的 VIP（无日卡痕迹）不受摘牌影响', () async {
      final back = UserProfile.fromJson({'nickname': '小明', 'badge': 'vip'});
      expect(back.badge, UserProfile.badgeVip);
      expect(back.owns(UserProfile.badgeVip), isTrue);
    });

    testWidgets('商城展示 VIP日卡：价格、说明与剩余次数', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(
            points: 300,
            vipCardCount: 2,
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('兑换后立即生效，24小时内佩戴VIP身份牌'), findsOneWidget);
      expect(find.text('可兑换次数已用 2/30'), findsOneWidget);
      expect(find.text('200 积分'), findsOneWidget);
      // 300 分够买两件商品
      expect(find.text('兑换'), findsNWidgets(2));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('兑换 VIP日卡：确认弹窗 → 走日卡购买通道', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final boughtIds = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(points: 300),
          buyOverride: (id) async {
            boughtIds.add(id);
            return const RedeemOutcome(true, '兑换成功，VIP身份牌生效24小时');
          },
        ),
      ));
      await tester.pump();

      // 第二张商品卡是 VIP日卡
      await tester.tap(find.text('兑换').last);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('兑换VIP日卡'), findsOneWidget);
      expect(find.textContaining('有效期24小时'), findsOneWidget);
      expect(find.textContaining('剩余 100'), findsOneWidget);

      await tester.tap(find.text('确认兑换'));
      await _settle(tester);
      expect(boughtIds, [UserProfile.badgeVip]);
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
