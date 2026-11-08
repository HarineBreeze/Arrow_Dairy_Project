import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/home_screen.dart';
import 'package:ayodiray/utils/diary_group_defaults.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// 笔记卡片改版回归：
/// 1. 有图卡片走「左图右文」（方案 D，4:3），无图卡片保留撕页日历徽章；
/// 2. 视图栏为 全部 / 按日 / 按月 / 按年，且「全部」不出现日期收纳栏。
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

/// 40×30（4:3）纯色 PNG
const String _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAALklEQVR4nO3NMQEAMAgAoLlg'
    'NrKKma3g5wMFiOx6F/7JKhaLxWKxWCwWi8XilQEMTAF1/KYm1AAAAABJRU5ErkJggg==';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
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
    dir = Directory(
        '/tmp/diary_card_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  Future<File> writeImage() async {
    final f = File('${dir.path}/cover.png');
    f.writeAsBytesSync(base64Decode(_pngB64));
    return f;
  }

  Future<void> writeEntries(List<DiaryEntry> entries) async {
    final f = File('${dir.path}/diaries.json');
    f.writeAsStringSync(jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  testWidgets('有图走左图右文，无图保留日期徽章', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

    final img = await writeImage();
    final now = DateTime.now();
    await writeEntries([
      DiaryEntry(
        id: 'with-image',
        title: '有图的笔记',
        content: '左图右文的摘要内容',
        imagePath: img.path,
        createdAt: now,
        updatedAt: now,
        publishDate: DateTime(now.year, now.month, now.day),
      ),
      DiaryEntry(
        id: 'no-image',
        title: '无图的笔记',
        content: '保留日期徽章的排版',
        createdAt: now,
        updatedAt: now,
        publishDate: DateTime(now.year, now.month, now.day - 1),
      ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await _settle(tester);

    expect(find.text('有图的笔记'), findsOneWidget);
    expect(find.text('无图的笔记'), findsOneWidget);
    // 有图卡：图片渲染（4:3 容器 124×93）
    expect(find.byType(Image), findsOneWidget);
    final imgBox = tester.getSize(find.byType(Image));
    expect(imgBox.width / imgBox.height, closeTo(4 / 3, 0.02),
        reason: '图片区必须是 4:3');
    // 无图卡：日期徽章显示「日」数字
    final day = DateTime(now.year, now.month, now.day - 1).day;
    expect(find.text('$day'), findsWidgets,
        reason: '无图卡应保留撕页日历徽章');
    // 心情/天气不再出现在卡片上
    expect(find.text('😊'), findsNothing);
    expect(find.text('☀️'), findsNothing);
  });

  testWidgets('视图栏四档；全部无收纳栏，按日出现日期分组', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

    final now = DateTime.now();
    await writeEntries([
      DiaryEntry(
        id: 'a',
        title: '今天的笔记',
        createdAt: now,
        updatedAt: now,
        publishDate: DateTime(now.year, now.month, now.day),
      ),
      DiaryEntry(
        id: 'b',
        title: '昨天的笔记',
        createdAt: now,
        updatedAt: now,
        publishDate: DateTime(now.year, now.month, now.day - 1),
      ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await _settle(tester);

    for (final label in ['全部', '按日', '按月', '按年']) {
      expect(find.text(label), findsWidgets, reason: '视图栏应有「$label」');
    }

    // 全部：平铺，无「x 篇」日期收纳栏
    expect(find.textContaining('篇'), findsNothing,
        reason: '「全部」视图不应出现日期收纳栏');

    // 切到按日：出现按日分组头（昨天那篇在最近 7 天内，默认展开）
    await tester.tap(find.text('按日').first);
    await tester.pump(const Duration(milliseconds: 300));
    await _settle(tester);

    final yesterday =
        DateTime(now.year, now.month, now.day - 1);
    final key = DiaryGroupDefaults.dateKey(yesterday);
    expect(key, isNotEmpty);
    expect(find.textContaining('篇'), findsWidgets,
        reason: '「按日」视图应按日折叠并显示分组头');
    expect(find.text('昨天的笔记'), findsOneWidget);
  });
}
