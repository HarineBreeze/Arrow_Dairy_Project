import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/theme/app_palette.dart';

void main() {
  final root = Directory.current.path;
  String src(String rel) => File('$root/$rel').readAsStringSync();

  final rewardSrc = src('lib/services/reward_service.dart');
  final mainSrc = src('lib/main.dart');
  final convertSrc = src('lib/widgets/wishlist_convert_celebration.dart');
  final trashSrc = src('lib/screens/trash_screen.dart');

  setUp(() {
    AppSettings.persistOverride = () async {};
  });
  tearDown(() async {
    // 还原全局主题到默认，避免污染其它测试
    await AppSettings.setAccentId(AccentCatalog.bamboo);
    AppSettings.persistOverride = null;
  });

  UserProfile noVipProfile() => UserProfile(
        badge: UserProfile.badgeNormal,
        ownedBadges: const [UserProfile.badgeNormal],
      );
  UserProfile vipProfile() => UserProfile(
        badge: UserProfile.badgeVip,
        ownedBadges: const [UserProfile.badgeNormal, UserProfile.badgeVip],
      );

  group('v5.0.24 ① 权益失去后 VIP 主题还原默认', () {
    test('无权益 + 当前 VIP 主题 → 还原竹青，返回 true', () async {
      await AppSettings.setAccentId('lotus');
      expect(AppSettings.accentId, 'lotus');
      final changed = await RewardService.syncVipAccent(noVipProfile());
      expect(changed, isTrue);
      expect(AppSettings.accentId, AccentCatalog.bamboo);
    });

    test('有权益 + 当前 VIP 主题 → 保留，返回 false', () async {
      await AppSettings.setAccentId('ocean');
      final changed = await RewardService.syncVipAccent(vipProfile());
      expect(changed, isFalse);
      expect(AppSettings.accentId, 'ocean');
    });

    test('无权益 + 当前非 VIP 主题 → 不动，返回 false', () async {
      await AppSettings.setAccentId('ink');
      final changed = await RewardService.syncVipAccent(noVipProfile());
      expect(changed, isFalse);
      expect(AppSettings.accentId, 'ink');
    });

    test('三种 VIP 主题（藕粉/雾蓝/霞紫）都会被还原', () async {
      for (final id in ['lotus', 'ocean', 'violet']) {
        await AppSettings.setAccentId(id);
        await RewardService.syncVipAccent(noVipProfile());
        expect(AppSettings.accentId, AccentCatalog.bamboo, reason: '$id 应被还原');
      }
    });

    test('源码：AccentCatalog 三种 VIP 主题均标记 vip=true', () {
      final vipStyles = AccentCatalog.styles.where((s) => s.vip).map((s) => s.id).toList();
      expect(vipStyles, containsAll(['lotus', 'ocean', 'violet']));
      expect(AccentCatalog.isVip('bamboo'), isFalse);
      expect(AccentCatalog.isVip('ink'), isFalse);
    });

    test('源码：novip 分支与 App 启动均调用 syncVipAccent', () {
      expect(rewardSrc, contains('static Future<bool> syncVipAccent(UserProfile profile)'));
      expect(rewardSrc, contains('AccentCatalog.isVip(current)'));
      expect(rewardSrc, contains('AppSettings.setAccentId(AccentCatalog.bamboo)'));
      // novip 分支调用
      expect(rewardSrc, contains('await syncVipAccent(profile);'));
      // 启动兜底
      expect(mainSrc, contains('RewardService.syncVipAccent(await UserStorage.load())'));
    });
  });

  group('v5.0.24 ② 转正翻转：单向翻一圈不翻回', () {
    test('源码：翻整圈 math.pi * 2，无 reverse / dismissed', () {
      expect(convertSrc, contains('final angle = t * math.pi * 2;'));
      expect(convertSrc, isNot(contains('_ctrl.reverse();')));
      expect(convertSrc, isNot(contains('AnimationStatus.dismissed')));
    });

    test('源码：completed 直接回调结束，粒子仍在', () {
      expect(convertSrc, contains('AnimationStatus.completed'));
      expect(convertSrc, contains('widget.onDone?.call()'));
      expect(convertSrc, contains('class _ConvertBurst extends CustomPainter'));
    });
  });

  group('v5.0.24 ③ 回收站首卡与筛选栏间距对齐卡片间距', () {
    test('源码：普通态 padding top=8（=卡片间距），选择态保持 14', () {
      expect(trashSrc, contains('16, _mode == null ? 8 : 14, 16, 12'));
      // 卡片间距 x = SizedBox(height: 8)
      expect(trashSrc, contains('const SizedBox(height: 8)'));
    });
  });
}
