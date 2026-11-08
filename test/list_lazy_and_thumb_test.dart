import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/edit_screen.dart';
import 'package:ayodiray/screens/home_screen.dart';
import 'package:ayodiray/widgets/entry_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// 体验优化回归（v4.9.7）：
/// 1. 列表缩略图按显示宽度降采样解码（cacheWidth），不再解整幅原图；
/// 2. 主页列表改 ListView.builder 懒加载，屏外卡片不构建；
/// 3. 编辑页首次点击正文，光标落在点击处而不是文末。
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
    dir = Directory('/tmp/lazy_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  File writeImage() {
    final f = File('${dir.path}/cover.png');
    f.writeAsBytesSync(base64Decode(_pngB64));
    return f;
  }

  void writeEntries(List<DiaryEntry> entries) {
    File('${dir.path}/diaries.json')
        .writeAsStringSync(jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  testWidgets('缩略图按显示宽度降采样（cacheWidth ≈ 宽×DPR×1.5）', (tester) async {
    final img = writeImage();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 124,
          height: 93,
          child: EntryImage(path: img.path, displayWidth: 124),
        ),
      ),
    ));
    await _settle(tester);

    final image = tester.widget<Image>(find.byType(Image));
    final dpr = tester.binding.window.devicePixelRatio;
    // Image.file(cacheWidth: x) 会把 provider 包成 ResizeImage
    final provider = image.image;
    expect(provider, isA<ResizeImage>(), reason: '应按显示宽度而非原图尺寸解码');
    final resize = provider as ResizeImage;
    expect(resize.width, (124 * dpr * 1.5).round());
    expect(resize.width! < 1600, isTrue);
  });

  testWidgets('主页列表懒加载：只构建可视范围内的卡片', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

    final now = DateTime.now();
    writeEntries([
      for (var i = 0; i < 40; i++)
        DiaryEntry(
          id: 'e$i',
          title: '笔记 $i',
          content: '第 $i 篇的内容',
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: i)),
        ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await _settle(tester);

    expect(find.text('笔记 0'), findsOneWidget);
    expect(find.byType(ListView), findsWidgets);
    // 40 篇里只构建可视范围内的十来张 —— 旧版 ListView(children:) 会 40 张全建
    final built = find.textContaining('笔记 ').evaluate().length;
    expect(built, greaterThan(3));
    expect(built, lessThan(40), reason: '屏外卡片应延迟构建');
    expect(find.text('笔记 39'), findsNothing, reason: '屏外的第 40 篇不应被构建');

  });

  testWidgets('编辑页首次点击正文：光标落在点击处而非文末', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

    final now = DateTime.now();
    final content = List.generate(12, (i) => '第 $i 行正文内容，用来把输入框撑高').join('\n');
    final entry = DiaryEntry(
      id: 'e1',
      title: '光标定位',
      content: content,
      createdAt: now,
      updatedAt: now,
      publishDate: DateTime(now.year, now.month, now.day),
    );

    await tester.pumpWidget(MaterialApp(home: EditScreen(entry: entry)));
    await _settle(tester);

    final field = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLength == 2000);
    expect(field, findsOneWidget);
    final rect = tester.getRect(field);
    // 点正文上半部分靠左的位置
    await tester.tapAt(Offset(rect.left + 40, rect.top + 20));
    await _settle(tester);

    final ctrl = tester.widget<TextField>(field).controller!;
    expect(ctrl.selection.baseOffset, greaterThan(0));
    expect(ctrl.selection.baseOffset, lessThan(ctrl.text.length),
        reason: '点在中部时不应把光标丢到文末');
  });
}
