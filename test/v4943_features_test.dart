import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/countdown_event.dart';
import 'package:ayodiray/theme/app_palette.dart';

/// v4.9.43 行为回归：
/// 1. 事件到期当天主文案「就是今天」、副标题不再叠「已过去/已拥有 0 天」；
/// 2. 主题色注册表：默认竹青免费、其余 4 套 VIP、按 id 查询与非法回落；
/// 3. AppPalette 主色重映射：默认竹青逐字节不变，选中其它色时主色族随色改变，
///    语义色（红/橙）不受影响。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('事件到期当天文案', () {
    CountdownEvent eventAt(DateTime t, {String type = '纪念日'}) =>
        CountdownEvent(
          id: 'e1',
          name: '测试事件',
          icon: '',
          note: '',
          target: t,
          type: type,
        );

    test('当天：displayText 就是今天，subtitle 为 null', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 20, 0);
      final e = eventAt(today);
      expect(e.daysLeft, 0);
      expect(e.displayText, '就是今天');
      expect(e.subtitle, isNull);
    });

    test('资产日当天同样只显示就是今天', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 20, 0);
      final e = eventAt(today, type: '资产日');
      expect(e.displayText, '就是今天');
      expect(e.subtitle, isNull);
    });

    test('未来仍显示还有 N 天；已过去显示已过去 N 天', () {
      final now = DateTime.now();
      final future = DateTime(now.year, now.month, now.day + 3, 12);
      final past = DateTime(now.year, now.month, now.day - 2, 12);
      expect(eventAt(future).displayText, '还有 3 天');
      expect(eventAt(future).subtitle, isNull);
      expect(eventAt(past).displayText, isEmpty);
      expect(eventAt(past).subtitle, '已过去 2 天');
    });
  });

  group('主题色注册表', () {
    test('共 5 套，竹青免费且为默认，v4.9.50 起 3 免费 2 VIP', () {
      expect(AccentCatalog.styles.length, 5);
      expect(AccentCatalog.styles.first.id, 'bamboo');
      expect(AccentCatalog.styles.first.vip, false);
      expect(AccentCatalog.styles.first.rgb, 0x3E8E6D);
      // 暖棕 / 墨灰改为免费，仅藕粉 / 雾蓝为 VIP
      expect(AccentCatalog.styles.where((s) => s.vip).length, 2);
      expect(AccentCatalog.styles.where((s) => !s.vip).length, 3);
      expect(AccentCatalog.styles.map((s) => s.id).toList(),
          ['bamboo', 'amber', 'ink', 'lotus', 'ocean']);
    });

    test('byId 非法值回落竹青', () {
      expect(AccentCatalog.byId(null).id, 'bamboo');
      expect(AccentCatalog.byId('not-exist').name, '竹青');
      expect(AccentCatalog.isVip('lotus'), true);
      expect(AccentCatalog.isVip('bamboo'), false);
    });
  });

  group('AppPalette 主色重映射', () {
    setUp(() {
      AppPalette.dark = false;
      AppPalette.accent = AccentCatalog.styles.first;
    });

    test('默认竹青：所有主色族原样返回（保护既有精确颜色断言）', () {
      expect(AppPalette.c(0xFF3E8E6D).value, 0xFF3E8E6D);
      expect(AppPalette.c(0xB33E8E6D).value, 0xB33E8E6D);
      expect(AppPalette.c(0xE63E8E6D).value, 0xE63E8E6D);
      expect(AppPalette.c(0x593E8E6D).value, 0x593E8E6D);
      expect(AppPalette.topBar.value, 0xFF3E8E6D);
    });

    test('选中藕粉：主色族按色相替换且保留 alpha', () {
      AppPalette.accent = AccentCatalog.byId('lotus');
      expect(AppPalette.c(0xFF3E8E6D).value, 0xFFD9788C);
      expect(AppPalette.c(0xB33E8E6D).value, 0xB3D9788C);
      expect(AppPalette.c(0x593E8E6D).value, 0x59D9788C);
      expect(AppPalette.topBar.value, 0xFFD9788C);
    });

    test('语义色不受主题色影响', () {
      AppPalette.accent = AccentCatalog.byId('ocean');
      expect(AppPalette.c(0xFFCB5C50).value, 0xFFCB5C50); // 红
      expect(AppPalette.c(0xFFF08C3A).value, 0xFFF08C3A); // 橙
    });

    test('深色顶栏：按当前主题色的深色墨绿替换', () {
      AppPalette.dark = true;
      AppPalette.accent = AccentCatalog.byId('ocean');
      expect(AppPalette.c(0xB33E8E6D).value, 0xFF1E2C3A);
      expect(AppPalette.topBar.value, 0xFF1E2C3A);
    });
  });
}
