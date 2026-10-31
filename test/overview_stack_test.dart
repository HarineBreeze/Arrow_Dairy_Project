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

      final c1 = tester.getRect(find.byKey(const ValueKey('card1')));
      final c2 = tester.getRect(find.byKey(const ValueKey('pie')));
      // 第二张卡顶边比第一张的顶边下移（被缩小并平移）
      expect(c2.top, greaterThan(c1.top + 4));
      // 但要比第一张卡的底边更靠下，才能「露出边缘」
      expect(c2.bottom, greaterThan(c1.top + 10));

      // 第二张卡被缩小：Transform.scale 只影响绘制，
      // getRect 拿到的是未缩放的布局尺寸，所以直接读变换矩阵的缩放分量
      final backScales = _ancestorScales(tester, 'pie');
      expect(backScales, isNotEmpty);
      expect(backScales.any((s) => (s - OverviewStack.kStackScale).abs() < 1e-6),
          isTrue,
          reason: '背面卡应被缩到 kStackScale，实际 $backScales');
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

      final after = tester.getRect(find.byKey(const ValueKey('card1')));
      final c2 = tester.getRect(find.byKey(const ValueKey('pie')));
      // 卡 1 已移到最底部（整体下移）
      expect(after.top, greaterThan(before.top + 4));
      // 卡 2 升到顶层：横向位置回到原位、宽度铺满
      expect(c2.left, closeTo(before.left, 1));
      expect(c2.width, closeTo(before.width, 1));
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

      expect(find.text('资产细分'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('20%'), findsOneWidget);
    });
  });
}
