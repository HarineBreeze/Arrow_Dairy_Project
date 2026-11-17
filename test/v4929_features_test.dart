import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/asset_screen.dart';
import 'package:ayodiray/screens/item_list_screen.dart';
import 'package:ayodiray/screens/note_view_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.29 回归：
/// 1. 筛选/排序弹层的「取消 / 确定 / 完成」按钮：取消去底纹描边，
///    按钮统一收至卡片右下角；
/// 2. 排序方式选项 chip 去描边；
/// 3. 笔记封面图不再包 Hero，全屏查看为纯淡入转场（无页面滑动观感）。
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

/// 假 path_provider + 空 assets.json / items.json，页面走「无数据」分支
void _seed() {
  final dir = Directory(
      '/tmp/v4929_${DateTime.now().microsecondsSinceEpoch}');
  dir.createSync(recursive: true);
  File('${dir.path}/assets.json').writeAsStringSync('[]');
  PathProviderPlatform.instance = _FakePathProvider(dir.path);
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

  group('弹层按钮统一：取消去底纹、收至右下角', () {
    testWidgets('资产筛选弹层：取消不再是描边按钮，双按钮右对齐', (tester) async {
      _seed();
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AssetScreen())));
      await _settle(tester);

      await tester.tap(find.byTooltip('筛选'));
      await _settle(tester);

      expect(find.text('取消'), findsOneWidget);
      expect(find.text('确定'), findsOneWidget);
      // 取消不再使用 OutlinedButton（描边+底纹）
      expect(
        find.ancestor(
            of: find.text('取消'), matching: find.byType(OutlinedButton)),
        findsNothing,
        reason: '取消按钮不应再带描边底纹',
      );
      // 两个按钮收至右下角：确定在最右（距右缘 ~20），取消在确定左侧
      final cancelRight = tester.getRect(find.text('取消')).right;
      final okRect = tester.getRect(find.text('确定'));
      expect(okRect.right, greaterThan(700), reason: '确定应贴近右下角');
      expect(cancelRight, lessThan(okRect.left), reason: '取消应在确定左侧');
    });

    testWidgets('物品排序弹层：选项无描边，完成按钮右对齐', (tester) async {
      _seed();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ItemListScreen(onOpenMenu: () {})),
      ));
      await _settle(tester);

      await tester.tap(find.byTooltip('排序方式'));
      await _settle(tester);

      expect(find.text('排序方式'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);

      // 选项 chip 不再带 Border 描边
      final chip = tester.widget<Container>(
        find.ancestor(
            of: find.text('购买时间'), matching: find.byType(Container)).first,
      );
      final decor = chip.decoration as BoxDecoration;
      expect(decor.border, isNull, reason: '排序选项不应再有描边');

      // 完成按钮收至右下角，不再占满整行
      final doneRect = tester.getRect(find.text('完成'));
      expect(doneRect.right, greaterThan(700), reason: '完成应贴近右下角');
      final btnRect = tester.getRect(find.ancestor(
          of: find.text('完成'), matching: find.byType(ElevatedButton)));
      expect(btnRect.width, lessThan(400), reason: '完成按钮不应占满整行');
    });
  });

  group('图片全屏查看：纯淡入转场', () {
    testWidgets('笔记封面不再包 Hero，页面内无共享元素', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 800);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(() => tester.binding.window.clearPhysicalSizeTestValue());

      await tester.pumpWidget(
          MaterialApp(home: NoteViewScreen(entry: _entry(imagePath: 'x'))));
      await _settle(tester);

      expect(find.byType(Hero), findsNothing,
          reason: '封面不应再包 Hero，避免打开查看器时整页滑动观感');
    });
  });
}
