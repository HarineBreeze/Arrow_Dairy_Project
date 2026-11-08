import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ayodiray/screens/image_crop_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// 固定 4:3 自由裁剪页回归：
/// 1. 裁剪几何（初始框 / 平移夹回 / 角缩放）比例恒为 4:3 且不越出显示区；
/// 2. 像素管线：输出写入新文件、比例锁定 4:3；
/// 3. UI：图片加载完成显示裁剪界面，图片缺失显示加载失败不崩溃。
///
/// 注：「完成」按钮触发的 toImage 在 testWidgets 的 FakeAsync 环境无法完成，
/// 因此像素管线用普通 test() 验证（与 lucide_gallery_test 同理）。
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
const String _png43 =
    'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAAK0lEQVR4nO3NMQ0AAAgDsCnDEVbQjAw4mvRvavpExGKxWCwWi8VisVj8N160u7t80lrKrAAAAABJRU5ErkJggg==';

/// 40×25（1.6，非 4:3）纯色 PNG
const String _pngWide =
    'iVBORw0KGgoAAAANSUhEUgAAACgAAAAZCAIAAADMuvsyAAAAKUlEQVR4nGOw68sdEMQwavGoxaMWj1o8avGoxaMWj1o8avGoxaMWU4wArxXG5Qdm07QAAAAASUVORK5CYII=';

void main() {
  group('裁剪几何（纯函数）', () {
    test('显示区比 4:3 更宽：初始框取全高，比例 4:3，左右居中', () {
      final r = initialCropRect(const Size(400, 200));
      expect(r.height, 200);
      expect(r.width, closeTo(200 * 4 / 3, 0.01));
      expect(r.top, 0);
      expect(r.left, closeTo((400 - 200 * 4 / 3) / 2, 0.01));
      expect(r.bottom, lessThanOrEqualTo(200 + 0.01));
      expect(r.right, lessThanOrEqualTo(400 + 0.01));
    });

    test('高受限：初始框取全高，比例 4:3', () {
      final r = initialCropRect(const Size(800, 600));
      expect(r.height, 600);
      expect(r.width, closeTo(800, 0.01));
    });

    test('角缩放：拖动右下角，比例锁定 4:3 且不越界', () {
      final disp = const Size(800, 600);
      var r = initialCropRect(disp);
      r = resizeCropRect(r, 3, const Offset(500, 400), disp);
      expect(r.width / r.height, closeTo(4 / 3, 0.01));
      expect(r.right, lessThanOrEqualTo(disp.width + 0.01));
      expect(r.bottom, lessThanOrEqualTo(disp.height + 0.01));
      // 拖得太小：不应低于最小尺寸
      r = resizeCropRect(r, 3, const Offset(10, 10), disp);
      expect(r.width, greaterThanOrEqualTo(kCropMinSize - 0.01));
    });

    test('平移夹回：拖出边界后停在显示区内', () {
      final disp = const Size(800, 600);
      final r = initialCropRect(disp).translate(9999, 9999);
      final clamped = clampCropRect(r, disp);
      expect(clamped.right, lessThanOrEqualTo(disp.width + 0.01));
      expect(clamped.bottom, lessThanOrEqualTo(disp.height + 0.01));
    });
  });

  group('裁剪像素管线（普通 test，真实异步）', () {
    late Directory dir;

    setUp(() {
      dir = Directory(
          '/tmp/crop_test_${DateTime.now().microsecondsSinceEpoch}');
      dir.createSync(recursive: true);
      PathProviderPlatform.instance = _FakePathProvider(dir.path);
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      PathProviderPlatform.instance = MethodChannelPathProvider();
    });

    Future<ui.Image> decode(String path) async {
      final bytes = await File(path).readAsBytes();
      return decodeImageFromList(bytes);
    }

    test('4:3 原图全图裁剪：输出与原图同尺寸、写入新文件', () async {
      final src = File('${dir.path}/src.png');
      src.writeAsBytesSync(base64Decode(_png43));
      final img = await decode(src.path);
      final out = await writeCroppedImage(
          img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          dir.path);

      expect(out, isNot(equals(src.path)), reason: '应写入新文件');
      final outImg = await decode(out);
      expect(outImg.width, 40);
      expect(outImg.height, 30);
    });

    test('局部裁剪：按 srcRect 输出并保持 4:3', () async {
      final src = File('${dir.path}/src.png');
      src.writeAsBytesSync(base64Decode(_png43));
      final img = await decode(src.path);
      final out = await writeCroppedImage(
          img, const Rect.fromLTWH(0, 0, 40, 30), dir.path);
      final outImg = await decode(out);
      expect(outImg.width / outImg.height, closeTo(4 / 3, 0.05));
    });

    test('非 4:3 原图：映射后的 4:3 srcRect 输出仍为 4:3', () async {
      final src = File('${dir.path}/src.png');
      src.writeAsBytesSync(base64Decode(_pngWide));
      final img = await decode(src.path);
      // 显示区 800x400（比 4:3 更宽）→ 初始框 (133.3, 0, 533.3, 400)，
      // 映射回原图 sx = 40/800：srcRect = (6.67, 0, 26.67, 20)
      final out = await writeCroppedImage(
          img, const Rect.fromLTWH(40 / 6, 0, 80 / 3, 20), dir.path);
      final outImg = await decode(out);
      expect(outImg.width / outImg.height, closeTo(4 / 3, 0.05));
    });
  });

  testWidgets('UI：图片加载后显示裁剪界面（测试环境不点完成，toImage 会挂起）',
      (tester) async {
    final dir = Directory(
        '/tmp/crop_ui_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      PathProviderPlatform.instance = MethodChannelPathProvider();
    });

    final src = File('${dir.path}/src.png');
    src.writeAsBytesSync(base64Decode(_png43));

    await tester.pumpWidget(MaterialApp(
      home: ImageCropScreen(imagePath: src.path),
    ));
    // decode 是真实异步：pump + runAsync 交替推进
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      if (find.byWidgetPredicate((w) => w is RawImage).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byWidgetPredicate((w) => w is RawImage), findsOneWidget,
        reason: '图片应加载完成');
    expect(find.text('自由裁剪'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('拖动裁剪框调整区域，比例固定 4:3'), findsOneWidget);
  });

  testWidgets('UI：图片文件缺失时显示加载失败而非崩溃', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ImageCropScreen(imagePath: '/nonexistent/nope.png'),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      if (find.text('图片加载失败').evaluate().isNotEmpty) break;
    }
    expect(find.text('图片加载失败'), findsOneWidget);
    expect(find.text('完成'), findsNothing);
  });
}
