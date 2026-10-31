import 'package:diary_app/widgets/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 取 [Pressable] 当前实际缩放值。
///
/// 只认 Pressable 内部那层 Transform（MaterialApp 自身也会插入带旋转的
/// Transform，直接取最后一个会拿到 √2/2 这类无关数值）。
double currentScale(WidgetTester tester) {
  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(Pressable),
      matching: find.byType(Transform),
    ),
  );
  return transform.transform.storage[0];
}

void main() {
  group('Pressable 缩放曲线', () {
    test('落定时为 1.0', () {
      expect(Pressable.scaleFor(0, 0.90), 1.0);
    });

    test('按到底时为 pressedScale（90%）', () {
      expect(Pressable.scaleFor(-1, 0.90), closeTo(0.90, 1e-9));
    });

    test('按压中段从 90% 线性回升到 100%', () {
      expect(Pressable.scaleFor(-0.5, 0.90), closeTo(0.95, 1e-9));
    });

    test('过冲区放大且不超过 102%', () {
      final peak = Pressable.scaleFor(Pressable.kCurveOvershoot, 0.90);
      expect(peak, closeTo(1.0 + Pressable.kOvershoot, 1e-9));
      // 超出归一化基准也不会超过 kOvershoot
      expect(Pressable.scaleFor(1.0, 0.90),
          closeTo(1.0 + Pressable.kOvershoot, 1e-9));
    });

    test('回弹曲线确实会越过 0（产生过冲）', () {
      // 控制器从 -1 走到 0：x = -1 + curve(t)
      const curve = Pressable.kReleaseCurve;
      var maxX = -1.0;
      var sawPast0 = false;
      for (var i = 0; i <= 200; i++) {
        final x = -1 + curve.transform(i / 200);
        if (x > maxX) maxX = x;
        if (x > 0) sawPast0 = true;
      }
      expect(sawPast0, isTrue, reason: '曲线必须让值越过 0，否则没有回弹');
      expect(maxX, greaterThan(0.0));
      expect(maxX, lessThan(0.2), reason: '过冲幅度应温和，不应夸张');
    });
  });

  group('Pressable 交互', () {
    testWidgets('按下缩到 90%，松手回到 100%', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(child: SizedBox(width: 100, height: 40)),
          ),
        ),
      ));

      expect(currentScale(tester), closeTo(1.0, 1e-6));

      final g = await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(currentScale(tester), closeTo(0.90, 1e-3),
          reason: '按下后应缩到 90%');

      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(currentScale(tester), closeTo(1.0, 1e-3),
          reason: '松手后应回到 100%');
    });

    testWidgets('松手回弹途中会放大到超过原尺寸', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(child: SizedBox(width: 100, height: 40)),
          ),
        ),
      ));

      final g = await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      await g.up();

      var peak = 0.0;
      // 1ms 步进采样整个回弹过程，避免跳帧错过过冲峰值
      for (var i = 0; i < 420; i++) {
        await tester.pump(const Duration(milliseconds: 1));
        final s = currentScale(tester);
        if (s > peak) peak = s;
      }
      expect(peak, greaterThan(1.0), reason: '回弹应先放大到略超原尺寸');
      expect(peak, lessThanOrEqualTo(1.0 + Pressable.kOvershoot + 1e-6));

      await tester.pump(const Duration(milliseconds: 200));
      expect(currentScale(tester), closeTo(1.0, 1e-3));
    });

    testWidgets('enabled = false 时不缩放', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              enabled: false,
              child: SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      ));

      final g = await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
      await tester.pump(const Duration(milliseconds: 120));
      expect(currentScale(tester), closeTo(1.0, 1e-6));
      await g.up();
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('external 模式由 PressableHandle 驱动', (tester) async {
      final handle = PressableHandle();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              external: true,
              handle: handle,
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      ));

      // external 不自己监听指针：真实按下不改变缩放
      final g = await tester.startGesture(tester.getCenter(find.byType(SizedBox)));
      await tester.pump(const Duration(milliseconds: 120));
      expect(currentScale(tester), closeTo(1.0, 1e-6),
          reason: 'external 模式不监听指针，按下不应触发');
      await g.up();
      await tester.pump(const Duration(milliseconds: 500));

      handle.press();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(currentScale(tester), closeTo(0.90, 1e-3),
          reason: 'handle.press() 应触发收缩');

      handle.release();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(currentScale(tester), closeTo(1.0, 1e-3),
          reason: 'handle.release() 应回到 100%');
    });

    testWidgets('包裹按钮不影响按钮本身的点击', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              child: TextButton(
                onPressed: () => tapped++,
                child: const Text('确认'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('确认'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tapped, 1, reason: 'Listener 不参与手势竞技场，不应吞掉点击');
    });
  });
}
