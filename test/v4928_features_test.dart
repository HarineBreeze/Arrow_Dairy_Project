import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/global_search_screen.dart';
import 'package:ayodiray/screens/note_view_screen.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/utils/app_sheet.dart';
import 'package:ayodiray/utils/haptics.dart';
import 'package:ayodiray/widgets/app_icons.dart';
import 'package:ayodiray/widgets/entry_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.28 回归：
/// 1. 全局搜索页移除命中条（x处匹配 / 上下切换）与结果选框；
/// 2. 笔记浏览页「更多」改横三点，热区 48×48；
/// 3. 笔记封面仅展示，不响应点击（v4.9.30 移除全屏预览入口）；
/// 4. 底部弹层统一 AppSheet（手柄 + 24 圆角）；
/// 5. 设置页「震动」开关全局生效。
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
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

const String _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

DiaryEntry _entry({String imagePath = ''}) {
  final t = DateTime(2026, 6, 25, 10, 30);
  return DiaryEntry(
    id: 'e1',
    title: '海边的一天',
    content: '今天去了海边，海边很美。',
    createdAt: t,
    updatedAt: t,
    publishDate: t,
    imagePath: imagePath,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory('/tmp/v4928_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    Haptics.throttleEnabled = false;
    AppSettings.persistOverride = () async {};
  });

  tearDown(() async {
    await AppSettings.setHapticsEnabled(true);
    Haptics.throttleEnabled = true;
    AppSettings.persistOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  group('全局搜索页去干扰', () {
    testWidgets('不再显示 x处匹配 与上/下切换按钮', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 800);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(() => tester.binding.window.clearPhysicalSizeTestValue());

      File('${dir.path}/diaries.json')
          .writeAsStringSync(jsonEncode([_entry().toJson()]));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GlobalSearchScreen(onOpenMenu: () {})),
      ));
      await _settle(tester);

      await tester.enterText(find.byType(TextField).first, '海边');
      await _settle(tester);

      expect(find.text('海边的一天'), findsOneWidget);
      expect(find.textContaining('处匹配'), findsNothing);
      expect(find.text('上一个'), findsNothing);
      expect(find.text('下一个'), findsNothing);
    });

    testWidgets('结果行不再带选中选框描边', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 800);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(() => tester.binding.window.clearPhysicalSizeTestValue());

      File('${dir.path}/diaries.json')
          .writeAsStringSync(jsonEncode([_entry().toJson()]));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GlobalSearchScreen(onOpenMenu: () {})),
      ));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, '海边');
      await _settle(tester);

      final boxes = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.border != null &&
            d.border!.top.color == const Color(0xFF3E8E6D);
      });
      expect(boxes, isEmpty, reason: '命中项选框已移除');
    });
  });

  group('笔记浏览页更多按钮', () {
    testWidgets('使用横三点图标，热区与返回键一致', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 800);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(() => tester.binding.window.clearPhysicalSizeTestValue());

      // 从二级路由进入，AppBar 才会出现返回箭头，可与其对比热区
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  ctx,
                  MaterialPageRoute(
                      builder: (_) => NoteViewScreen(entry: _entry())),
                ),
                child: const Text('进入'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('进入'));
      await tester.pumpAndSettle();
      await _settle(tester);

      final more = find.byKey(const ValueKey('note_action_more'));
      expect(more, findsOneWidget);
      final btn = tester.widget<IconButton>(more);
      final icon = btn.icon as AppIcon;
      expect(icon.path, AppIcons.moreH, reason: '竖三点改横三点');
      expect(
          btn.constraints,
          const BoxConstraints.tightFor(width: 56, height: 56));

      final backSize = tester.getSize(find.byType(BackButton));
      expect(tester.getSize(more), backSize, reason: '热区与返回键一致');
    });
  });

  group('图片封面（v4.9.30 起仅展示）', () {
    testWidgets('点击封面不再打开全屏预览', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 800);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(() => tester.binding.window.clearPhysicalSizeTestValue());

      final img = File('${dir.path}/cover.png')
        ..writeAsBytesSync(base64Decode(_pngBase64));

      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(entry: _entry(imagePath: img.path)),
      ));
      await _settle(tester);

      await tester.tap(find.byType(EntryImage));
      await tester.pumpAndSettle();

      // v4.9.30：预览入口已移除，点击封面不应推入任何新页面
      expect(find.byType(NoteViewScreen), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget,
          reason: '导航栈不应出现第二页');
    });
  });

  group('底部弹层统一', () {
    testWidgets('统一手柄与 24 圆角', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => AppSheet.show<void>(
                ctx,
                builder: (_) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('菜单项'),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('菜单项'), findsOneWidget);
      expect(find.byKey(const ValueKey('app_sheet_handle')), findsOneWidget);

      final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
      final shape = sheet.shape as RoundedRectangleBorder;
      final radius = (shape.borderRadius as BorderRadius).topLeft.x;
      expect(radius, 24);
    });
  });

  group('震动总开关', () {
    testWidgets('关闭后全局静默，开启瞬间震动一次', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('vector_diary/haptic'),
        (call) async {
          calls.add(call);
          return true;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('vector_diary/haptic'), null));

      tester.binding.window.physicalSizeTestValue = const Size(400, 900);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(() => tester.binding.window.clearPhysicalSizeTestValue());

      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await _settle(tester);

      await tester.scrollUntilVisible(find.text('震动'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pump();

      expect(find.text('振动测试'), findsNothing, reason: '旧入口已改名');

      final switchFinder = find.descendant(
        of: find.ancestor(of: find.text('震动'), matching: find.byType(Row)).first,
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(switchFinder).value, isTrue);

      // 关闭 → 全局静默
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(AppSettings.hapticsEnabled, isFalse);
      expect(Haptics.enabled, isFalse);
      final before = calls.length;
      await Haptics.medium();
      expect(calls.length, before, reason: '关闭后不再发震动请求');

      // 开启 → 立刻震一次
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(AppSettings.hapticsEnabled, isTrue);
      expect(Haptics.enabled, isTrue);
      expect(calls.length, greaterThan(before), reason: '开启瞬间震一次');
    });
  });
}
