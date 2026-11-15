import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/trash_screen.dart';
import 'package:ayodiray/services/trash_storage.dart';

/// v4.9.20 回收站交互回归：
/// 1. 卡片上不再有还原 / 彻底删除按钮，操作移到顶栏；
/// 2. 顶栏「还原」进入选择模式，可单选 / 多选后确认还原；
/// 3. 顶栏「删除」弹出菜单：选择性删除（含全选）/ 清空回收站；
/// 4. 旧版本拼进副标题的 mood emoji 在读档时被清理。
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
    dir = Directory('/tmp/v4920_trash_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  Map<String, dynamic> diaryJson(String id, String title,
      {String mood = ''}) {
    final now = DateTime(2026, 11, 10, 9, 30);
    return DiaryEntry(
      id: id,
      title: title,
      content: '正文内容',
      createdAt: now,
      updatedAt: now,
      publishDate: now,
      mood: mood,
    ).toJson();
  }

  void writeTrash(List<Map<String, dynamic>> entries) {
    File('${dir.path}/trash.json').writeAsStringSync(jsonEncode(entries));
  }

  Map<String, dynamic> trashItem({
    required String id,
    required String bizId,
    required String title,
    String subtitle = '2026.11.10',
    Map<String, dynamic>? data,
    int daysAgo = 2,
  }) =>
      {
        'id': id,
        'kind': 'diary',
        'data': data ?? diaryJson(bizId, title),
        'deletedAt': DateTime.now()
            .subtract(Duration(days: daysAgo))
            .toIso8601String(),
        'title': title,
        'subtitle': subtitle,
      };

  /// 等待某个条件成立（回收站批量操作是连续真实文件 IO，
  /// 假时钟下需要多次 runAsync 窗口才能全部落盘）
  Future<void> _until(
      WidgetTester tester, bool Function() cond) async {
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      });
      await tester.pump();
      if (cond()) return;
    }
  }

  List<String> readDiaryTitles() {
    final f = File('${dir.path}/diaries.json');
    if (!f.existsSync()) return [];
    try {
      final list = jsonDecode(f.readAsStringSync()) as List<dynamic>;
      return list
          .map((e) => (e as Map<String, dynamic>)['title'] as String)
          .toList();
    } catch (_) {
      // 落盘中途读取到半截内容：当作还没写完
      return [];
    }
  }

  List<dynamic> readTrashRaw() {
    final f = File('${dir.path}/trash.json');
    if (!f.existsSync()) return [];
    return jsonDecode(f.readAsStringSync()) as List<dynamic>;
  }

  Widget host() => MaterialApp(
        home: Scaffold(body: TrashScreen(onOpenMenu: () {})),
      );

  testWidgets('副标题里的旧 emoji 在读档时被清理', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    writeTrash([
      trashItem(
        id: 't1',
        bizId: 'd1',
        title: '带表情的旧笔记',
        subtitle: '2026.11.10 · 😄',
        data: diaryJson('d1', '带表情的旧笔记', mood: '😄'),
      ),
    ]);

    await tester.pumpWidget(host());
    await _settle(tester);

    expect(find.text('2026.11.10'), findsOneWidget);
    expect(find.textContaining('😄'), findsNothing);
    // 回写落盘：记录的 subtitle 字段不再带表情（data 里保留原始 mood 字段）
    final raw = readTrashRaw().first as Map<String, dynamic>;
    expect(raw['subtitle'], '2026.11.10');
  });

  testWidgets('还原：顶栏按钮 → 选择模式 → 多选确认 → 回到日记列表', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    writeTrash([
      trashItem(id: 't1', bizId: 'd1', title: '笔记一'),
      trashItem(id: 't2', bizId: 'd2', title: '笔记二'),
      trashItem(id: 't3', bizId: 'd3', title: '笔记三'),
    ]);

    await tester.pumpWidget(host());
    await _settle(tester);

    // 卡片上不再有还原按钮
    expect(find.text('还原'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('trash-restore')));
    await tester.pump();
    expect(find.text('已选 0 项'), findsOneWidget);
    expect(find.text('选择要还原的内容，可多选'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('trash-entry-t1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('trash-entry-t3')));
    await tester.pump();
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('trash-confirm')));
    await _settle(tester);
    await _until(tester, () => readDiaryTitles().length >= 2);
    // 等页面自身重读回收站，把已还原的条目从列表里移除
    await _until(tester, () =>
        find.text('笔记一').evaluate().isEmpty &&
        find.text('笔记三').evaluate().isEmpty);
    await _settle(tester);

    expect(readDiaryTitles(), containsAll(['笔记一', '笔记三']));
    expect(readDiaryTitles(), isNot(contains('笔记二')));
    // 未选中的仍在回收站
    expect(find.text('笔记二'), findsOneWidget);
    expect(find.text('笔记一'), findsNothing);
    await tester.pump(const Duration(seconds: 2)); // 排空 toast 定时器
  });

  testWidgets('选择性删除：菜单进入 → 全选 → 确认弹窗 → 彻底删除', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    writeTrash([
      trashItem(id: 't1', bizId: 'd1', title: '笔记甲'),
      trashItem(id: 't2', bizId: 'd2', title: '笔记乙'),
    ]);

    await tester.pumpWidget(host());
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('trash-delete')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('选择性删除'), findsOneWidget);
    expect(find.text('清空回收站'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('trash-menu-selective')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('选择要彻底删除的内容，可多选或全选'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('trash-select-all')));
    await tester.pump();
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('trash-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('彻底删除 2 项?'), findsOneWidget);

    await tester.tap(find.text('彻底删除'));
    await _settle(tester);
    await _until(tester, () => readTrashRaw().isEmpty);
    await _settle(tester);

    expect(readTrashRaw(), isEmpty);
    expect(find.text('回收站是空的'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('清空回收站仍保留在删除菜单里', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    writeTrash([
      trashItem(id: 't1', bizId: 'd1', title: '笔记丙'),
    ]);

    await tester.pumpWidget(host());
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('trash-delete')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('trash-menu-clear')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('清空回收站?'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await _settle(tester);
    await _until(tester, () => readTrashRaw().isEmpty);
    await _settle(tester);
    expect(readTrashRaw(), isEmpty);
    await tester.pump(const Duration(seconds: 2));
  });
}
