import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/home_screen.dart';
import 'package:ayodiray/screens/item_list_screen.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/utils/app_version.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v5.0.6：
/// 1. 置顶卡带去掉「置顶 x 篇」标题，卡片上移；
/// 2. 「数据栏 → 置顶卡」与「置顶卡 → 首张笔记卡」间距相等；
/// 3. 笔记数据栏 / 物品数据栏高度收窄（上下留白 14 → 10）；
/// 4. 杂货店身份商品名改为「身份·诞生日」。
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
    dir = Directory('/tmp/v5006_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  Future<void> writeEntries(List<DiaryEntry> entries) async {
    final f = File('${dir.path}/diaries.json');
    f.writeAsStringSync(jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  group('置顶卡带：去标题 + 上下间距相等', () {
    testWidgets('不再出现「置顶 x 篇」小标题，卡片整体上移', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 900);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

      final now = DateTime.now();
      await writeEntries([
        DiaryEntry(
          id: 'pinned',
          title: '置顶',
          content: '置顶摘要',
          pinned: true,
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day),
        ),
        DiaryEntry(
          id: 'normal',
          title: '普通笔记',
          content: '普通摘要',
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day - 1),
        ),
      ]);

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await _settle(tester);

      // 标题已移除（原先为「置顶 1 篇」）
      expect(find.textContaining('置顶 '), findsNothing,
          reason: '置顶卡带不应再有「置顶 x 篇」标题');
      // 卡带与卡片本身仍在
      expect(find.byKey(const ValueKey('pinned-rail')), findsOneWidget);
      expect(find.text('置顶'), findsOneWidget);
    });

    testWidgets('数据栏→置顶卡 与 置顶卡→首张笔记卡 间距相等', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 900);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

      final now = DateTime.now();
      await writeEntries([
        DiaryEntry(
          id: 'pinned',
          title: '置顶',
          content: '置顶摘要',
          pinned: true,
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day),
        ),
        DiaryEntry(
          id: 'normal',
          title: '普通笔记',
          content: '普通摘要',
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day - 1),
        ),
      ]);

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await _settle(tester);

      // 数据栏底边：数据栏是「总篇数」最近的 Container（带竖向 padding）
      final statsRect = tester.getRect(find
          .ancestor(
              of: find.text('总篇数'), matching: find.byType(Container))
          .first);
      final railBox = find.byKey(const ValueKey('pinned-rail'));
      final railRect = tester.getRect(railBox);
      final railPad =
          tester.widget<Padding>(railBox).padding as EdgeInsets;
      final cardRect =
          tester.getRect(find.byKey(const ValueKey('note-row-normal')));

      // 取「可见卡面」而非含 padding 的外框：
      // 上间距 = 数据栏底 → 置顶卡面顶；下间距 = 置顶卡面底 → 笔记卡卡面顶
      final gapTop =
          (railRect.top + railPad.top) - statsRect.bottom;
      final gapBottom = (cardRect.top + 8) - (railRect.bottom - railPad.bottom);

      expect(gapTop, closeTo(gapBottom, 1.5),
          reason: '置顶卡上边距($gapTop)应等于下边距($gapBottom)');
      expect(gapTop, lessThan(20), reason: '去掉标题后间距应属于紧凑范围');
    });
  });

  group('数据栏高度收窄', () {
    testWidgets('笔记数据栏上下留白为 10', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 900);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

      final now = DateTime.now();
      await writeEntries([
        DiaryEntry(
          id: 'a',
          title: '笔记',
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day),
        ),
      ]);

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await _settle(tester);

      final box = tester.widget<Container>(find
          .ancestor(
              of: find.text('总篇数'), matching: find.byType(Container))
          .first);
      final pad = box.padding as EdgeInsets;
      expect(pad.top, 10);
      expect(pad.bottom, 10);
    });

    testWidgets('物品数据栏上下留白为 10', (tester) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 900);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ItemListScreen(onOpenMenu: () {})),
      ));
      await _settle(tester);

      final box = tester.widget<Container>(find
          .ancestor(
              of: find.text('物品数'), matching: find.byType(Container))
          .first);
      final pad = box.padding as EdgeInsets;
      expect(pad.top, 10);
      expect(pad.bottom, 10);
    });
  });

  group('杂货店身份名', () {
    test('诞生日商品名为「身份·诞生日」', () {
      final item = RewardService.shopBadges
          .firstWhere((s) => s.id == UserProfile.badgeBirthday);
      expect(item.name, '身份·诞生日');
      // 与「主题·暖棕」同一命名格式
      expect(item.name.contains('·'), isTrue);
    });

    test('版本号推进到 V5.0.6', () {
      expect(AppVersion.displayVersion, 'V5.0.7');
    });
  });
}
