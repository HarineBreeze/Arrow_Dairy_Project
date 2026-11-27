import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/asset.dart';
import 'package:ayodiray/widgets/asset_pie_card.dart';
import 'package:ayodiray/widgets/asset_sankey_card.dart';

Asset _a(String type, double amount) => Asset(
      id: type,
      type: type,
      amount: amount,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 360, child: child)),
      ),
    );

/// 无固定高度、由内容撑开的卡片，模拟真实三张卡（净资产/饼图/桑基）——
/// 真实卡都是 Container + Column，会被外层 tight 约束拉伸。
Widget _flexCard(String key, double naturalH) => Container(
      key: ValueKey(key),
      color: const Color(0xFFFFFFFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [SizedBox(height: naturalH)],
      ),
    );

void main() {
  group('v5.0.9 卡片尺寸与溢出修复', () {
    testWidgets('三张卡渲染为同一长宽（等高等宽）', (tester) async {
      await tester.pumpWidget(_host(OverviewStack(
        card1: _flexCard('a', 180),
        card2: _flexCard('b', 160),
        card3: _flexCard('c', 200),
        hasSecond: true,
        hasThird: true,
      )));
      await tester.pumpAndSettle();

      final a = tester.getSize(find.byKey(const ValueKey('a')));
      final b = tester.getSize(find.byKey(const ValueKey('b')));
      final c = tester.getSize(find.byKey(const ValueKey('c')));

      expect(a.height, b.height, reason: '资产数据与资产细分卡应等高');
      expect(b.height, c.height, reason: '资产细分与资产构成卡应等高');
      expect(a.width, b.width, reason: '三卡应等宽');
      expect(b.width, c.width, reason: '三卡应等宽');
      expect(a.height, greaterThanOrEqualTo(200),
          reason: '轮盘高度应取三卡自然高度最大值');
    });

    testWidgets('切到第三张后三卡仍同尺寸', (tester) async {
      await tester.pumpWidget(_host(OverviewStack(
        card1: _flexCard('a', 180),
        card2: _flexCard('b', 160),
        card3: _flexCard('c', 200),
        hasSecond: true,
        hasThird: true,
      )));
      await tester.pumpAndSettle();

      // 左滑两次到第三张卡
      final stackCenter = tester.getCenter(find.byType(OverviewStack));
      await tester.dragFrom(stackCenter, const Offset(-120, 0));
      await tester.pumpAndSettle();
      await tester.dragFrom(stackCenter, const Offset(-120, 0));
      await tester.pumpAndSettle();

      final a = tester.getSize(find.byKey(const ValueKey('a')));
      final c = tester.getSize(find.byKey(const ValueKey('c')));
      expect(a.height, c.height, reason: '翻页后三卡尺寸不应变化');
    });

    testWidgets('桑基顶部标签不被裁切（top 夹在图表区内）', (tester) async {
      final d = buildSankeyData([
        _a('银行储蓄', 335000),
        _a('基金', 20000),
        _a('信用卡', -5000), // 负债占比很小 → 顶部节点很矮
      ]);
      await tester.pumpWidget(_host(AssetSankeyCard(
        data: d,
        money: (v) => '¥${v.toStringAsFixed(0)}',
      )));
      await tester.pumpAndSettle();

      // 负债节点很矮，标签 top 曾被算成负数，导致文字溢出卡片顶部被裁切
      final debtPos = find.ancestor(
        of: find.text('¥-5000'),
        matching: find.byType(Positioned),
      );
      expect(debtPos, findsOneWidget);
      final top = tester.widget<Positioned>(debtPos.first).top!;
      expect(top, greaterThanOrEqualTo(0), reason: '负债标签 top 不应为负: $top');
    });

    testWidgets('桑基四个标签都落在卡片边框内', (tester) async {
      final d = buildSankeyData([
        _a('银行储蓄', 335000),
        _a('基金', 20000),
        _a('信用卡', -5000),
      ]);
      await tester.pumpWidget(_host(AssetSankeyCard(
        data: d,
        money: (v) => '¥${v.toStringAsFixed(0)}',
      )));
      await tester.pumpAndSettle();

      final cardRect = tester.getRect(find.byType(AssetSankeyCard));
      for (final label in [
        '1项负债',
        '¥-5000',
        '净资产',
        '¥350000',
        '1项金融资产',
        '¥20000',
        '1项固定资产',
        '¥335000',
      ]) {
        final f = find.text(label);
        if (f.evaluate().isEmpty) continue;
        final r = tester.getRect(f);
        expect(r.top >= cardRect.top - 0.5, isTrue,
            reason: '$label 超出卡片顶部');
        expect(r.bottom <= cardRect.bottom + 0.5, isTrue,
            reason: '$label 超出卡片底部');
        expect(r.left >= cardRect.left - 0.5, isTrue,
            reason: '$label 超出卡片左侧');
        expect(r.right <= cardRect.right + 0.5, isTrue,
            reason: '$label 超出卡片右侧');
      }
    });
  });
}
