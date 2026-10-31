import 'dart:convert';
import 'dart:io';

import 'package:diary_app/screens/asset_screen.dart';
import 'package:diary_app/widgets/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 资产全景卡片的「按压 → 回弹」生命周期回归。
///
/// 覆盖的三条实机 bug：
/// 1. 点击卡片进入编辑页后，卡片停在 90% 不再回弹；
/// 2. 停住之后再次点击 / 拖拽换位也毫无反应；
/// 3. 该页其它卡片随之失去回弹动画（同一实例的 _down 卡死）。
///
/// 以及新增的长按拖拽逻辑：按住不松手保持 90%，松手后才走弹簧回弹。
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

/// 读某张卡片当前缩放（取卡片自身的 Pressable 那层的 Transform.scale）。
///
/// 找不到时返回 1.0：按压首帧 AnimationController 尚未 notifyListeners，
/// widget 树里还没有非单位的 Transform，此时按「未缩放」处理即可。
double scaleOf(WidgetTester tester, String note) {
  final pressables = find.ancestor(
      of: find.text(note), matching: find.byType(Pressable));
  if (pressables.evaluate().isEmpty) return 1.0;
  final transforms = find.descendant(
      of: pressables.first, matching: find.byType(Transform));
  if (transforms.evaluate().isEmpty) return 1.0;
  return tester.widget<Transform>(transforms.first).transform.storage[0];
}

Future<void> boot(WidgetTester tester) async {
  final dir = Directory('/tmp/pl_${DateTime.now().microsecondsSinceEpoch}');
  dir.createSync(recursive: true);
  File('${dir.path}/assets.json').writeAsStringSync(jsonEncode([
    {'id': 'a1', 'icon': '🏦', 'note': '借张三', 'type': '欠款', 'amount': -500},
    {'id': 'a2', 'icon': '💳', 'note': '日常支出', 'type': '信用卡', 'amount': -2000},
    {'id': 'a3', 'icon': '🏦', 'note': '工资卡', 'type': '银行储蓄', 'amount': 3000},
  ]));
  PathProviderPlatform.instance = _FakePathProvider(dir.path);

  await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AssetScreen())));
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

void main() {
  testWidgets('点击卡片进入编辑页再返回：卡片回到 100%', (tester) async {
    await boot(tester);
    expect(scaleOf(tester, '借张三'), closeTo(1.0, 1e-6));

    await tester.tap(find.text('借张三'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 编辑页已打开，此时卡片应当在 100%（跳转前已主动复位）
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(nav.canPop(), isTrue, reason: '点击卡片应打开编辑页');

    nav.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(scaleOf(tester, '借张三'), closeTo(1.0, 1e-3),
        reason: '返回后卡片必须回到 100%，不能卡在 90%');
  });

  testWidgets('点击返回后，其它卡片仍有回弹动画', (tester) async {
    await boot(tester);

    await tester.tap(find.text('借张三'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 另一张卡片按压时仍要缩到 90%
    // 返回后列表可能还要重新布局一帧
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('日常支出').evaluate().length, 1,
        reason: '返回后列表应正常渲染');
    final g = await tester.startGesture(tester.getCenter(find.text('日常支出')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester, '日常支出'), closeTo(0.90, 1e-3),
        reason: '其它卡片的按压动画不能被前一页的操作带坏');

    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(scaleOf(tester, '日常支出'), closeTo(1.0, 1e-3));
  });

  testWidgets('长按不松手：保持 90%，松手后才回弹', (tester) async {
    await boot(tester);

    final g = await tester.startGesture(tester.getCenter(find.text('借张三')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(scaleOf(tester, '借张三'), closeTo(0.90, 1e-3), reason: '按下应为 90%');

    // 长按超过拖拽阈值（500ms），期间必须一直保持 90%，不能中途回弹
    await tester.pump(const Duration(milliseconds: 400));
    expect(scaleOf(tester, '借张三'), closeTo(0.90, 1e-3),
        reason: '长按拖拽期间应保持 90%');
    await tester.pump(const Duration(milliseconds: 400));
    expect(scaleOf(tester, '借张三'), closeTo(0.90, 1e-3),
        reason: '长按持续期间不能自己弹回去');

    await g.up();
    // 松手后先过冲再回到 100%
    var peak = 0.0;
    for (var i = 0; i < 420; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      final s = scaleOf(tester, '借张三');
      if (s > peak) peak = s;
    }
    expect(peak, greaterThan(1.0), reason: '松手后应先放大过 100%');
    expect(peak, lessThanOrEqualTo(1.0 + Pressable.kOvershoot + 1e-6));
    expect(scaleOf(tester, '借张三'), closeTo(1.0, 1e-3));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('拖拽换位松手：卡片回弹，顺序仍正确', (tester) async {
    await boot(tester);

    final start = tester.getCenter(find.text('借张三'));
    final target = tester.getCenter(find.text('工资卡'));
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700));
    final gap = target.dy - start.dy;
    for (var i = 1; i <= 12; i++) {
      await g.moveBy(Offset(0, gap / 12));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    List<String> order() {
      const notes = ['借张三', '日常支出', '工资卡'];
      final present = notes.where((n) => find.text(n).evaluate().isNotEmpty);
      return present.toList()
        ..sort((a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy));
    }

    expect(order(), ['日常支出', '工资卡', '借张三']);
    expect(scaleOf(tester, '借张三'), closeTo(1.0, 1e-3),
        reason: '拖拽结束后不能停在 90%');
  });
}
