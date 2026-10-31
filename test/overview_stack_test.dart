import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/models/asset.dart';
import 'package:diary_app/widgets/asset_pie_card.dart';

Asset _a(String type, double amount, {String id = ''}) => Asset(
      id: id.isEmpty ? type : id,
      type: type,
      amount: amount,
    );

Widget _host(OverviewStack stack) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: stack),
        ),
      ),
    );

Widget _card1() => Container(
      key: const ValueKey('card1'),
      height: 190,
      decoration: BoxDecoration(
        color: const Color(0xFF3B6FE0),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
          child: Text('净资产', style: TextStyle(color: Colors.white))),
    );

Widget _card2(List<AssetSlice> slices) => AssetPieCard(
      key: const ValueKey('pie'),
      slices: slices,
      money: (v) => '¥${v.toStringAsFixed(0)}',
    );

/// 收集某个 key 的卡片外层的 Transform 缩放分量。
/// 堆叠只在卡片外套了 `Transform.translate > Transform.scale`，
/// 而 `Transform.scale` 只影响绘制、不改布局尺寸（[WidgetTester.getRect]
/// 拿到的永远是未缩放的尺寸），所以缩放只能从变换矩阵里读。
List<double> _ancestorScales(WidgetTester tester, String key) => tester
    .widgetList<Transform>(find.ancestor(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(Transform),
    ))
    .map((t) => t.transform.storage[0])
    .toList();

void main() {
  group('资产细分聚合', () {
    test('只统计金额为正，并按金额降序计算占比', () {
      final slices = buildSlices([
        _a('银行储蓄', 2000),
        _a('货币基金', 3000),
        _a('基金', 5000),
        _a('信用卡', -1000), // 负资产不计入
      ]);
      expect(slices.map((e) => e.type).toList(), ['基金', '货币基金', '银行储蓄']);
      expect(slices[0].ratio, closeTo(0.5, 1e-9));
      expect(slices[1].ratio, closeTo(0.3, 1e-9));
      expect(slices[2].ratio, closeTo(0.2, 1e-9));
      // 全部占比之和为 1
      expect(slices.fold<double>(0, (s, e) => s + e.ratio), closeTo(1.0, 1e-9));
    });

    test('同类型多张卡合并；全是负资产时返回空', () {
      final merged = buildSlices([
        _a('银行储蓄', 1000),
        _a('银行储蓄', 3000),
      ]);
      expect(merged.length, 1);
      expect(merged.first.amount, 4000);

      expect(buildSlices([_a('信用卡', -500)]), isEmpty);
    });
  });

  group('看板堆叠', () {
    testWidgets('第二张卡默认只露出下沿：整体在顶层卡下方', (tester) async {
      final slices = buildSlices([_a('银行储蓄', 1), _a('货币基金', 1)]);
      await tester.pumpWidget(_host(OverviewStack(
        card1: _card1(),
        card2: _card2(slices),
      )));
      await tester.pumpAndSettle();

      // 第二张卡此刻被 Offstage 收起（不布局不绘制），只靠装饰露边表示存在：
      // 必须在 onstage 判定里找不到它，否则等于白画一层昂贵的饼图
      expect(find.byKey(const ValueKey('pie')), findsNothing,
          reason: '非顶层卡片应离屏，不能参与布局与绘制');
      expect(find.byKey(const ValueKey('card1')), findsOneWidget);

      // 露边的确存在，且位置在顶层卡下方（错开 kStackOffset*2）
      final c1 = tester.getRect(find.byKey(const ValueKey('card1')));
      // 灰边 = Stack 的第一个 child（IgnorePointer 包裹的固定底色装饰）
      final stackW = tester.widget<Stack>(find.byType(Stack).first);
      final ghostFinder = find.descendant(
        of: find.byWidget(stackW.children.first),
        matching: find.byType(DecoratedBox),
      );
      expect(ghostFinder, findsOneWidget, reason: '装饰露边应被绘制');
      final ghost = tester.getRect(ghostFinder);
      expect(ghost.top, greaterThan(c1.top + 4),
          reason: '第三层装饰边应在顶层卡下方露出');

      // 顶层卡没有被缩小
      final frontScales = _ancestorScales(tester, 'card1');
      expect(frontScales.every((s) => (s - 1.0).abs() < 1e-6), isTrue,
          reason: '顶层卡不应缩放，实际 $frontScales');
    });

    testWidgets('左滑可切到第二张卡，第二张升至顶层完整显示', (tester) async {
      final slices = buildSlices([_a('银行储蓄', 1), _a('货币基金', 1)]);
      await tester.pumpWidget(_host(OverviewStack(
        card1: _card1(),
        card2: _card2(slices),
      )));
      await tester.pumpAndSettle();

      final before = tester.getRect(find.byKey(const ValueKey('card1')));

      await tester.drag(
          find.byKey(const ValueKey('card1')), const Offset(-260, 0));
      await tester.pumpAndSettle();

      // 翻页后：卡 2 变成顶层（上屏、完整显示），卡 1 收起
      expect(find.byKey(const ValueKey('pie')), findsOneWidget,
          reason: '卡 2 应升到顶层');
      expect(find.byKey(const ValueKey('card1')), findsNothing,
          reason: '卡 1 应滑到最底部并离屏');

      final c2 = tester.getRect(find.byKey(const ValueKey('pie')));
      expect(c2.left, closeTo(before.left, 1));
      expect(c2.width, closeTo(before.width, 1));
      // 顶层卡不缩放
      final scales = _ancestorScales(tester, 'pie');
      expect(scales.every((s) => (s - 1.0).abs() < 1e-6), isTrue,
          reason: '升到顶层的卡不应残留缩放，实际 $scales');
    });

    testWidgets('两个方向都能拖：右滑能在饼图页切回数据看板', (tester) async {
      final slices = buildSlices([_a('银行储蓄', 1), _a('货币基金', 1)]);
      await tester.pumpWidget(_host(OverviewStack(
        card1: _card1(),
        card2: _card2(slices),
      )));
      await tester.pumpAndSettle();

      // 左滑 → 饼图
      await tester.drag(
          find.byKey(const ValueKey('card1')), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pie')), findsOneWidget);

      // 右滑 → 回到数据看板（轮换，两个方向都生效）
      await tester.drag(
          find.byKey(const ValueKey('pie')), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('card1')), findsOneWidget,
          reason: '在饼图页右滑应切回数据看板');
      expect(find.byKey(const ValueKey('pie')), findsNothing);
    });

    testWidgets('轮换可来回切换多次，状态不会错乱', (tester) async {
      final slices = buildSlices([_a('银行储蓄', 1)]);
      await tester.pumpWidget(_host(OverviewStack(
        card1: _card1(),
        card2: _card2(slices),
      )));
      await tester.pumpAndSettle();

      for (var i = 0; i < 3; i++) {
        // 左滑
        await tester.drag(find.byKey(const ValueKey('card1')),
            const Offset(-260, 0));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('pie')), findsOneWidget,
            reason: '第 ${i + 1} 轮左滑后应显示饼图');

        // 右滑
        await tester.drag(
            find.byKey(const ValueKey('pie')), const Offset(260, 0));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('card1')), findsOneWidget,
            reason: '第 ${i + 1} 轮右滑后应显示数据看板');
      }
    });

    testWidgets('滑动距离不够时弹回原位', (tester) async {
      final slices = buildSlices([_a('银行储蓄', 1), _a('货币基金', 1)]);
      await tester.pumpWidget(_host(OverviewStack(
        card1: _card1(),
        card2: _card2(slices),
      )));
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byKey(const ValueKey('card1')));

      await tester.drag(
          find.byKey(const ValueKey('card1')), const Offset(-20, 0));
      await tester.pumpAndSettle();

      final after = tester.getRect(find.byKey(const ValueKey('card1')));
      expect(after.left, closeTo(before.left, 1));
      expect(after.top, closeTo(before.top, 1));
    });

    testWidgets('第三层灰边必须画在顶层卡下面，不能盖住净资产卡', (tester) async {
      final slices = buildSlices([_a('银行储蓄', 1)]);
      await tester.pumpWidget(_host(OverviewStack(
        card1: _card1(),
        card2: _card2(slices),
      )));
      await tester.pumpAndSettle();

      // Stack 越靠前的 child 越先绘制（越在底下）。
      // 灰边必须是 Stack 的第一个 child，否则会盖在净资产卡上。
      final stack = tester.widget<Stack>(find.byType(Stack).first);
      expect(stack.children.first, isA<IgnorePointer>(),
          reason: '第三层灰边应排在 Stack 最前面（最先绘制，位于最底层）');
      final ghost = stack.children.first as IgnorePointer;
      // 灰边只是固定底色的装饰，不含任何真实卡片
      final comp = find.descendant(
        of: find.byWidget(ghost),
        matching: find.byKey(const ValueKey('card1')),
      );
      expect(comp, findsNothing, reason: '灰边层不应包含真实卡片内容');
      // 顶层卡在灰边之后绘制
      final idx = stack.children.indexWhere((w) => w is! IgnorePointer);
      expect(idx, greaterThan(0), reason: '真实卡片必须画在灰边之上');
    });

    testWidgets('切换过程中不重建卡片子树（卡顿根因回归）', (tester) async {
      final slices = buildSlices([_a('银行储蓄', 1)]);
      await tester.pumpWidget(_host(OverviewStack(
        card1: _card1(),
        card2: _card2(slices),
      )));
      await tester.pumpAndSettle();

      final card1El = tester.element(find.byKey(const ValueKey('card1')));
      final stackEl = tester.element(find.byType(OverviewStack));

      // 慢慢拖到门槛以上再松手，逐帧采样：拖动与翻页动画期间，
      // 卡片与 OverviewStack 自身的 Element 必须始终是同一个实例
      final g = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('card1'))));
      var frames = 0;
      for (var i = 0; i < 20; i++) {
        await g.moveBy(const Offset(-12, 0));
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        if (find.byKey(const ValueKey('card1')).evaluate().isNotEmpty) {
          expect(
            identical(tester.element(find.byKey(const ValueKey('card1'))), card1El),
            isTrue,
            reason: '第 $frames 帧：拖动期间卡片不能被重建',
          );
        }
        expect(identical(tester.element(find.byType(OverviewStack)), stackEl),
            isTrue,
            reason: '第 $frames 帧：拖动期间 OverviewStack 不应重建');
      }
      await g.up();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      // 翻页完成后，第二张卡在顶层
      expect(find.byKey(const ValueKey('pie')), findsOneWidget);
    });

    testWidgets('没有正资产时不显示第二张卡', (tester) async {
      await tester.pumpWidget(_host(OverviewStack(
        hasSecond: false,
        card1: _card1(),
        card2: _card2(const []),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pie')), findsNothing);
      expect(find.byKey(const ValueKey('card1')), findsOneWidget);
    });

    testWidgets('饼图卡渲染各类型的占比文字', (tester) async {
      final slices = buildSlices([
        _a('银行储蓄', 2000),
        _a('货币基金', 3000),
        _a('基金', 5000),
      ]);
      await tester.pumpWidget(_host(OverviewStack(
        card1: _card1(),
        card2: _card2(slices),
      )));
      await tester.pumpAndSettle();

      // 饼图卡平时是离屏的，先翻到它再断言内容
      await tester.drag(
          find.byKey(const ValueKey('card1')), const Offset(-260, 0));
      await tester.pumpAndSettle();

      expect(find.text('资产细分'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
    });
  });
}
