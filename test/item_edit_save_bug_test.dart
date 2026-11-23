import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ayodiray/models/item.dart';
import 'package:ayodiray/screens/item_edit_screen.dart';
import 'package:ayodiray/services/item_storage.dart';
import 'package:ayodiray/widgets/save_done_button.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v5.0.7 回归：物品编辑页点「完成」后必须保存并返回上一页。
///
/// 修复前：_save 里任何一处 IO 异常都会让 finish() 永远不被调用，
/// 按钮停在打勾状态、页面不返回、物品没保存。
/// 修复后：保存失败会提示「保存失败，请重试」并复位按钮。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  final memory = <Item>[];

  setUp(() {
    dir = Directory('/tmp/item_edit_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    memory.clear();
    // 预置待编辑的物品
    memory.add(Item(
      id: 'i1',
      name: '旧名字',
      price: 100,
      acquiredDate: DateTime(2026, 1, 1),
    ));
    ItemStorage.loadOverride = () async => List.of(memory);
    ItemStorage.saveOverride = (items) async {
      memory
        ..clear()
        ..addAll(items);
    };
  });

  tearDown(() {
    ItemStorage.resetOverride();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  final item = Item(
    id: 'i1',
    name: '旧名字',
    price: 100,
    acquiredDate: DateTime(2026, 1, 1),
  );

  Future<void> openAndEdit(WidgetTester tester, {required String action}) async {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: Text('列表页'))),
    ));
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute(builder: (_) => ItemEditScreen(item: item)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '新名字');
    await tester.pump();
    await tester.tap(find.text(action == 'fail' ? '完成' : '完成'));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('编辑已有物品：点完成后保存并返回上一页', (tester) async {
    await openAndEdit(tester, action: 'ok');

    // 播完收缩 + 对勾 + 粒子 + 停留，onDone pop
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('列表页'), findsOneWidget, reason: '保存完成后应返回上一页');
    expect(memory, isNotEmpty, reason: '编辑结果应已写入存储');
    expect(memory.first.name, '新名字');
    expect(memory.first.id, 'i1', reason: '应更新原物品而不是新增');
  });

  testWidgets('保存抛异常：提示失败并复位按钮，不再卡在打勾界面', (tester) async {
    ItemStorage.saveOverride = (items) async => throw Exception('disk error');
    await openAndEdit(tester, action: 'fail');

    await tester.pump(const Duration(milliseconds: 600));
    // toast 还在展示期内先断言，再 pumpAndSettle 让其自然消失
    expect(find.text('保存失败，请重试'), findsOneWidget,
        reason: '保存失败必须有可见提示');
    await tester.pumpAndSettle();
    // 等 toast 的自动消失 Timer 走完，避免「Timer still pending」
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('保存失败，请重试'), findsOneWidget,
        reason: '保存失败必须有可见提示');
    // 按钮复位：不再是打勾状态，「完成」可再次点击
    expect(find.text('完成'), findsOneWidget);
    final st =
        tester.state<SaveDoneButtonState>(find.byType(SaveDoneButton));
    expect(st.canTap, isTrue, reason: '复位后按钮应可再次点击');
  });

  testWidgets('SaveDoneButton：finish 在收缩动画进行中调用，onDone 仍应回调', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

    var doneCount = 0;
    final key = GlobalKey<SaveDoneButtonState>();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: SaveDoneButton(
              key: key,
              color: const Color(0xFF3E8E6D),
              validate: () => null,
              onTap: () {},
              onDone: () => doneCount++,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byType(SaveDoneButton));
    await tester.pump(); // _onTap：animateTo(0.54) 启动
    await tester.pump(const Duration(milliseconds: 50));

    // 模拟「落盘比收缩动画快」：finish 不 await（fire-and-forget，真机等价）
    unawaited(key.currentState!.finish());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(doneCount, 1, reason: '收缩动画进行中 finish，onDone 仍应回调');
  });
}
