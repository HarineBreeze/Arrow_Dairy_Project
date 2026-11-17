import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/asset_edit_screen.dart';
import 'package:ayodiray/screens/countdown_edit_screen.dart';
import 'package:ayodiray/screens/countdown_screen.dart';
import 'package:ayodiray/screens/edit_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';
import 'package:ayodiray/screens/note_view_screen.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.31 回归：
/// 1. 编辑页（事件/物品/资产/笔记）AppBar 颜色与对应主页顶栏一致（0xB33E8E6D）；
/// 2. 编辑页 + 笔记浏览页顶栏高度与各主页一致（48）。
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

DiaryEntry _makeEntry({String imagePath = ''}) {
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

  setUp(() {
    final dir = Directory(
        '/tmp/v4931_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  /// 主页顶栏同款颜色（70% 绿）
  const Color homeBarColor = Color(0xB33E8E6D);

  AppBar appBarOf(WidgetTester tester) =>
      tester.widget<AppBar>(find.byType(AppBar).first);

  group('编辑页顶栏颜色与主页一致', () {
    testWidgets('事件主页顶栏为 70% 绿，事件编辑页 AppBar 同色', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: CountdownScreen())));
      await _settle(tester);
      // 主页顶栏 Container 确实使用 0xB33E8E6D
      final hasHomeBar = tester.allWidgets.any((w) =>
          w is Container && w.color == homeBarColor && w.constraints?.maxHeight == 48);
      expect(hasHomeBar, isTrue, reason: '事件主页顶栏应为 70% 绿、高 48');

      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: CountdownEditScreen())));
      await _settle(tester);
      final bar = appBarOf(tester);
      expect(bar.backgroundColor, homeBarColor,
          reason: '事件编辑页 AppBar 应与主页同色');
      expect(bar.toolbarHeight, 48, reason: '事件编辑页顶栏应与主页同高');
    });

    testWidgets('物品编辑页 AppBar 颜色/高度与主页一致（愿望单粉色保留）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: ItemEditScreen())));
      await _settle(tester);
      final bar = appBarOf(tester);
      expect(bar.backgroundColor, homeBarColor);
      expect(bar.toolbarHeight, 48);
    });

    testWidgets('资产编辑页 AppBar 颜色/高度与主页一致', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: AssetEditScreen())));
      await _settle(tester);
      final bar = appBarOf(tester);
      expect(bar.backgroundColor, homeBarColor);
      expect(bar.toolbarHeight, 48);
    });

    testWidgets('笔记编辑页与浏览页 AppBar 颜色/高度与主页一致', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: EditScreen())));
      await _settle(tester);
      final bar = appBarOf(tester);
      expect(bar.backgroundColor, homeBarColor);
      expect(bar.toolbarHeight, 48);

      // 浏览页：封面图用真实像素，避免 EntryImage 异常
      final imgDir = Directory(
          '/tmp/v4931_img_${DateTime.now().microsecondsSinceEpoch}')
        ..createSync(recursive: true);
      final img = File('${imgDir.path}/cover.png')
        ..writeAsBytesSync(base64Decode(_pngBase64));

      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(
            entry: _makeEntry(imagePath: img.path)),
      ));
      await _settle(tester);
      final viewBar = appBarOf(tester);
      expect(viewBar.backgroundColor, homeBarColor);
      expect(viewBar.toolbarHeight, 48);
      // 图标热区同步为 48×48
      final more = tester.widget<IconButton>(
          find.byKey(const ValueKey('note_action_more')));
      expect(more.constraints, const BoxConstraints.tightFor(width: 48, height: 48));
    });
  });
}
