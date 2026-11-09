import 'dart:io';

import 'package:ayodiray/screens/countdown_edit_screen.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.12 回归：
/// 1. 事件编辑页移除重复规则/提醒时间的说明提示语，「提前提醒」改名「提醒时间」；
/// 2. 物品编辑页版式对齐事件编辑页：小节标题在上（物品类型/物品图标/日期/计算方式），
///    行内标签（物品名/物品价格等）改为节标题。
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
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory('/tmp/relayout_${DateTime.now().microsecondsSinceEpoch}');
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

  testWidgets('事件编辑页：提示语移除，节名改为「提醒时间」', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: CountdownEditScreen()));
    await _settle(tester);

    expect(find.text('提醒时间'), findsOneWidget, reason: '提前提醒应改名提醒时间');
    expect(find.text('提前提醒'), findsNothing);
    expect(find.textContaining('到期后自动进入'), findsNothing,
        reason: '重复规则的说明提示语应移除');
    expect(find.textContaining('在事件日'), findsNothing,
        reason: '提醒的说明提示语应移除');
    expect(find.text('重复规则'), findsOneWidget, reason: '节本身保留');
  });

  testWidgets('物品编辑页：节标题在上，四个节名按新文案', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(const MaterialApp(home: ItemEditScreen()));
    await _settle(tester);

    for (final label in ['物品类型', '物品图标', '日期', '计算方式']) {
      expect(find.text(label), findsOneWidget, reason: '$label 节标题应存在');
    }
    expect(find.text('均价计算方式'), findsNothing, reason: '旧节名应移除');
    expect(find.text('物品状态'), findsOneWidget);
    expect(find.text('物品名称'), findsOneWidget);
    expect(find.text('物品价格'), findsOneWidget);

    // 行内标签不再存在（已改为节标题）
    expect(find.text('物品名'), findsNothing);
  });
}
