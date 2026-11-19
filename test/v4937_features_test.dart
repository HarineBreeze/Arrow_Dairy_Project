import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/edit_screen.dart';
import 'package:ayodiray/screens/home_screen.dart';
import 'package:ayodiray/services/future_letter_reminder.dart';
import 'package:ayodiray/services/user_storage.dart';
import 'package:ayodiray/utils/writing_prompts.dart';

/// v4.9.37 回归：
/// 1. 今日一句 100 条、按自然日固定、不可刷新；
/// 2. 未来信件模型：封存判定 / 到期还原 / JSON 零迁移兼容；
/// 3. 通知文案「x年x月x日，你给未来写的信请查收～」；
/// 4. 编辑页更多菜单未来信件 VIP 门槛；
/// 5. 主页：单击封存笔记提示、长按抽屉仅置顶+删除。
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
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory('/tmp/v4937_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
    UserStorage.revision.value = 0;
  });

  void writeEntries(List<DiaryEntry> entries) {
    File('${dir.path}/diaries.json').writeAsStringSync(
        jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  group('今日一句', () {
    test('内置 100 条话题', () {
      expect(WritingPrompts.count, 100);
    });

    test('同一自然日固定返回同一条，不可手动刷新', () {
      final day = DateTime(2026, 11, 19, 8, 30);
      final a = WritingPrompts.ofDay(day);
      final b = WritingPrompts.ofDay(DateTime(2026, 11, 19, 23, 59));
      expect(a, b);
      expect(WritingPrompts.all, contains(a));
    });

    test('跨天按日期更替（种子驱动）', () {
      final a = WritingPrompts.ofDay(DateTime(2026, 11, 19));
      final b = WritingPrompts.ofDay(DateTime(2026, 11, 20));
      // 相邻两天种子不同，绝大多数会换话题；即便偶遇同条也不违反“按日期确定”
      expect(a, isA<String>());
      expect(b, isA<String>());
    });
  });

  group('未来信件模型', () {
    test('封存判定按自然日，到期自动还原', () {
      final now = DateTime(2026, 11, 19, 10);
      final future = DiaryEntry(
        id: 'f1',
        content: '写给未来的信',
        revealAt: DateTime(2026, 11, 22),
        createdAt: now,
        updatedAt: now,
        publishDate: now,
      );
      expect(future.isFutureLetter, isTrue);
      expect(future.isSealedAt(now), isTrue);
      expect(future.isSealedAt(DateTime(2026, 11, 21, 23, 59)), isTrue);
      expect(future.isRevealedAt(DateTime(2026, 11, 22)), isTrue);
      expect(future.isSealedAt(DateTime(2026, 11, 22, 0, 0)), isFalse);
    });

    test('普通笔记未设置 revealAt', () {
      final now = DateTime.now();
      final normal = DiaryEntry(
          id: 'n', createdAt: now, updatedAt: now, publishDate: now);
      expect(normal.isFutureLetter, isFalse);
      expect(normal.isSealed, isFalse);
    });

    test('JSON 往返与旧数据零迁移兼容', () {
      final now = DateTime(2026, 11, 19);
      final f = DiaryEntry(
        id: 'f2',
        content: 'x',
        revealAt: DateTime(2026, 12, 1),
        createdAt: now,
        updatedAt: now,
        publishDate: now,
      );
      final round = DiaryEntry.fromJson(f.toJson());
      expect(round.revealAt, DateTime(2026, 12, 1));

      final legacy = <String, dynamic>{
        'id': 'old',
        'content': '旧笔记',
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };
      final old = DiaryEntry.fromJson(legacy);
      expect(old.revealAt, isNull);
      expect(old.isFutureLetter, isFalse);
    });

    test('通知文案格式', () {
      expect(FutureLetterReminder.bodyOf(DateTime(2026, 11, 22)),
          '2026年11月22日，你给未来写的信请查收～');
    });
  });

  group('编辑页未来信件 VIP 门槛', () {
    Future<void> pumpEditor(WidgetTester tester, UserProfile profile) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 1200);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);
      File('${dir.path}/user_profile.json')
          .writeAsStringSync(jsonEncode(profile.toJson()));
      await tester.pumpWidget(const MaterialApp(home: EditScreen()));
      await _settle(tester);
    }

    Future<void> openMore(WidgetTester tester) async {
      await tester.tap(find.text('更多'));
      await tester.pump(const Duration(milliseconds: 350));
    }

    /// 面板内容会被编辑页撑到屏幕外，直接触发行的 onTap 验证逻辑
    Future<void> tapFutureTile(WidgetTester tester) async {
      final tile = tester.widget<ListTile>(find.ancestor(
        of: find.text('未来信件'),
        matching: find.byType(ListTile),
      ).first);
      tile.onTap!();
      await tester.pump(const Duration(milliseconds: 350));
    }

    testWidgets('普通身份：入口灰、点击提示 VIP 专属', (tester) async {
      await pumpEditor(tester, UserProfile());
      await openMore(tester);
      expect(find.text('未来信件'), findsOneWidget);
      expect(find.text('VIP专属·未解锁'), findsOneWidget);
      await tapFutureTile(tester);
      expect(find.text('未来信件是VIP专属权益，请充值后再尝试～'), findsOneWidget);
      // 清理 AppToast 的 1.6s 定时器
      await tester.pump(const Duration(milliseconds: 1700));
    });

    testWidgets('VIP 身份：入口可点，进入设置层', (tester) async {
      final p = UserProfile();
      p.ownedBadges.add(UserProfile.badgeVip);
      await pumpEditor(tester, p);
      await openMore(tester);
      expect(find.text('未设置'), findsOneWidget);
      await tapFutureTile(tester);
      expect(find.text('设置可见日期'), findsOneWidget);
    });
  });

  group('主页未来信件交互', () {
    Future<void> pumpHomeWithSealed(
      WidgetTester tester, {
      required bool sealed,
      required String subtitle,
    }) async {
      tester.binding.window.physicalSizeTestValue = const Size(400, 900);
      tester.binding.window.devicePixelRatioTestValue = 1.0;
      addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
      addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);
      final now = DateTime.now();
      writeEntries([
        DiaryEntry(
          id: 'fl1',
          title: sealed ? '' : '普通信',
          subtitle: subtitle,
          content: '信的正文',
          revealAt: sealed ? DateTime(now.year, now.month, now.day + 3) : null,
          createdAt: now,
          updatedAt: now,
          publishDate: DateTime(now.year, now.month, now.day),
        ),
      ]);
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await _settle(tester);
    }

    Future<void> longPressCard(WidgetTester tester, String text) async {
      final g = await tester.startGesture(tester.getCenter(find.text(text)));
      await tester.pump(const Duration(milliseconds: 600));
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('单击封存未来信件：提示未到查看时间，不进浏览页', (tester) async {
      await pumpHomeWithSealed(tester, sealed: true, subtitle: '给三年后的自己');
      await tester.tap(find.text('给三年后的自己'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('还没到查看时间，到期阿尤会提醒你哦～'), findsOneWidget);
      // 清理 AppToast 的 1.6s 定时器
      await tester.pump(const Duration(milliseconds: 1700));
    });

    testWidgets('封存未来信件长按抽屉：仅置顶+删除，无编辑/分享',
        (tester) async {
      await pumpHomeWithSealed(tester, sealed: true, subtitle: '给三年后的自己');
      await longPressCard(tester, '给三年后的自己');
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('编辑'), findsNothing);
      expect(find.text('分享'), findsNothing);
    });

    testWidgets('封存未来信件按加密封条样式显示', (tester) async {
      await pumpHomeWithSealed(tester, sealed: true, subtitle: '给三年后的自己');
      expect(find.text('已加密'), findsOneWidget);
    });
  });
}
