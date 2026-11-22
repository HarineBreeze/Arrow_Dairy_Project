import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/main.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/countdown_edit_screen.dart';
import 'package:ayodiray/screens/profile_edit_screen.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.47 行为回归：
/// 1. 事件编辑页 VIP 角标跟在「到期提醒」标题后，旧名「提醒时间」移除；
/// 2. 底部滑入警示语 AppToast 的背景随主题色换（竹青原值逐字节不变）；
/// 3. 档案页移除「点击更换头像」提示；
/// 4. 侧边栏设置按钮图标走主题主色；
/// 5. 设置页「深色模式」改右箭头抽屉，含跟随系统/已开启/已关闭。
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
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() => AppSettings.persistOverride = () async {});
  tearDownAll(() => AppSettings.persistOverride = null);

  setUp(() async {
    dir = Directory('/tmp/v4947_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    await AppSettings.setThemeMode(AppThemeMode.system);
    await AppSettings.setAccentId('bamboo');
    AppToast.resetForTest();
  });

  tearDown(() async {
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    await AppSettings.setThemeMode(AppThemeMode.system);
    await AppSettings.setAccentId('bamboo');
    AppToast.resetForTest();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  group('警示语主题色', () {
    test('竹青 toastBg 为原值逐字节不变', () {
      AppPalette.accent = AccentCatalog.byId('bamboo');
      expect(AppPalette.toastBg, const Color(0xFF24382F));
    });

    test('其它主题 toastBg 换成各自深色顶栏色', () {
      for (final id in ['lotus', 'ocean', 'amber', 'ink', 'violet']) {
        final a = AccentCatalog.byId(id);
        AppPalette.accent = a;
        expect(AppPalette.toastBg, Color(0xFF000000 | a.darkTop),
            reason: '${a.name} 警示语底应跟随主题深色');
      }
    });

    testWidgets('深色模式下弹警示语：背景用主题深色', (tester) async {
      await AppSettings.setAccentId('ocean');
      await AppSettings.setThemeMode(AppThemeMode.dark);
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();
      AppToast.show(tester.element(find.byType(Scaffold)), '测试警示');
      await tester.pumpAndSettle();
      // 页面本身有 Material，抽屉 toast 是后弹出的第二个，取 .last
      final material = tester.widget<Material>(
        find.byType(Material).last,
      );
      expect(material.color, AppPalette.toastBg);
      AppToast.resetForTest();
      await tester.pump();
    });
  });

  group('事件编辑页到期提醒', () {
    testWidgets('标题为「到期提醒」，旧名移除，角标紧跟标题', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // 授予 VIP 以显示用户身份牌角标
      final vip = UserProfile(
          ownedBadges: [UserProfile.badgeNormal, UserProfile.badgeVip]);
      File('${dir.path}/user_profile.json')
          .writeAsStringSync(jsonEncode(vip.toJson()));
      await tester.pumpWidget(const MaterialApp(home: CountdownEditScreen()));
      await _settle(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.text('到期提醒'), findsOneWidget);
      expect(find.text('提醒时间'), findsNothing);
      // 源码断言：角标通过 labelTrailing 跟在「到期提醒」标题后（右侧溢出角标已移除）
      final src = File('lib/screens/countdown_edit_screen.dart').readAsStringSync();
      expect(src.contains("label: '到期提醒',"), isTrue);
      expect(src.contains('labelTrailing: Transform.scale('), isTrue);
      expect(src.contains('right: -4,'), isFalse,
          reason: '右上角溢出角标应已移除');
    });
  });

  group('档案页', () {
    testWidgets('移除「点击更换头像」提示语', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: ProfileEditScreen(
          profile: UserProfile(),
          loadOverride: () async => UserProfile(),
        ),
      ));
      await _settle(tester);
      expect(find.text('点击更换头像'), findsNothing);
    });
  });

  group('侧边栏设置按钮', () {
    test('设置图标走主题主色而非中性灰（源码断言）', () {
      final src = File('lib/screens/side_menu.dart').readAsStringSync();
      // 设置按钮的 settings 图标应传主题主色 c(0xFF3E8E6D)
      expect(
        src.contains('AppIcons.settings,\n                    size: 22, color: AppPalette.c(0xFF3E8E6D)'),
        isTrue,
        reason: '设置按钮图标应走主题主色，普通/深色都随主题色换',
      );
    });
  });
}
