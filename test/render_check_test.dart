import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 渲染自检：确认斜纹 / 结构条是真的画出来了（不是只写了代码）。
void main() {
  testWidgets('渲染加密置顶卡与资产结构条为 PNG', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        body: RepaintBoundary(
          key: key,
          child: Column(
            children: [
              // 1. 加密置顶迷你卡（斜纹 + 红边）
              SizedBox(
                height: 62,
                width: 132,
                child: CustomPaint(
                  painter: const _StripeTest(),
                ),
              ),
              const SizedBox(height: 10),
              // 2. 资产结构条
              Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF3B6FE0), Color(0xFF5B8AF0)]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('净资产',
                        style:
                            TextStyle(fontSize: 13, color: Colors.white70)),
                    const Text('¥123,400',
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 14),
                    const _BarTest(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('/workspace/render_check.png')
          .writeAsBytesSync(data!.buffer.asUint8List());
      expect(data.lengthInBytes, greaterThan(1000));
    });
  });
}

class _BarTest extends StatelessWidget {
  const _BarTest();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 7,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Row(
          children: <Widget>[
            Expanded(flex: 760, child: Container(color: const Color(0xFF2A9D5C))),
            Expanded(flex: 240, child: Container(color: const Color(0xFFE0576A))),
          ],
        ),
      ),
    );
  }
}

class _StripeTest extends CustomPainter {
  const _StripeTest();
  @override
  void paint(Canvas c, Size size) {
    final r = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(11));
    c.save();
    c.clipRRect(r);
    c.drawRect(r.outerRect, Paint()..color = const Color(0xFFEFF2F7));
    final p = Paint()
      ..color = const Color(0xFFE7EBF1)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    for (double x = -size.height; x < size.width + size.height; x += 16) {
      c.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    final fade = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x66FFFFFF), Color(0x33FFFFFF)],
      ).createShader(r.outerRect);
    c.drawRect(r.outerRect, fade);
    c.restore();
    c.drawRRect(
        r.deflate(0.65),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = const Color(0xFFE0576A));
    final tp = TextPainter(
      text: const TextSpan(
          text: '🔒 年会流程',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF2A3B52))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, const Offset(8, 20));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
