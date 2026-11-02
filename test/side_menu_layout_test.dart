import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/models/user_profile.dart';
import 'package:diary_app/screens/side_menu.dart';
import 'package:diary_app/widgets/app_icons.dart';
import 'package:diary_app/widgets/avatar.dart';

/// 侧边栏头部排版（左右）与细线图标接入的回归测试。
void main() {
  Widget host(UserProfile profile, {String tab = 'diary'}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 800,
          child: SideMenu(
            profile: profile,
            currentTab: tab,
            onClose: () {},
            onOpenProfile: () {},
            onOpenDiary: () {},
            onOpenItems: () {},
            onOpenAssets: () {},
            onOpenCountdown: () {},
            onOpenSettings: () {},
            onOpenGlobalSearch: () {},
            onOpenTrash: () {},
          ),
        ),
      ),
    );
  }

  setUp(() {});

  testWidgets('头像在左、昵称与 ID 在右（横向位置对比）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host(UserProfile(nickname: '小明')));
    await tester.pump();

    final avatarRect = tester.getRect(find.byType(CircleAvatar).first);
    final nickRect = tester.getRect(find.text('小明'));
    final idRect = tester.getRect(find.text('ID：10001'));

    // 昵称整体位于头像右边缘右侧
    expect(nickRect.left, greaterThan(avatarRect.right),
        reason: '昵称应在头像右侧，而不是下方');
    // ID 也在头像右侧
    expect(idRect.left, greaterThan(avatarRect.right));
    // ID 在昵称下方
    expect(idRect.top, greaterThan(nickRect.bottom - 2));
    // 头像垂直居中于整个头部：头像中心 y 落在文字块上下范围内
    final textBlockCenterY = (nickRect.top + idRect.bottom) / 2;
    expect(avatarRect.center.dy, closeTo(textBlockCenterY, 8),
        reason: '头像应与文字块垂直居中对齐');
  });

  testWidgets('昵称过长时省略显示，不挤出侧栏', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host(UserProfile(nickname: '一二三四五六七八九十')));
    await tester.pump();

    final nick = tester.widget<Text>(find.text('一二三四五六七八九十'));
    expect(nick.overflow, TextOverflow.ellipsis);
    expect(nick.maxLines, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('六个导航项 + 设置项都使用细线图标（AppIcon）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host(UserProfile(nickname: '小明')));
    await tester.pump();

    for (final label in ['全局搜索', '写日记', '物品清单', '重要事件', '资产全景', '回收站', '设置']) {
      expect(find.text(label), findsOneWidget, reason: '缺少导航项 $label');
    }

    // 6 个导航 + settings + chevR = 8 个
    expect(find.byType(AppIcon), findsNWidgets(8));
    // 侧栏内不应再残留 Material 图标
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('全部图标路径都能被解析器接受（不抛异常）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final tab in ['search', 'diary', 'items', 'countdown', 'assets', 'trash']) {
      await tester.pumpWidget(host(UserProfile(nickname: '小明'), tab: tab));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'tab=$tab 渲染异常');
    }
  });
}
