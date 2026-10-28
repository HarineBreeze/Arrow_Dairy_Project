import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/screens/asset_screen.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// 真实渲染自检：用假的 path_provider + 临时目录里的 assets.json
/// 拉起真正的 AssetScreen，验证「数据看板下方的正/负资产结构条」
/// 确实被构建并渲染出来，且绿/红两段按金额比例分配宽度。
///
/// 说明：部分 Flutter 版本下 find.byKey 对该元素遍历有怪癖，
/// 这里直接沿元素树走到结构条节点并读取其 RenderObject 尺寸，
/// 是比 finder 更硬核的渲染证明。
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

  Directory seedAssets(List<Map<String, Object>> assets) {
    final dir = Directory(
        '/tmp/asset_test_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    final body = assets
        .map((a) => '{"id":"${a['id']}","icon":"${a['icon']}","note":"",'
            '"type":"${a['type']}","amount":${a['amount']}}')
        .join(',');
    File('${dir.path}/assets.json').writeAsStringSync('[$body]');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    return dir;
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AssetScreen()),
    ));
    // _init 有多级 await：真实 IO 需要 runAsync 完成，假区协程需要 pump 恢复
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

  /// 沿「理财资产」文本向上找到看板 Column，再取最后一个子树（结构条）
  Element? findBarElement(WidgetTester tester) {
    if (find.text('理财资产').evaluate().isEmpty) return null;
    final statEl = tester.element(find.text('理财资产'));
    Element? overviewCol;
    statEl.visitAncestorElements((anc) {
      if (anc.widget is Column &&
          (anc.widget as Column).children.length == 7) {
        overviewCol = anc;
        return false;
      }
      return true;
    });
    if (overviewCol == null) return null;
    Element? barEl;
    overviewCol!.visitChildren((child) {
      if (child.widget is ClipRRect) barEl = child;
    });
    return barEl;
  }

  testWidgets('看板下方渲染正/负资产结构条，绿红按 75%/25% 分配', (tester) async {
    final dir = seedAssets([
      {'id': '1', 'icon': '🏦', 'type': '银行储蓄', 'amount': 7500},
      {'id': '2', 'icon': '💳', 'type': '信用卡', 'amount': -2500},
    ]);
    addTearDown(() {
      dir.deleteSync(recursive: true);
      PathProviderPlatform.instance = MethodChannelPathProvider();
    });

    await pumpScreen(tester);

    // 1. 数据看板正常渲染
    expect(find.text('净资产'), findsOneWidget);
    expect(find.text('¥5000'), findsOneWidget); // 7500 + (-2500)

    // 2. 结构条元素存在且已挂载
    final barEl = findBarElement(tester);
    expect(barEl, isNotNull, reason: '数据看板下方必须构建出正/负资产结构条');

    // 3. 真实渲染尺寸：高度 7、宽度铺满
    final ro = barEl!.renderObject as RenderBox?;
    expect(ro, isNotNull);
    expect(ro!.hasSize, isTrue, reason: '结构条已完成布局');
    expect(ro.size.height, moreOrLessEquals(7, epsilon: 0.5));
    expect(ro.size.width, greaterThan(100));

    // 4. 配置层面：绿/红两段 flex 按金额比例（7500:2500 → 750:250）
    final clip = barEl.widget as ClipRRect;
    final sized = clip.child! as SizedBox;
    expect(sized.height, 7);
    final row = sized.child! as Row;
    final flexes = row.children
        .whereType<Expanded>()
        .map((e) => e.flex)
        .toList();
    expect(flexes.length, 2, reason: '应有绿（正资产）红（负资产）两段');
    expect(flexes[0] / flexes[1], closeTo(3.0, 0.01),
        reason: '绿:红 应为 7500:2500 = 3:1');
    final greenBox = (row.children[0] as Expanded).child as ColoredBox;
    final redBox = (row.children[1] as Expanded).child as ColoredBox;
    expect(greenBox.color, const Color(0xFF2A9D5C), reason: '正资产=绿色');
    expect(redBox.color, const Color(0xFFE0576A), reason: '负资产=红色');
  });

  testWidgets('只有正资产（无负债）时结构条整条绿色', (tester) async {
    final dir = seedAssets([
      {'id': '1', 'icon': '🏦', 'type': '银行储蓄', 'amount': 1200},
    ]);
    addTearDown(() {
      dir.deleteSync(recursive: true);
      PathProviderPlatform.instance = MethodChannelPathProvider();
    });

    await pumpScreen(tester);

    final barEl = findBarElement(tester);
    expect(barEl, isNotNull);
    final clip = barEl!.widget as ClipRRect;
    final row = ((clip.child! as SizedBox).child!) as Row;
    final flexes = row.children.whereType<Expanded>().map((e) => e.flex).toList();
    expect(flexes.length, 1, reason: '无负资产时只有绿色一段');
    final greenOnly = (row.children[0] as Expanded).child as ColoredBox;
    expect(greenOnly.color, const Color(0xFF2A9D5C));
  });
}
