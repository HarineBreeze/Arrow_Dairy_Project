import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/widgets/save_done_button.dart';

Widget _host({
  required VoidCallback? onTap,
  required VoidCallback onDone,
  double width = 300,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SaveDoneButton(
            color: const Color(0xFF3B6FE0),
            onTap: onTap,
            onDone: onDone,
          ),
        ),
      ),
    ),
  );
}

/// 取 SaveDoneButton 内部按下标的 Material 宽度（收缩的进度指示）
double _materialWidth(WidgetTester tester) {
  final m = find.descendant(
    of: find.byType(SaveDoneButton),
    matching: find.byType(Material),
  );
  return tester.getSize(m.first).width;
}

void main() {
  group('完成按钮动画', () {
    testWidgets('初始为整条宽度，显示「完成」', (tester) async {
      await tester.pumpWidget(_host(onTap: () {}, onDone: () {}));
      expect(find.text('完成'), findsOneWidget);
      expect(_materialWidth(tester), closeTo(300, 1));
    });

    testWidgets('点击后收缩成圆形：宽高相等且等于按钮高度', (tester) async {
      await tester.pumpWidget(_host(onTap: () {}, onDone: () {}));
      await tester.tap(find.byType(SaveDoneButton));
      await tester.pump();
      // 点击后先走「收缩 + 描边」阶段（约 540ms），此处停在收缩末端
      await tester.pump(const Duration(milliseconds: 560));

      final m = find.descendant(
        of: find.byType(SaveDoneButton),
        matching: find.byType(Material),
      );
      final size = tester.getSize(m.first);
      expect(size.width, closeTo(size.height, 0.5));
      expect(size.width, closeTo(48, 1)); // height 默认 48
    });

    testWidgets('落盘完成后 finish() 才回调 onDone', (tester) async {
      var done = 0;
      await tester.pumpWidget(_host(onTap: () {}, onDone: () => done++));
      await tester.tap(find.byType(SaveDoneButton));
      await tester.pump(const Duration(milliseconds: 560));
      // 点击后、finish 前还不该返回
      expect(done, 0);

      final key = tester.state<SaveDoneButtonState>(find.byType(SaveDoneButton));
      key.finish();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(done, 0); // 还在打勾/粒子/停留中

      await tester.pump(const Duration(milliseconds: 800));
      expect(done, 1);
    });

    testWidgets('连点只播放一次，不会重复调用 onDone', (tester) async {
      var done = 0;
      var taps = 0;
      await tester.pumpWidget(_host(onTap: () => taps++, onDone: () => done++));
      await tester.tap(find.byType(SaveDoneButton));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(SaveDoneButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      // 第二次点击被忽略：收缩期间 onTap 仍处于禁用态
      expect(taps, 1);

      final key = tester.state<SaveDoneButtonState>(find.byType(SaveDoneButton));
      key.finish();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(done, 1);
    });

    testWidgets('onTap 为 null 时点击不报错也不播放', (tester) async {
      var done = 0;
      await tester.pumpWidget(_host(onTap: null, onDone: () => done++));
      await tester.tap(find.byType(SaveDoneButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(done, 0);
      expect(find.text('完成'), findsOneWidget);
    });
  });
}
