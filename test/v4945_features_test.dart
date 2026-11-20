import 'dart:io';

import 'package:ayodiray/main.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.45 行为回归：
/// 1. 全局 scaffoldBackgroundColor 随主题色页面底（pageRgb）换色——
///    物品编辑/笔记浏览/设置/字体/笔记编辑/档案/杂货店等走全局背景的页面
///    与资产/事件页取色方式统一；
/// 2. 深色下页面底固定深灰绿，不随主题色变；
/// 3. 竹青默认逐字节不变（保护既有精确颜色断言）。
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

  setUpAll(() {
    AppSettings.persistOverride = () async {};
  });
  tearDownAll(() {
    AppSettings.persistOverride = null;
  });

  setUp(() async {
    dir = Directory('/tmp/v4945_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppPalette.dark = false;
    await AppSettings.setThemeMode(AppThemeMode.light);
    await AppSettings.setAccentId('bamboo');
  });

  tearDown(() async {
    AppPalette.dark = false;
    await AppSettings.setThemeMode(AppThemeMode.system);
    await AppSettings.setAccentId('bamboo');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  group('全局页面底随主题色换色', () {
    testWidgets('竹青默认：scaffold 背景逐字节为 0xFFF5FAF7', (tester) async {
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      expect(_appOf(tester).theme!.scaffoldBackgroundColor,
          const Color(0xFFF5FAF7));
    });

    testWidgets('切到藕粉：scaffold 背景换成藕粉页面底 pageRgb', (tester) async {
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      await AppSettings.setAccentId('lotus');
      await tester.pump();
      final lotus = AccentCatalog.byId('lotus');
      expect(_appOf(tester).theme!.scaffoldBackgroundColor,
          Color(0xFF000000 | lotus.pageRgb));
      expect(_appOf(tester).theme!.scaffoldBackgroundColor,
          isNot(const Color(0xFFF5FAF7)));
    });

    testWidgets('切到雾蓝：scaffold 背景换成雾蓝页面底 pageRgb', (tester) async {
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      await AppSettings.setAccentId('ocean');
      await tester.pump();
      final ocean = AccentCatalog.byId('ocean');
      expect(_appOf(tester).theme!.scaffoldBackgroundColor,
          Color(0xFF000000 | ocean.pageRgb));
    });

    testWidgets('深色下：页面底固定深灰绿，不随主题色变', (tester) async {
      await AppSettings.setThemeMode(AppThemeMode.dark);
      await tester.pumpWidget(const DiaryApp());
      await tester.pump();
      await AppSettings.setAccentId('lotus');
      await tester.pump();
      expect(_appOf(tester).darkTheme!.scaffoldBackgroundColor,
          const Color(0xFF101613));
    });
  });

  test('每套主题色 pageRgb 都是有效 24 位颜色', () {
    for (final s in AccentCatalog.styles) {
      expect(s.pageRgb & 0xFFFFFF != 0, true, reason: '${s.name} 页面底非空');
      expect(s.pageRgb & 0xFF000000, 0, reason: '${s.name} pageRgb 不含 alpha');
    }
  });
}
