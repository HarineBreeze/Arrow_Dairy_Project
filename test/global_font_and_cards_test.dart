import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/main.dart';
import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/global_search_screen.dart';
import 'package:ayodiray/screens/home_screen.dart';
import 'package:ayodiray/screens/note_view_screen.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/screens/trash_screen.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.13 回归：
/// 1. 设置页「笔记字体」改名「字体」，字体经主题全局生效；
/// 2. 回收站卡片去图标、天数移到右上角（更小）、底部提示新文案；
/// 3. 浏览页标题取消白色底纹；
/// 4. 搜索页筛选栏去量词、结果卡去图标。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory('/tmp/v4913_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() async {
    await AppSettings.setFontFamily('');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  void usePhone(WidgetTester tester, {double height = 900}) {
    tester.binding.window.physicalSizeTestValue = Size(400, height);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);
  }

  testWidgets('设置页字体项改名为「字体」', (tester) async {
    usePhone(tester, height: 1600);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await _settle(tester);

    expect(find.text('笔记字体'), findsNothing, reason: '旧名称应全部替换');
    // 分组标题 + 功能项标题，两处都叫「字体」
    expect(find.text('字体'), findsNWidgets(2));

    // 「字体」分组标题旁不再有圈叹号提示：全页只剩数据备份分组那一个
    expect(find.text('!'), findsOneWidget,
        reason: '「字体」分组标题旁的提示符号应已移除');
  });

  testWidgets('字体设置经主题全局生效', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(const DiaryApp());
    await _settle(tester);

    final ctx = tester.element(find.byType(HomeScreen));
    expect(Theme.of(ctx).textTheme.bodyText1?.fontFamily, isNot('LXGWWenKai'),
        reason: '默认字体时不应带上所选字体');

    await tester.runAsync(() => AppSettings.setFontFamily('LXGWWenKai'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final ctx2 = tester.element(find.byType(HomeScreen));
    expect(Theme.of(ctx2).textTheme.bodyText1?.fontFamily, 'LXGWWenKai',
        reason: '切换后主题应带上所选字体，全 App 的正文样式随之生效');
  });

  testWidgets('回收站卡片去图标，天数移到右上角且更小', (tester) async {
    usePhone(tester, height: 900);
    final entry = {
      'id': 'trash-1',
      'kind': 'diary',
      'data': <String, dynamic>{},
      'deletedAt': DateTime.now()
          .subtract(const Duration(days: 3))
          .toIso8601String(),
      'title': '被删的笔记',
      'subtitle': '副标题',
    };
    File('${dir.path}/trash.json').writeAsStringSync(jsonEncode([entry]));

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrashScreen(onOpenMenu: () {}))));
    await _settle(tester);

    expect(find.text('被删的笔记'), findsOneWidget);
    expect(find.text('还原'), findsOneWidget);
    expect(find.text('彻底删除'), findsOneWidget);

    // 卡片内不再有类型图标，也没有还原/删除图标（顶栏「清空」不在卡片内）
    final card = find
        .ancestor(of: find.text('被删的笔记'), matching: find.byType(Container))
        .first;
    expect(
        tester
            .widgetList<AppIcon>(
                find.descendant(of: card, matching: find.byType(AppIcon)))
            .isEmpty,
        isTrue,
        reason: '回收站卡片不应再有图标');

    // 天数标签：小字号 + 贴右上角
    final days = find.text('4 天后消失');
    expect(days, findsOneWidget);
    final style = tester.widget<Text>(days).style!;
    expect(style.fontSize, 10, reason: '天数应缩小');
    final rect = tester.getRect(days);
    final cardRect = tester.getRect(card);
    expect(rect.right, greaterThan(cardRect.right - 24),
        reason: '应贴卡片右侧');
    expect(rect.center.dy, lessThan(cardRect.top + 34),
        reason: '应在卡片顶部区域');

    expect(find.text('超过7天的内容将彻底删除'), findsOneWidget);
  });

  testWidgets('浏览页标题套白色圆角底纹', (tester) async {
    usePhone(tester);
    final now = DateTime.now();
    final note = DiaryEntry(
      id: 'n1',
      title: '标题有底纹',
      content: '正文内容',
      createdAt: now,
      updatedAt: now,
      publishDate: now,
    );

    await tester.pumpWidget(MaterialApp(home: NoteViewScreen(entry: note)));
    await _settle(tester);

    final title = find.text('标题有底纹');
    expect(title, findsOneWidget);

    // 标题应存在一个直接的白色圆角卡片祖先（底纹回归）
    final containers = tester
        .widgetList<Container>(
            find.ancestor(of: title, matching: find.byType(Container)))
        .toList();
    final hasWhiteCard = containers.any((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.color == Colors.white;
    });
    expect(hasWhiteCard, isTrue, reason: '标题应有白色底纹');
  });

  testWidgets('搜索页筛选栏无量词，结果卡无图标', (tester) async {
    usePhone(tester);
    final now = DateTime.now();
    File('${dir.path}/diaries.json').writeAsStringSync(jsonEncode([
      DiaryEntry(
        id: 's1',
        title: '旅行随记',
        content: '海边的风',
        createdAt: now,
        updatedAt: now,
        publishDate: now,
      ).toJson()
    ]));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: GlobalSearchScreen(onOpenMenu: () {})),
    ));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).first, '旅行');
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);

    expect(find.text('旅行随记'), findsOneWidget);
    expect(find.text('笔记 1'), findsOneWidget, reason: '计数不带量词');
    expect(find.textContaining('篇'), findsNothing);

    // 结果卡内不应有笔记图标
    final icons = tester.widgetList<AppIcon>(find.byType(AppIcon));
    for (final icon in icons) {
      expect([AppIcons.diary, AppIcons.lock].contains(icon.path), isFalse,
          reason: '搜索结果卡不应再有类型图标');
    }
  });
}
