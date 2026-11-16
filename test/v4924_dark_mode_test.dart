import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/main.dart';
import 'package:ayodiray/screens/home_screen.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.24 深色模式回归：
/// 1. 语义色板浅色逐值等于原字面量（保证 385 项既有精确颜色断言零回归）；
/// 2. 深色映射生效，品牌色/主色自动保持，顶栏分区色块随主题变深；
/// 3. 主题模式三态持久化与「跟随系统」解析；
/// 4. 设置页新增「外观」分组的深色模式 / 跟随系统开关可交互；
/// 5. DiaryApp 正确选择 theme / darkTheme / themeMode，并同步 AppPalette.dark；
/// 6. 系统亮度变化（跟随系统）时自动刷新。
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

  // widget test 跑在 FakeAsync 环境里，真实文件写入会让 await 永久挂起。
  // 全程注入内存 no-op 替身绕开落盘；内存状态 / toJson 快照 / notifier
  // 仍是完整逻辑。load() 的读档往返测试走真实文件（普通 test 的真实
  // async 环境安全，不受此替身影响）。
  setUpAll(() {
    AppSettings.persistOverride = () async {};
  });

  tearDownAll(() {
    AppSettings.persistOverride = null;
  });

  setUp(() async {
    dir = Directory('/tmp/v4924_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    // 每个用例都从干净状态开始：浅色 + 跟随系统
    AppPalette.dark = false;
    await AppSettings.setThemeMode(AppThemeMode.system);
  });

  tearDown(() async {
    AppPalette.dark = false;
    await AppSettings.setThemeMode(AppThemeMode.system);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  group('语义色板 AppPalette', () {
    test('浅色模式 c() 逐值返回原始字面量（零回归基线）', () {
      AppPalette.dark = false;
      for (final k in AppPalette.darkMap.keys) {
        expect(AppPalette.c(k), Color(k),
            reason: '浅色下 0x${k.toRadixString(16)} 必须等于原字面量');
      }
      // 未登记颜色浅色也原样返回
      expect(AppPalette.c(0xFF3E8E6D), const Color(0xFF3E8E6D));
      expect(AppPalette.c(0xFFCB5C50), const Color(0xFFCB5C50));
    });

    test('深色模式 c() 返回映射值', () {
      AppPalette.dark = true;
      for (final e in AppPalette.darkMap.entries) {
        expect(AppPalette.c(e.key), Color(e.value),
            reason: '深色下 0x${e.key.toRadixString(16)} 应映射为 0x${e.value.toRadixString(16)}');
      }
    });

    test('深色模式未登记的品牌/语义色保持原值', () {
      AppPalette.dark = true;
      // 竹青主色、危险红、内测橙、身份牌红、渐变绿等都不该被主题改写
      for (final k in <int>[
        0xFF3E8E6D, 0xFFCB5C50, 0xFFF08C3A, 0xFF5CA985,
        0xFFFFD666, 0xFF9B6BE0, 0xFFE0576A,
      ]) {
        expect(AppPalette.c(k), Color(k),
            reason: '品牌色 0x${k.toRadixString(16)} 深色下应保持');
      }
    });

    test('白色卡片背景深色下转为深灰绿（84 处 surface 不能漏）', () {
      // 回归：darkMap 若漏登记 0xFFFFFFFF，深色页面会顶着一堆刺眼白块。
      AppPalette.dark = false;
      expect(AppPalette.c(0xFFFFFFFF), Colors.white);
      expect(AppPalette.surface, Colors.white);
      AppPalette.dark = true;
      expect(AppPalette.c(0xFFFFFFFF), const Color(0xFF18221E));
      expect(AppPalette.surface, const Color(0xFF18221E));
      expect(AppPalette.surface.computeLuminance(),
          lessThan(Colors.white.computeLuminance()));
    });

    test('加密/置顶卡斜纹与半透明白遮罩深色下不留亮块', () {
      // 回归：置顶卡正文底 0xE6FFFFFF、斜纹 fade 的 0xCC/0xB3/0x99FFFFFF
      // 以及斜纹底色，深色下必须全部转为深墨，否则会残留刺眼白块。
      const keys = <int>[
        0xFFEEF4F0, 0xFFE4EDE8, 0xFFFBE3E8, 0xFFF0CBD4,
        0xE6FFFFFF, 0xCCFFFFFF, 0xB3FFFFFF, 0x99FFFFFF,
      ];
      AppPalette.dark = false;
      for (final k in keys) {
        expect(AppPalette.c(k), Color(k),
            reason: '浅色下 0x${k.toRadixString(16)} 保持原值');
      }
      AppPalette.dark = true;
      for (final k in keys) {
        final mapped = AppPalette.c(k);
        expect(mapped, isNot(Color(k)),
            reason: '深色下 0x${k.toRadixString(16)} 必须被映射');
        expect(mapped.computeLuminance(), lessThan(0.3),
            reason: '深色下 0x${k.toRadixString(16)} 不应残留亮色，实际 '
                '0x${mapped.value.toRadixString(16)}');
      }
    });

    test('surface / topBar 深浅取色不同且深色为深色系', () {
      AppPalette.dark = false;
      final lightSurface = AppPalette.surface;
      final lightTopBar = AppPalette.topBar;
      AppPalette.dark = true;
      final darkSurface = AppPalette.surface;
      final darkTopBar = AppPalette.topBar;

      expect(lightSurface, Colors.white);
      expect(lightTopBar, const Color(0xFF3E8E6D));
      expect(darkSurface, isNot(lightSurface));
      expect(darkTopBar, isNot(lightTopBar));
      // 深色的亮度明显低于对应浅色
      expect(darkSurface.computeLuminance(),
          lessThan(lightSurface.computeLuminance()));
      expect(darkTopBar.computeLuminance(),
          lessThan(lightTopBar.computeLuminance()));
    });

    test('顶部导航栏分区色块随主题变深（需求点名，不能漏）', () {
      // 0xB33E8E6D 是各主页顶栏 / 状态栏贯通区的半透明主色块；
      // 0xCC3E8E6D 是 AppBar 背景色块。
      AppPalette.dark = false;
      expect(AppPalette.c(0xB33E8E6D), const Color(0xB33E8E6D));
      expect(AppPalette.c(0xCC3E8E6D), const Color(0xCC3E8E6D));
      AppPalette.dark = true;
      final block1 = AppPalette.c(0xB33E8E6D);
      final block2 = AppPalette.c(0xCC3E8E6D);
      expect(block1, const Color(0xFF22342C));
      expect(block2, const Color(0xFF22342C));
      expect(block1.computeLuminance(),
          lessThan(const Color(0xB33E8E6D).computeLuminance()));
      expect(block2.computeLuminance(),
          lessThan(const Color(0xCC3E8E6D).computeLuminance()));
    });
  });

  group('主题模式持久化与解析', () {
    test('resolveDark 三态 × 系统亮度', () {
      expect(AppSettings.resolveDark(AppThemeMode.light, Brightness.dark), false);
      expect(AppSettings.resolveDark(AppThemeMode.light, Brightness.light), false);
      expect(AppSettings.resolveDark(AppThemeMode.dark, Brightness.light), true);
      expect(AppSettings.resolveDark(AppThemeMode.dark, Brightness.dark), true);
      expect(AppSettings.resolveDark(AppThemeMode.system, Brightness.light), false);
      expect(AppSettings.resolveDark(AppThemeMode.system, Brightness.dark), true);
    });

    test('setThemeMode 写入 notifier 与 toJson', () async {
      await AppSettings.setThemeMode(AppThemeMode.dark);
      expect(AppSettings.themeMode, AppThemeMode.dark);
      expect(AppSettings.themeModeNotifier.value, AppThemeMode.dark);
      expect(AppSettings.toJson()['themeMode'], 'dark');

      await AppSettings.setThemeMode(AppThemeMode.light);
      expect(AppSettings.toJson()['themeMode'], 'light');
    });

    test('load 往返：写入文件后能读回主题模式', () async {
      final f = File('${dir.path}/app_settings.json');
      await f.writeAsString(jsonEncode({
        'fontFamily': '',
        'themeMode': 'dark',
      }));
      await AppSettings.load();
      expect(AppSettings.themeMode, AppThemeMode.dark);
      expect(AppSettings.themeModeNotifier.value, AppThemeMode.dark);
    });

    test('load 兼容旧档缺 themeMode（回落跟随系统）', () async {
      final f = File('${dir.path}/app_settings.json');
      await f.writeAsString(jsonEncode({'fontFamily': ''}));
      await AppSettings.load();
      expect(AppSettings.themeMode, AppThemeMode.system);
    });

    test('load 忽略非法 themeMode 值', () async {
      final f = File('${dir.path}/app_settings.json');
      await f.writeAsString(jsonEncode({'themeMode': 'weird'}));
      await AppSettings.load();
      expect(AppSettings.themeMode, AppThemeMode.system);
    });
  });

  group('设置页深色模式开关', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pump();
    }

    testWidgets('存在「外观」分组与「深色模式」「跟随系统」两个开关', (tester) async {
      await pumpSettings(tester);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('深色模式'), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget,
          reason: '「跟随系统」作为独立设置项标题');
      expect(find.textContaining('跟随系统（当前'), findsOneWidget,
          reason: '深色模式副标题展示当前系统亮度');
      expect(find.byType(Switch), findsNWidgets(2));
    });

    testWidgets('默认跟随系统：深色模式开关禁用，关闭跟随系统后可手动切换',
        (tester) async {
      await pumpSettings(tester);
      final switches = find.byType(Switch);
      // 第 1 个 = 深色模式（跟随系统时禁用），第 2 个 = 跟随系统
      expect(tester.widget<Switch>(switches.at(0)).onChanged, isNull,
          reason: '跟随系统时深色模式开关应禁用');
      expect(tester.widget<Switch>(switches.at(1)).value, isTrue);

      // 关闭「跟随系统」-> 手动浅色
      await tester.tap(switches.at(1));
      await tester.pumpAndSettle();
      expect(AppSettings.themeMode, AppThemeMode.light);
      expect(tester.widget<Switch>(switches.at(0)).onChanged, isNotNull,
          reason: '手动模式下深色开关应可操作');

      // 打开「深色模式」-> 手动深色
      await tester.tap(switches.at(0));
      await tester.pumpAndSettle();
      expect(AppSettings.themeMode, AppThemeMode.dark);
      expect(find.text('已开启'), findsOneWidget);
    });
  });

  group('DiaryApp 主题装配', () {
    MaterialApp appOf(WidgetTester tester) =>
        tester.widget<MaterialApp>(find.byType(MaterialApp));

    testWidgets('默认跟随系统：themeMode=system 且提供 light/dark 两套主题',
        (tester) async {
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      final app = appOf(tester);
      expect(app.themeMode, ThemeMode.system);
      expect(app.theme, isNotNull);
      expect(app.darkTheme, isNotNull);
      expect(app.theme!.brightness, Brightness.light);
      expect(app.darkTheme!.brightness, Brightness.dark);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('手动深色：themeMode=dark 且 AppPalette.dark 同步为 true',
        (tester) async {
      await AppSettings.setThemeMode(AppThemeMode.dark);
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      expect(appOf(tester).themeMode, ThemeMode.dark);
      expect(AppPalette.dark, isTrue);
      expect(appOf(tester).darkTheme!.scaffoldBackgroundColor,
          const Color(0xFF101613));
      expect(appOf(tester).darkTheme!.appBarTheme.backgroundColor,
          const Color(0xFF22342C));
    });

    testWidgets('手动浅色：themeMode=light 且 AppPalette.dark 同步为 false',
        (tester) async {
      await AppSettings.setThemeMode(AppThemeMode.light);
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      expect(appOf(tester).themeMode, ThemeMode.light);
      expect(AppPalette.dark, isFalse);
      expect(appOf(tester).theme!.scaffoldBackgroundColor,
          const Color(0xFFF5FAF7));
    });

    testWidgets('运行中切换主题：notifier 触发重建并刷新 AppPalette.dark',
        (tester) async {
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      expect(AppPalette.dark, isFalse); // 测试宿主默认系统亮度 light

      await tester.runAsync(
          () => AppSettings.setThemeMode(AppThemeMode.dark));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(AppPalette.dark, isTrue);
      expect(appOf(tester).themeMode, ThemeMode.dark);
    });

    testWidgets('跟随系统：系统亮度变化后 AppPalette.dark 与主题同步刷新',
        (tester) async {
      // 明确置为跟随系统
      await AppSettings.setThemeMode(AppThemeMode.system);
      final binding = tester.binding;
      binding.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(() =>
          binding.platformDispatcher.clearPlatformBrightnessTestValue());

      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      expect(AppPalette.dark, isFalse);

      // 系统切到深色，应触发 didChangePlatformBrightness 重建
      binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(AppPalette.dark, isTrue,
          reason: '跟随系统时系统亮度变深，全局色板应刷新');
    });
  });

  group('图标库新增 moon / sun', () {
    test('moon / sun 已注册且路径非空', () {
      expect(AppIcons.pathOf('moon'), AppIcons.moon);
      expect(AppIcons.pathOf('sun'), AppIcons.sun);
      expect(AppIcons.moon.isNotEmpty, isTrue);
      expect(AppIcons.sun.isNotEmpty, isTrue);
    });
  });
}
