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
}
