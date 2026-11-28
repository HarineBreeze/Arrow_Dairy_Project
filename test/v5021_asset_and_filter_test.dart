import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/asset.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/asset_edit_screen.dart';
import 'package:ayodiray/services/asset_repay_reminder.dart';
import 'package:ayodiray/theme/app_palette.dart';

void main() {
  final root = Directory.current.path;
  String src(String rel) => File('$root/$rel').readAsStringSync();

  final assetScreenSrc = src('lib/screens/asset_screen.dart');
  final itemListSrc = src('lib/screens/item_list_screen.dart');
  final countdownSrc = src('lib/screens/countdown_screen.dart');
  final assetEditSrc = src('lib/screens/asset_edit_screen.dart');
  final assetModelSrc = src('lib/models/asset.dart');
  final homeSrc = src('lib/screens/home_screen.dart');
  final mainKtSrc = src(
      'android/app/src/main/kotlin/com/Ayo/diary_app/MainActivity.kt');
  final manifestSrc = src('android/app/src/main/AndroidManifest.xml');
  final itemEditSrc = src('lib/screens/item_edit_screen.dart');
  final convertSrc = src('lib/widgets/wishlist_convert_celebration.dart');

  Future<void> settle(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
  }

  group('v5.0.21 ① 三个主页筛选抽屉按钮移到标题栏同行', () {
    test('源码：资产筛选抽屉标题行含取消/确定', () {
      expect(assetScreenSrc, contains("const Text('筛选'"),
          reason: '资产筛选抽屉应有「筛选」标题');
      // 标题行 Row 内含 Spacer + 取消 + 确定（取 _openFilterSheet 到下一个方法之间的片段）
      final start = assetScreenSrc.indexOf('void _openFilterSheet()');
      final end = assetScreenSrc.indexOf('void _openSettings()', start) > start
          ? assetScreenSrc.indexOf('void _openSettings()', start)
          : start + 5000;
      final sheet = assetScreenSrc.substring(start, end > start ? end : start + 5000);
      expect(sheet, contains('const Spacer()'), reason: '标题与按钮同排');
      expect(sheet, contains("const Text('取消')"));
      expect(sheet, contains("Text('确定'"));
    });
    test('源码：物品排序抽屉标题行含完成', () {
      final start = itemListSrc.indexOf('void _showSortSheet()');
      final end = itemListSrc.indexOf('\n  }', start);
      final sheet = itemListSrc.substring(start, end);
      expect(sheet, contains("Text('排序方式'"));
      expect(sheet, contains("Text('完成'"));
      expect(sheet, contains('const Spacer()'), reason: '标题与完成按钮同排');
      expect(sheet, isNot(contains('alignment: Alignment.centerRight')),
          reason: '物品排序抽屉底部完成按钮应移除');
    });
    test('源码：事件筛选抽屉标题行含确定', () {
      final start = countdownSrc.indexOf('void _showFilterSheet()');
      final end = countdownSrc.indexOf('\n  }', start);
      final sheet = countdownSrc.substring(start, end);
      expect(sheet, contains("Text('按事件类型筛选'"));
      expect(sheet, contains("Text('确定'"));
      expect(sheet, contains('const Spacer()'), reason: '标题与确定按钮同排');
      expect(sheet, isNot(contains('alignment: Alignment.centerRight')),
          reason: '事件筛选抽屉底部确定按钮应移除');
    });
  });

  group('v5.0.21 ② 资产所有人选项', () {
    test('模型：owners 含全部 8 个选项且默认本人', () {
      expect(Asset.owners, [
        '本人', '对象', '配偶', '父亲', '母亲', '兄弟', '姐妹', '朋友',
      ]);
      expect(Asset(id: 'x').owner, '本人');
    });
    test('模型：owner 字段可序列化往返', () {
      final a = Asset(id: 'o1', owner: '配偶');
      final b = Asset.fromJson(a.toJson());
      expect(b.owner, '配偶');
    });
    testWidgets('编辑页：资产所有人默认本人，选项型行渲染', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
      await settle(tester);
      expect(find.text('资产所有人'), findsOneWidget);
      expect(find.text('本人'), findsOneWidget);
    });
  });

  group('v5.0.21 ③ 还款时间（权益 + 负资产条件）', () {
    test('模型：repayDate 可序列化往返', () {
      final d = DateTime(2027, 3, 15);
      final a = Asset(id: 'r1', type: '信用卡', repayDate: d);
      expect(Asset.fromJson(a.toJson()).repayDate, d);
    });
    test('提醒：负资产才注册，正文含所有人与类型', () {
      final a = Asset(id: 'r', type: '信用卡', owner: '本人',
          repayDate: DateTime(2027, 3, 15));
      final body = AssetRepayReminder.bodyOf(a);
      expect(body, contains('本人的信用卡'));
      expect(body, contains('2027年3月15日'));
      expect(AssetRepayReminder.bodyOf(Asset(id: 'x')),
          isNot(contains('null')));
    });
    test('源码：正资产提示文案与 VIP 提示口径', () {
      expect(assetEditSrc, contains('选择负资产时可用'));
      expect(assetEditSrc,
          contains('还款时间是VIP专属权益，请充值后再尝试～'));
    });
    test('源码：还款可用条件为负资产 + VIP', () {
      expect(assetEditSrc, contains('bool get _repayEnabled => _isLiability && _isVip'));
    });
    testWidgets('编辑页：新增资产时还款时间置灰（正资产默认）', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
      await settle(tester);
      expect(find.text('还款时间'), findsOneWidget);
      expect(find.text('选择还款日期'), findsOneWidget);
    });
    test('源码：VIP 身份牌用在还款时间行', () {
      expect(assetEditSrc, contains('const IdentityBadge('));
      expect(assetEditSrc, contains('badge: UserProfile.badgeVip, scale: 0.62'));
    });
  });

  group('v5.0.21 ④ 原生通知链路', () {
    test('源码：Dart 通道名与 Kotlin 一致', () {
      expect(src('lib/services/asset_repay_reminder.dart'),
          contains("MethodChannel('vector_diary/asset_repay')"));
      expect(mainKtSrc, contains('vector_diary/asset_repay'));
    });
    test('源码：独立 id 段避免与倒数日/信件冲突', () {
      expect(mainKtSrc, contains('REQ_BASE = 81000'));
      expect(mainKtSrc, contains('NOTIFY_BASE = 40000'));
      expect(mainKtSrc, contains('asset_repay_reminders'));
    });
    test('源码：Receiver 已在 Manifest 注册', () {
      expect(manifestSrc, contains('.AssetRepayReceiver'));
    });
    test('源码：首页接入同步 + 横幅', () {
      expect(homeSrc, contains('AssetRepayReminder.syncAll'));
      expect(homeSrc, contains('AssetRepayBannerHost'));
      expect(homeSrc, contains('_initAssetRepay'));
    });
    test('源码：到期 9:00 推送', () {
      expect(src('lib/services/asset_repay_reminder.dart'),
          contains('DateTime(d.year, d.month, d.day, 9, 0)'));
    });
  });

  group('v5.0.21 ⑤ 愿望单转正特效 + 使用次数样式', () {
    test('源码：转正调用庆祝层且含粒子', () {
      expect(itemListSrc, contains('showWishlistConvertCelebration'));
      expect(convertSrc, contains('CustomPaint'));
      expect(convertSrc, contains('_ConvertBurst'));
      expect(convertSrc, contains('Haptics.medium'));
    });
    test('源码：使用次数改为已攒金额同款（加减左、数值右、箭头）', () {
      // 使用次数行引用 Spacer + chevR，与已攒金额行同构
      final usageStart = itemEditSrc.indexOf('Widget _buildUsageField()');
      final usageEnd = itemEditSrc.indexOf('void _changeUsage', usageStart);
      final usageBody = itemEditSrc.substring(usageStart, usageEnd);
      expect(usageBody, contains('const Spacer()'));
      expect(usageBody, contains('AppIcons.chevR'));
      expect(usageBody, contains('AppIcons.minus'));
      expect(usageBody, contains('AppIcons.plus'));
    });
  });

  group('v5.0.21 ⑥ 颜色适配（规范 4/6）', () {
    test('新增庆祝组件主体走 AppPalette，不写死卡片底色', () {
      expect(convertSrc, contains('AppPalette.surface'));
      expect(convertSrc, contains('AppPalette.c(0xFF24382F)'));
    });
    test('还款横幅主体走 AppPalette', () {
      final bannerSrc = src('lib/widgets/asset_repay_banner.dart');
      expect(bannerSrc, contains('AppPalette.c(0xFFFFFFFF)'));
      expect(bannerSrc, contains('AppPalette.c(0xFFE4F2EB)'));
    });
  });
}
