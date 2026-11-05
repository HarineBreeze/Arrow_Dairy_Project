import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/utils/usable_days.dart';

/// 看板卡片上「净资产 / 可使用 x 天」两栏的展示契约。
///
/// 不启动整个 AssetScreen（依赖存储与加密状态，重且脆弱），
/// 而是按卡片里同样的两栏结构组装最小 widget，钉住四件事：
/// 标题与数字**在同一行**、两栏基线对齐、算不出数时显示占位、隐藏时同步隐藏。
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
              // 左栏：标题 + 金额同一行
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text('净资产', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    const SizedBox(width: 19, height: 19),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          hideNumbers ? '****' : '¥100,000',
                          maxLines: 1,
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 右栏：「可使用」+「x 天」同一行
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    const Text('可使用', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: hasValue
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    hideNumbers
                                        ? '****'
                                        : UsableDays.format(days),
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
                      ),
                    ),
                    GestureDetector(
                      key: const ValueKey('usable-days-settings'),
                      onTap: onTapDot,
                      behavior: HitTestBehavior.opaque,
                      child: const SizedBox(
                        width: 16,
                        height: 16,
                        child: Center(child: Text('!')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('标题与数字在同一行：数字不在标题下方', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    final titleRect = tester.getRect(find.text('可使用'));
    final numRect =
        tester.getRect(find.byKey(const ValueKey('usable-days-number')));

    // 关键契约：数字不再位于标题下方，而是同一行的右侧
    expect(numRect.left, greaterThan(titleRect.right),
        reason: '数字应在标题右侧，而不是换行到下方');
    // 垂直方向上两者高度重叠 —— 同一行才可能成立
    final overlapTop = titleRect.top > numRect.top ? titleRect.top : numRect.top;
    final overlapBottom = titleRect.bottom < numRect.bottom
        ? titleRect.bottom
        : numRect.bottom;
    expect(overlapBottom - overlapTop, greaterThan(0),
        reason: '标题与数字应在同一水平带上');
  });

  testWidgets('两栏基线一致：净资产金额与可使用天数在同一条线上', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    final netNumRect = tester.getRect(find.text('¥100,000'));
    final useNumRect =
        tester.getRect(find.byKey(const ValueKey('usable-days-number')));

    // 两栏都走 baseline 对齐，数字底缘应该几乎重合
    expect((netNumRect.bottom - useNumRect.bottom).abs(), lessThan(3.0));
  });

  testWidgets('标题字号一致，且都是小字（不跟数字同字号）', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    final useTitle = tester.widget<Text>(find.text('可使用')).style!;
    final netTitle = tester.widget<Text>(find.text('净资产')).style!;
    final numStyle = tester
        .widget<Text>(find.byKey(const ValueKey('usable-days-number')))
        .style!;

    expect(useTitle.fontSize, netTitle.fontSize);
    expect(useTitle.fontSize, lessThan(numStyle.fontSize!));
  });

  testWidgets('数字字号与净资产金额一致', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    final numStyle = tester
        .widget<Text>(find.byKey(const ValueKey('usable-days-number')))
        .style!;
    final netStyle = tester.widget<Text>(find.text('¥100,000')).style!;

    expect(numStyle.fontSize, netStyle.fontSize);
    expect(numStyle.fontWeight, netStyle.fontWeight);
  });

  testWidgets('两栏各占一半：右栏标题在卡片中线右侧', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

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

    expect(
        find.byKey(const ValueKey('usable-days-placeholder')), findsOneWidget);
    expect(find.byKey(const ValueKey('usable-days-settings')), findsOneWidget);
  });

  testWidgets('每月预算为 0 也算不出，同样显示占位', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000, monthlyCost: 0));
    await tester.pump();

    expect(
        find.byKey(const ValueKey('usable-days-placeholder')), findsOneWidget);
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
