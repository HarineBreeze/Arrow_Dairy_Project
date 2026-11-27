import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/global_search_screen.dart';
import 'package:ayodiray/screens/profile_edit_screen.dart';
import 'package:ayodiray/screens/trash_screen.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_toast.dart';
import 'package:ayodiray/widgets/app_icons.dart';

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
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// 找 path 为右箭头的 AppIcon
Finder _chevron() => find.byWidgetPredicate(
      (w) => w is AppIcon && w.path == AppIcons.chevR,
    );

/// 写入一条日记，使搜索页/回收站有内容（分类栏仅在有结果时渲染）
void _seedDiary(String dir) {
  final now = DateTime.now();
  File('$dir/diaries.json').writeAsStringSync(jsonEncode([
    DiaryEntry(
      id: 'v5011-note',
      title: '分类栏测试笔记',
      content: '内容',
      createdAt: now,
      updatedAt: now,
      publishDate: now,
    ).toJson()
  ]));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    dir = Directory('/tmp/v5011_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppToast.resetForTest();
  });
  tearDown(() {
    AppToast.resetForTest();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('搜索页分类栏固定显示（v5.0.12）', () {
    testWidgets('无搜索词时分类栏仍固定在搜索栏下方', (tester) async {
      // 不注入任何数据、不输入搜索词 —— 分类栏应始终渲染
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GlobalSearchScreen(onOpenMenu: () {})),
      ));
      await _settle(tester);

      for (final label in ['全部', '笔记', '物品', '事件', '资产']) {
        expect(find.text(label), findsOneWidget,
            reason: '无搜索词时也应固定显示分类 $label');
      }
      // 分类栏应紧跟在搜索栏（56 高）下方：顶边 y 约等于 56
      final barTop = tester.getTopLeft(find.text('全部')).dy;
      expect(barTop, lessThan(90), reason: '分类栏应固定在搜索栏下方，不居中');
    });

    testWidgets('搜索无结果时分类栏仍显示', (tester) async {
      _seedDiary(dir.path);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GlobalSearchScreen(
                onOpenMenu: () {}, initialQuery: '绝不可能匹配的关键词')),
      ));
      await _settle(tester);

      expect(find.text('没有匹配的内容'), findsOneWidget);
      expect(find.text('全部'), findsOneWidget,
          reason: '无结果时分类栏仍应固定显示');
    });
  });

  group('搜索页分类栏（日记页同款）', () {
    testWidgets('五个等宽文字标签 + 底部滑块', (tester) async {
      _seedDiary(dir.path);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GlobalSearchScreen(
                onOpenMenu: () {}, initialQuery: '分类栏测试')),
      ));
      await _settle(tester);

      for (final label in ['全部', '笔记', '物品', '事件', '资产']) {
        expect(find.text(label), findsWidgets, reason: '应含分类 $label');
      }
      // 底部滑块：40×3 主题色圆角块（Container 用 tight constraints 定尺寸）
      final sliders = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final c = w.constraints;
        return c != null &&
            c.maxWidth == 40 &&
            c.minWidth == 40 &&
            c.maxHeight == 3 &&
            c.minHeight == 3;
      });
      expect(sliders, findsOneWidget, reason: '应有一个底部滑块');
    });

    testWidgets('点击分类标签切换选中态并筛选', (tester) async {
      _seedDiary(dir.path);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GlobalSearchScreen(
                onOpenMenu: () {}, initialQuery: '分类栏测试')),
      ));
      await _settle(tester);

      // 默认「全部」选中（w600）；点「物品」后「物品」变选中
      await tester.tap(find.text('物品').first);
      await tester.pump(const Duration(milliseconds: 300));
      final itemText = tester.widget<Text>(find.text('物品').first);
      expect(itemText.style?.fontWeight, FontWeight.w600,
          reason: '点选后该标签变为选中态');
    });
  });

  group('回收站分类栏（日记页同款）', () {
    testWidgets('含全部/笔记/物品/事件/资产文字标签', (tester) async {
      final entry = {
        'id': 'v5011-trash',
        'kind': 'diary',
        'data': <String, dynamic>{},
        'deletedAt': DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
        'title': '回收站测试',
        'subtitle': '',
      };
      File('${dir.path}/trash.json').writeAsStringSync(jsonEncode([entry]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrashScreen(onOpenMenu: () {})),
      ));
      await _settle(tester);

      for (final label in ['全部', '笔记', '物品', '事件', '资产']) {
        expect(find.text(label), findsWidgets, reason: '应含分类 $label');
      }
      final sliders = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final c = w.constraints;
        return c != null &&
            c.maxWidth == 40 &&
            c.minWidth == 40 &&
            c.maxHeight == 3 &&
            c.minHeight == 3;
      });
      expect(sliders, findsOneWidget, reason: '应有底部滑块');
    });
  });

  group('档案页「解锁专属权益」入口', () {
    testWidgets('位于身份栏上方，主题色底纹 + 右箭头，点击提示暂未实装',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ProfileEditScreen(
                profile: UserProfile(), loadOverride: () async => UserProfile())),
      ));
      await _settle(tester);

      expect(find.text('解锁专属权益'), findsOneWidget);

      // 找到入口容器：主题色底纹（AppPalette.accentColor）+ 含右箭头
      final rights = find.ancestor(
        of: find.text('解锁专属权益'),
        matching: find.byType(InkWell),
      );
      expect(rights, findsOneWidget);
      final container = tester.widget<Container>(
        find.descendant(of: rights, matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.color, AppPalette.accentColor,
          reason: '底纹应为当前主题色');

      // 右箭头在该栏内
      expect(
        find.descendant(of: rights, matching: _chevron()),
        findsOneWidget,
        reason: '右侧应有右箭头图标',
      );

      // 点击提示
      await tester.tap(find.text('解锁专属权益'));
      await tester.pumpAndSettle();
      expect(find.text('功能暂未实装'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
