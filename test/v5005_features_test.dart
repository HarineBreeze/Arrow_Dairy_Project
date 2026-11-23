import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/services/user_storage.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_toast.dart';

/// v5.0.5 回归：
/// 1. 笔记预览卡图片由 4:3 改为 1:1（卡片尺寸不变）——见 diary_card_image_test；
/// 2. 暖棕主题色位置移到墨灰与藕粉之间，取消免费，改为灵感杂货店
///    「主题·暖棕」1400 点永久兑换，未解锁时置灰并给引导提示。
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
    dir = Directory('/tmp/v5005_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
    UserStorage.revision.value = 0;
    AppToast.resetForTest();
  });

  void writeProfile(UserProfile p) {
    File('${dir.path}/user_profile.json').writeAsStringSync(jsonEncode(p.toJson()));
  }

  group('主题色注册表（v5.0.5）', () {
    test('暖棕移到墨灰与藕粉之间', () {
      expect(AccentCatalog.styles.map((s) => s.id).toList(),
          ['bamboo', 'ink', 'amber', 'lotus', 'ocean', 'violet']);
    });

    test('暖棕取消免费：needsShop=true 且不是 VIP', () {
      final amber = AccentCatalog.byId('amber');
      expect(amber.needsShop, isTrue);
      expect(amber.vip, isFalse);
      expect(AccentCatalog.needsShop('amber'), isTrue);
      expect(AccentCatalog.needsShop('bamboo'), isFalse);
      expect(AccentCatalog.needsShop('ink'), isFalse);
      // 名称与配色不变（仅权益形态改变）
      expect(amber.name, '暖棕');
      expect(amber.rgb, 0xB07D4F);
    });

    test('只有暖棕一套需要兑换', () {
      final needShop = AccentCatalog.styles.where((s) => s.needsShop).toList();
      expect(needShop.length, 1);
      expect(needShop.single.id, 'amber');
    });
  });

  group('灵感杂货店 · 主题·暖棕', () {
    test('商品定义：1400 点、永久、限兑 1 次', () {
      final item = RewardService.shopBadgeOf('themeAmber');
      expect(item, isNotNull);
      expect(item!.name, '主题·暖棕');
      expect(item.price, 1400);
      expect(item.limit, 1);
      expect(item.isTheme, isTrue);
      expect(item.isVipTimeCard, isFalse);
      expect(item.accentId, 'amber');
      expect(item.duration, Duration.zero, reason: '期限永久');
      expect(item.note, isNotEmpty);
    });

    test('商品列表包含它', () {
      expect(RewardService.shopBadges.any((e) => e.id == 'themeAmber'), isTrue);
    });
  });

  group('buyThemeAccent 兑换流程', () {
    test('灵感充足：扣 1400 → 写入已解锁主题', () async {
      writeProfile(UserProfile(points: 1500));
      final r = await RewardService.buyThemeAccent('themeAmber');
      expect(r.ok, isTrue);
      expect(r.message, contains('暖棕'));

      final p = await UserStorage.load();
      expect(p.points, 100);
      expect(p.ownsAccent('amber'), isTrue);
      expect(p.ownedAccents, contains('amber'));
    });

    test('灵感不足：不扣分、不解锁', () async {
      writeProfile(UserProfile(points: 1000));
      final r = await RewardService.buyThemeAccent('themeAmber');
      expect(r.ok, isFalse);
      expect(r.message, '灵感不足，还差 400 点');

      final p = await UserStorage.load();
      expect(p.points, 1000);
      expect(p.ownsAccent('amber'), isFalse);
    });

    test('已解锁：不重复扣分', () async {
      writeProfile(UserProfile(points: 2000, ownedAccents: ['amber']));
      final r = await RewardService.buyThemeAccent('themeAmber');
      expect(r.ok, isFalse);
      expect(r.message, '已拥有该主题色');
      expect((await UserStorage.load()).points, 2000);
    });

    test('非主题商品：拒绝', () async {
      final r = await RewardService.buyThemeAccent('vip');
      expect(r.ok, isFalse);
      expect(r.message, '商品不存在');
    });

    test('商品不存在：拒绝', () async {
      final r = await RewardService.buyThemeAccent('nope');
      expect(r.ok, isFalse);
      expect(r.message, '商品不存在');
    });

    test('兑换后 usedCount 记为 1（卡片显示 1/1 且置灰）', () async {
      writeProfile(UserProfile(points: 1500));
      await RewardService.buyThemeAccent('themeAmber');
      final p = await UserStorage.load();
      final item = RewardService.shopBadgeOf('themeAmber')!;
      expect(item.usedCount(p), 1);
    });
  });

  group('UserProfile.ownedAccents 序列化', () {
    test('默认空列表，ownsAccent 为 false', () {
      final p = UserProfile();
      expect(p.ownedAccents, isEmpty);
      expect(p.ownsAccent('amber'), isFalse);
    });

    test('toJson / fromJson 往返保留', () {
      final p = UserProfile(points: 100, ownedAccents: ['amber']);
      final back = UserProfile.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      expect(back.ownedAccents, ['amber']);
      expect(back.ownsAccent('amber'), isTrue);
    });

    test('旧档案无 ownedAccents 字段：回落空列表（零迁移）', () {
      final old = {
        'nickname': 'AyoDiray',
        'points': 10,
        'badge': UserProfile.badgeNormal,
        'ownedBadges': [UserProfile.badgeNormal],
        'userId': '10001',
        'registeredAt': '2024-01-01',
      };
      final p = UserProfile.fromJson(old);
      expect(p.ownedAccents, isEmpty);
      expect(p.points, 10);
    });
  });

  group('设置页主题色抽屉', () {
    testWidgets('暖棕未解锁：置灰并提示去灵感杂货店', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      writeProfile(UserProfile(points: 0)); // 未拥有暖棕
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await _settle(tester);

      final entry = find.text('主题色');
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await _settle(tester);

      expect(find.text('暖棕'), findsOneWidget, reason: '抽屉里应列出暖棕');
      await tester.tap(find.text('暖棕'));
      await _settle(tester);

      expect(find.text('未解锁，赶紧前往灵感杂货店兑换吧～'), findsOneWidget);

      // AppToast 自带 1.6s 自动收回定时器；显式清掉，避免测试结束时
      // 仍挂着 pending Timer 触发框架断言。
      AppToast.resetForTest();
      await tester.pump(const Duration(milliseconds: 400));
    });

    testWidgets('已解锁暖棕：点击直接选中，不出未解锁提示', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      writeProfile(UserProfile(points: 0, ownedAccents: ['amber']));
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await _settle(tester);

      final entry = find.text('主题色');
      await tester.ensureVisible(entry);
      await tester.pump();
      await tester.tap(entry);
      await _settle(tester);

      await tester.tap(find.text('暖棕'));
      await _settle(tester);

      expect(find.text('未解锁，赶紧前往灵感杂货店兑换吧～'), findsNothing);
      expect(AppPalette.accent.id, 'amber', reason: '已解锁可直接切换');
    });
  });
}
