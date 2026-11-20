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
import 'package:ayodiray/widgets/identity_badge.dart';

/// 身份切换 / 灵感杂货店 / 活动分组文案的回归测试。
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

  group('灵感杂货店兑换', () {
    test('灵感充足：扣 50 分 → 加入已拥有 → 立即佩戴', () async {
      writeProfile(UserProfile(points: 120));
      final r = await RewardService.buyBadge(UserProfile.badgeBirthday);
      expect(r.ok, isTrue);
      expect(r.message, contains('诞生日'));

      final p = await UserStorage.load();
      expect(p.points, 70);
      expect(p.badge, UserProfile.badgeBirthday);
      expect(p.owns(UserProfile.badgeBirthday), isTrue);
    });

    test('灵感不足：不扣分、不发放', () async {
      writeProfile(UserProfile(points: 30));
      final r = await RewardService.buyBadge(UserProfile.badgeBirthday);
      expect(r.ok, isFalse);
      expect(r.message, contains('灵感不足'));

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
      expect(r.message, '已拥有该身份');
      expect((await UserStorage.load()).points, 100);
    });

    test('商品不在售：拒绝', () async {
      final r = await RewardService.buyBadge('not-a-badge');
      expect(r.ok, isFalse);
      expect(r.message, '商品不存在');
    });
  });

  group('身份切换', () {
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
      expect(r.message, '尚未拥有该身份');
    });

    test('已是当前牌：提示无需切换', () async {
      writeProfile(UserProfile(badge: UserProfile.badgeNormal));
      final r = await RewardService.wearBadge(UserProfile.badgeNormal);
      expect(r.ok, isFalse);
      expect(r.message, '已是当前身份');
    });
  });

  group('设置页活动分组', () {
    testWidgets('标题为「活动」，兑换码副标题为「参与活动获得兑换码」', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();

      expect(find.text('活动'), findsOneWidget);
      expect(find.text('兑换与灵感'), findsNothing);
      expect(find.text('参与活动获得兑换码'), findsOneWidget);
      expect(find.text('兑换码'), findsOneWidget);
    });
  });

  group('灵感杂货店页面', () {
    testWidgets('商品卡：名称 + 备注 + 价格 + 兑换次数，没有按钮', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(points: 120),
        ),
      ));
      await tester.pump();

      expect(find.text('灵感杂货店'), findsOneWidget);
      expect(find.text('剩余灵感'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);

      // 分组标题与提示语
      expect(find.text('道具兑换'), findsOneWidget);
      expect(find.text('灵感是兑换道具的货币，可通过参与活动的方式获得'),
          findsOneWidget);

      // 诞生日（商品名带「-身份」后缀）
      expect(find.text('诞生日-身份'), findsOneWidget);
      expect(find.text('纪念APP正式上线，1年后下架'), findsOneWidget);
      expect(find.text('50 点'), findsOneWidget);
      expect(find.text('0/1'), findsOneWidget, reason: '次数改为「已兑/上限」');

      // VIP日卡
      expect(find.text('VIP日卡'), findsOneWidget);
      expect(find.text('兑换后可获得VIP权益1日'), findsOneWidget);
      expect(find.text('200 点'), findsOneWidget);
      expect(find.text('0/30'), findsOneWidget, reason: '次数改为「已兑/上限」');

      // 卡片不再有独立按钮文案，也不再展示身份胶囊
      expect(find.text('兑换'), findsNothing);
      expect(find.text('已拥有'), findsNothing);
      expect(find.text('灵感不足'), findsNothing);
      expect(find.byType(IdentityBadge), findsNothing);

      // 兑换次数：无底纹（外层不该有带圆角色块的 Container 包着数字），
      // 字色与商品备注同为淡灰 #8FA09A
      final countText = tester.widget<Text>(find.text('0/30'));
      expect(countText.style?.color, const Color(0xFF8FA09A));
      final noteText = tester.widget<Text>(find.text('兑换后可获得VIP权益1日'));
      expect(countText.style?.color, noteText.style?.color,
          reason: '次数字色与商品简介一致');
      final decorated = find.ancestor(
        of: find.text('0/30'),
        matching: find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).borderRadius ==
                BorderRadius.circular(8)),
      );
      // 旧版次数胶囊（圆角 8 的小色块）应彻底移除；白卡是圆角 16，不匹配
      expect(decorated, findsNothing, reason: '兑换次数不应再有独立底纹胶囊');
    });

    testWidgets('提示语与分组标题：灵感是兑换道具的货币 / 道具兑换', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(points: 120),
        ),
      ));
      await tester.pump();

      expect(find.text('灵感是兑换道具的货币，可通过参与活动的方式获得'),
          findsOneWidget);
      expect(find.text('道具兑换'), findsOneWidget);
      expect(find.text('灵感可通过参与活动的方式获得'), findsNothing);
      expect(find.text('身份'), findsNothing);
      expect(find.text('佩戴后显示在昵称旁'), findsNothing);
      expect(find.textContaining('兑换后会立即佩戴'), findsNothing);
      expect(find.textContaining('每日首次发布笔记'), findsNothing);
    });

    testWidgets('灵感不足：点击卡片提示差额，不弹确认框、不扣分', (tester) async {
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

      await tester.tap(find.byKey(const ValueKey('shop-item-birthday')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('灵感不足'), findsOneWidget);
      expect(find.textContaining('是否要花费'), findsNothing);
      expect(bought, 0);
      await tester.pump(const Duration(seconds: 2)); // 排空 toast 定时器
    });

    testWidgets('已拥有：卡片置灰，点击提示已拥有', (tester) async {
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

      // 卡片背景变灰
      final card = tester.widget<Container>(find
          .descendant(
              of: find.byKey(const ValueKey('shop-item-birthday')),
              matching: find.byType(Container))
          .first);
      expect((card.decoration as BoxDecoration).color,
          const Color(0xFFF2F6F4));

      await tester.tap(find.byKey(const ValueKey('shop-item-birthday')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('已拥有「诞生日-身份」'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('可兑换：点卡片弹「是否要花费x灵感兑换」→ 确认后扣分刷新', (tester) async {
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
            return const RedeemOutcome(true, '兑换成功，已佩戴「诞生日」身份');
          },
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('shop-item-birthday')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('是否要花费 50 点灵感兑换「诞生日-身份」'),
          findsOneWidget);
      expect(find.textContaining('兑换后剩余'), findsNothing,
          reason: '确认框不再提示兑换后剩余灵感');

      await tester.tap(find.text('确认'));
      await _settle(tester);

      expect(find.text('70'), findsOneWidget, reason: '余额应刷新为 70');
      await tester.pump(const Duration(seconds: 2)); // 排空 toast 定时器
    });
  });

  group('VIP日卡', () {
    test('兑换：扣 200 分 → 计次数 → 立即佩戴且 1 天内生效', () async {
      writeProfile(UserProfile(points: 260));
      final r = await RewardService.buyVipCard(UserProfile.badgeVip);
      expect(r.ok, isTrue);
      expect(r.message, contains('1天'));

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

    test('灵感不足：不扣分、不计次', () async {
      writeProfile(UserProfile(points: 199));
      final r = await RewardService.buyVipCard(UserProfile.badgeVip);
      expect(r.ok, isFalse);
      expect(r.message, contains('灵感不足'));

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

    testWidgets('杂货店展示 VIP日卡：备注、价格与已兑次数', (tester) async {
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

      expect(find.text('兑换后可获得VIP权益1日'), findsOneWidget);
      expect(find.text('2/30'), findsOneWidget);
      expect(find.text('200 点'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('兑换 VIP日卡：点卡片 → 确认框 → 走日卡购买通道', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final boughtIds = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(points: 300),
          buyOverride: (id) async {
            boughtIds.add(id);
            return const RedeemOutcome(true, '兑换成功，VIP身份生效1天');
          },
        ),
      ));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('shop-item-vip')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('是否要花费 200 点灵感兑换「VIP日卡」'), findsOneWidget);
      expect(find.textContaining('有效期1天'), findsOneWidget);
      expect(find.textContaining('兑换后剩余'), findsNothing);

      await tester.tap(find.text('确认'));
      await _settle(tester);
      expect(boughtIds, [UserProfile.badgeVip]);
      await tester.pump(const Duration(seconds: 2)); // 排空 toast 定时器
    });

    testWidgets('日卡达到 30 次上限：卡片置灰，点击提示上限', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: PointsShopScreen(
          loadOverride: () async => UserProfile(
            points: 9999,
            vipCardCount: 30,
          ),
        ),
      ));
      await tester.pump();

      final card = tester.widget<Container>(find
          .descendant(
              of: find.byKey(const ValueKey('shop-item-vip')),
              matching: find.byType(Container))
          .first);
      expect((card.decoration as BoxDecoration).color,
          const Color(0xFFF2F6F4));

      await tester.tap(find.byKey(const ValueKey('shop-item-vip')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('已达兑换上限'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('档案页身份', () {
    testWidgets('点「身份」弹出选项，可在普通版与已有牌之间切换', (tester) async {
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

      await tester.tap(find.text('身份'));
      await tester.pump(); // route 入栈
      await tester.pump(const Duration(milliseconds: 400)); // 弹层滑入
      await tester.pump(const Duration(milliseconds: 400));
      // v4.9.48：「选择身份」标题移除，弹层直接列选项
      expect(find.text('选择身份'), findsNothing);
      // 选项：普通版恒在 + 已拥有的 VIP
      expect(find.byKey(const ValueKey('badge_option_normal')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge_option_vip')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('badge_option_normal')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // 弹层滑出
      await tester.pump(const Duration(milliseconds: 400));

      expect(worn, UserProfile.badgeNormal);
      expect(find.text('选择身份'), findsNothing, reason: '选完应关闭选项');
      expect(find.text('普通版'), findsOneWidget, reason: '页面应显示已切换的普通版');
      await tester.pump(const Duration(seconds: 2)); // 排空 toast 定时器
    });

    testWidgets('身份选择页：移除名称文字，右侧显示有效期（永久/剩余x天）',
        (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(600, 1200);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(
          profile: UserProfile(
            badge: UserProfile.badgeNormal,
            vipCardCount: 1,
            vipCardExpireAt: DateTime.now()
                .add(const Duration(hours: 20))
                .toIso8601String(),
          ),
          wearOverride: (id) async =>
              const RedeemOutcome(true, '已切换'),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('身份'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // 普通版（永久拥有）→「永久」
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('badge_validity_normal')))
            .data,
        '永久',
      );
      // VIP 日卡（限时、非永久拥有）→「剩余1天」
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('badge_validity_vip')))
            .data,
        '剩余1天',
      );
      // 选项里不再有单独的铭牌名称文字（只有胶囊本身）
      expect(find.byKey(const ValueKey('badge_option_vip')), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('点「灵感」进入灵感杂货店', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(
          profile: UserProfile(points: 60),
          loadOverride: () async => UserProfile(points: 60),
          shopBuilder: () => const Scaffold(
            body: Center(child: Text('灵感杂货店页')),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('灵感'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('灵感杂货店页'), findsOneWidget);
    });
  });
}
