import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/widgets/wheel_picker.dart';

void main() {
  testWidgets('滚轮日期选择器：弹出 CupertinoDatePicker 并返回日期', (tester) async {
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

    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.year, 2024);
    expect(result!.month, 3);
    expect(result!.day, 15);
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
}
