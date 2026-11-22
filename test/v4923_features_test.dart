import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/points_shop_screen.dart';
import 'package:ayodiray/screens/profile_edit_screen.dart';
import 'package:ayodiray/screens/side_menu.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/services/user_storage.dart';
import 'package:ayodiray/widgets/identity_badge.dart';

/// v4.9.23：顺序用户 ID / VIP 时效累加 / VIP周卡 / 终身VIP 的回归测试。
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
    dir = Directory('/tmp/v4923_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    UserProfile.resetUserIdSeq();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
    UserStorage.revision.value = 0;
  });

  File profileFile() => File('${dir.path}/user_profile.json');
  File seqFile() => File('${dir.path}/user_id_seq.json');

  void writeJson(Map<String, dynamic> json) =>
      profileFile().writeAsStringSync(jsonEncode(json));

  void writeProfile(UserProfile p) => writeJson(p.toJson());

  group('顺序用户 ID', () {
    test('首次读档分配 10001，并固化到序列文件', () async {
      final p = await UserStorage.load();
      expect(p.userId, '10001');
      expect(p.registeredAt, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));

      final seq = jsonDecode(seqFile().readAsStringSync()) as Map<String, dynamic>;
      expect(seq['last'], 10001);

      // 再读一次不漂移
      expect((await UserStorage.load()).userId, '10001');
    });

    test('删除档案后重建：接着发 10002，不退回起点', () async {
      expect((await UserStorage.load()).userId, '10001');
      profileFile().deleteSync();
      expect((await UserStorage.load()).userId, '10002');
      profileFile().deleteSync();
      expect((await UserStorage.load()).userId, '10003');
    });

    test('旧 AYO- 随机 ID 自动迁移为顺序号，且再次读档稳定', () async {
      final json = UserProfile(points: 50).toJson();
      json['userId'] = 'AYO-K3J2-9X7Q';
      writeJson(json);

      final p = await UserStorage.load();
      expect(p.userId, '10001', reason: '旧格式 ID 应迁移为顺序号');
      expect(p.points, 50, reason: '迁移不能丢其它档案字段');
      expect((await UserStorage.load()).userId, '10001');
    });

    test('档案里的顺序号大于序列文件时同步序列', () async {
      final json = UserProfile().toJson();
      json['userId'] = '10020';
      writeJson(json);

      expect((await UserStorage.load()).userId, '10020');
      profileFile().deleteSync();
      expect((await UserStorage.load()).userId, '10021',
          reason: '后续发号不能与已有 10020 撞车');
    });

    test('isSequentialId：纯数字且不小于起点', () {
      expect(UserStorage.isSequentialId('10001'), isTrue);
      expect(UserStorage.isSequentialId('10020'), isTrue);
      expect(UserStorage.isSequentialId('AYO-K3J2-9X7Q'), isFalse);
      expect(UserStorage.isSequentialId(''), isFalse);
      expect(UserStorage.isSequentialId('9999'), isFalse);
    });

    testWidgets('侧边栏显示档案里的真实 ID（不再是写死的 10001）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final profile = UserProfile(nickname: '小明', initialUserId: '10086');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 800,
            child: SideMenu(
              profile: profile,
              currentTab: 'diary',
              onClose: () {},
              onOpenProfile: () {},
              onOpenDiary: () {},
              onOpenItems: () {},
              onOpenAssets: () {},
              onOpenCountdown: () {},
              onOpenSettings: () {},
              onOpenGlobalSearch: () {},
              onOpenTrash: () {},
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text('ID：10086'), findsOneWidget);
      expect(find.text('ID：10001'), findsNothing);
    });
  });

  group('VIP 时效累加', () {
    test('两次日卡：到期时间在原基础上累加 48 小时，不覆盖', () async {
      writeProfile(UserProfile(points: 1000));

      expect((await RewardService.buyVipCard('vip')).ok, isTrue);
      final p1 = await UserStorage.load();
      final expire1 = p1.vipCardExpireTime!;

      expect((await RewardService.buyVipCard('vip')).ok, isTrue);
      final p2 = await UserStorage.load();
      expect(p2.vipCardCount, 2);
      expect(p2.vipCardExpireTime!.difference(expire1).inHours, 24,
          reason: '第二次应在第一次到期时间上再 +24 小时');
      expect(UserProfile.daysLeft(p2.vipCardExpireTime), 2);
    });

    test('日卡 + 周卡：累计 8 天，剩余天数随之增加', () async {
      writeProfile(UserProfile(points: 5000));

      await RewardService.buyVipCard('vip'); // +1 天
      await RewardService.buyVipCard('vipWeekCard'); // +7 天
      final p = await UserStorage.load();

      expect(p.vipCardCount, 1);
      expect(p.vipWeekCardCount, 1);
      expect(p.points, 5000 - 200 - 1400);
      expect(UserProfile.daysLeft(p.vipCardExpireTime), 8);
      expect(
        UserProfile.validityLabel(UserProfile.badgeVip,
            owned: false, expiresAt: p.vipCardExpireTime),
        '剩余8天',
      );
    });

    test('已过期的 VIP 再购买：从当前时刻起算，不叠加历史时间', () async {
      final json = UserProfile(points: 5000).toJson();
      json['vipCardCount'] = 1;
      json['vipCardExpireAt'] = DateTime.now()
          .subtract(const Duration(days: 3))
          .toIso8601String();
      writeJson(json);

      expect((await RewardService.buyVipCard('vipWeekCard')).ok, isTrue);
      final p = await UserStorage.load();
      expect(UserProfile.daysLeft(p.vipCardExpireTime), 7,
          reason: '过期的 3 天不应被累加回来');
    });

    test('daysLeft 随实际购买天数线性增加', () {
      final now = DateTime.now();
      expect(UserProfile.daysLeft(now.add(const Duration(days: 1))), 1);
      expect(UserProfile.daysLeft(now.add(const Duration(days: 2))), 2);
      expect(UserProfile.daysLeft(now.add(const Duration(days: 7))), 7);
      expect(UserProfile.daysLeft(now.add(const Duration(days: 8))), 8);
      expect(UserProfile.daysLeft(now.subtract(const Duration(hours: 1))), 0);
      expect(UserProfile.daysLeft(null), 0);
    });

    test('永久拥有 VIP 且买了限时卡：仍显示剩余天数（随购买增加）', () {
      final expires = DateTime.now().add(const Duration(days: 8));
      expect(
        UserProfile.validityLabel(UserProfile.badgeVip,
            owned: true, expiresAt: expires),
        '剩余8天',
      );
      // 没有限时权益的永久 VIP → 永久
      expect(
        UserProfile.validityLabel(UserProfile.badgeVip,
            owned: true, expiresAt: null),
        '永久',
      );
    });

    Future<String?> readVipValidity(WidgetTester tester, UserProfile p) async {
      // 每次给 MaterialApp 一个全新 key → 重建 Navigator，
      // 避免上一次弹出的底部弹层路由残留、遮挡点击。
      await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        home: ProfileEditScreen(
          profile: p,
          wearOverride: (id) async => const RedeemOutcome(true, 'ok'),
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('身份'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      return tester
          .widget<Text>(find.byKey(const ValueKey('badge_validity_vip')))
          .data;
    }

    testWidgets('身份选择页：VIP 剩余天数随购买的实际天数增加', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final oneDay = UserProfile(
        vipCardCount: 1,
        vipCardExpireAt:
            DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      );
      expect(await readVipValidity(tester, oneDay), '剩余1天');

      final eightDays = UserProfile(
        vipCardCount: 1,
        vipWeekCardCount: 1,
        vipCardExpireAt:
            DateTime.now().add(const Duration(days: 8)).toIso8601String(),
      );
      expect(await readVipValidity(tester, eightDays), '剩余8天');
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('VIP周卡', () {
    test('商品定义：1400 点 / 限 6 次 / 每次 7 天', () {
      final item = RewardService.shopBadgeOf('vipWeekCard')!;
      expect(item.price, 1400);
      expect(item.limit, 6);
      expect(item.kind, ShopItemKind.vipWeekCard);
      expect(item.duration, const Duration(days: 7));
      expect(item.isVipTimeCard, isTrue);
      expect(RewardService.vipWeekCardMaxCount, 6);
    });

    test('兑换周卡：扣 1400、周卡次数 +1、VIP 增加 7 天', () async {
      writeProfile(UserProfile(points: 2000));
      final r = await RewardService.buyVipCard('vipWeekCard');
      expect(r.ok, isTrue);
      expect(r.message, contains('7天'));

      final p = await UserStorage.load();
      expect(p.points, 600);
      expect(p.vipWeekCardCount, 1);
      expect(p.badge, UserProfile.badgeVip);
      expect(p.owns(UserProfile.badgeVip), isFalse, reason: '限时 VIP 非永久拥有');
      expect(UserProfile.daysLeft(p.vipCardExpireTime), 7);
    });

    test('周卡与日卡次数互不占用', () async {
      writeProfile(UserProfile(points: 99999));
      await RewardService.buyVipCard('vipWeekCard');
      var p = await UserStorage.load();
      expect(p.vipWeekCardCount, 1);
      expect(p.vipCardCount, 0);

      await RewardService.buyVipCard('vip');
      p = await UserStorage.load();
      expect(p.vipWeekCardCount, 1);
      expect(p.vipCardCount, 1);
    });

    test('周卡灵感不足 / 达到 6 次上限：拒绝且不扣分', () async {
      writeProfile(UserProfile(points: 1399));
      var r = await RewardService.buyVipCard('vipWeekCard');
      expect(r.ok, isFalse);
      expect(r.message, contains('灵感不足'));
      expect((await UserStorage.load()).points, 1399);

      writeProfile(UserProfile(points: 99999, vipWeekCardCount: 6));
      r = await RewardService.buyVipCard('vipWeekCard');
      expect(r.ok, isFalse);
      expect(r.message, contains('兑换上限'));
      expect((await UserStorage.load()).points, 99999);
    });

    testWidgets('杂货店展示 VIP周卡：1400 点 / 0/6 / 7日权益', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(points: 2000),
        ),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('shop-item-vipWeekCard')), findsOneWidget);
      expect(find.text('VIP周卡'), findsOneWidget);
      expect(find.text('1400 点'), findsOneWidget);
      expect(find.text('0/6'), findsOneWidget);
      expect(find.text('兑换后可获得VIP权益7日'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('兑换周卡：确认框显示有效期7天并走周卡通道', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final bought = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(points: 2000),
          buyOverride: (id) async {
            bought.add(id);
            return const RedeemOutcome(true, 'ok');
          },
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('shop-item-vipWeekCard')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('是否要花费 1400 点灵感兑换「VIP周卡」'),
          findsOneWidget);
      expect(find.textContaining('有效期7天'), findsOneWidget);

      await tester.tap(find.text('确认'));
      await _settle(tester);
      expect(bought, ['vipWeekCard']);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('终身VIP', () {
    test('zhongshenvip：获得终身VIP、永久拥有、不限次（v4.9.50 内测）', () async {
      final r = await RewardService.redeem('zhongshenvip');
      expect(r.ok, isTrue);
      expect(r.message, contains('终身VIP'));

      final p = await UserStorage.load();
      expect(p.badge, UserProfile.badgeVipForever);
      expect(p.owns(UserProfile.badgeVipForever), isTrue);
      // v4.9.50：身份码改为不限次，不写 redeemedCodes
      expect(p.redeemedCodes, isNot(contains('zhongshenvip')));

      final again = await RewardService.redeem(' ZHONGSHENVIP ');
      expect(again.ok, isTrue);
      expect(again.message, contains('终身VIP'));
    });

    test('终身VIP 不受限时 VIP 到期摘牌影响', () async {
      final json = UserProfile(
        badge: UserProfile.badgeVipForever,
        ownedBadges: [UserProfile.badgeVipForever],
        vipCardCount: 1,
        vipCardExpireAt: DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      ).toJson();
      writeJson(json);

      final p = await UserStorage.load();
      expect(p.badge, UserProfile.badgeVipForever);
      expect(p.owns(UserProfile.badgeVipForever), isTrue);
    });

    testWidgets('终身VIP：红底白字胶囊', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(
          child: IdentityBadge(badge: UserProfile.badgeVipForever),
        ),
      ));
      expect(find.text('终身VIP'), findsOneWidget);
      final box = tester.widget<Container>(find.ancestor(
          of: find.text('终身VIP'), matching: find.byType(Container)));
      expect((box.decoration as BoxDecoration).color, const Color(0xFFCB5C50));
      final text = tester.widget<Text>(find.text('终身VIP'));
      expect(text.style?.color, Colors.white);
    });

    testWidgets('终身VIP 在身份选择页显示「永久」', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(
          profile: UserProfile(
            badge: UserProfile.badgeVipForever,
            ownedBadges: [UserProfile.badgeVipForever],
          ),
          wearOverride: (id) async => const RedeemOutcome(true, 'ok'),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('身份'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('badge_option_vip_forever')),
          findsOneWidget);
      expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('badge_validity_vip_forever')))
            .data,
        '永久',
      );
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
