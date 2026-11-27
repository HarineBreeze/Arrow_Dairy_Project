import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/models/asset.dart';
import 'package:ayodiray/widgets/asset_pie_card.dart';
import 'package:ayodiray/widgets/asset_sankey_card.dart';

Asset _a(String type, double amount, {String id = ''}) => Asset(
      id: id.isEmpty ? type : id,
      type: type,
      amount: amount,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Widget _card1() => Container(
      key: const ValueKey('card1'),
      height: 190,
      color: const Color(0xFF3E8E6D),
    );

Widget _card2() => Container(
      key: const ValueKey('pie'),
      height: 190,
      color: const Color(0xFF3E7BD6),
    );

Widget _card3() => Container(
      key: const ValueKey('sankey'),
      height: 220,
      color: const Color(0xFFA9C7E8),
    );

Widget _stack() => OverviewStack(
      card1: _card1(),
      card2: _card2(),
      card3: _card3(),
      hasSecond: true,
      hasThird: true,
    );

bool _visible(WidgetTester tester, String key) {
  final f = find.ancestor(
    of: find.byKey(ValueKey(key), skipOffstage: false),
    matching: find.byType(Visibility),
  );
  if (f.evaluate().isEmpty) return true;
  return tester.widget<Visibility>(f.first).visible;
}

void main() {
  group('资产桑基图聚合', () {
    test('金融=基金/黄金/股票，固定=银行储蓄/货币基金，负债=负数', () {
      final d = buildSankeyData([
        _a('银行储蓄', 2000),
        _a('货币基金', 1000),
        _a('基金', 3000),
        _a('黄金', 500),
        _a('股票', 1500),
        _a('信用卡', -800),
        _a('欠款', -200),
      ]);
      expect(d.finance.amount, 5000); // 3000+500+1500
      expect(d.finance.count, 3);
      expect(d.fixed.amount, 3000); // 2000+1000
      expect(d.fixed.count, 2);
      expect(d.debt.amount, 1000); // 800+200 绝对值
      expect(d.debt.count, 2);
      expect(d.total, 8000); // 正资产之和
      expect(d.net.amount, 7000); // 8000 - 1000
      expect(d.isValid, isTrue);
    });

    test('守恒关系：净资产 + 负债 = 总资产 = 金融 + 固定', () {
      final d = buildSankeyData([
        _a('银行储蓄', 2000),
        _a('基金', 3000),
        _a('信用卡', -800),
      ]);
      expect(d.net.amount + d.debt.amount, closeTo(d.total, 1e-9));
      expect(d.finance.amount + d.fixed.amount, closeTo(d.total, 1e-9));
    });

    test('净资产为负（资不抵债）时 isValid=false', () {
      final d = buildSankeyData([
        _a('银行储蓄', 500),
        _a('欠款', -2000),
      ]);
      expect(d.net.amount, -1500);
      expect(d.isValid, isFalse);
    });

    test('无资产时 isValid=false，各项计数为 0', () {
      final d = buildSankeyData([]);
      expect(d.total, 0);
      expect(d.isValid, isFalse);
      expect(d.debt.count, 0);
      expect(d.finance.count, 0);
    });

    test('未知正数类型归入固定资产兜底', () {
      final d = buildSankeyData([_a(' mysterious', 123)]);
      expect(d.fixed.amount, 123);
      expect(d.fixed.count, 1);
    });
  });

  group('资产构成卡渲染', () {
    testWidgets('展示四端点标签与金额，隐藏数字时显示星号', (tester) async {
      final d = buildSankeyData([
        _a('银行储蓄', 2000),
        _a('基金', 3000),
        _a('信用卡', -800),
      ]);
      await tester.pumpWidget(_host(AssetSankeyCard(
        data: d,
        money: (v) => '¥${v.toStringAsFixed(0)}',
      )));
      await tester.pumpAndSettle();

      expect(find.text('资产构成'), findsOneWidget);
      expect(find.text('净资产'), findsOneWidget);
      expect(find.text('1项金融资产'), findsOneWidget);
      expect(find.text('1项固定资产'), findsOneWidget);
      expect(find.text('1项负债'), findsOneWidget);
      expect(find.text('¥3000'), findsOneWidget);
      expect(find.text('¥-800'), findsOneWidget);
    });

    testWidgets('净资产为负时显示降级文案，不画流带', (tester) async {
      final d = buildSankeyData([
        _a('银行储蓄', 500),
        _a('欠款', -2000),
      ]);
      await tester.pumpWidget(_host(AssetSankeyCard(
        data: d,
        money: (v) => '¥${v.toStringAsFixed(0)}',
      )));
      await tester.pumpAndSettle();

      expect(find.text('净资产为负，暂不展示构成图'), findsOneWidget);
      expect(find.text('1项金融资产'), findsNothing);
    });
  });

  group('看板三卡轮换', () {
    testWidgets('第三张卡默认隐藏，左滑两次到达桑基卡', (tester) async {
      await tester.pumpWidget(_host(_stack()));
      await tester.pumpAndSettle();

      expect(_visible(tester, 'card1'), isTrue);
      expect(_visible(tester, 'sankey'), isFalse);

      // 第 1 次左滑 → 饼图
      await tester.drag(
          find.byKey(const ValueKey('card1')), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(_visible(tester, 'pie'), isTrue);

      // 第 2 次左滑 → 桑基
      await tester.drag(
          find.byKey(const ValueKey('pie')), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(_visible(tester, 'sankey'), isTrue,
          reason: '连续左滑两次应到达第三张桑基卡');
      expect(_visible(tester, 'card1'), isFalse);
    });

    testWidgets('右滑从第一张回绕到第三张', (tester) async {
      await tester.pumpWidget(_host(_stack()));
      await tester.pumpAndSettle();

      await tester.drag(
          find.byKey(const ValueKey('card1')), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(_visible(tester, 'sankey'), isTrue,
          reason: '第一张右滑应回绕到第三张桑基卡');
    });

    testWidgets('三次左滑回到起点，轮换自洽', (tester) async {
      await tester.pumpWidget(_host(_stack()));
      await tester.pumpAndSettle();

      for (final key in ['card1', 'pie', 'sankey']) {
        await tester.drag(
            find.byKey(ValueKey(key)), const Offset(-260, 0));
        await tester.pumpAndSettle();
      }
      expect(_visible(tester, 'card1'), isTrue,
          reason: '三张卡轮换一周应回到第一张');
    });

    testWidgets('指示圈数量为三枚', (tester) async {
      await tester.pumpWidget(_host(_stack()));
      await tester.pumpAndSettle();

      // 空心圈 = 带 border 的圆形 Container，数量等于卡数 3
      final hollow = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle &&
          (w.decoration as BoxDecoration).border != null);
      expect(hollow, findsNWidgets(3));
    });

    testWidgets('三卡切换时看板高度恒定', (tester) async {
      await tester.pumpWidget(_host(_stack()));
      await tester.pumpAndSettle();

      final before = tester.getSize(find.byType(OverviewStack)).height;
      // 桑基卡 220 比 card1 190 高，轮盘应锁定在 220
      expect(before, greaterThanOrEqualTo(220));

      await tester.drag(
          find.byKey(const ValueKey('card1')), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(OverviewStack)).height,
          closeTo(before, 0.5));

      await tester.drag(
          find.byKey(const ValueKey('pie')), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(OverviewStack)).height,
          closeTo(before, 0.5));
    });

    testWidgets('未提供 card3 时退化为两卡', (tester) async {
      await tester.pumpWidget(_host(OverviewStack(
        card1: _card1(),
        card2: _card2(),
      )));
      await tester.pumpAndSettle();

      final hollow = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle &&
          (w.decoration as BoxDecoration).border != null);
      expect(hollow, findsNWidgets(2));
    });
  });
}
