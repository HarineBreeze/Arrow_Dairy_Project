import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/utils/usable_days.dart';

/// 看板卡片上「可使用 x 天」那一行的展示契约。
///
/// 这里不启动整个 AssetScreen（它依赖存储与加密状态，跑起来很重且脆弱），
/// 而是按卡片里同样的规则组装一个最小 widget，钉住三条行为：
/// 总资产为空不显示、月消费为 0 不显示、参数齐全时显示天数与圈叹号。
void main() {
  Widget buildRow({
    double? total,
    double monthlyCost = 0,
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
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (days != null && days > 0) ...[
                Text(
                  hideNumbers
                      ? '可使用 ****天'
                      : '可使用 ${UsableDays.format(days)}',
                  key: const ValueKey('usable-days-text'),
                ),
                const SizedBox(width: 2),
              ],
              GestureDetector(
                key: const ValueKey('usable-days-settings'),
                onTap: onTapDot,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  child: const Text('!'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('参数齐全时显示「可使用」与天数', (tester) async {
    await tester.pumpWidget(buildRow(total: 100000, monthlyCost: 5000));
    await tester.pump();

    expect(find.text('可使用 45.1 万天'), findsOneWidget);
    expect(find.text('!'), findsOneWidget);
  });

  testWidgets('总资产为空：不显示天数，但圈叹号仍在（否则用户找不到入口）',
      (tester) async {
    await tester.pumpWidget(buildRow(total: null, monthlyCost: 5000));
    await tester.pump();

    expect(find.byKey(const ValueKey('usable-days-text')), findsNothing);
    expect(find.byKey(const ValueKey('usable-days-settings')), findsOneWidget);
  });

  testWidgets('月消费为 0：不显示天数', (tester) async {
    await tester.pumpWidget(buildRow(total: 100000, monthlyCost: 0));
    await tester.pump();

    expect(find.byKey(const ValueKey('usable-days-text')), findsNothing);
    expect(find.byKey(const ValueKey('usable-days-settings')), findsOneWidget);
  });

  testWidgets('隐藏金额时天数也一起隐藏', (tester) async {
    await tester.pumpWidget(
        buildRow(total: 100000, monthlyCost: 5000, hideNumbers: true));
    await tester.pump();

    expect(find.text('可使用 ****天'), findsOneWidget);
  });

  testWidgets('点圈叹号会触发回调', (tester) async {
    var tapped = false;
    await tester.pumpWidget(buildRow(
      total: 100000,
      monthlyCost: 5000,
      onTapDot: () => tapped = true,
    ));
    await tester.tap(find.byKey(const ValueKey('usable-days-settings')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
