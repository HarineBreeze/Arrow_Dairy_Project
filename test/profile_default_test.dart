import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/profile_edit_screen.dart';
import 'package:ayodiray/services/user_storage.dart';
import 'package:ayodiray/widgets/avatar.dart';

/// 默认头像 / 默认昵称 / 昵称上限的回归测试。

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

void main() {
  // 每条用例使用独立的临时目录，避免读到彼此的档案文件
  setUp(() {
    final dir = Directory(
        '/tmp/profile_default_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  testWidgets('未设置头像：显示内置默认头像图（书本+爱心书签）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final profile = UserProfile(avatarPath: '');
    expect(profile.avatarPath, '');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: buildAppAvatar(profile))),
    ));
    await tester.pumpAndSettle();

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    expect(avatar.backgroundImage, isA<AssetImage>(),
        reason: '默认头像应使用内置资源图，而不是蓝底文字');
    expect(
        (avatar.backgroundImage as AssetImage).assetName, kDefaultAvatarAsset);
  });

  test('新用户默认昵称为 AyoDiray', () {
    expect(UserProfile().nickname, 'AyoDiray');
    expect(UserProfile.fromJson({}).nickname, 'AyoDiray');
    // 旧数据里昵称为空的，也落到默认昵称
    expect(UserProfile.fromJson({'nickname': ''}).nickname, 'AyoDiray');
    // 设置过的昵称保持不变
    expect(UserProfile.fromJson({'nickname': '小明'}).nickname, '小明');
  });

  testWidgets('昵称输入框：上限 10 个字，计数器显示 /10', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: ProfileEditScreen(profile: UserProfile()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('8/10'), findsOneWidget,
        reason: '默认昵称 AyoDiray 为 8 个字符');

    await tester.enterText(find.byType(TextField).first, '一二三四五六七八九十');
    await tester.pump();
    expect(find.text('10/10'), findsOneWidget);

    // 第 11 个字应被 maxLength 拦下
    await tester.enterText(find.byType(TextField).first, '一二三四五六七八九十十一');
    await tester.pump();
    expect(find.text('10/10'), findsOneWidget);
    expect(find.text('11/10'), findsNothing);
  });

  testWidgets('清空昵称后保存：档案落盘为默认昵称', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final seed = UserProfile(nickname: '旧名字');
    // widget 测试跑在 FakeAsync 区，真实文件 I/O 必须包进 runAsync
    await tester.runAsync(() => UserStorage.save(seed));

    await tester.pumpWidget(MaterialApp(home: ProfileEditScreen(profile: seed)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    await tester.tap(find.text('完成'));
    // 页面内部会 await UserStorage.save（真实 I/O）：交替 runAsync 与 pump，
    // 让假区里挂起的 I/O future 有机会完成，同时推进保存动画
    for (var i = 0; i < 12; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(() => UserStorage.load());
    expect(saved?.nickname, 'AyoDiray');
  });

  testWidgets('性别收拢到右箭头：页面只显示当前值，点开弹层含男/女/无', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: ProfileEditScreen(profile: UserProfile(gender: 'male')),
    ));
    await tester.pump();

    // 默认页只展示当前值「男」，三个胶囊选项已移除
    expect(find.text('男'), findsOneWidget);
    expect(find.text('女'), findsNothing);
    expect(find.byKey(const ValueKey('profile-gender-row')), findsOneWidget);

    // 昵称 / 性别 / ID / 使用时间在同一张白色圆角卡内
    for (final label in ['昵称', '性别', 'ID', '使用时间']) {
      final containers = tester
          .widgetList<Container>(
              find.ancestor(of: find.text(label), matching: find.byType(Container)))
          .toList();
      final hasWhiteCard = containers.any((c) {
        final d = c.decoration;
        return d is BoxDecoration &&
            d.color == Colors.white &&
            d.borderRadius == BorderRadius.circular(16);
      });
      expect(hasWhiteCard, isTrue, reason: '「$label」应在白色圆角卡片内');
    }

    // 点性别行 → 弹出选项（含「无」），当前项「男」打勾
    await tester.tap(find.byKey(const ValueKey('profile-gender-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('选择性别'), findsOneWidget);
    expect(find.byKey(const ValueKey('gender_option_male')), findsOneWidget);
    expect(find.byKey(const ValueKey('gender_option_female')), findsOneWidget);
    expect(find.byKey(const ValueKey('gender_option_none')), findsOneWidget);
    expect(find.text('无'), findsOneWidget, reason: '弹层里仍有「无」选项');
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('ID 淡灰只读、使用时间显示天数', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final profile = UserProfile();
    await tester.pumpWidget(
        MaterialApp(home: ProfileEditScreen(profile: profile)));
    await tester.pump();

    expect(find.text('ID'), findsOneWidget);
    expect(find.text(profile.userId), findsOneWidget);
    final idText = tester.widget<Text>(find.text(profile.userId));
    expect(idText.style?.color, const Color(0xFF8FA09A),
        reason: 'ID 字色为淡灰');
    // 不可编辑：整页只有昵称一个输入框
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('已使用 '), findsOneWidget);
    expect(find.text('已使用 ${profile.usedDays} 天'), findsOneWidget);
  });

  testWidgets('点用户ID 复制的是档案里的 ID', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final profile = UserProfile();
    String? copied;
    await tester.pumpWidget(MaterialApp(
      home: ProfileEditScreen(
        profile: profile,
        clipboardOverride: (text) async => copied = text,
      ),
    ));
    await tester.pump();

    expect(find.byKey(const ValueKey('profile-user-id-row')), findsOneWidget);
    expect(find.text(profile.userId), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-user-id-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(copied, profile.userId, reason: '点击应把用户ID写入剪贴板');
    expect(find.text('已复制用户ID'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('性别弹层选「无」后保存，性别落为空字符串', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: ProfileEditScreen(profile: UserProfile(gender: 'male')),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('profile-gender-row')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('gender_option_none')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('选择性别'), findsNothing, reason: '选完弹层应关闭');

    await tester.tap(find.text('完成'));
    for (var i = 0; i < 12; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(() => UserStorage.load());
    expect(saved?.gender, '');
  });
}
