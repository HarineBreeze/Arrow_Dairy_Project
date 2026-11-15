import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/home_screen.dart';
import 'package:ayodiray/screens/profile_edit_screen.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/services/user_storage.dart';
import 'package:ayodiray/widgets/identity_badge.dart';

/// 积分 / 身份铭牌 / 兑换码 / 卡片分享的回归测试。
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
    dir = Directory('/tmp/rewards_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
    UserStorage.revision.value = 0;
  });

  Future<void> writeProfile(UserProfile p) async {
    File('${dir.path}/user_profile.json')
        .writeAsStringSync(jsonEncode(p.toJson()));
  }

  group('档案模型', () {
    test('积分 / 铭牌 / 兑换记录可往返序列化', () {
      final p = UserProfile(
        nickname: '阿尤',
        points: 120,
        badge: UserProfile.badgeVip,
        redeemedCodes: ['ayouriji', 'vip'],
        lastWriteReward: '2026-11-13',
      );
      final back = UserProfile.fromJson(p.toJson());
      expect(back.points, 120);
      expect(back.badge, 'vip');
      expect(back.redeemedCodes, ['ayouriji', 'vip']);
      expect(back.lastWriteReward, '2026-11-13');
    });

    test('旧档案缺字段时回落为 0 积分 / 普通版身份牌', () {
      final back = UserProfile.fromJson({'nickname': '小明'});
      expect(back.points, 0);
      expect(back.badge, UserProfile.badgeNormal);
      expect(back.ownedBadges, [UserProfile.badgeNormal]);
      expect(back.redeemedCodes, isEmpty);
      expect(back.lastWriteReward, '');
    });

    test('旧档案已佩戴的铭牌会补进已拥有列表', () {
      final back = UserProfile.fromJson({'nickname': '小明', 'badge': 'vip'});
      expect(back.badge, UserProfile.badgeVip);
      expect(back.owns(UserProfile.badgeVip), isTrue);
      expect(back.owns(UserProfile.badgeNormal), isTrue);
    });

    test('用户ID / 注册日可往返序列化，新档案自动生成', () {
      final p = UserProfile();
      expect(p.userId, isNotEmpty);
      expect(p.userId, startsWith('AYO-'));
      expect(p.registeredAt, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(p.usedDays, 1, reason: '注册当天记为第 1 天');

      final back = UserProfile.fromJson(p.toJson());
      expect(back.userId, p.userId, reason: 'ID 必须稳定不漂移');
      expect(back.registeredAt, p.registeredAt);
    });

    test('不同用户生成不同 ID', () {
      final a = UserProfile();
      final b = UserProfile();
      expect(a.userId, isNot(b.userId));
    });

    test('使用时间按自然日递增', () {
      final old = UserProfile.dayKey(
          DateTime.now().subtract(const Duration(days: 9)));
      final p = UserProfile.fromJson({'registeredAt': old});
      expect(p.usedDays, 10, reason: '9 天前注册 → 含当天共 10 天');
    });

    test('旧档案缺 ID / 注册日时读档会补齐并固化', () async {
      // 模拟 v4.9.21 以前的档案（没有 userId / registeredAt）
      File('${dir.path}/user_profile.json').writeAsStringSync(jsonEncode({
        'nickname': '老用户',
        'points': 50,
      }));
      final p = await UserStorage.load();
      expect(p.userId, isNotEmpty);
      expect(p.registeredAt, isNotEmpty);
      // 回写固化：再读一次仍是同一个 ID
      final again = await UserStorage.load();
      expect(again.userId, p.userId);
      expect(again.points, 50);
    });

    test('身份牌有效期文案：永久 / 剩余x天', () {
      final vip = UserProfile.badgeVip;
      // 永久拥有 → 永久
      expect(UserProfile.validityLabel(vip, owned: true, expiresAt: null),
          '永久');
      expect(UserProfile.validityLabel(UserProfile.badgeNormal,
          owned: true, expiresAt: null), '永久');
      // 限时 VIP 日卡 → 剩余1天
      expect(
        UserProfile.validityLabel(vip,
            owned: false,
            expiresAt: DateTime.now().add(const Duration(hours: 20))),
        '剩余1天',
      );
      // 多日有效期
      expect(
        UserProfile.validityLabel(vip,
            owned: false,
            expiresAt: DateTime.now().add(const Duration(days: 3))),
        '剩余3天',
      );
      // 已过期 / 没有到期时间 → 回落永久
      expect(UserProfile.validityLabel(vip, owned: false, expiresAt: null),
          '永久');
      expect(
        UserProfile.validityLabel(vip,
            owned: false,
            expiresAt: DateTime.now().subtract(const Duration(hours: 1))),
        '永久',
      );
    });
  });

  group('兑换码', () {
    test('ayouriji：+100 积分，重复兑换被拒', () async {
      final first = await RewardService.redeem(' ayouriji ');
      expect(first.ok, isTrue);
      expect(first.message, contains('+100'));
      expect((await UserStorage.load()).points, 100);

      final second = await RewardService.redeem('AYOURIJI');
      expect(second.ok, isFalse);
      expect(second.message, '该兑换码已使用过');
      expect((await UserStorage.load()).points, 100, reason: '不能重复加分');
    });

    test('17381113325：每次 +1000 积分，不限次数', () async {
      final first = await RewardService.redeem('17381113325');
      expect(first.ok, isTrue);
      expect(first.message, contains('+1000'));
      expect((await UserStorage.load()).points, 1000);

      // 前后空格也能识别，第二次仍然成功
      final second = await RewardService.redeem(' 17381113325 ');
      expect(second.ok, isTrue);
      final p = await UserStorage.load();
      expect(p.points, 2000);
      expect(p.redeemedCodes, isEmpty, reason: '无限次码不写已使用记录');
    });

    test('13031210237：每次 -1000 积分，不限次数，最低为 0 不为负', () async {
      // 先用加分码攒到 2500
      await RewardService.redeem('17381113325');
      await RewardService.redeem('17381113325');
      await RewardService.redeem('ayouriji');
      expect((await UserStorage.load()).points, 2100);

      final first = await RewardService.redeem('13031210237');
      expect(first.ok, isTrue);
      expect(first.message, contains('-1000'));
      expect((await UserStorage.load()).points, 1100);

      // 无限次：第二次仍生效；不写已用记录
      final second = await RewardService.redeem(' 13031210237 ');
      expect(second.ok, isTrue);
      var p = await UserStorage.load();
      expect(p.points, 100);
      expect(p.redeemedCodes, isNot(contains('13031210237')));

      // 第三次余额不足 1000：只扣到 0，绝不为负
      final third = await RewardService.redeem('13031210237');
      expect(third.ok, isTrue);
      expect(third.message, contains('-100'));
      p = await UserStorage.load();
      expect(p.points, 0, reason: '积分最低为 0');

      // 已经是 0 再兑，仍为 0
      await RewardService.redeem('13031210237');
      expect((await UserStorage.load()).points, 0);
    });

    test('neice：获得内测版身份牌', () async {
      final r = await RewardService.redeem('neice');
      expect(r.ok, isTrue);
      expect(r.message, contains('内测版'));
      final p = await UserStorage.load();
      expect(p.badge, UserProfile.badgeBeta);
      expect(p.owns(UserProfile.badgeBeta), isTrue);
      expect(p.owns(UserProfile.badgeNormal), isTrue, reason: '普通版恒在');
    });

    test('vip：获得 VIP 身份牌（覆盖已有佩戴）', () async {
      await writeProfile(UserProfile(badge: UserProfile.badgeBeta));
      final r = await RewardService.redeem('vip');
      expect(r.ok, isTrue);
      expect(r.message, contains('VIP'));
      expect((await UserStorage.load()).badge, UserProfile.badgeVip);
    });

    test('无效兑换码不改变任何数据', () async {
      final r = await RewardService.redeem('notacode');
      expect(r.ok, isFalse);
      expect(r.message, contains('无效'));
      final p = await UserStorage.load();
      expect(p.points, 0);
      expect(p.badge, UserProfile.badgeNormal);
    });

    test('每次兑换都会通知档案更新（侧边栏铭牌即时刷新）', () async {
      var fired = 0;
      void listener() => fired++;
      UserStorage.revision.addListener(listener);
      addTearDown(() => UserStorage.revision.removeListener(listener));

      await RewardService.redeem('vip');
      expect(fired, greaterThan(0));
    });
  });

  group('每日首次发布奖励', () {
    test('当天第一次 +20，第二次不再加', () async {
      final first = await RewardService.awardDailyWrite();
      expect(first, RewardService.dailyWritePoints);
      expect((await UserStorage.load()).points, 20);

      final second = await RewardService.awardDailyWrite();
      expect(second, 0);
      expect((await UserStorage.load()).points, 20);
    });

    test('第二天再次发布可继续领取', () async {
      await writeProfile(UserProfile(points: 20, lastWriteReward: '2000-01-01'));
      final earned = await RewardService.awardDailyWrite();
      expect(earned, 20);
      expect((await UserStorage.load()).points, 40);
    });
  });

  group('身份牌组件', () {
    testWidgets('普通版：灰底白字', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: IdentityBadge(badge: UserProfile.badgeNormal)),
      ));
      expect(find.text('普通版'), findsOneWidget);
      final box = tester.widget<Container>(
          find.ancestor(of: find.text('普通版'), matching: find.byType(Container)));
      expect((box.decoration as BoxDecoration).color,
          const Color(0xFF8FA09A));
    });

    testWidgets('诞生日：绿底白字', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: IdentityBadge(badge: UserProfile.badgeBirthday)),
      ));
      expect(find.text('诞生日'), findsOneWidget);
      final box = tester.widget<Container>(find.ancestor(
          of: find.text('诞生日'), matching: find.byType(Container)));
      expect((box.decoration as BoxDecoration).color,
          const Color(0xFF3E8E6D));
    });

    testWidgets('内测版：橙底白字', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: IdentityBadge(badge: UserProfile.badgeBeta)),
      ));
      expect(find.text('内测版'), findsOneWidget);
      final box = tester.widget<Container>(
          find.ancestor(of: find.text('内测版'), matching: find.byType(Container)));
      expect((box.decoration as BoxDecoration).color,
          const Color(0xFFF08C3A));
    });

    testWidgets('VIP：红底白字', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: IdentityBadge(badge: UserProfile.badgeVip)),
      ));
      expect(find.text('VIP'), findsOneWidget);
      final box = tester.widget<Container>(
          find.ancestor(of: find.text('VIP'), matching: find.byType(Container)));
      expect((box.decoration as BoxDecoration).color,
          const Color(0xFFCB5C50));
    });

    testWidgets('未知 id 不占位', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Center(child: IdentityBadge(badge: 'unknown')),
      ));
      expect(find.byType(Container), findsNothing);
    });
  });

  group('个人信息页', () {
    testWidgets('显示身份牌与积分', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(
          profile: UserProfile(points: 120, badge: UserProfile.badgeVip),
        ),
      ));
      await tester.pump();

      expect(find.text('身份牌'), findsOneWidget);
      expect(find.text('VIP'), findsOneWidget);
      expect(find.text('积分'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('分'), findsOneWidget);
    });

    testWidgets('默认佩戴普通版身份牌', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(profile: UserProfile(points: 0)),
      ));
      await tester.pump();

      expect(find.text('普通版'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });
  });

  group('设置页兑换码', () {
    testWidgets('输入兑换码 → 提示兑换结果', (tester) async {
      String? got;
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(
          redeemOverride: (code) async {
            got = code;
            return const RedeemOutcome(true, '兑换成功，+100 积分');
          },
        ),
      ));
      await tester.pump();

      expect(find.text('兑换码'), findsOneWidget);
      await tester.tap(find.text('兑换码'));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField), 'ayouriji');
      await tester.tap(find.text('兑换'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(got, 'ayouriji');
      expect(find.text('兑换成功，+100 积分'), findsOneWidget);
      // 排空提示自动收起定时器
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('笔记卡片长按分享', () {
    Future<void> writeEntries(List<DiaryEntry> entries) async {
      File('${dir.path}/diaries.json')
          .writeAsStringSync(jsonEncode(entries.map((e) => e.toJson()).toList()));
    }

    Future<void> longPressCard(WidgetTester tester, String text) async {
      final g = await tester.startGesture(tester.getCenter(find.text(text)));
      await tester.pump(const Duration(milliseconds: 600));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('普通笔记：菜单含分享，点击后走分享链路', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 900);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

      final now = DateTime.now();
      await writeEntries([
        DiaryEntry(
          id: 'n1',
          title: '分享测试笔记',
          content: '正文',
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day),
        ),
      ]);

      DiaryEntry? shared;
      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(onShare: (ctx, entry) async => shared = entry),
      ));
      await _settle(tester);

      await longPressCard(tester, '分享测试笔记');
      expect(find.text('分享'), findsOneWidget);
      // 顺序：置顶、编辑、分享、删除
      final pinY = tester.getCenter(find.text('置顶')).dy;
      final editY = tester.getCenter(find.text('编辑')).dy;
      final shareY = tester.getCenter(find.text('分享')).dy;
      final delY = tester.getCenter(find.text('删除')).dy;
      expect(pinY < editY && editY < shareY && shareY < delY, isTrue,
          reason: '菜单顺序应为置顶、编辑、分享、删除');

      await tester.tap(find.text('分享'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(shared?.id, 'n1');
    });

    testWidgets('加密笔记：菜单只有置顶，不出现分享', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 900);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

      final now = DateTime.now();
      await writeEntries([
        DiaryEntry(
          id: 'e1',
          title: '',
          subtitle: '私密片段',
          content: '加密内容',
          encrypted: true,
          password: '1234',
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day),
        ),
      ]);

      var sharedCalls = 0;
      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(onShare: (ctx, entry) async => sharedCalls++),
      ));
      await _settle(tester);

      await longPressCard(tester, '私密片段');
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('分享'), findsNothing);
      expect(find.text('编辑'), findsNothing);
      expect(find.text('删除'), findsNothing);
      expect(sharedCalls, 0);
    });
  });
}
