import 'dart:io';

import 'package:ayodiray/main.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.46 行为回归：
/// 1. 深色模式随主题色换色：每套主题色配齐深色页面底/卡片底/底纹；
///    c() 深色下把深墨绿中性色重映射到当前主题色；
/// 2. 全局 darkTheme 的顶栏 / 页面底随主题色换（设置/档案/杂货店等
///    走全局 AppBarTheme 的页面从此跟随）；
/// 3. 竹青默认所有深色值逐字节不变（保护既有精确颜色断言）。
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

MaterialApp _appOf(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() => AppSettings.persistOverride = () async {});
  tearDownAll(() => AppSettings.persistOverride = null);

  setUp(() async {
    dir = Directory('/tmp/v4946_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppPalette.dark = false;
    await AppSettings.setThemeMode(AppThemeMode.dark);
    await AppSettings.setAccentId('bamboo');
  });

  tearDown(() async {
    AppPalette.dark = false;
    await AppSettings.setThemeMode(AppThemeMode.system);
    await AppSettings.setAccentId('bamboo');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  group('深色配套色板', () {
    test('6 套都配齐深色页面底/卡片底/底纹', () {
      for (final s in AccentCatalog.styles) {
        expect(s.darkPage & 0xFFFFFF != 0, true, reason: '${s.name} 深色页面底非空');
        expect(s.darkSurface & 0xFFFFFF != 0, true, reason: '${s.name} 深色卡片底非空');
        expect(s.darkTintBg & 0xFFFFFF != 0, true, reason: '${s.name} 深色底纹非空');
      }
    });

    test('竹青深色配套色是原 darkMap 字面值，逐字节不变', () {
      final b = AccentCatalog.byId('bamboo');
      expect(b.darkTop, 0x22342C);
      expect(b.darkTint, 0x59B189);
      expect(b.darkPage, 0x101613);
      expect(b.darkSurface, 0x18221E);
      expect(b.darkTintBg, 0x233A2F);
    });
  });

  group('深色下 c() 随主题色换色', () {
    test('藕粉深色：页面底/卡片底/底纹都换成藕粉深色系', () {
      AppPalette.dark = true;
      AppPalette.accent = AccentCatalog.byId('lotus');
      final a = AccentCatalog.byId('lotus');
      expect(AppPalette.c(0xFFF5FAF7).value, 0xFF000000 | a.darkPage);
      expect(AppPalette.c(0xFFFFFFFF).value, 0xFF000000 | a.darkSurface);
      expect(AppPalette.c(0xFFE4F2EB).value, 0xFF000000 | a.darkTintBg);
      expect(AppPalette.c(0xFF3E8E6D).value, 0xFF000000 | a.rgb);
    });

    test('竹青深色：中性色保持原 darkMap 值', () {
      AppPalette.dark = true;
      AppPalette.accent = AccentCatalog.byId('bamboo');
      expect(AppPalette.c(0xFFF5FAF7).value, 0xFF101613);
      expect(AppPalette.c(0xFFFFFFFF).value, 0xFF18221E);
      expect(AppPalette.c(0xFFE4F2EB).value, 0xFF233A2F);
    });
  });

  group('全局 darkTheme 随主题色换', () {
    testWidgets('竹青：darkTheme 顶栏/页面底为原深墨绿', (tester) async {
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      expect(_appOf(tester).darkTheme!.appBarTheme.backgroundColor,
          const Color(0xFF22342C));
      expect(_appOf(tester).darkTheme!.scaffoldBackgroundColor,
          const Color(0xFF101613));
    });

    testWidgets('藕粉：darkTheme 顶栏/页面底换成藕粉深色系', (tester) async {
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      await AppSettings.setAccentId('lotus');
      await tester.pump();
      final a = AccentCatalog.byId('lotus');
      expect(_appOf(tester).darkTheme!.appBarTheme.backgroundColor,
          Color(0xFF000000 | a.darkTop));
      expect(_appOf(tester).darkTheme!.scaffoldBackgroundColor,
          Color(0xFF000000 | a.darkPage));
      expect(_appOf(tester).darkTheme!.cardColor,
          Color(0xFF000000 | a.darkSurface));
    });
  });
}
