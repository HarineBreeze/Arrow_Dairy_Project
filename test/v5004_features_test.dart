import 'dart:io';

import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/utils/app_version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// v5.0.4 回归（叠加在电脑端 v5.0.3 之上）：
/// 1. 深色模式下隐私锁/密码向导「未选中项」不再亮眼：0xFFF5F8F6 已登记深色暗底纹；
/// 2. 修改资产密码：验证身份后复用通用 3 步向导（showPinSetupWizard3）收集新凭证；
/// 3. 向导结果落盘走 AssetStorage.updatePin；
/// 4. 版本号 V5.0.4。

String _src(String rel) =>
    File('${Directory.current.path}/lib/$rel').readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('版本号', () {
    test('展示版本推进到 V5.0.5', () {
      expect(AppVersion.displayVersion, 'V5.0.5');
    });
  });

  group('深色配色（向导未选中项）', () {
    test('0xFFF5F8F6 浅色保持原值、深色映射为暗底纹', () {
      AppPalette.dark = false;
      AppPalette.accent = AccentCatalog.byId('bamboo');
      expect(AppPalette.c(0xFFF5F8F6), const Color(0xFFF5F8F6));

      AppPalette.dark = true;
      expect(AppPalette.c(0xFFF5F8F6), const Color(0xFF233A2F));
      AppPalette.dark = false;
    });

    test('同主题暗色系：深色底纹随主题色变化', () {
      AppPalette.dark = true;
      AppPalette.accent = AccentCatalog.byId('bamboo');
      final bamboo = AppPalette.c(0xFFF5F8F6);
      AppPalette.accent = AccentCatalog.byId('ocean');
      final ocean = AppPalette.c(0xFFF5F8F6);
      AppPalette.accent = AccentCatalog.byId('violet');
      final violet = AppPalette.c(0xFFF5F8F6);
      expect(bamboo, const Color(0xFF233A2F));
      expect(ocean, const Color(0xFF22303F)); // 雾蓝 darkTintBg
      expect(violet, const Color(0xFF322645)); // 霞紫 darkTintBg
      expect(bamboo, isNot(ocean));
      expect(ocean, isNot(violet));
      AppPalette.dark = false;
      AppPalette.accent = AccentCatalog.byId('bamboo');
    });
  });

  group('修改资产密码 = 验证身份 + 通用3步向导', () {
    test('_openChangePin 验证通过后调用 showPinSetupWizard3', () {
      final s = _src('screens/asset_screen.dart');
      final start = s.indexOf('Future<void> _openChangePin()');
      final end = s.indexOf('// ---------- 筛选 ----------');
      final body = s.substring(start, end);
      // 先验证身份
      expect(body.contains('const _ChangePinDialog()'), true);
      // 验证通过后复用 3 步向导（与开启加密访问同款）
      expect(body.contains('showPinSetupWizard3(context)'), true);
      // 结果落盘
      expect(body.contains('AssetStorage.updatePin('), true);
    });

    test('改密码弹窗只做身份验证，验证通过即 pop(true)', () {
      final s = _src('screens/asset_screen.dart');
      final start = s.indexOf('class _ChangePinDialog extends StatefulWidget');
      final body = s.substring(start);
      expect(body.contains("Navigator.pop(context, true)"), true);
      // 不再在本弹窗内一步收集新密码
      expect(body.contains('设置新密码'), false);
      expect(body.contains('再输入一遍新密码'), false);
    });

    test('通用向导仍是 3 步：设置密码→确认密码→设置密保', () {
      final s = _src('widgets/pin_setup_wizard.dart');
      expect(s.contains("title: '设置密码'"), true);
      expect(s.contains("title: '确认密码'"), true);
      expect(s.contains("title: '设置密保'"), true);
    });
  });
}
