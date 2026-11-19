import 'package:flutter/material.dart';

import '../utils/stationery.dart';

/// 「VIP 信纸」本地渲染器。
///
/// 信纸全部用 CustomPainter + 渐变绘制，零图片、零网络、
/// 文字内容不离开设备。可作为整页正文底纹，也可作为抽屉里的缩略图。
class StationeryPaper extends StatelessWidget {
  final String styleId;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// 是否绘制横纹。抹茶横纹的横线需要与正文文字行对齐，因此整页大
  /// 底纹应传 false（只画底色），由包住正文文字的内层信纸负责画线。
  final bool showRuling;

  /// 抹茶横纹的横线间距 = 正文行高（15 * 1.8）。
  static const double ruledLineSpacing = 27;

  const StationeryPaper({
    Key? key,
    required this.styleId,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.showRuling = true,
  }) : super(key: key);

  /// 正文文字颜色：星夜来信为浅色，其余为深绿。
  static Color textColor(String styleId) => styleId == 'night'
      ? const Color(0xFFE8F3EC)
      : const Color(0xFF24382F);

  /// 抽屉缩略图（44×56 的迷你信纸）。
  static Widget swatch(String styleId, {bool selected = false}) {
    return Container(
      width: 52,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xFF3E8E6D) : const Color(0xFFE2EBE5),
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: StationeryPaper(
        styleId: styleId,
        padding: EdgeInsets.zero,
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: _gradient(styleId),
        color: _flatColor(styleId),
        borderRadius: BorderRadius.circular(12),
        border: _border(styleId),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // 横线起点 = 内边距顶部（正文首行行框的上缘），
              // 间距 = 正文行高，保证每行文字都落在两条横线之间
              child: CustomPaint(
                painter: _StationeryPainter(
                  styleId,
                  lineTop: showRuling
                      ? padding.resolve(TextDirection.ltr).top
                      : -1,
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }

  BoxBorder? _border(String id) {
    switch (id) {
      case 'grid':
        return Border.all(color: const Color(0xFFCDE6D8), width: 6);
      case 'kraft':
        return Border.all(color: const Color(0xFFD8BF94), width: 2);
      default:
        return null;
    }
  }

  LinearGradient? _gradient(String id) {
    switch (id) {
      case 'lined':
        return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFBFDFB), Color(0xFFEFF7F1)]);
      case 'night':
        return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1C3B32), Color(0xFF122A24)]);
      case 'kraft':
        return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0E2C6), Color(0xFFE6D3AE)]);
      case 'grid':
        return const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FCF9), Color(0xFFF4FAF6)]);
      default:
        return null;
    }
  }

  Color? _flatColor(String id) => null;
}

class _StationeryPainter extends CustomPainter {
  final String id;

  /// 抹茶横纹的首条横线 y 坐标（= 正文首行行框上缘）；< 0 表示不画线。
  final double lineTop;
  _StationeryPainter(this.id, {this.lineTop = -1});

  @override
  void paint(Canvas canvas, Size size) {
    switch (id) {
      case 'lined':
        _paintLined(canvas, size);
        break;
      case 'grid':
        _paintGrid(canvas, size);
        break;
      case 'night':
        _paintNight(canvas, size);
        break;
      case 'kraft':
        _paintKraft(canvas, size);
        break;
    }
  }

  /// 抹茶横纹：只有抹茶绿横线（取消红色装订线），横线从正文首行
  /// 上缘起、按正文行高（27px）分布，文字恰好落在两条横线之间。
  void _paintLined(Canvas canvas, Size size) {
    if (lineTop < 0) return; // 外层大底纹不画线，由内层正文信纸负责
    final p = Paint()
      ..color = const Color(0x333E8E6D)
      ..strokeWidth = 1;
    final spacing = StationeryPaper.ruledLineSpacing;
    for (double y = lineTop; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x223E8E6D)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  void _paintNight(Canvas canvas, Size size) {
    final star = Paint()..color = const Color(0xFFF3E6B8);
    final spots = <Offset>[
      Offset(size.width * 0.2, size.height * 0.25),
      Offset(size.width * 0.7, size.height * 0.18),
      Offset(size.width * 0.4, size.height * 0.6),
      Offset(size.width * 0.82, size.height * 0.5),
      Offset(size.width * 0.55, size.height * 0.82),
      Offset(size.width * 0.3, size.height * 0.88),
    ];
    for (var i = 0; i < spots.length; i++) {
      canvas.drawCircle(spots[i], i.isEven ? 2.0 : 1.4, star);
    }
    // 弯月：亮圆 + 与底色同色的偏移圆覆盖
    canvas.drawCircle(
        Offset(size.width - 34, 34), 16, Paint()..color = const Color(0xFFF3E6B8));
    canvas.drawCircle(Offset(size.width - 26, 28), 15,
        Paint()..color = const Color(0xFF1C3B32));
  }

  void _paintKraft(Canvas canvas, Size size) {
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x775A7848)
      ..strokeWidth = 1.4;
    // 用虚线路径
    final rect = Rect.fromLTWH(12, 12, size.width - 24, size.height - 24);
    _drawDashedRect(canvas, rect, dash, 6, 4);
    // 顶部胶带
    final tape = Paint()..color = const Color(0x88FFF6E2);
    canvas.drawRect(
        Rect.fromLTWH(size.width / 2 - 34, 0, 68, 16), tape);
  }

  void _drawDashedRect(
      Canvas canvas, Rect rect, Paint paint, double dash, double gap) {
    // top
    _dashLine(canvas, rect.topLeft, rect.topRight, paint, dash, gap);
    _dashLine(canvas, rect.bottomLeft, rect.bottomRight, paint, dash, gap);
    _dashLine(canvas, rect.topLeft, rect.bottomLeft, paint, dash, gap);
    _dashLine(canvas, rect.topRight, rect.bottomRight, paint, dash, gap);
  }

  void _dashLine(Canvas c, Offset a, Offset b, Paint p, double dash, double gap) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) return;
    final dir = d / len;
    double pos = 0;
    while (pos < len) {
      final end = (pos + dash).clamp(0.0, len).toDouble();
      c.drawLine(a + dir * pos, a + dir * end, p);
      pos += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _StationeryPainter old) => old.id != id;
}
