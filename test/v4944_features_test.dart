import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/theme/app_palette.dart';

/// v4.9.44 行为回归：
/// 1. 主题色一整套跟随：主色（按钮/高亮字/置顶边框/图标色）、
///    浅底纹（标签底/图标底纹）、页面底，切换主题色时同步换色；
/// 2. 默认竹青所有值逐字节不变（保护既有精确颜色断言）；
/// 3. 每套主题色都配齐主色/浅底纹/页面底/深色顶栏/深色底纹。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppPalette.dark = false;
    AppPalette.accent = AccentCatalog.styles.first;
  });

  group('主题色配套色板', () {
    test('共 5 套，每套都配齐 tintRgb/pageRgb/darkTop/darkTint', () {
      for (final s in AccentCatalog.styles) {
        expect(s.rgb & 0xFFFFFF != 0, true, reason: '${s.name} 主色非空');
        expect(s.tintRgb & 0xFFFFFF != 0, true, reason: '${s.name} 浅底纹非空');
        expect(s.pageRgb & 0xFFFFFF != 0, true, reason: '${s.name} 页面底非空');
        expect(s.darkTop & 0xFFFFFF != 0, true, reason: '${s.name} 深顶栏非空');
        expect(s.darkTint & 0xFFFFFF != 0, true, reason: '${s.name} 深底纹非空');
      }
    });

    test('竹青配套色就是原字面量，逐字节不变', () {
      final b = AccentCatalog.byId('bamboo');
      expect(b.rgb, 0x3E8E6D);
      expect(b.tintRgb, 0xE4F2EB);
      expect(b.pageRgb, 0xF5FAF7);
    });
  });

  group('一整套换色（浅色）', () {
    test('默认竹青：主色/浅底纹/页面底全部原样返回', () {
      expect(AppPalette.c(0xFF3E8E6D).value, 0xFF3E8E6D);
      expect(AppPalette.c(0xFFE4F2EB).value, 0xFFE4F2EB);
      expect(AppPalette.c(0xFFF5FAF7).value, 0xFFF5FAF7);
      expect(AppPalette.c(0xFFE4EDE8).value, 0xFFE4EDE8);
      expect(AppPalette.c(0xFFF2F6F4).value, 0xFFF2F6F4);
    });

    test('藕粉：主色 + 浅底纹 + 页面底同步换成粉色系', () {
      AppPalette.accent = AccentCatalog.byId('lotus');
      final lotus = AccentCatalog.byId('lotus');
      expect(AppPalette.c(0xFF3E8E6D).value, 0xFF000000 | lotus.rgb);
      expect(AppPalette.c(0xFFE4F2EB).value, 0xFF000000 | lotus.tintRgb);
      expect(AppPalette.c(0xFFE4EDE8).value, 0xFF000000 | lotus.tintRgb);
      expect(AppPalette.c(0xFFF5FAF7).value, 0xFF000000 | lotus.pageRgb);
      expect(AppPalette.c(0xFFF2F6F4).value, 0xFF000000 | lotus.pageRgb);
    });

    test('雾蓝/暖棕/墨灰：浅底纹与页面底各自跟随', () {
      for (final id in ['ocean', 'amber', 'ink']) {
        AppPalette.accent = AccentCatalog.byId(id);
        final s = AccentCatalog.byId(id);
        expect(AppPalette.c(0xFFE4F2EB).value, 0xFF000000 | s.tintRgb,
            reason: '$id 浅底纹');
        expect(AppPalette.c(0xFFF5FAF7).value, 0xFF000000 | s.pageRgb,
            reason: '$id 页面底');
      }
    });

    test('写死主色入口改走 c() 后，非主题语义色仍不变', () {
      AppPalette.accent = AccentCatalog.byId('lotus');
      // 投资蓝是语义色，不应跟随主题色
      expect(AppPalette.c(0xFF3E7BD6).value, 0xFF3E7BD6);
      expect(AppPalette.c(0xFFCB5C50).value, 0xFFCB5C50);
    });
  });

  group('一整套换色（深色）', () {
    test('非竹青深色：不透明主色（按钮/高亮字/图标色）跟随主题色', () {
      AppPalette.dark = true;
      AppPalette.accent = AccentCatalog.byId('ocean');
      expect(AppPalette.c(0xFF3E8E6D).value, 0xFF4A7FB5);
    });

    test('竹青深色：不透明主色保持原值（保护既有断言）', () {
      AppPalette.dark = true;
      AppPalette.accent = AccentCatalog.styles.first;
      expect(AppPalette.c(0xFF3E8E6D).value, 0xFF3E8E6D);
    });

    test('非竹青深色：顶栏与极淡底纹仍跟随各自深色配套色', () {
      AppPalette.dark = true;
      AppPalette.accent = AccentCatalog.byId('amber');
      expect(AppPalette.topBar.value, 0xFF33261C);
      expect(AppPalette.c(0x593E8E6D).value, 0x59C9A47A);
    });
  });
}
