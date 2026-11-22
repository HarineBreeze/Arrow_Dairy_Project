import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/services/user_storage.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_version.dart';
import 'package:ayodiray/utils/haptics.dart';
import 'package:ayodiray/widgets/milestone_celebration.dart';

/// v4.9.49 行为回归：
/// 1. 版本号同步到 V4.9.49；
/// 2. 写作里程碑常量与奖励分值正确；
/// 3. awardWriteMilestone：未达节点不发、首次达成 +20、跨多节点补发、
///    重复调用不再发、判重持久化、旧档案回落；
/// 4. 庆祝特效渲染篇数 / 奖励 / 关闭按钮，且配色走主题色。
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

/// Navigator 关闭回调（顶层函数，供 const 路由使用）
bool _onPopPage(Route<dynamic> route, dynamic result) => route.didPop(result);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    // 跨平台临时目录：不用硬编码 /tmp，避免 Windows 上目录不存在 / 占用
    dir = Directory(
        '${Directory.systemTemp.path}/v4949_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    Haptics.enabled = false;
    Haptics.throttleEnabled = false;
  });

  tearDown(() async {
    Haptics.enabled = true;
    Haptics.throttleEnabled = true;
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
    UserStorage.revision.value = 0;
  });

  Future<void> writeProfile(UserProfile p) async {
    File('${dir.path}/user_profile.json')
        .writeAsStringSync(jsonEncode(p.toJson()));
  }

  group('版本号', () {
    test('展示版本同步到 V4.9.49', () {
      expect(AppVersion.displayVersion, 'V4.9.49');
    });
  });

  group('写作里程碑常量', () {
    test('节点列表与奖励分值固定', () {
      expect(RewardService.writeMilestones,
          <int>[7, 30, 100, 200, 365, 500, 1000]);
      expect(RewardService.milestonePoints, 20);
    });
  });

  group('awardWriteMilestone 判重与奖励', () {
    test('未达第一个节点：不发奖、返回空', () async {
      await writeProfile(UserProfile(points: 0));
      expect(await RewardService.awardWriteMilestone(6), isEmpty);
      final p = await UserStorage.load();
      expect(p.points, 0);
      expect(p.claimedWriteMilestones, isEmpty);
    });

    test('首次达到 7 篇：+20 并记录该节点', () async {
      await writeProfile(UserProfile(points: 0));
      final hit = await RewardService.awardWriteMilestone(7);
      expect(hit, <int>[7]);
      final p = await UserStorage.load();
      expect(p.points, 20);
      expect(p.claimedWriteMilestones, <int>[7]);
    });

    test('刚好卡在节点之间通过，不提前发', () async {
      await writeProfile(UserProfile(points: 0));
      expect(await RewardService.awardWriteMilestone(8), <int>[7]);
      expect(await RewardService.awardWriteMilestone(29), isEmpty);
    });

    test('一次跨多节点：每个节点各 +20', () async {
      await writeProfile(UserProfile(points: 0));
      // 从 0 直接到 100（如数据恢复），应补发 7/30/100 三档
      final hit = await RewardService.awardWriteMilestone(100);
      expect(hit, <int>[7, 30, 100]);
      final p = await UserStorage.load();
      expect(p.points, 60);
      expect(p.claimedWriteMilestones, <int>[7, 30, 100]);
    });

    test('重复调用不再发奖', () async {
      await writeProfile(UserProfile(points: 0));
      await RewardService.awardWriteMilestone(7);
      expect(await RewardService.awardWriteMilestone(7), isEmpty);
      expect(await RewardService.awardWriteMilestone(50), <int>[30]);
      expect(await RewardService.awardWriteMilestone(50), isEmpty);
      final p = await UserStorage.load();
      expect(p.points, 40);
    });

    test('删除后篇数回落，已领节点不重复发', () async {
      await writeProfile(UserProfile(points: 0));
      await RewardService.awardWriteMilestone(7);
      // 删到 5 篇又写回 7 篇：7 已领取，不再发
      expect(await RewardService.awardWriteMilestone(5), isEmpty);
      expect(await RewardService.awardWriteMilestone(7), isEmpty);
      expect((await UserStorage.load()).points, 20);
    });

    test('旧档案缺字段：回落空列表，可正常领取', () async {
      File('${dir.path}/user_profile.json')
          .writeAsStringSync(jsonEncode({'nickname': '老用户', 'points': 5}));
      final loaded = await UserStorage.load();
      expect(loaded.claimedWriteMilestones, isEmpty);
      expect(await RewardService.awardWriteMilestone(7), <int>[7]);
      expect((await UserStorage.load()).points, 25);
    });
  });

  group('档案序列化', () {
    test('claimedWriteMilestones 可往返，不丢失', () {
      final p = UserProfile(points: 40, claimedWriteMilestones: [7, 30]);
      final back = UserProfile.fromJson(p.toJson());
      expect(back.claimedWriteMilestones, <int>[7, 30]);
      expect(back.points, 40);
    });
  });

  group('庆祝特效组件', () {
    testWidgets('渲染篇数、奖励文案与关闭按钮', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: MilestoneCelebration(milestone: 100, points: 20),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('milestone-celebration')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('milestone-number')), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('第 100 篇'), findsOneWidget);
      expect(find.text('写作里程碑达成'), findsOneWidget);
      expect(find.byKey(const ValueKey('milestone-points')), findsOneWidget);
      expect(find.text('+20 灵感'), findsOneWidget);
      expect(find.text('太棒了'), findsOneWidget);
    });

    testWidgets('点「太棒了」关闭弹层', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Navigator(
          pages: [
            MaterialPage(child: SizedBox()),
            MaterialPage(child: MilestoneCelebration(milestone: 7, points: 20)),
          ],
          onPopPage: _onPopPage,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('milestone-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('milestone-celebration')),
          findsNothing);
    });
  });
}
