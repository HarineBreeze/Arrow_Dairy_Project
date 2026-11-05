import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/utils/usable_days.dart';

/// 看板卡片上「净资产 / 可使用 x 天」两栏的展示契约。
///
/// 不启动整个 AssetScreen（依赖存储与加密状态，重且脆弱），
/// 而是按卡片里同样的两栏结构组装最小 widget，钉住这些契约：
/// - 左右两栏并排，各自「上标题、下数字」
/// - 两个标题在同一行，两个数字在同一行
/// - 算不出数时显示占位、隐藏时同步隐藏、点圈叹号能进设置
void main() {
  /// 模拟看板的两栏：左净资产、右可使用，结构完全对称
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

    // 标题行锁 18px：13px 文字行盒约 18px，锁 16px 会溢出压到数字上；
    // 18px 同时保证两栏高度一致（图标高度不同也不会错行）。
    Widget titleRow(String title, {Widget? trailing}) => SizedBox(
          height: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(title, style: const TextStyle(fontSize: 13)),
              if (trailing != null) trailing,
            ],
          ),
        );

    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左栏：标题行 + 金额行
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleRow(
                      '净资产',
                      trailing: const SizedBox(
                        width: 18,
                        height: 18,
                        child: Center(
                          child: Icon(Icons.visibility_outlined, size: 15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hideNumbers ? '****' : '¥100,000',
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 右栏：标题行 + 天数行
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleRow(
                      '可使用',
                      trailing: GestureDetector(
                        key: const ValueKey('usable-days-settings'),
                        onTap: onTapDot,
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: Center(child: Text('!')),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: hasValue
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

  testWidgets('两个标题在同一行，两个数字在下一行', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    final netTitle = tester.getRect(find.text('净资产'));
    final useTitle = tester.getRect(find.text('可使用'));
    final netNum = tester.getRect(find.text('¥100,000'));
    final useNum =
        tester.getRect(find.byKey(const ValueKey('usable-days-number')));

    // 标题行：两个标题齐平。允许 2px 内的差异 —— 右栏标题后面挂着
    // 16px 的圈叹号、左栏挂 15px 的眼睛，两者的字体度量与盒子高度
    // 不完全相同，1~2px 的浮动在视觉上看不出。
    expect((netTitle.top - useTitle.top).abs(), lessThan(2.0),
        reason: '两个标题应在同一行');
    // 数字行：两个数字齐平
    expect((netNum.top - useNum.top).abs(), lessThan(2.0),
        reason: '两个数字应在同一行');
    // 标题在上、数字在下
    expect(netNum.top, greaterThan(netTitle.bottom));
    expect(useNum.top, greaterThan(useTitle.bottom));
  });

  testWidgets('数字不遮挡标题：数字上缘在标题下缘之下', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    final useTitle = tester.getRect(find.text('可使用'));
    final useNum =
        tester.getRect(find.byKey(const ValueKey('usable-days-number')));
    final netTitle = tester.getRect(find.text('净资产'));
    final netNum = tester.getRect(find.text('¥100,000'));

    // 两栏都必须满足：数字完整落在标题下方，不能有一点重叠。
    // 之前标题行被硬锁 16px、13px 文字行盒约 18px，文字溢出把数字
    // 顶到了标题上 —— 这条断言就是防止那种情况复发。
    expect(useNum.top, greaterThanOrEqualTo(useTitle.bottom),
        reason: '数字上缘不能高于标题下缘');
    expect(netNum.top, greaterThanOrEqualTo(netTitle.bottom),
        reason: '净资产金额同样不能压到标题');
  });

  testWidgets('右栏在左侧标题行的右边（两栏并排，不是上下堆叠）', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    final netTitle = tester.getRect(find.text('净资产'));
    final useTitle = tester.getRect(find.text('可使用'));

    expect(useTitle.left, greaterThan(netTitle.right),
        reason: '「可使用」应在「净资产」右侧');
  });

  testWidgets('数字与标题左对齐，不缩进', (tester) async {
    await tester.pumpWidget(buildCard(total: 100000));
    await tester.pump();

    final useTitle = tester.getRect(find.text('可使用'));
    final useNum =
        tester.getRect(find.byKey(const ValueKey('usable-days-number')));

    expect((useNum.left - useTitle.left).abs(), lessThan(2.0),
        reason: '数字应与标题左缘对齐');
  });

  testWidgets('标题字号小于数字字号，两栏标题字号一致', (tester) async {
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
