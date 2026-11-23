import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/countdown_event.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/countdown_edit_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';
import 'package:ayodiray/screens/settings_screen.dart';

/// v4.9.26 回归：
/// 1. 设置页「字体」并入「外观」分组，全页仅一处「字体」；
/// 2. 事件编辑页 事件类型 / 重复规则 / 提醒时间 改为「值 + 右箭头」行，
///    点整行弹底部选择层，选中项打勾并更新值；
/// 3. 物品编辑页 物品状态 / 物品类型 / 计算方式 同样行式化；
/// 4. 既有硬约束不破坏：外观分组无开关（仅反馈震动1个）、事件日期三块 2:2:1。
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
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory('/tmp/v4926_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  Future<void> tall(WidgetTester tester) =>
      tester.binding.setSurfaceSize(const Size(1080, 2400));

  group('设置页：字体并入外观', () {
    testWidgets('「字体」仅一处，外观仍有两个开关', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await _settle(tester);

      expect(find.text('字体'), findsOneWidget,
          reason: '字体分组标题已并入外观，全页只剩功能项一处');
      expect(find.text('外观'), findsOneWidget);
      // v4.9.47：深色模式/跟随系统改为右箭头+抽屉，外观分组已无开关；
      // v5.0.1 新增「隐私锁」开关，现共「震动」+「隐私锁」2 个
      expect(find.byType(Switch), findsNWidgets(2));
    });

    testWidgets('点字体行进入字体选择页', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await _settle(tester);

      await tester.tap(find.text('字体'));
      await tester.pumpAndSettle();
      expect(find.textContaining('字体'), findsWidgets);
    });
  });

  group('事件编辑页：选项行式弹层', () {
    testWidgets('点「到期提醒」行弹底部选择层，选「提前 3 天」后值更新',
        (tester) async {
      await tall(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // 到期提醒为 VIP 专属：先授予 VIP 身份再进入
      final vipProfile = UserProfile(
          ownedBadges: [UserProfile.badgeNormal, UserProfile.badgeVip]);
      File('${dir.path}/user_profile.json')
          .writeAsStringSync(jsonEncode(vipProfile.toJson()));
      await tester.pumpWidget(const MaterialApp(home: CountdownEditScreen()));
      await _settle(tester);
      // 等待编辑页异步读取档案判断 VIP 权限
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.text('到期提醒'), findsOneWidget);
      expect(find.text('当天'), findsOneWidget, reason: '默认当天，作为行内当前值');

      // 全量并行时偶发命中失败：直接找到包住「到期提醒」的 InkWell 触发 onTap，
      // 避开坐标命中。
      final rowInk = tester.widget<InkWell>(
        find.ancestor(
          of: find.text('到期提醒'),
          matching: find.byType(InkWell),
        ),
      );
      rowInk.onTap!();
      await tester.pumpAndSettle();
      // v4.9.46：弹层标题已移除，只保留四个选项
      expect(find.text('选择到期提醒'), findsNothing);
      expect(find.text('提前 3 天'), findsOneWidget);

      await tester.tap(find.text('提前 3 天').last);
      await tester.pumpAndSettle();
      expect(find.text('提前 3 天'), findsOneWidget, reason: '选择后成为行内当前值');
    });

    testWidgets('点「重复规则」行弹层，选「每月」后值更新；日期三块仍在',
        (tester) async {
      await tall(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final e = CountdownEvent(
        id: 'e1',
        icon: '🎂',
        name: '生日',
        target: DateTime(2030, 5, 1, 9, 30),
        type: '纪念日',
      );
      await tester.pumpWidget(
          MaterialApp(home: CountdownEditScreen(event: e)));
      await _settle(tester);

      // 日期三块硬约束仍在
      expect(find.text('2030年5月1日'), findsOneWidget);
      expect(find.text('09:30'), findsOneWidget);
      expect(find.text('倒数'), findsOneWidget);

      expect(find.text('重复规则'), findsOneWidget);
      expect(find.text('不重复'), findsOneWidget, reason: '默认不重复，作为行内当前值');

      await tester.tap(find.text('重复规则'));
      await tester.pumpAndSettle();
      expect(find.text('选择重复规则'), findsNothing,
          reason: 'v4.9.46 抽屉标题已移除');
      await tester.tap(find.text('每月').last);
      await tester.pumpAndSettle();
      expect(find.text('每月'), findsOneWidget);
    });
  });

  group('物品编辑页：选项行式弹层', () {
    testWidgets('状态 / 类型 / 计算方式 都是单处标签且可点弹层', (tester) async {
      await tall(tester);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
      await _settle(tester);

      for (final label in ['物品状态', '物品类型', '计算方式']) {
        expect(find.text(label), findsOneWidget, reason: '$label 应恰好一处');
      }
      expect(find.text('已拥有'), findsOneWidget);
      expect(find.text('数码设备'), findsOneWidget, reason: '默认类型作为行内当前值');

      // 状态弹层：切到愿望单
      await tester.tap(find.text('物品状态'));
      await tester.pumpAndSettle();
      expect(find.text('选择物品状态'), findsNothing,
          reason: 'v4.9.46 抽屉标题已移除');
      await tester.tap(find.text('愿望单').last);
      await tester.pumpAndSettle();
      expect(find.text('愿望单'), findsOneWidget);

      // 类型弹层：切到衣物
      await tester.tap(find.text('物品类型'));
      await tester.pumpAndSettle();
      expect(find.text('选择物品类型'), findsNothing,
          reason: 'v4.9.46 抽屉标题已移除');
      await tester.tap(find.text('衣物').last);
      await tester.pumpAndSettle();
      expect(find.text('衣物'), findsOneWidget);
    });
  });
}
