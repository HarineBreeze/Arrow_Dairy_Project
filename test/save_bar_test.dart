import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/widgets/save_bar.dart';
import 'package:diary_app/widgets/save_done_button.dart';

Widget _host({
  required GlobalKey<SaveDoneButtonState> key,
  VoidCallback? onCancel,
  VoidCallback? onSave,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SaveBar(
          saveKey: key,
          color: const Color(0xFF3B6FE0),
          onCancel: onCancel,
          validate: () => null,
          onSave: onSave,
          onDone: () {},
        ),
      ),
    ),
  );
}

double _cancelOpacity(WidgetTester tester) {
  final op = find.ancestor(
      of: find.text('取消'), matching: find.byType(Opacity));
  return tester.widget<Opacity>(op.first).opacity;
}

void main() {
  testWidgets('未点击时取消与完成左右分布，取消可见且可点', (tester) async {
    final key = GlobalKey<SaveDoneButtonState>();
    var canceled = 0;
    await tester.pumpWidget(_host(key: key, onCancel: () => canceled++));
    await tester.pump();

    expect(find.text('取消'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(_cancelOpacity(tester), 1.0);

    // 点击取消应触发回调（未被完成按钮遮挡）
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(canceled, 1);
  });

  testWidgets('点击完成后取消淡出、完成进入动画', (tester) async {
    final key = GlobalKey<SaveDoneButtonState>();
    var saved = 0;
    await tester.pumpWidget(_host(key: key, onSave: () => saved++));
    await tester.pump();

    expect(_cancelOpacity(tester), 1.0);

    await tester.tap(find.text('完成'));
    await tester.pump();
    expect(saved, 1);

    // 收缩阶段推进（collapse 约 300ms），取消应逐渐淡出
    await tester.pump(const Duration(milliseconds: 150));
    expect(_cancelOpacity(tester), lessThan(1.0));

    await tester.pump(const Duration(milliseconds: 250));
    expect(_cancelOpacity(tester), 0.0);
  });
}
