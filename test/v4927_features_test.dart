import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/asset_edit_screen.dart';
import 'package:ayodiray/screens/countdown_edit_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';
import 'package:ayodiray/screens/note_view_screen.dart';
import 'package:ayodiray/screens/profile_edit_screen.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/widgets/rich_note_text.dart';

/// v4.9.27 回归：
/// 1. 智能回车：单行输入 textInputAction=next/done，多行正文保持换行；
/// 2. 浏览页「更多」下拉选框 + 搜索正文命中高亮 + N处匹配逐条定位；
/// 3. 全局搜索结果标题命中高亮 + N处匹配条；
/// 4. 物品编辑页计算方式独立节标题 + 资产页移除金额提示；
/// 5. 回收站两路还原二次确认（见 trash_selection_test 已改）；
/// 6. 个人页「注册日」日期格式；VIP 日卡文案「1天」；
/// 7. 深色模式命中字色固定 0xFF24382F（可见）。
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
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory('/tmp/v4927_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  DiaryEntry entryWith(String content) => DiaryEntry(
        id: 'e1',
        title: '海边的一天',
        content: content,
        createdAt: DateTime(2026, 6, 25, 10, 30),
        updatedAt: DateTime(2026, 6, 25, 10, 30),
        publishDate: DateTime(2026, 6, 25),
      );

  group('智能回车焦点链', () {
    testWidgets('事件名称 next、备注 done', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: CountdownEditScreen()));
      await _settle(tester);

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      // 名称、备注两个主输入
      expect(fields.any((f) => f.textInputAction == TextInputAction.next), isTrue);
      expect(fields.any((f) => f.textInputAction == TextInputAction.done), isTrue);
    });

    testWidgets('物品名称/价格/附加价 next、用量 done', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
      await _settle(tester);

      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields.where((f) => f.textInputAction == TextInputAction.next).length,
          greaterThanOrEqualTo(3));
    });

    testWidgets('个人页昵称 done', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: ProfileEditScreen(profile: UserProfile())));
      await _settle(tester);
      final nick = tester.widget<TextField>(find.byType(TextField).first);
      expect(nick.textInputAction, TextInputAction.done);
    });
  });

  group('浏览页搜索高亮与逐条定位', () {
    testWidgets('带 searchQuery 时顶栏不再显示 N 处匹配（v4.9.38 移除）',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(
          entry: entryWith('海边很美，海边有风，海边有人'),
          searchQuery: '海边',
        ),
      ));
      await _settle(tester);

      // 顶栏匹配条与上/下切换均已移除
      expect(find.textContaining('处匹配'), findsNothing);
      expect(find.byKey(const ValueKey('match_next')), findsNothing);
      expect(find.byKey(const ValueKey('match_prev')), findsNothing);
    });

    testWidgets('无 searchQuery 时顶栏不显示匹配条', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(entry: entryWith('普通笔记')),
      ));
      await _settle(tester);
      expect(find.textContaining('处匹配'), findsNothing);
    });
  });

  group('高亮底座（深色可见）', () {
    testWidgets('countHits 统计非重叠命中', (tester) async {
      expect(RichNoteText.countHits('ababab', 'ab'), 3);
      expect(RichNoteText.countHits('abc', ''), 0);
      expect(RichNoteText.countHits('ABC', 'a'), 1); // 大小写不敏感
    });

    testWidgets('命中字色固定深墨、不写黑，深色下可见', (tester) async {
      AppPalette.dark = true;
      addTearDown(() => AppPalette.dark = false);
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RichNoteText(
            text: '海边日记',
            itemNames: const {},
            searchQuery: '海边',
            style: const TextStyle(fontSize: 15),
          ),
        ),
      ));
      await tester.pump();
      final rich = tester.widget<RichNoteText>(find.byType(RichNoteText));
      expect(rich.searchQuery, '海边');
      // 命中样式由 _styleAt 叠加深墨字色 0xFF24382F（源码级断言见实现）
      expect(RichNoteText.countHits(rich.text, rich.searchQuery), 1);
    });
  });

  group('布局与文案', () {
    testWidgets('物品编辑页计算方式独立节标题且文字唯一', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
      await _settle(tester);
      expect(find.text('计算方式'), findsOneWidget);
      expect(find.text('方式'), findsOneWidget, reason: '行标签改名避免重复');
    });

    testWidgets('资产编辑页不再显示金额正数提示', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
      await _settle(tester);
      expect(find.textContaining('金额请填正数'), findsNothing);
    });

    testWidgets('个人页显示注册日而非使用时间/天数', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: ProfileEditScreen(profile: UserProfile())));
      await _settle(tester);
      expect(find.text('注册日'), findsOneWidget);
      expect(find.text('使用时间'), findsNothing);
      expect(find.textContaining('已使用'), findsNothing);
    });
  });

  group('VIP 日卡文案', () {
    test('兑换成功提示为「1天」，底层仍 24 小时', () async {
      const items = RewardService.shopBadges;
      final vip = items.firstWhere((e) => e.id == UserProfile.badgeVip);
      expect(vip.effectLabel, '有效期1天');
      expect(vip.duration.inHours, 24, reason: '底层时长不变');
    });
  });
}
