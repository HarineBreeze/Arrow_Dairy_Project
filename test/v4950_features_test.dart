import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/services/user_storage.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_version.dart';
import 'package:ayodiray/utils/haptics.dart';

/// v4.9.50 行为回归：
/// 1. 版本号同步到 V4.9.50；
/// 2. 主题色：暖棕 / 墨灰免费且紧跟竹青，藕粉 / 雾蓝仍 VIP；
/// 3. 兑换码 vip / zhongshenvip / neice 不限次、每次生效、不写 redeemedCodes。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = Directory(
        '${Directory.systemTemp.path}/v4950_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    Haptics.enabled = false;
    Haptics.throttleEnabled = false;
  });

  tearDown(() async {
    Haptics.enabled = true;
    Haptics.throttleEnabled = true;
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
    UserStorage.revision.value = 0;
  });

  Future<UserProfile> writeProfile(UserProfile p) async {
    final f = File('${dir.path}/user_profile.json');
    await f.writeAsString(jsonEncode(p.toJson()));
    return p;
  }

  Future<UserProfile> readProfile() async => UserStorage.load();

  group('版本号', () {
    test('展示版本同步到 V4.9.50', () {
      expect(AppVersion.displayVersion, 'V4.9.50');
    });
  });

  group('主题色免费属性与排序', () {
    test('暖棕 / 墨灰为免费，藕粉 / 雾蓝为 VIP', () {
      final byId = {for (final s in AccentCatalog.styles) s.id: s};
      expect(byId['bamboo']!.vip, false);
      expect(byId['amber']!.vip, false); // 暖棕
      expect(byId['ink']!.vip, false); // 墨灰
      expect(byId['lotus']!.vip, true); // 藕粉
      expect(byId['ocean']!.vip, true); // 雾蓝
    });

    test('暖棕 / 墨灰排在竹青之后、VIP 色之前', () {
      final ids = AccentCatalog.styles.map((s) => s.id).toList();
      expect(ids, ['bamboo', 'amber', 'ink', 'lotus', 'ocean']);
    });

    test('按序 Free 色共 3 套', () {
      expect(AccentCatalog.styles.where((s) => !s.vip).length, 3);
    });
  });

  group('身份兑换码不限次', () {
    test('3 个码登记在不限次表，限次表为空', () {
      expect(
          RewardService.unlimitedBadgeCodes.keys.toSet(),
          {'vip', 'zhongshenvip', 'neice'});
      expect(RewardService.badgeCodes.isEmpty, true);
    });

    test('vip 可重复兑换且不写 redeemedCodes', () async {
      await writeProfile(UserProfile());
      final r1 = await RewardService.redeem('VIP'); // 忽略大小写
      expect(r1.ok, true);
      expect(r1.message, contains('VIP'));
      final p1 = await readProfile();
      expect(p1.badge, UserProfile.badgeVip);
      expect(p1.redeemedCodes.contains('vip'), false);

      // 先切回普通，再兑换一次：仍可成功，证明不限次
      p1.badge = UserProfile.badgeNormal;
      await writeProfile(p1);
      final r2 = await RewardService.redeem('vip');
      expect(r2.ok, true);
      final p2 = await readProfile();
      expect(p2.badge, UserProfile.badgeVip);
      expect(p2.redeemedCodes.contains('vip'), false);
    });

    test('zhongshenvip / neice 各自可重复兑换', () async {
      await writeProfile(UserProfile());
      for (final code in ['zhongshenvip', 'neice', 'zhongshenvip', 'neice']) {
        final r = await RewardService.redeem(code);
        expect(r.ok, true);
      }
      final p = await readProfile();
      expect(p.ownedBadges, contains(UserProfile.badgeVipForever));
      expect(p.ownedBadges, contains(UserProfile.badgeBeta));
      expect(p.redeemedCodes.contains('zhongshenvip'), false);
      expect(p.redeemedCodes.contains('neice'), false);
    });

    test('已出现在历史 redeemedCodes 里的身份码也不被拦截', () async {
      // 老档案里这三个码曾被记为已用；改为不限次后必须照常生效
      final p = UserProfile()..redeemedCodes = ['vip', 'neice', 'zhongshenvip'];
      await writeProfile(p);
      final r = await RewardService.redeem('vip');
      expect(r.ok, true);
      expect(r.message, isNot('该兑换码已使用过'));
      final after = await readProfile();
      expect(after.badge, UserProfile.badgeVip);
    });
  });
}
