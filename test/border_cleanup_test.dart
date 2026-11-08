import 'dart:convert';
import 'dart:io';

import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/screens/asset_edit_screen.dart';
import 'package:ayodiray/screens/edit_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';
import 'package:ayodiray/screens/settings_screen.dart';
import 'package:ayodiray/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.10 回归：
/// 1. 已有封面图时不再显示「更换」角标（点图本身即可编辑）；
/// 2. 资产 / 物品编辑页与设置页的选框、功能框取消描边。
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

const String _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAACgAAAAeCAIAAADRv8uKAAAALklEQVR4nO3NMQEAMAgAoLlg'
    'NrKKma3g5wMFiOx6F/7JKhaLxWKxWCwWi8XilQEMTAF1/KYm1AAAAABJRU5ErkJggg==';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// 收集页面内所有 Container 的描边颜色（BoxDecoration + Border）
List<Color> _borderColors(WidgetTester tester) {
  final colors = <Color>[];
  for (final c in tester.widgetList<Container>(find.byType(Container))) {
    final d = c.decoration;
    if (d is BoxDecoration && d.border is Border) {
      colors.add((d.border as Border).top.color);
    }
  }
  return colors;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory('/tmp/border_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  void usePhone(WidgetTester tester) {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);
  }

  testWidgets('已有封面图时不再出现「更换」角标，垃圾桶仍在', (tester) async {
    usePhone(tester);
    final img = File('${dir.path}/cover.png')
      ..writeAsBytesSync(base64Decode(_pngB64));
    final now = DateTime.now();
    final entry = DiaryEntry(
      id: 'e1',
      title: '有图笔记',
      content: '正文',
      imagePath: img.path,
      createdAt: now,
      updatedAt: now,
      publishDate: now,
    );

    await tester.pumpWidget(MaterialApp(home: EditScreen(entry: entry)));
    await _settle(tester);

    expect(find.text('更换'), findsNothing, reason: '点图片就能换图，角标重复');
    // 顶栏删除按钮也是垃圾桶（size 24），封面图角标为 15，按尺寸区分
    expect(
        find.byWidgetPredicate((w) =>
            w is AppIcon && w.path == AppIcons.trash && w.size == 15),
        findsOneWidget,
        reason: '移除封面图的垃圾桶入口应保留');
  });

  testWidgets('资产编辑页选框与输入框无描边', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: AssetEditScreen()));
    await _settle(tester);

    final colors = _borderColors(tester);
    expect(colors, isNot(contains(const Color(0xFFE8EDF5))),
        reason: '输入框/卡片不应再有浅灰描边');
    expect(colors, isNot(contains(const Color(0xFFE4F2EB))),
        reason: '图标选中框不应再有描边（浅绿底已表达选中）');
  });

  testWidgets('物品编辑页选框无描边', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
    await _settle(tester);

    final colors = _borderColors(tester);
    expect(colors, isNot(contains(const Color(0xFFE4F2EB))),
        reason: '状态/分类/日期等选框不应再有描边');
    expect(colors, isNot(contains(const Color(0xFFE8EDF5))),
        reason: '图标格不应再有浅灰描边');
  });

  testWidgets('设置页功能框无描边（提示圈保留）', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await _settle(tester);

    final colors = _borderColors(tester);
    expect(colors, isNot(contains(const Color(0xFFE8EDF5))),
        reason: '导出/导入、字体、反馈等功能框不应再有描边');
  });
}
