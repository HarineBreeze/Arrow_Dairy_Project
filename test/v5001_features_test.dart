import 'dart:io';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/services/app_lock_storage.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/note_stats.dart';
import 'package:ayodiray/widgets/pattern_lock_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// v5.0.1 行为回归：
/// 1. 笔记主页数据栏统计：总篇数 / 总字数 / 连续记录 / 最长记录；
/// 2. 隐私锁：AppLockStorage 存取、密码/手势校验、密保、关闭；
/// 3. 九宫格手势序列工具；
/// 4. 设置页「隐私」分组开关存在；
/// 5. 版本号 V5.0.1。

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

DiaryEntry _entry(String content, DateTime date, {String id = 'x'}) => DiaryEntry(
      id: id,
      content: content,
      createdAt: date,
      updatedAt: date,
      publishDate: date,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() => AppSettings.persistOverride = () async {});
  tearDownAll(() => AppSettings.persistOverride = null);

  setUp(() async {
    dir = Directory('/tmp/v5001_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
  });

  tearDown(() {
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('笔记数据栏统计 NoteStats', () {
    final now = DateTime(2026, 11, 23, 12);

    test('总篇数与总字数按全部笔记统计', () {
      final stats = NoteStats.compute([
        _entry('abcd', DateTime(2026, 11, 23), id: '1'),
        _entry('你好世界!', DateTime(2026, 11, 22), id: '2'),
      ], now: now);
      expect(stats.totalCount, 2);
      // 'abcd'=4 + '你好世界!'=5
      expect(stats.totalChars, 9);
    });

    test('空列表全 0', () {
      final stats = NoteStats.compute([], now: now);
      expect(stats.totalCount, 0);
      expect(stats.totalChars, 0);
      expect(stats.streak, 0);
      expect(stats.longest, 0);
      expect(stats.isCurrent, false);
    });

    test('今天有记录 → 连续记录，天数从今天往前数', () {
      final stats = NoteStats.compute([
        _entry('a', DateTime(2026, 11, 23), id: '1'),
        _entry('a', DateTime(2026, 11, 22), id: '2'),
        _entry('a', DateTime(2026, 11, 21), id: '3'),
      ], now: now);
      expect(stats.isCurrent, true);
      expect(stats.streak, 3);
      expect(stats.streakLabel, '连续记录');
      expect(stats.streakValue, '3天');
    });

    test('今天没写但昨天有 → 仍算连续（今天尚未结束）', () {
      final stats = NoteStats.compute([
        _entry('a', DateTime(2026, 11, 22), id: '1'),
        _entry('a', DateTime(2026, 11, 21), id: '2'),
      ], now: now);
      expect(stats.isCurrent, true);
      expect(stats.streak, 2);
    });

    test('今天昨天都没写 → 断更，显示最长记录', () {
      final stats = NoteStats.compute([
        _entry('a', DateTime(2026, 11, 20), id: '1'),
        _entry('a', DateTime(2026, 11, 19), id: '2'),
        _entry('a', DateTime(2026, 11, 18), id: '3'),
        _entry('a', DateTime(2026, 11, 10), id: '4'),
      ], now: now);
      expect(stats.isCurrent, false);
      expect(stats.streak, 0);
      expect(stats.longest, 3);
      expect(stats.streakLabel, '最长记录');
      expect(stats.streakValue, '3天');
    });

    test('同一天多篇只算一天连续', () {
      final stats = NoteStats.compute([
        _entry('a', DateTime(2026, 11, 23, 8), id: '1'),
        _entry('a', DateTime(2026, 11, 23, 20), id: '2'),
        _entry('a', DateTime(2026, 11, 22), id: '3'),
      ], now: now);
      expect(stats.isCurrent, true);
      expect(stats.streak, 2);
    });

    test('最长连续取历史最大段（含断更后的新段）', () {
      final stats = NoteStats.compute([
        _entry('a', DateTime(2026, 11, 23), id: '1'),
        _entry('a', DateTime(2026, 11, 15), id: '2'),
        _entry('a', DateTime(2026, 11, 14), id: '3'),
        _entry('a', DateTime(2026, 11, 13), id: '4'),
        _entry('a', DateTime(2026, 11, 12), id: '5'),
      ], now: now);
      expect(stats.isCurrent, true);
      expect(stats.streak, 1); // 当前只连续今天
      expect(stats.longest, 4); // 历史最长 12~15
    });
  });

  group('九宫格手势工具', () {
    test('patternToString 逗号连接', () {
      expect(patternToString([0, 1, 2, 5, 8]), '0,1,2,5,8');
    });
    test('至少 4 个点才有效', () {
      expect(isValidPattern([0, 1, 2]), false);
      expect(isValidPattern([0, 1, 2, 5]), true);
    });
  });

  group('AppLockStorage 隐私锁存储', () {
    test('初始未开启', () async {
      expect(await AppLockStorage.hasLock(), false);
    });

    test('保存密码锁后可校验密码与密保，类型正确', () async {
      await AppLockStorage.saveLock(
        type: AppLockType.password,
        pin: '1234',
        question: '你的生日？',
        answer: '0101',
      );
      expect(await AppLockStorage.hasLock(), true);
      expect(await AppLockStorage.loadType(), AppLockType.password);
      expect(await AppLockStorage.verifyPin('1234'), true);
      expect(await AppLockStorage.verifyPin('0000'), false);
      expect(await AppLockStorage.verifyAnswer(' 0101 '), true);
      expect(await AppLockStorage.verifyAnswer('9999'), false);
      expect(await AppLockStorage.getQuestion(), '你的生日？');
    });

    test('保存手势锁后可校验手势、不可再用密码', () async {
      await AppLockStorage.saveLock(
        type: AppLockType.gesture,
        pattern: '0,1,2,5,8',
        question: '宠物名？',
        answer: '旺财',
      );
      expect(await AppLockStorage.loadType(), AppLockType.gesture);
      expect(
          await AppLockStorage.verifyPattern('0,1,2,5,8'), true);
      expect(await AppLockStorage.verifyPattern('0,1,2'), false);
      expect(await AppLockStorage.verifyPin('0,1,2,5,8'), false);
    });

    test('重设密码后新密码生效、旧密码失效', () async {
      await AppLockStorage.saveLock(
        type: AppLockType.password,
        pin: '1234',
        question: 'q',
        answer: 'a',
      );
      await AppLockStorage.reset(type: AppLockType.password, pin: '8888');
      expect(await AppLockStorage.verifyPin('8888'), true);
      expect(await AppLockStorage.verifyPin('1234'), false);
    });

    test('关闭后锁文件删除', () async {
      await AppLockStorage.saveLock(
        type: AppLockType.password,
        pin: '1234',
        question: 'q',
        answer: 'a',
      );
      expect(await AppLockStorage.hasLock(), true);
      await AppLockStorage.clearLock();
      expect(await AppLockStorage.hasLock(), false);
    });
  });

  group('设置页隐私锁入口', () {
    testWidgets('「隐私」分组含隐私锁开关', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(lockStateOverride: false),
      ));
      await tester.pumpAndSettle();
      expect(find.text('隐私'), findsOneWidget);
      expect(find.text('隐私锁'), findsOneWidget);
      expect(find.byKey(const ValueKey('privacy_lock_switch')),
          findsOneWidget);
    });
  });
}
