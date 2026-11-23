import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/countdown_edit_screen.dart';
import 'package:ayodiray/screens/trash_screen.dart';
import 'package:ayodiray/services/app_settings.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_toast.dart';
import 'package:ayodiray/utils/app_version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// v5.0.0 行为回归：
/// 1. 非 VIP 点击「到期提醒」提示语不再丢失（含 VIP 期间已设过提醒的情况）；
/// 2. 回收站底部提示语改为「超过时间的内容将彻底删除」；
/// 3. 新增紫色系主题「霞紫」（VIP）：全套浅色/深色配套色齐备、重映射生效；
/// 4. 笔记编辑页「更多」按钮文字与「地点」同款加粗。

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
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() => AppSettings.persistOverride = () async {});
  tearDownAll(() => AppSettings.persistOverride = null);

  setUp(() async {
    dir = Directory('/tmp/v5000_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
  });

  tearDown(() {
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.byId('bamboo');
  });

  group('版本号', () {
    test('展示版本推进到 V5.0.1', () {
      expect(AppVersion.displayVersion, 'V5.0.1');
    });
  });

  group('非 VIP 到期提醒提示语', () {
    test('wasSet 分支不再直接 return，统一弹 VIP 提示（源码断言）', () {
      final src = File('lib/screens/countdown_edit_screen.dart').readAsStringSync();
      // 提示语文案仍在
      expect(src.contains('到期提醒是VIP专属权益，请充值后再尝试～'), isTrue);
      // 旧的「已设提醒禁用修改且不弹提示」直接 return 分支应已移除
      expect(src.contains('禁用修改且不弹提示'), isFalse);
      // wasSet 仍用于 value 显示（保持不变），但不作为 return 条件
      expect(src.contains('final wasSet = _initialRemindDays > 0;'), isTrue);
    });

    testWidgets('非 VIP 身份下点击到期提醒弹出 VIP 提示（widget）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // 普通身份（无 VIP 权益）
      final normal = UserProfile(
          ownedBadges: [UserProfile.badgeNormal]);
      File('${dir.path}/user_profile.json')
          .writeAsStringSync(jsonEncode(normal.toJson()));

      await tester.pumpWidget(const MaterialApp(home: CountdownEditScreen()));
      await _settle(tester);

      // 找到「到期提醒」所在行并点击
      final row = find.ancestor(
        of: find.text('到期提醒'),
        matching: find.byType(InkWell),
      );
      expect(row, findsWidgets);
      await tester.tap(row.first);
      await tester.pump();
      expect(find.text('到期提醒是VIP专属权益，请充值后再尝试～'), findsOneWidget);
      // 清理 AppToast 的自动收起 Timer，避免测试结束时 pending
      AppToast.resetForTest();
      await tester.pump(const Duration(milliseconds: 1700));
    });
  });

  group('回收站底部提示语文案', () {
    testWidgets('提示语为「超过时间的内容将彻底删除」', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrashScreen(onOpenMenu: () {})),
      ));
      await _settle(tester);
      expect(find.text('超过时间的内容将彻底删除'), findsOneWidget);
      expect(find.text('超过7天的内容将彻底删除'), findsNothing);
    });
  });

  group('霞紫主题', () {
    test('注册表中霞紫为 VIP，id=violet，全套色值齐备', () {
      final v = AccentCatalog.byId('violet');
      expect(v.name, '霞紫');
      expect(v.vip, true);
      for (final value in [
        v.rgb, v.tintRgb, v.pageRgb, v.darkTop, v.darkTint, v.darkPage,
        v.darkSurface, v.darkTintBg,
      ]) {
        expect(value & 0xFFFFFF != 0, true, reason: '霞紫配套色非空');
      }
      expect(AccentCatalog.isVip('violet'), true);
    });

    test('浅色下霞紫主色/浅底纹/页面底随主题重映射', () {
      AppPalette.dark = false;
      final v = AccentCatalog.byId('violet');
      AppPalette.accent = v;
      expect(AppPalette.c(0xFF3E8E6D).value, 0xFF000000 | v.rgb);
      expect(AppPalette.c(0xFFE4F2EB).value, 0xFF000000 | v.tintRgb);
      expect(AppPalette.c(0xFFF5FAF7).value, 0xFF000000 | v.pageRgb);
    });

    test('深色下霞紫顶栏/页面底/卡片底/底纹随主题重映射', () {
      AppPalette.dark = true;
      final v = AccentCatalog.byId('violet');
      AppPalette.accent = v;
      expect(AppPalette.topBar.value, 0xFF000000 | v.darkTop);
      expect(AppPalette.c(0xFF3E8E6D).value, 0xFF000000 | v.rgb);
      expect(AppPalette.c(0xFFFFFFFF).value, 0xFF000000 | v.darkSurface);
      expect(AppPalette.c(0xFFF5FAF7).value, 0xFF000000 | v.darkPage);
      expect(AppPalette.c(0xFFE4F2EB).value, 0xFF000000 | v.darkTintBg);
    });
  });

  group('笔记编辑页更多按钮加粗', () {
    test('「更多」文字加粗与「地点」同款（源码断言）', () {
      final src = File('lib/screens/edit_screen.dart').readAsStringSync();
      // 「更多」按钮 Text 带 w600
      final moreIdx = src.indexOf("'更多'");
      expect(moreIdx, greaterThan(-1));
      final moreBlock = src.substring(moreIdx, moreIdx + 260);
      expect(moreBlock.contains('fontWeight: FontWeight.w600'), isTrue);
      // 「地点/日期」按钮 _buildInfoCell 也用 w600
      expect(src.contains('fontWeight: FontWeight.w600'), isTrue);
    });
  });
}
