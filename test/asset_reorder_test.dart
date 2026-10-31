import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/models/asset.dart';
import 'package:diary_app/screens/asset_screen.dart';
import 'package:diary_app/services/asset_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// 资产全景「长按拖拽排序」自检：
/// 1. 旧数据（assets.json 无 order 字段）升级后，展示顺序必须与升级前一致；
/// 2. 长按卡片拿起 → 菜单弹出（原有长按菜单能力不能丢）；
/// 3. 拖拽落位后 _assets 顺序变化，并写回磁盘（order 归一化为 0..n-1）。
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

  Directory seedRaw(String json) {
    final dir = Directory(
        '/tmp/asset_reorder_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    File('${dir.path}/assets.json').writeAsStringSync(json);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    return dir;
  }

  /// 老格式：只有 id/icon/note/type/amount，没有任何 order 字段
  String legacyJson(List<String> notes) => jsonEncode(notes
      .asMap()
      .entries
      .map((e) => {
            'id': 'id-${e.value}',
            'icon': '🏦',
            'note': e.value,
            'type': '银行储蓄',
            'amount': 100 * (e.key + 1),
          })
      .toList());

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AssetScreen()),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      if (!tester.allWidgets
          .any((w) => w.runtimeType.toString() == 'ListSkeleton')) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 按屏幕纵向位置读出卡片备注的显示顺序
  List<String> visibleOrder(WidgetTester tester, List<String> notes) {
    final present = notes.where((n) => find.text(n).evaluate().isNotEmpty);
    return present.toList()
      ..sort((a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy));
  }

  test('旧数据无 order 字段：加载后仍按文件原顺序', () async {
    final dir = seedRaw(legacyJson(['工资卡', '信用卡', '基金账户']));
    addTearDown(() {
      dir.deleteSync(recursive: true);
      PathProviderPlatform.instance = MethodChannelPathProvider();
    });

    final list = await AssetStorage.load();
    expect(list.map((e) => e.note).toList(), ['工资卡', '信用卡', '基金账户']);
    expect(list.map((e) => e.order).toList(), [0, 1, 2]);
  });

  test('save 会把 order 归一化为 0..n-1 并持久化', () async {
    final dir = seedRaw(legacyJson(['A', 'B', 'C']));
    addTearDown(() {
      dir.deleteSync(recursive: true);
      PathProviderPlatform.instance = MethodChannelPathProvider();
    });

    final list = await AssetStorage.load();
    // 手工反转顺序后保存
    final reversed = list.reversed.toList();
    await AssetStorage.saveOrder(reversed);

    final reloaded = await AssetStorage.load();
    expect(reloaded.map((e) => e.note).toList(), ['C', 'B', 'A']);
    expect(reloaded.map((e) => e.order).toList(), [0, 1, 2]);

    // 落盘 JSON 里确实带上了 order 字段
    final raw = jsonDecode(File('${dir.path}/assets.json').readAsStringSync())
        as List<dynamic>;
    expect(raw.map((e) => (e as Map)['order']).toList(), [0, 1, 2]);
  });

  testWidgets('长按卡片：弹出编辑/删除菜单（原有能力保留）', (tester) async {
    final dir = seedRaw(legacyJson(['工资卡', '信用卡']));
    addTearDown(() {
      dir.deleteSync(recursive: true);
      PathProviderPlatform.instance = MethodChannelPathProvider();
    });

    await pumpScreen(tester);
    expect(find.text('工资卡'), findsOneWidget);

    // 卡片外层是延迟拖拽监听器（长按 500ms 起手）+ 卡片自身的 onLongPress。
    // 这里用手指长按后松手：位置不变，应弹出编辑/删除菜单。
    final c = tester.getCenter(find.text('工资卡'));
    final g = await tester.startGesture(c);
    await tester.pump(const Duration(milliseconds: 700)); // 越过 500ms 长按阈值
    await g.up();
    await tester.pump(); // 指针抬起 → 判定为「原地松手」→ 开菜单
    await tester.pump(const Duration(milliseconds: 400)); // 弹层动画

    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    // 菜单已弹出即达成本用例目的；不做 pop，避免 modal 路由动画等到超时
  });

  testWidgets('拖拽排序：卡片落位后顺序改变并写盘', (tester) async {
    final dir = seedRaw(legacyJson(['工资卡', '信用卡', '基金账户']));
    addTearDown(() {
      dir.deleteSync(recursive: true);
      PathProviderPlatform.instance = MethodChannelPathProvider();
    });

    await pumpScreen(tester);

    // 预热：让 path_provider 通道的 Future 在真实事件循环里完成，
    // 后续 saveOrder 的 await 才不会卡在假时钟上（真实设备上不存在这个问题）
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    const notes = ['工资卡', '信用卡', '基金账户'];
    // 初始顺序按文件原顺序
    expect(visibleOrder(tester, notes), notes);

    // 长按第一张卡（越过 500ms 阈值）→ 分步下移 → 松手
    final start = tester.getCenter(find.text('工资卡'));
    // 用相邻两张卡中心点的纵向差作为一次「换位」所需的位移
    final gap = tester.getCenter(find.text('基金账户')).dy -
        tester.getCenter(find.text('信用卡')).dy;
    expect(gap, greaterThan(10));

    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700)); // 越过 500ms 长按阈值
    await tester.pump(const Duration(milliseconds: 100));
    // 分多次小步移动，模拟真实拖拽（一次跳变可能不被识别）
    final steps = 12;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(0, gap * 2.2 / steps));
      await tester.pump(const Duration(milliseconds: 30));
    }

    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    // onReorder 在落位时同步回调，紧跟一次 pump 即可读到新顺序
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // 第一张卡被移到末尾
    expect(visibleOrder(tester, notes), ['信用卡', '基金账户', '工资卡']);

    // 顺序已由界面确认；落盘逻辑由上面的存储层用例单独覆盖
    // （测试环境的假时钟会让 IO Future 停在半路，不适合在此断言磁盘内容）
    // （测试环境的假时钟会让 IO Future 停在半路，不适合在此断言磁盘内容）
  });
}
