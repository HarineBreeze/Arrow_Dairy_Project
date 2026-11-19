import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:share_plus_platform_interface/method_channel/method_channel_share.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/models/item.dart';
import 'package:ayodiray/screens/note_view_screen.dart';
import 'package:ayodiray/widgets/share_card.dart';
import 'package:ayodiray/widgets/stationery_paper.dart';

/// 把文档/临时目录指到临时目录
class _FakePaths extends PathProviderPlatform {
  final String docs;
  final String tmp;
  _FakePaths(this.docs, this.tmp);
  @override
  Future<String?> getApplicationDocumentsPath() async => docs;
  @override
  Future<String?> getTemporaryPath() async => tmp;
}

const String _kTinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAADwAAAAtCAIAAAB9FJ8bAAAAUElEQVR4nO3OQQ3AIAAAMYZQ3EzMXM4DjxKSq4I+63vHbebpwI7SSmmltFJaKa2UVkorpZXSSmmltFJaKa2UVkorpZXSSmmltFJaKa1cmf4B7sUB5sVs5a4AAAAASUVORK5CYII=';

DiaryEntry _entry({String location = '厦门·鼓浪屿', String? imagePath}) {
  return DiaryEntry(
    id: 'e1',
    title: '海边的一天',
    content: '今天去了海边，\n风很大但很舒服。\n[ ] 洗照片\n[x] 写日记',
    imagePath: imagePath ?? '',
    location: location,
    createdAt: DateTime(2026, 11, 11, 9, 30),
    updatedAt: DateTime(2026, 11, 11, 9, 30),
    publishDate: DateTime(2026, 11, 11),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;
  late Directory tmp;
  late File fakePng;

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('share_docs');
    tmp = await Directory.systemTemp.createTemp('share_tmp');
    PathProviderPlatform.instance = _FakePaths(docs.path, tmp.path);
    // 测试宿主是 Linux，share_plus 会选到 Linux 实现（未实现直接抛错），
    // 这里钉回 MethodChannel 实现，配合下面的通道 mock 断言调用
    SharePlatform.instance = MethodChannelShare();
    // 文件 IO 必须在 setUp（FakeAsync 之外）完成，testWidgets 内 await 真实
    // IO 会永远不返回
    fakePng = File('${tmp.path}/share_fake.png');
    await fakePng.writeAsBytes(base64Decode(_kTinyPngBase64));
  });

  tearDown(() async {
    await docs.delete(recursive: true);
    await tmp.delete(recursive: true);
  });

  group('浏览页顶栏「更多」下拉选框', () {
    testWidgets('三按钮收进更多，点按从锚点弹出编辑/删除/分享', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: NoteViewScreen(entry: _entry())),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // 顶栏不再常驻编辑/删除/分享三个独立按钮
      expect(find.byKey(const ValueKey('note_action_edit')), findsNothing);
      expect(find.byKey(const ValueKey('note_action_delete')), findsNothing);
      expect(find.byKey(const ValueKey('note_action_share')), findsNothing);
      expect(find.byKey(const ValueKey('note_action_more')), findsOneWidget);

      // 点「更多」弹下拉选框，三项顺序：编辑、删除、分享
      await tester.tap(find.byKey(const ValueKey('note_action_more')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('分享'), findsOneWidget);
      final editY = tester.getCenter(find.text('编辑')).dy;
      final delY = tester.getCenter(find.text('删除')).dy;
      final shareY = tester.getCenter(find.text('分享')).dy;
      expect(editY, lessThan(delY));
      expect(delY, lessThan(shareY));
    });
  });

  group('分享卡底部信息条样式', () {
    testWidgets('信息条紧贴内容区：自然高度、Logo 左缘与正文白卡对齐',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ShareCard(
                  entry: _entry(),
                  items: const <Item>[],
                  footerKey: const ValueKey('share_footer'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final footerBox = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('share_footer')),
      );
      // 信息条为自然高度（上下 14/16 内边距 + 40px Logo 行），不再占 1/6 大白区
      expect(footerBox.size.height, lessThan(120));
      expect(footerBox.size.height, greaterThan(40));

      // Logo 左缘与内容区标题白卡左缘对齐（同一 20px 内边距）
      final logoLeft = tester.getTopLeft(
        find.descendant(
          of: find.byKey(const ValueKey('share_footer')),
          matching: find.byWidgetPredicate((w) =>
              w is Image && w.image is AssetImage),
        ),
      ).dx;
      final titleCardLeft = tester.getTopLeft(
        // 树中第一个白色圆角卡 = 标题卡（其后还有正文内联与待办卡）
        find.byWidgetPredicate((w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color == Colors.white)
            .first,
      ).dx;
      expect(logoLeft, closeTo(titleCardLeft, 0.5));

      // 内容区之下就是信息条，再往下没有多余白色区域
      final columnBox = tester.renderObject<RenderBox>(
        find.byType(ShareCard),
      );
      expect(
        footerBox.size.height,
        closeTo(
          columnBox.size.height -
              tester.getTopLeft(find.byKey(const ValueKey('share_footer'))).dy,
          0.5,
        ),
      );

      expect(find.text('阿尤日记'), findsOneWidget);
      expect(find.text('2026/11/11 09:30'), findsOneWidget);
      expect(find.text('厦门·鼓浪屿'), findsOneWidget);
    });
  });

  group('分享按钮链路', () {
    testWidgets('点击分享：显示进度弹窗 → 关弹窗 → 调起系统分享（带标题文案）',
        (tester) async {
      final out = fakePng;

      int shareCalls = 0;
      Object? lastArgs;
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
        shareCalls++;
        lastArgs = call.arguments;
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
            .setMockMethodCallHandler(shareChannel, null);
      });

      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(
          entry: _entry(),
          // 注入替身：跳过真实截图（FakeAsync 下 toImage 不完成）。
          // 故意延迟 300ms（FakeAsync 定时器），以便断言进度弹窗出现过
          shareCapture: (ctx, entry, items) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return out;
          },
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey('note_action_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享'));
      await tester.pump(const Duration(milliseconds: 200)); // 菜单退出 + 弹窗入场
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('正在生成分享图…'), findsOneWidget,
          reason: '生成期间应显示进度弹窗');

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('正在生成分享图…'), findsNothing, reason: '生成完应关闭弹窗');
      expect(shareCalls, 1, reason: '应调起一次系统分享');
      final args = lastArgs as Map<dynamic, dynamic>?;
      expect(args, isNotNull);
      expect(args!['paths'].toString(), contains(out.path));
      expect(args['text'].toString(), contains('海边的一天'));
    });

    testWidgets('生成失败：不调起分享并提示重试', (tester) async {
      int shareCalls = 0;
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, (call) async {
        shareCalls++;
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
            .setMockMethodCallHandler(shareChannel, null);
      });

      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(
          entry: _entry(),
          shareCapture: (ctx, entry, items) async => null,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.byKey(const ValueKey('note_action_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(shareCalls, 0);
      expect(find.text('分享图生成失败，请重试'), findsOneWidget);
      // 排空提示的自动收起定时器
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('分享卡保留信纸样式', () {
    Future<void> pumpShare(WidgetTester tester, DiaryEntry entry) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                ShareCard(entry: entry, items: const <Item>[]),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    DiaryEntry _entryWith(String stationery) {
      final e = _entry(location: '');
      e.stationery = stationery;
      return e;
    }

    testWidgets('设置信纸的笔记分享时保留信纸渲染层', (tester) async {
      await pumpShare(tester, _entryWith('night'));
      expect(find.byType(StationeryPaper), findsWidgets);
      expect(find.text('海边的一天'), findsOneWidget);
      expect(find.textContaining('今天去了海边'), findsOneWidget);
    });

    testWidgets('星夜来信：信纸之外的区域同步压暗', (tester) async {
      await pumpShare(tester, _entryWith('night'));
      // 信纸渲染层存在，且内容区背景为压暗的深色
      expect(find.byType(StationeryPaper), findsWidgets);
      final darkBg = find.byWidgetPredicate((w) =>
          w is Container &&
          w.color == const Color(0xFF1A201C));
      expect(darkBg, findsOneWidget);
    });

    testWidgets('已下架样式读回回退经典，分享不报错', (tester) async {
      await pumpShare(tester, _entryWith('washi'));
      expect(find.text('海边的一天'), findsOneWidget);
    });
  });
}
