import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/widgets/format_toolbar.dart';

/// 模拟编辑页的底部结构：
///   Column( Expanded(正文), 工具栏 )  +  bottomNavigationBar(保存栏)
///
/// 键盘弹出时 Scaffold 会把 body 的高度收缩掉 `viewInsets.bottom`，
/// 工具栏作为 body 的最后一个子项，自然贴在这段收缩区的顶部 = 键盘上方。
class _Host extends StatelessWidget {
  final double keyboardHeight;

  const _Host({this.keyboardHeight = 300});

  @override
  Widget build(BuildContext context) {
    // MediaQuery 必须放在 MaterialApp **里面**：MaterialApp 会用
    // View / MediaQuery.fromView 再包一层，放在外面注入的 insets 会被覆盖掉。
    return MaterialApp(
      home: Builder(
        builder: (outer) => MediaQuery(
          data: MediaQuery.of(outer).copyWith(
            size: const Size(800, 600),
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          child: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Container(color: const Color(0xFFF3F6FB)),
                ),
                FormatToolbar(
                  controller: TextEditingController(),
                  formats: const [],
                  onChanged: (_) {},
                  onClose: () {},
                  onInsertTodo: () {},
                ),
              ],
            ),
            bottomNavigationBar: const SizedBox(height: 72),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('工具栏作为正文区最后一项：底边贴着正文区底边（= 键盘顶部）',
      (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(FormatToolbar));
    // 600 高屏幕 - 300 键盘 = 300 的可用区，工具栏贴着这块区的底边
    expect(bar.bottom, closeTo(300, 1));
    expect(bar.height, greaterThan(30));
  });

  testWidgets('键盘越高，工具栏越靠上（实时跟随）', (tester) async {
    await tester.pumpWidget(const _Host(keyboardHeight: 100));
    await tester.pumpAndSettle();
    final low = tester.getRect(find.byType(FormatToolbar)).bottom;

    await tester.pumpWidget(const _Host(keyboardHeight: 400));
    await tester.pumpAndSettle();
    final high = tester.getRect(find.byType(FormatToolbar)).bottom;

    expect(low, closeTo(500, 1));
    expect(high, closeTo(200, 1));
    expect(high, lessThan(low));
  });

  testWidgets('格式栏提供待办插入入口', (tester) async {
    var inserted = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FormatToolbar(
          controller: TextEditingController(text: '一段正文'),
          formats: const [],
          onChanged: (_) {},
          onClose: () {},
          onInsertTodo: () => inserted++,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.check_box_outlined));
    await tester.pumpAndSettle();
    expect(inserted, 1);
  });

  testWidgets('工具栏横向撑满，不与保存栏重叠', (tester) async {
    await tester.pumpWidget(const _Host());
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(FormatToolbar));
    expect(bar.width, 800);
    // 保存栏从 300 开始，工具栏底边不超过它
    expect(bar.bottom, lessThanOrEqualTo(300));
  });
}
