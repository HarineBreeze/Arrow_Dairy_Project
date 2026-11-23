import 'dart:io';

import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

/// v5.0.3 回归：
/// 1. 设置页版本号随列表滚动、不吸底；
/// 2. 回收站空态移除「删除内容 7 日恢复」提示；
/// 3. 资产数据看板空态仍可见（显示 0）；
/// 4. 资产设置抽屉无「设置」标题 + 3 步密码向导 + 移除本机提示；
/// 5. 笔记设置密码 2 步向导；
/// 6. 深色模式默认关闭；
/// 7. 日记筛选栏与数据栏之间加分割线；
/// 8. 版本号 V5.0.3。

String _src(String rel) =>
    File('${Directory.current.path}/lib/$rel').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('版本号', () {
    test('展示版本同步到 V5.0.3', () {
      expect(AppVersion.displayVersion, 'V5.0.3');
    });
  });

  group('设置页版本号不吸底', () {
    test('body 直接是 ListView，版本号作为列表末项', () {
      final s = _src('screens/settings_screen.dart');
      expect(s.contains('body: ListView('), true);
      expect(s.contains('body: Column('), false);
      expect(s.contains('AppVersion.displayVersion'), true);
      expect(s.contains('版本号置于列表内容最底部'), true);
    });
  });

  group('回收站空态提示', () {
    test('移除「删除的内容支持7日内恢复」提示语', () {
      final s = _src('screens/trash_screen.dart');
      expect(s.contains('删除的内容支持7日内恢复'), false);
      expect(s.contains('7日内恢复'), false);
      expect(s.contains('回收站是空的'), true);
    });
  });

  group('资产数据看板空态可见', () {
    test('空态 ListView 内保留 _buildOverview', () {
      final s = _src('screens/asset_screen.dart');
      final emptyBranch = s.substring(
          s.indexOf('child: _filtered.isEmpty'),
          s.indexOf(': ReorderableListView.builder'));
      expect(emptyBranch.contains('_buildOverview()'), true);
      expect(emptyBranch.contains('数值显示 0'), true);
    });
  });

  group('资产设置抽屉与加密弹窗', () {
    test('抽屉移除「设置」标题', () {
      final s = _src('screens/asset_screen.dart');
      expect(s.contains("child: Text('设置',"), false);
      expect(s.contains('移除「设置」标题'), true);
    });

    test('开启加密访问走 3 步向导，无「密码仅保存在本机」', () {
      final s = _src('screens/asset_screen.dart');
      expect(s.contains('showPinSetupWizard3(context)'), true);
      expect(s.contains('_PinSetupDialog'), false);
      expect(s.contains('密码仅保存在本机'), false);
    });
  });

  group('密码向导步骤数', () {
    test('showPinSetupWizard3 = 确认步开启（3 步）', () {
      final s = _src('widgets/pin_setup_wizard.dart');
      expect(s.contains('showPinSetupWizard3'), true);
      expect(s.contains('_showWizard(context, confirm: true)'), true);
      expect(s.contains('showPinSetupWizard2'), true);
      expect(s.contains('_showWizard(context, confirm: false)'), true);
      expect(s.contains('密码仅保存在本机'), false);
    });

    test('笔记页设置密码走 2 步向导', () {
      final s = _src('screens/edit_screen.dart');
      expect(s.contains('showPinSetupWizard2(context)'), true);
    });

    test('向导主题化：AppPalette 背景 + accentColor 主按钮 + 右对齐', () {
      final s = _src('widgets/pin_setup_wizard.dart');
      expect(s.contains('AppThemeScope.watch(context)'), true);
      expect(s.contains('backgroundColor: AppPalette.c(0xFFFFFFFF)'), true);
      expect(s.contains('color: AppPalette.accentColor'), true);
      expect(s.contains('MainAxisAlignment.end'), true);
    });
  });

  group('深色模式默认关闭', () {
    test('默认主题模式为 light，非法值也回落 light', () {
      final s = _src('services/app_settings.dart');
      expect(s.contains('AppThemeMode _themeMode = AppThemeMode.light'), true);
      expect(s.contains('ValueNotifier<AppThemeMode>(AppThemeMode.light)'), true);
      expect(s.contains('orElse: () => AppThemeMode.light'), true);
      expect(AppThemeMode.light, isNot(AppThemeMode.dark));
    });
  });

  group('日记筛选栏与数据栏分割线', () {
    test('_buildViewBar 与 _buildStatsBar 之间有 Divider', () {
      final s = _src('screens/home_screen.dart');
      final start = s.indexOf('        _buildViewBar(),');
      final end = s.indexOf('        _buildStatsBar(),', start);
      final between = s.substring(start, end);
      expect(between.contains('Divider(height: 1, color: AppPalette.c(0xFFE8EDF5))'),
          true);
      expect(between.contains('v5.0.3'), true);
    });
  });
}
