import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/home_screen.dart';
import 'package:ayodiray/utils/app_motion.dart';
import 'package:ayodiray/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.9 回归：统一转场 / 回顶按钮位置（与新建 FAB 同水平线）/
/// 卡片封面图不再做 Hero 共享元素飞行
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
    dir = Directory('/tmp/motion_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  Future<void> writeEntries(List<DiaryEntry> entries) async {
    File('${dir.path}/diaries.json').writeAsStringSync(
        jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  void usePhone(WidgetTester tester) {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);
  }

  test('AppMotion.slide 统一 300ms 且每次返回新路由', () {
    final raw1 = AppMotion.slide<void>(const SizedBox());
    final raw2 = AppMotion.slide<void>(const SizedBox());
    expect(raw1, isA<PageRouteBuilder<void>>());
    expect(identical(raw1, raw2), isFalse, reason: '不能复用同一路由实例');
    final a = raw1 as PageRouteBuilder<void>;
    expect(a.transitionDuration, const Duration(milliseconds: 300));
    expect(a.reverseTransitionDuration, const Duration(milliseconds: 300));
  });

  testWidgets('长列表滚动后出现回顶按钮，点击回到顶部', (tester) async {
    usePhone(tester);
    final now = DateTime.now();
    await writeEntries([
      for (var i = 0; i < 40; i++)
        DiaryEntry(
          id: 'e$i',
          title: '笔记 $i',
          content: '内容 $i',
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day - i),
        ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await _settle(tester);

    final upIcon = find.byWidgetPredicate(
        (w) => w is AppIcon && w.path == AppIcons.arrowUp);
    expect(upIcon, findsNothing, reason: '未滚动时不应出现回顶按钮');

    // 取竖向列表（视图栏是横向 Scrollable，不能用 first/last 猜）
    final vList = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down);
    // 取主列表：树里有多个竖向 Scrollable（日历/空态等 max=0），
    // 用 maxScrollExtent 最大的那个才可靠
    ScrollPosition? main;
    for (final e in vList.evaluate()) {
      final st = (e as StatefulElement).state as ScrollableState;
      final cur = main;
      if (cur == null || st.position.maxScrollExtent > cur.maxScrollExtent) {
        main = st.position;
      }
    }
    main!.jumpTo(900);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(upIcon, findsOneWidget, reason: '滚过一屏应出现回顶按钮');

    // 与新建 FAB 同一水平线，且排在 FAB 左侧不重叠
    final backRect = tester.getRect(upIcon);
    final fabRect = tester.getRect(find.byType(FloatingActionButton));
    expect((backRect.center.dy - fabRect.center.dy).abs(), lessThan(1.5),
        reason: '回顶按钮中心应与新建按钮中心对齐');
    expect(backRect.right, lessThanOrEqualTo(fabRect.left - 8),
        reason: '回顶按钮应在新建按钮左侧且留出间隙');

    await tester.tap(upIcon);
    // 回顶是 420ms 的动画，需要逐帧推进（单次 pump 不会跑完曲线）
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(main.pixels, lessThan(1), reason: '点击后应回到列表顶部');
    expect(upIcon, findsNothing, reason: '回到顶部后按钮应消失');
    expect(find.text('笔记 0', skipOffstage: false), findsOneWidget);
  });

  testWidgets('卡片封面图不再使用 Hero：转场只保留整页滑入', (tester) async {
    usePhone(tester);
    final img = File('${dir.path}/cover.png')
      ..writeAsBytesSync(base64Decode(_pngB64));
    final now = DateTime.now();
    await writeEntries([
      DiaryEntry(
        id: 'hero-1',
        title: '有图笔记',
        content: '不再共享元素',
        imagePath: img.path,
        createdAt: now,
        updatedAt: now,
        publishDate: DateTime(now.year, now.month, now.day),
      ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await _settle(tester);

    // 图片飞行与整页右→左滑入叠加时轨迹会拐弯，已移除共享元素
    // （FAB 自带默认 Hero tag，这里只检查封面图那一类）
    final coverHeroes = tester
        .widgetList<Hero>(find.byType(Hero))
        .where((h) => h.tag.toString().startsWith('note_cover_'));
    expect(coverHeroes, isEmpty, reason: '卡片封面图不应再包 Hero');
    expect(find.byType(Image), findsOneWidget, reason: '封面图本身仍要渲染');
  });
}
