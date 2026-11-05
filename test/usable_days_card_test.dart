import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/utils/usable_days.dart';

/// 看板卡片上「可使用 x 天」两栏的展示契约。
///
/// 不启动整个 AssetScreen（依赖存储与加密状态，重且脆弱），
/// 而是按卡片里同样的两栏结构组装最小 widget，钉住三件事：
/// 版式与净资产一致（上标题下数字）、算不出数时显示占位、隐藏时同步隐藏。
void main() {
  /// 模拟看板的两栏：左净资产、右可使用，规格完全对称
  Widget buildCard({
    double? total,
    double monthlyCost = 3000,
    bool hideNumbers = false,
    VoidCallback? onTapDot,
  }) {
    final days = UsableDays.compute(
      total: total,
      monthlyCost: monthlyCost,
      daysPerMonth: 30,
      annualRate: 3,
      inflationRate: 2,
    );
    final hasValue = days != null && days > 0;
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 20,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: const Text('净资产',
                              style: TextStyle(fontSize: 13)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(hideNumbers ? '****' : '¥100,000',
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 20,
                        child: Row(
                        children: [
                          const Text('可使用',
                              style: TextStyle(fontSize: 13)),
                          const SizedBox(width: 4),
                          GestureDetector(
                            key: const ValueKey('usable-days-settings'),
                            onTap: onTapDot,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              width: 16,
                              height: 16,
                              alignment: Alignment.center,
                              child: const Text('!'),
                            ),
                          ),
                        ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      hasValue
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  hideNumbers ? '****' : UsableDays.format(days),
                                  key: const ValueKey('usable-days-number'),
                                  style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w700),
                                ),
                                if (!hideNumbers)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 2),
                                    child: Text('天',
                                        style: TextStyle(fontSize: 14)),
                                  ),
                              ],
                            )
                          : const Text('—',
                              key: ValueKey('usable-days-placeholder'),
                              style: TextStyle(fontSize: 32)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('标题是「可使用」，数字在下方（与净资产同版式）', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    final titleRect = tester.getRect(find.text('可使用'));
    final numRect = tester.getRect(find.byKey(const ValueKey('usable-days-number')));
    final netTitleRect = tester.getRect(find.text('净资产'));
    final netNumRect = tester.getRect(find.text('¥100,000'));

    // 标题在数字上方
    expect(titleRect.bottom, lessThanOrEqualTo(numRect.top));
    // 与净资产同版式：两栏起点一致（标题行同为 Row 首行，
    // 1~2px 的差异来自不同文本的字体度量，视觉上看不出）
    expect(titleRect.top, closeTo(netTitleRect.top, 2.0));
    // 数字行起点一致（同为标题下方 4px）
    expect(numRect.top, closeTo(netNumRect.top, 0.5));
    // 字号一致：比较实际 FontSize，而不是文本框高度 ——
    // 「¥」在测试字体里会回退，把行盒撑高，高度对比没有意义
    final numStyle = tester
        .widget<Text>(find.byKey(const ValueKey('usable-days-number')))
        .style!;
    final netStyle = tester.widget<Text>(find.text('¥100,000')).style!;
    expect(numStyle.fontSize, netStyle.fontSize, reason: '数字字号应与净资产一致');
    expect(numStyle.fontWeight, netStyle.fontWeight);
  });

  testWidgets('两栏各占一半：数字左缘在卡片中线右侧', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    // 卡片本身宽 360（见 buildCard），两栏各占一半 —— 用卡片宽度判中线，
    // 不能用屏幕宽度：外层 Scaffold 在测试里是整屏
    const cardW = 360.0;
    final netRect = tester.getRect(find.text('净资产'));
    final useRect = tester.getRect(find.text('可使用'));

    expect(useRect.left, greaterThan(netRect.right), reason: '右栏应在左栏右侧');
    expect(useRect.left, greaterThan(cardW / 2 - 60),
        reason: '右栏应落在卡片右半部分');
  });

  testWidgets('算不出时显示占位 —，圈叹号仍在', (tester) async {
    await tester.pumpWidget(buildCard(total: null, monthlyCost: 3000));
    await tester.pump();

    expect(find.byKey(const ValueKey('usable-days-placeholder')), findsOneWidget);
    expect(find.byKey(const ValueKey('usable-days-settings')), findsOneWidget);
  });

  testWidgets('每月预算为 0 也算不出，同样显示占位', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000, monthlyCost: 0));
    await tester.pump();

    expect(find.byKey(const ValueKey('usable-days-placeholder')), findsOneWidget);
  });

  testWidgets('隐藏金额时数字变 ****，且「天」小字一起消失', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000, hideNumbers: true));
    await tester.pump();

    expect(find.text('****'), findsNWidgets(2), reason: '净资产与可使用都要隐藏');
    expect(find.text('天'), findsNothing);
  });

  testWidgets('点圈叹号会触发回调', (tester) async {
    var tapped = false;
    await tester.pumpWidget(buildCard(
      total: 100000,
      onTapDot: () => tapped = true,
    ));
    await tester.tap(find.byKey(const ValueKey('usable-days-settings')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
