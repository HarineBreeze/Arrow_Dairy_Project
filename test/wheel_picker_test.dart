import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/widgets/wheel_picker.dart';

/// 找到包含某个标签的那一列滚轮
Finder _columnWith(String label) => find.ancestor(
      of: find.text(label, skipOffstage: false),
      matching: find.byType(CupertinoPicker),
    );

void main() {
  testWidgets('滚轮日期选择器：年/月/日三列，单位全中文', (tester) async {
    DateTime? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showWheelDatePicker(
                    context, initial: DateTime(2024, 3, 15));
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 三列滚轮
    expect(find.byType(CupertinoPicker), findsNWidgets(3));
    // 不再使用 CupertinoDatePicker（它会输出英文月名）
    expect(find.byType(CupertinoDatePicker), findsNothing);
    // 单位中文
    expect(find.text('年', skipOffstage: false), findsWidgets);
    expect(find.text('月', skipOffstage: false), findsWidgets);
    expect(find.text('日', skipOffstage: false), findsWidgets);
    // 英文月份名不应出现
    for (final en in ['March', 'Mar', 'September', 'Sep', 'Jan']) {
      expect(find.text(en, skipOffstage: false), findsNothing);
    }

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.year, 2024);
    expect(result!.month, 3);
    expect(result!.day, 15);
  });

  testWidgets('滚轮日期选择器：列顺序固定为 年 → 月 → 日', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  showWheelDatePicker(context, initial: DateTime(2024, 3, 15)),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final yearX = tester.getCenter(_columnWith('2024').first).dx;
    final monthX = tester.getCenter(_columnWith('3').first).dx;
    final dayX = tester.getCenter(_columnWith('15').first).dx;
    expect(yearX, lessThan(monthX));
    expect(monthX, lessThan(dayX));
  });

  testWidgets('滚轮时间选择器：弹出 CupertinoTimerPicker 并返回时间', (tester) async {
    TimeOfDay? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showWheelTimePicker(
                    context, initial: const TimeOfDay(hour: 9, minute: 30));
              },
              child: const Text('打开时间'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开时间'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoTimerPicker), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.hour, 9);
    expect(result!.minute, 30);
  });

  testWidgets('滚轮日期+时间：日期段同样是中文三列', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showWheelDateTimePicker(context,
                  initial: DateTime(2025, 1, 8, 14, 30)),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPicker), findsWidgets);
    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(find.text('年', skipOffstage: false), findsWidgets);
    expect(find.text('日', skipOffstage: false), findsWidgets);
  });
}
