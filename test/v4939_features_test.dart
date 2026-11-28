import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/asset_edit_screen.dart';
import 'package:ayodiray/screens/edit_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';
import 'package:ayodiray/screens/note_view_screen.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/services/trash_storage.dart';
import 'package:ayodiray/services/user_storage.dart';

/// v4.9.39 回归：
/// 1. 置顶数量上限（免费3，VIP不限）+ 提示语；
/// 2. 权益身份删除入回收站保留30天，普通7天；
/// 3. 未来信件进回收站显示「未来信件」；
/// 4. 资产编辑页取消+完成双按钮；
/// 5. 物品附加价格提示语、资产「输入数额」；
/// 6. 搜索进入浏览页移除「N处匹配」。
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
    dir = Directory('/tmp/v4939_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
    UserStorage.revision.value = 0;
    EditScreen.lastSavedId = null;
  });

  void writeProfile(UserProfile p) {
    File('${dir.path}/user_profile.json')
        .writeAsStringSync(jsonEncode(p.toJson()));
  }

  group('置顶数量上限', () {
    test('免费用户：0/2 未达上限，3 达到上限', () {
      final p = UserProfile();
      expect(RewardService.pinLimitReached(0, p), isFalse);
      expect(RewardService.pinLimitReached(2, p), isFalse);
      expect(RewardService.pinLimitReached(3, p), isTrue);
      expect(RewardService.pinLimitReached(5, p), isTrue);
    });

    test('VIP 类身份不限数量', () {
      for (final badge in [
        UserProfile.badgeBeta,
        UserProfile.badgeVip,
        UserProfile.badgeVipForever,
      ]) {
        final p = UserProfile();
        p.ownedBadges.add(badge);
        expect(RewardService.pinLimitReached(10, p), isFalse, reason: badge);
      }
    });

    test('提示语文案', () {
      expect(RewardService.pinLimitMessage('篇笔记'),
          '非VIP用户最多置顶3篇笔记哦～');
      expect(RewardService.pinLimitMessage('件事'),
          '非VIP用户最多置顶3件事哦～');
    });
  });

  group('回收站保留期与未来信件标题', () {
    test('免费用户删除 → 保留 7 天', () async {
      writeProfile(UserProfile());
      final now = DateTime.now();
      await TrashStorage.addDiary(DiaryEntry(
        id: 'n1',
        title: '普通笔记',
        createdAt: now,
        updatedAt: now,
        publishDate: now,
      ));
      final list = await TrashStorage.load();
      expect(list.first.keepDays, 7);
      expect(list.first.daysLeft, 7);
    });

    test('VIP 用户删除 → 保留 30 天', () async {
      final p = UserProfile();
      p.ownedBadges.add(UserProfile.badgeVip);
      writeProfile(p);
      final now = DateTime.now();
      await TrashStorage.addDiary(DiaryEntry(
        id: 'n2',
        title: 'VIP 的笔记',
        createdAt: now,
        updatedAt: now,
        publishDate: now,
      ));
      final list = await TrashStorage.load();
      expect(list.first.keepDays, 30);
      expect(list.first.daysLeft, 30);
    });

    test('未来信件进回收站不显示真实标题', () async {
      writeProfile(UserProfile());
      final now = DateTime.now();
      await TrashStorage.addDiary(DiaryEntry(
        id: 'fl1',
        title: '绝密的真实标题',
        revealAt: now.add(const Duration(days: 3)),
        createdAt: now,
        updatedAt: now,
        publishDate: now,
      ));
      final list = await TrashStorage.load();
      expect(list.first.title, '未来信件');
      expect(list.first.title, isNot('绝密的真实标题'));
    });

    test('旧记录缺 keepDays → 回落 7 天', () {
      final now = DateTime.now();
      final e = TrashEntry.fromJson({
        'id': 'old',
        'kind': 'diary',
        'data': {},
        'deletedAt': now.toIso8601String(),
        'title': '旧',
        'subtitle': '',
      });
      expect(e.keepDays, 7);
    });
  });

  group('编辑页文案与按钮', () {
    testWidgets('资产编辑页：取消 + 完成双按钮', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
      await _settle(tester);
      expect(find.text('取消'), findsWidgets);
      expect(find.text('完成'), findsOneWidget);
    });

    testWidgets('资产编辑页：金额提示为 v5.0.23 的「输入金额」', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
      await _settle(tester);
      expect(find.text('输入金额'), findsOneWidget);
    });

    testWidgets('物品编辑页：v5.0.23 附加价格提示为「如卖出/折扣（选填）」', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
      await _settle(tester);
      expect(find.text('如卖出/折扣（选填）'), findsOneWidget);
      expect(find.text('输入附加价格，如卖出/折扣（选填）'), findsNothing);
      expect(find.text('¥ 可为负数（选填）'), findsNothing);
    });

    testWidgets('搜索进入浏览页：顶栏不再显示 N 处匹配', (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(
          entry: DiaryEntry(
            id: 's1',
            content: '海边很美，海边有风',
            createdAt: now,
            updatedAt: now,
            publishDate: now,
          ),
          searchQuery: '海边',
        ),
      ));
      await _settle(tester);
      expect(find.textContaining('处匹配'), findsNothing);
    });
  });
}
