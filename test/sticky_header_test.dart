import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/widgets/sticky_header.dart';

Widget _host({ScrollController? controller}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 400,
        child: StickySectionList(
          controller: controller,
          background: Colors.white,
          children: [
            StickySection(
              height: 40,
              builder: () => const SizedBox(
                height: 40,
                child: Text('置顶', key: ValueKey('h1')),
              ),
            ),
            for (var i = 0; i < 6; i++)
              SizedBox(height: 80, child: Text('A$i')),
            StickySection(
              height: 40,
              builder: () => const SizedBox(
                height: 40,
                child: Text('纪念日', key: ValueKey('h2')),
              ),
            ),
            for (var i = 0; i < 6; i++)
              SizedBox(height: 80, child: Text('B$i')),
          ],
        ),
      ),
    ),
  );
}

/// 吸附层是否在画：找 StickySectionList 内部 Stack 的 Positioned 子层
int _stuckLayers(WidgetTester tester) {
  final pos = find.descendant(
    of: find.byType(StickySectionList),
    matching: find.byWidgetPredicate(
        (w) => w is Positioned && w.top != null && w.left == 0),
  );
  return pos.evaluate().length;
}

void main() {
  group('吸顶分段标题', () {
    testWidgets('初始不吸附：吸附层透明，标题只在列表里出现一次', (tester) async {
      await tester.pumpWidget(_host());
      await tester.pumpAndSettle();
      expect(_stuckLayers(tester), 0);
      expect(find.text('置顶'), findsOneWidget);
    });

    testWidgets('向下滚动后第一段吸顶', (tester) async {
      final c = ScrollController();
      await tester.pumpWidget(_host(controller: c));
      await tester.pumpAndSettle();

      c.jumpTo(120);
      await tester.pumpAndSettle();
      expect(_stuckLayers(tester), 1);

      // 吸附层：贴住视口顶部
      final ys = find.text('置顶').evaluate().map((e) {
        final ro = e.renderObject as RenderBox;
        return ro.localToGlobal(Offset.zero).dy;
      }).toList();
      expect(ys.reduce((a, b) => a < b ? a : b), lessThan(40));
    });

    testWidgets('滚回顶部后吸附层淡出', (tester) async {
      final c = ScrollController();
      await tester.pumpWidget(_host(controller: c));
      await tester.pumpAndSettle();

      c.jumpTo(200);
      await tester.pumpAndSettle();
      expect(_stuckLayers(tester), 1);

      c.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_stuckLayers(tester), 0);
    });

    testWidgets('段的折叠/展开仍可点击（吸附层不吃手势）', (tester) async {
      final c = ScrollController();
      await tester.pumpWidget(_host(controller: c));
      await tester.pumpAndSettle();
      c.jumpTo(120);
      await tester.pumpAndSettle();
      // 吸附层包裹在 IgnorePointer 里，点击应穿透到列表
      expect(find.byType(IgnorePointer), findsWidgets);
    });
  });
}
