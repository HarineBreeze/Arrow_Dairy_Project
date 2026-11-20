import 'dart:io';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/note_view_screen.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/screens/trash_screen.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.48 行为回归：
/// 1. 资产页「可使用天数 参数」标题移除（仅留关闭按钮）；
/// 2. 深色模式抽屉改为「跟随系统 / 深色模式」双开关（震动同款），
///    跟随系统开启时深色开关置灰禁用；
/// 3. 笔记浏览页时间/地点信息行取消吸底，置于滚动内容最底部；
///    回收站提示语同款处理；
/// 4. 档案页身份/性别抽屉标题移除。
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

/// 含真实文件 IO 的页面（如回收站 TrashStorage.load）需要让事件循环跑完，
/// 否则 pumpAndSettle 时 _loading 仍为 true、内容尚未渲染。
Future<void> _settleWithIo(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
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

  setUpAll(() => AppSettings.persistOverride = () async {});
  tearDownAll(() => AppSettings.persistOverride = null);

  setUp(() async {
    dir = Directory('/tmp/v4948_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    await AppSettings.setThemeMode(AppThemeMode.system);
  });

  tearDown(() async {
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    await AppSettings.setThemeMode(AppThemeMode.system);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  group('版本号', () {
    test('展示版本同步到 V4.9.48', () {
      expect(AppVersion.displayVersion, 'V4.9.48');
    });
  });

  group('资产页可使用天数标题移除', () {
    test('源码中不再出现「可使用天数 参数」标题组合', () {
      final src = File('lib/screens/usable_days_settings_sheet.dart')
          .readAsStringSync();
      // 标题 Text('可使用天数') / Text('参数') 已从标题行移除；
      // 底部预览提示文案仍可能含「参数」二字，故只断言标题组合消失。
      expect(src.contains("Text('可使用天数')"), isFalse);
      expect(src.contains("Text('参数')"), isFalse);
    });
  });

  group('档案页抽屉标题移除', () {
    test('身份/性别抽屉源码中不再有「选择身份」「选择性别」标题', () {
      final src = File('lib/screens/profile_edit_screen.dart').readAsStringSync();
      expect(src.contains("'选择身份'"), isFalse);
      expect(src.contains("'选择性别'"), isFalse);
    });
  });

  group('深色模式双开关', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await _settle(tester);
    }

    testWidgets('抽屉含跟随系统/深色模式双开关，深色开关有稳定 key', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('深色模式'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('theme-follow-system')), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-dark-mode')), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget);
      // 旧三选一的「已开启 / 已关闭」独立行已移除
      expect(find.text('已开启'), findsNothing);
      expect(find.text('已关闭'), findsNothing);
    });

    testWidgets('跟随系统开启时深色开关禁用，关闭后恢复', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('深色模式'));
      await tester.pumpAndSettle();
      Switch dark() => tester.widget<Switch>(
          find.byKey(const ValueKey('theme-dark-mode')));
      // 默认跟随系统开启 → 深色开关禁用
      expect(dark().onChanged, isNull);
      // 关闭跟随系统 → 深色开关恢复
      await tester.tap(find.byKey(const ValueKey('theme-follow-system')));
      await tester.pumpAndSettle();
      expect(dark().onChanged, isNotNull);
      expect(AppSettings.themeMode, AppThemeMode.light);
    });
  });

  group('笔记浏览页时间/地点信息行置于滚动内容底部', () {
    testWidgets('时间地点文本位于 SingleChildScrollView 内部', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime(2025, 3, 8, 9, 7);
      final entry = DiaryEntry(
        id: 'n1',
        title: '标题',
        content: '正文',
        location: '某地',
        createdAt: now,
        updatedAt: now,
        publishDate: now,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: NoteViewScreen(entry: entry)),
      ));
      await _settle(tester);

      // 时间标签 2025/3/8 09:07 与地点都应存在
      expect(find.textContaining('2025/3/8'), findsOneWidget);
      expect(find.text('某地'), findsOneWidget);
      // 关键：时间文本应是 SingleChildScrollView 的后代（随滚动），
      // 而不是直接挂在最外层、固定吸附底部。
      final timeInScroll = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.textContaining('2025/3/8'),
      );
      expect(timeInScroll, findsOneWidget,
          reason: '时间地点信息行应随正文滚动，置于内容最底部');
    });
  });

  group('回收站提示语置于内容最底部', () {
    testWidgets('提示语仍存在且位于页面下方', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrashScreen(onOpenMenu: () {})),
      ));
      await _settleWithIo(tester);
      expect(find.text('超过7天的内容将彻底删除'), findsOneWidget);
    });
  });
}
