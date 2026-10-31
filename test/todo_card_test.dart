import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/widgets/todo_card.dart';

Widget _host(String content, {ValueChanged<String>? onToggle}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TodoCard(
              content: content,
              itemNames: const {'牛奶'},
              onToggle: onToggle,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('列出全部待办，并显示完成进度', (tester) async {
    await tester.pumpWidget(_host('导语\n[ ] 买牛奶\n[x] 交电费\n[ ] 写周报'));

    expect(find.text('待办清单'), findsOneWidget);
    expect(find.text('买牛奶'), findsOneWidget);
    expect(find.text('交电费'), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('点按一行 → 回调新的正文，且只翻转该行', (tester) async {
    String? got;
    const src = '导语\n[ ] 买牛奶\n[ ] 写周报';
    await tester.pumpWidget(_host(src, onToggle: (v) => got = v));

    await tester.tap(find.text('买牛奶'));
    await tester.pumpAndSettle();

    expect(got, '导语\n[x] 买牛奶\n[ ] 写周报');
  });

  testWidgets('没有待办时整块不渲染', (tester) async {
    await tester.pumpWidget(_host('只有一段普通正文'));
    expect(find.text('待办清单'), findsNothing);
    expect(find.byType(TodoCard), findsOneWidget); // 组件在，但输出空
  });

  testWidgets('勾选后进度条前进', (tester) async {
    await tester.pumpWidget(_host('[ ] A\n[ ] B', onToggle: (_) {}));
    expect(find.text('0 / 2'), findsOneWidget);

    // 模拟勾选后重新渲染（浏览页是乐观更新，直接换 content）
    await tester.pumpWidget(_host('[x] A\n[ ] B', onToggle: (_) {}));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
  });
}
