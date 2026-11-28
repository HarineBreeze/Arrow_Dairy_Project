import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/screens/asset_edit_screen.dart';
import 'package:ayodiray/screens/global_search_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/theme/app_palette.dart';
import 'package:ayodiray/widgets/app_icons.dart';
import 'package:ayodiray/widgets/asset_trend_chart.dart';

void main() {
  final root = Directory.current.path;
  String src(String rel) => File('$root/$rel').readAsStringSync();
  final itemSrc = src('lib/screens/item_edit_screen.dart');
  final assetEditSrc = src('lib/screens/asset_edit_screen.dart');
  final chartSrc = src('lib/widgets/asset_trend_chart.dart');
  final settingsSrc = src('lib/screens/settings_screen.dart');
  final itemListSrc = src('lib/screens/item_list_screen.dart');
  final countdownSrc = src('lib/screens/countdown_screen.dart');
  final searchSrc = src('lib/screens/global_search_screen.dart');

  Future<void> settle(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
  }

  group('v5.0.20 ① 物品编辑页提示语格式与去「请」字', () {
    testWidgets('三个待输入提示语：去「请」字 + 统一 13 灰 hintStyle', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
      await settle(tester);

      expect(find.text('输入物品名'), findsOneWidget);
      expect(find.text('输入物品价格'), findsOneWidget);
      expect(find.text('输入附加价格，如卖出/折扣（选填）'), findsOneWidget);
      expect(find.text('请输入物品名'), findsNothing);
      expect(find.text('请输入物品价格'), findsNothing);

      // 三处 hintStyle 的色值均为辅助灰 0xFF8FA09A
      final nameField = tester.widget<TextField>(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.hintText == '输入物品名'));
      final priceField = tester.widget<TextField>(
          find.byWidgetPredicate((w) =>
              w is TextField && w.decoration?.hintText == '输入物品价格'));
      final extraField = tester.widget<TextField>(
          find.byWidgetPredicate((w) => w is TextField &&
              w.decoration?.hintText == '输入附加价格，如卖出/折扣（选填）'));
      expect(nameField.decoration!.hintStyle!.fontSize, 13);
      expect(priceField.decoration!.hintStyle!.fontSize, 13);
      expect(extraField.decoration!.hintStyle!.fontSize, 13);
      expect(nameField.decoration!.hintStyle!.color, AppPalette.c(0xFF8FA09A));
      expect(priceField.decoration!.hintStyle!.color, AppPalette.c(0xFF8FA09A));
      expect(extraField.decoration!.hintStyle!.color, AppPalette.c(0xFF8FA09A));
    });
  });

  group('v5.0.20 ② 资产类型抽屉移除选中底纹', () {
    test('源码：_pickTypeSheet 选中项不再铺 E4F2EB 底纹', () {
      expect(assetEditSrc, isNot(contains('color: t == _type\n                                ? AppPalette.c(0xFFE4F2EB)')),
          reason: '选中底纹应移除');
      expect(assetEditSrc, contains('选中态只用加粗/主色文字 + 右侧勾选图标表达，不再铺底色'),
          reason: '应保留注释说明与其它选项抽屉一致');
    });
  });

  group('v5.0.20 ③ 趋势图图例/查看时间底纹主题色适配', () {
    test('源码：图例底纹与选中胶囊底纹均改用 E4F2EB', () {
      // 图例信息条底纹
      expect(chartSrc, contains('color: AppPalette.c(0xFFE4F2EB)'));
      // 查看时间胶囊选中底纹
      expect(chartSrc, contains('color: selected ? AppPalette.c(0xFFE4F2EB) : Colors.transparent'));
      // 旧写死的 ED F3FD / E4E8EB 底纹不再用于这两处
      expect(chartSrc, isNot(contains('color: AppPalette.c(0xFFEDF3FD)')));
      expect(chartSrc,
          isNot(contains('color: selected ? AppPalette.c(0xFFE4E8EB)')));
    });

    test('E4F2EB 随主题与深色自适应（常规/深色双适配）', () {
      AppPalette.dark = false;
      expect(AppPalette.c(0xFFE4F2EB),
          const Color(0xFFE4F2EB)); // 默认竹青浅底原样
      AppPalette.dark = true;
      expect(AppPalette.c(0xFFE4F2EB),
          const Color(0xFF233A2F)); // 深色翻为深底纹
      AppPalette.dark = false;
    });
  });

  group('v5.0.20 ④ 设置页导入副标题', () {
    testWidgets('导入数据副标题改为「将备份的数据导入到APP」', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await settle(tester);
      expect(find.text('将备份的数据导入到APP'), findsOneWidget);
      expect(find.text('支持增添合并或完全覆盖两种导入方式'), findsNothing);
    });
  });

  group('v5.0.20 ⑤⑥ 两个筛选器改为独占一行勾选样式', () {
    test('源码：物品排序与事件筛选均由 Wrap 改 Column + 勾选图标', () {
      // 物品排序抽屉
      expect(itemListSrc, contains('for (final f in _ItemSortField.values)'),
          reason: '排序选项应逐行铺开');
      expect(itemListSrc, contains('AppIcon(AppIcons.check'),
          reason: '选中项带勾选图标');
      expect(itemListSrc, isNot(contains('Wrap(')),
          reason: '旧的多按钮 Wrap 应移除');
      // 事件筛选抽屉
      expect(countdownSrc, contains('Column(children: ['),
          reason: '事件筛选选项应逐行铺开');
      expect(countdownSrc, contains('AppIcon(AppIcons.check'));
      expect(countdownSrc, isNot(contains('Wrap(children: [')),
          reason: '旧的多按钮 Wrap 应移除');
    });
  });

  group('v5.0.20 ⑦ 搜索结果三者与筛选栏「全部」左对齐', () {
    test('源码：分区标题/卡片标题/副标题统一用动态 allLeft', () {
      expect(searchSrc, contains('final allLeft = (cellW - 26) / 2'));
      expect(searchSrc, contains('EdgeInsets.only(left: allLeft, bottom: 7)'));
      expect(searchSrc, contains('EdgeInsets.fromLTRB(allLeft, 11, 14, 11)'));
      expect(searchSrc, contains('Divider(height: 1, indent: allLeft)'));
      // 4 处 _ResultRow 均传入 allLeft
      expect(searchSrc, contains('allLeft: allLeft'));
    });

    test('对齐基线：「全部」在 1/5 等宽 cell 居中的左边缘计算正确', () {
      // 常规 390 宽：cellW=78，allLeft=(78-26)/2=26
      const width = 390.0;
      final cellW = width / 5;
      final allLeft = (cellW - 26) / 2;
      expect(allLeft, closeTo(26, 0.01));
      // 三者共用同一基线：分区标题、卡片标题、副标题均引用 allLeft
      expect(searchSrc, contains('EdgeInsets.only(left: allLeft, bottom: 7)'));
      expect(searchSrc, contains('EdgeInsets.fromLTRB(allLeft, 11, 14, 11)'));
    });
  });
}
