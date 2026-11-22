import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/countdown_event.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/countdown_edit_screen.dart';
import 'package:ayodiray/screens/points_shop_screen.dart';
import 'package:ayodiray/screens/profile_edit_screen.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/services/user_storage.dart';

/// v4.9.36 回归：
/// 1. 单位「分」→「点」，提示语补「灵感」；
/// 2. 首次新增事件/物品/资产各 +20（仅 1 次）；
/// 3. 提醒时间 VIP 专属门槛（内测版/VIP/终身VIP）；
/// 4. 兑换码 novip：无限次清身份与权益 + 返还兑换次数。
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
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory('/tmp/v4936_${DateTime.now().microsecondsSinceEpoch}');
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

  group('模型：首次新增奖励标记', () {
    test('旧档案无字段时回落 false，零迁移兼容', () {
      final json = {'nickname': 'A', 'points': 5};
      final p = UserProfile.fromJson(json);
      expect(p.firstEventReward, isFalse);
      expect(p.firstItemReward, isFalse);
      expect(p.firstAssetReward, isFalse);
    });

    test('toJson 含三个标记，fromJson 往返保留', () {
      final p = UserProfile(
        firstEventReward: true,
        firstItemReward: true,
        firstAssetReward: false,
      );
      final back = UserProfile.fromJson(p.toJson());
      expect(back.firstEventReward, isTrue);
      expect(back.firstItemReward, isTrue);
      expect(back.firstAssetReward, isFalse);
    });
  });

  group('首次新增奖励：每类各 1 次', () {
    test('三类首次各 +20，重复不再发', () async {
      writeProfile(UserProfile(points: 0));
      expect(await RewardService.awardFirstAdd(FirstAddKind.event), 20);
      expect((await UserStorage.load()).points, 20);
      expect(await RewardService.awardFirstAdd(FirstAddKind.event), 0);
      expect(await RewardService.awardFirstAdd(FirstAddKind.item), 20);
      expect(await RewardService.awardFirstAdd(FirstAddKind.asset), 20);
      final p = await UserStorage.load();
      expect(p.points, 60);
      expect(p.firstEventReward, isTrue);
      expect(p.firstItemReward, isTrue);
      expect(p.firstAssetReward, isTrue);
      // 全部重复领取都返回 0
      expect(await RewardService.awardFirstAdd(FirstAddKind.item), 0);
      expect(await RewardService.awardFirstAdd(FirstAddKind.asset), 0);
      expect((await UserStorage.load()).points, 60);
    });
  });

  group('VIP 权限判断（提醒时间门槛）', () {
    test('普通版无权限', () {
      expect(RewardService.hasVipPrivilege(UserProfile()), isFalse);
    });
    test('拥有内测版/VIP/终身VIP 任一即有权限', () {
      expect(
          RewardService.hasVipPrivilege(UserProfile(
              ownedBadges: [UserProfile.badgeNormal, UserProfile.badgeBeta])),
          isTrue);
      expect(
          RewardService.hasVipPrivilege(UserProfile(
              ownedBadges: [UserProfile.badgeNormal, UserProfile.badgeVip])),
          isTrue);
      expect(
          RewardService.hasVipPrivilege(UserProfile(
              ownedBadges: [
            UserProfile.badgeNormal,
            UserProfile.badgeVipForever
          ])),
          isTrue);
    });
    test('限时 VIP 生效中有权限，过期后无权限', () {
      final active = UserProfile(
          vipCardExpireAt:
              DateTime.now().add(const Duration(days: 1)).toIso8601String());
      expect(RewardService.hasVipPrivilege(active), isTrue);
      final expired = UserProfile(
          vipCardExpireAt:
              DateTime.now().subtract(const Duration(days: 1)).toIso8601String());
      expect(RewardService.hasVipPrivilege(expired), isFalse);
    });
  });

  group('兑换码 novip', () {
    test('清除非普通版身份与 VIP 权益，且可无限次使用', () async {
      writeProfile(UserProfile(
        points: 100,
        badge: UserProfile.badgeVip,
        ownedBadges: [
          UserProfile.badgeNormal,
          UserProfile.badgeVip,
          UserProfile.badgeBeta,
          UserProfile.badgeBirthday,
        ],
        vipCardExpireAt:
            DateTime.now().add(const Duration(days: 3)).toIso8601String(),
        vipCardCount: 5,
        vipWeekCardCount: 2,
      ));
      final r = await RewardService.redeem('novip');
      expect(r.ok, isTrue);
      final p = await UserStorage.load();
      expect(p.badge, UserProfile.badgeNormal);
      expect(p.ownedBadges, [UserProfile.badgeNormal]);
      expect(p.vipCardExpireAt, '');
      expect(p.vipCardCount, 0);
      expect(p.vipWeekCardCount, 0);
      // 灵感不受影响
      expect(p.points, 100);
      // 无限次：再次使用仍成功
      final r2 = await RewardService.redeem('NOVIP');
      expect(r2.ok, isTrue);
      expect(p.redeemedCodes, isEmpty);
    });

    test('普通版使用 novip 返回无需清除，仍为成功', () async {
      writeProfile(UserProfile(badge: UserProfile.badgeNormal));
      final r = await RewardService.redeem('novip');
      expect(r.ok, isTrue);
      expect(r.message, contains('已是普通版'));
    });
  });

  group('UI 文案', () {
    testWidgets('档案页灵感栏单位为「点」', (tester) async {
      writeProfile(UserProfile(points: 42));
      await tester.pumpWidget(MaterialApp(
          home: ProfileEditScreen(profile: UserProfile(points: 42))));
      await _settle(tester);
      expect(find.text('点'), findsWidgets);
      expect(find.text('分'), findsNothing);
    });

    testWidgets('杂货店兑换确认文案含「点灵感」', (tester) async {
      writeProfile(UserProfile(points: 500));
      await tester.pumpWidget(const MaterialApp(home: PointsShopScreen()));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('shop-item-birthday')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('点灵感兑换'), findsOneWidget);
    });

    testWidgets('无 VIP 时到期提醒灰化，点击弹 VIP 专属提示', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      writeProfile(UserProfile(points: 0)); // 普通版
      await tester.pumpWidget(const MaterialApp(home: CountdownEditScreen()));
      await _settle(tester);
      expect(find.text('未解锁'), findsOneWidget);
      await tester.tap(find.text('到期提醒'));
      await tester.pumpAndSettle();
      expect(find.textContaining('VIP专属权益，请充值后再尝试'), findsOneWidget);
      // AppToast 内部有 1.6s 定时关闭，测试结束前 flush 掉避免 timer 残留
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('曾有到期提醒但 VIP 失去后：保持值、点击弹充值提示', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      writeProfile(UserProfile(points: 0)); // 普通版，无 VIP
      final e = CountdownEvent(
        id: 'e1',
        icon: '🎉',
        name: '测试',
        type: '纪念日',
        target: DateTime.now().add(const Duration(days: 10)),
        remindBeforeDays: 3, // 曾设置过提醒
      );
      await tester.pumpWidget(
          MaterialApp(home: CountdownEditScreen(event: e)));
      await _settle(tester);
      // 保留原提醒值，不显示「未解锁」
      expect(find.text('提前 3 天'), findsOneWidget);
      expect(find.text('未解锁'), findsNothing);
      await tester.tap(find.text('到期提醒'));
      await tester.pumpAndSettle();
      // v5.0.0：VIP 失去后点击也弹充值提示（不再静默 return），但仍保持原值、不弹选择层
      expect(find.textContaining('VIP专属权益，请充值后再尝试'), findsOneWidget);
      expect(find.text('选择到期提醒'), findsNothing);
      await tester.pump(const Duration(seconds: 2)); // flush AppToast timer
    });
  });
}
