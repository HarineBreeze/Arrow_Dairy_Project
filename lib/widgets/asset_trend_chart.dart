import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 趋势图上的一个「按天快照」点。
class TrendPoint {
  final DateTime time;
  final double totalAssets; // 全资产（正数之和）
  final double totalDebt; // 负债（负数之和，带符号；绘制时取绝对值高度）

  const TrendPoint({
    required this.time,
    required this.totalAssets,
    required this.totalDebt,
  });

  /// 净资产 = 总资产 - 负资产（负债取绝对值）。
  /// totalDebt 为带符号的负债之和（负数），故等价于 totalAssets + totalDebt。
  double get netWorth => totalAssets - totalDebt.abs();
}

/// 时间范围。
enum TrendRange {
  threeMonths,
  sixMonths,
  thisYear,
  oneYear;

  String get label {
    switch (this) {
      case TrendRange.threeMonths:
        return '近3月';
      case TrendRange.sixMonths:
        return '近6月';
      case TrendRange.thisYear:
        return '今年';
      case TrendRange.oneYear:
        return '近1年';
    }
  }

  DateTime cutoff(DateTime now) {
    switch (this) {
      case TrendRange.threeMonths:
        return now.subtract(const Duration(days: 90));
      case TrendRange.sixMonths:
        return now.subtract(const Duration(days: 180));
      case TrendRange.thisYear:
        return DateTime(now.year, 1, 1);
      case TrendRange.oneYear:
        return now.subtract(const Duration(days: 365));
    }
  }
}

/// 资产趋势折线图卡片（含顶部汇总条 + 阶梯图 + 时间范围选择）。
class AssetTrendChart extends StatefulWidget {
  /// 全部按天快照点，按时间升序。
  final List<TrendPoint> points;

  const AssetTrendChart({Key? key, required this.points}) : super(key: key);

  @override
  State<AssetTrendChart> createState() => _AssetTrendChartState();
}

class _AssetTrendChartState extends State<AssetTrendChart> {
  TrendRange _range = TrendRange.oneYear;

  List<TrendPoint> get _visible {
    final cutoff = _range.cutoff(DateTime.now());
    return widget.points.where((p) => !p.time.isBefore(cutoff)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final points = _visible;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F24382F),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildInfoBar(points),
          const SizedBox(height: 10),
          SizedBox(
            height: 240,
            child: points.isEmpty
                ? Center(
                    child: Text('该时间段暂无资产变动记录',
                        style: TextStyle(
                            fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
                  )
                : RepaintBoundary(
                    child: CustomPaint(
                      painter: _TrendPainter(points: points),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          _buildRangeSelector(),
        ],
      ),
    );
  }

  /// 顶部汇总条：最后一点的日期 + 全资产（蓝）+ 净资产（红）+ 负债（绿）。
  Widget _buildInfoBar(List<TrendPoint> points) {
    final last = points.isEmpty ? null : points.last;
    final date = last == null
        ? '--'
        : '${last.time.month.toString().padLeft(2, '0')}-${last.time.day.toString().padLeft(2, '0')}';
    final assets = last?.totalAssets ?? 0;
    final debt = last?.totalDebt ?? 0;
    final netWorth = last?.netWorth ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFEDF3FD),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(date,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.c(0xFF24382F))),
          const SizedBox(width: 10),
          Expanded(child: _legendDot(_kAssetColor, '全资产', assets)),
          const SizedBox(width: 6),
          Expanded(child: _legendDot(_kNetWorthColor, '净资产', netWorth)),
          const SizedBox(width: 6),
          Expanded(child: _legendDot(_kDebtColor, '负债', debt)),
        ],
      ),
    );
  }

  /// 汇总条里的单项图例：色块 + 「标签 金额」（金额千分位）。
  Widget _legendDot(Color color, String label, double value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 3, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text('$label ${_thousands(value)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, color: AppPalette.c(0xFF24382F))),
        ),
      ],
    );
  }

  Widget _buildRangeSelector() {
    return Row(
      children: [
        for (final r in TrendRange.values) ...[
          Expanded(
            child: PressableRangeChip(
              label: r.label,
              selected: r == _range,
              onTap: () => setState(() => _range = r),
            ),
          ),
        ],
      ],
    );
  }

  /// 千分位（带符号），例图风格：38,609 / -1,075。
  static String _thousands(double v) {
    final neg = v < 0;
    final digits = v.abs().round().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '${neg ? '-' : ''}$buf';
  }
}

/// 时间范围胶囊（轻量按压反馈，不依赖 haptics）。
class PressableRangeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const PressableRangeChip({
    Key? key,
    required this.label,
    required this.selected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppPalette.c(0xFFE4E8EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? AppPalette.c(0xFF24382F)
                    : AppPalette.c(0xFF647A70))),
      ),
    );
  }
}

const Color _kAssetColor = Color(0xFF6BA7E8); // 全资产：蓝
const Color _kNetWorthColor = Color(0xFFE05252); // 净资产：红（总资产 - 负资产）
const Color _kDebtColor = Color(0xFF3FA96F); // 负资产/负债：绿

/// 阶梯折线绘制器。
///
/// - 三条阶梯线：全资产（蓝）、净资产（红，总资产-负债）、负债（绿，取绝对值高度）；
/// - 左 Y 轴按「万」给出 5 条水平虚线网格 + 标签；
/// - 末端竖直虚线落到 0 线 + 三色实心端点；
/// - X 轴两端标注起止日期。
class _TrendPainter extends CustomPainter {
  final List<TrendPoint> points;

  _TrendPainter({required this.points});

  static const leftPad = 46.0;
  static const rightPad = 14.0;
  static const topPad = 12.0;
  static const bottomPad = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    final left = leftPad;
    final right = size.width - rightPad;
    final top = topPad;
    final bottom = size.height - bottomPad;
    final plotW = right - left;
    final plotH = bottom - top;
    if (plotW <= 0 || plotH <= 0) return;

    final maxAbs = points.fold<double>(0.0, (m, p) {
      final v = math.max(p.totalAssets,
          math.max(p.netWorth, p.totalDebt.abs()));
      return math.max(m, v);
    });
    final step = _niceStep(maxAbs / 4);
    final axisTop = step * 4;
    final first = points.first.time;
    final last = points.last.time;
    final span = last.difference(first).inMilliseconds.toDouble();

    double xOf(DateTime t) => span <= 0
        ? left
        : left + t.difference(first).inMilliseconds / span * plotW;
    double yOf(double value) => bottom - (value / axisTop).clamp(0.0, 1.0) * plotH;

    // 1) 水平网格 + Y 轴标签
    final gridPaint = Paint()
      ..color = Color(0x1A8FA09A)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = bottom - i / 4 * plotH;
      canvas.drawLine(Offset(left, y), Offset(right, y), gridPaint);
      final label = _axisLabel(step * i);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontSize: 11, color: AppPalette.c(0xFF9AA8A2)),
        ),
        textAlign: TextAlign.right,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(left - 8 - tp.width, y - tp.height / 2));
    }

    // 2) 三条阶梯线：全资产（蓝）、净资产（红）、负债（绿）
    _drawStepLine(canvas, points, left, right, xOf, yOf, _kAssetColor,
        (p) => p.totalAssets);
    _drawStepLine(canvas, points, left, right, xOf, yOf, _kNetWorthColor,
        (p) => p.netWorth);
    _drawStepLine(canvas, points, left, right, xOf, yOf, _kDebtColor,
        (p) => p.totalDebt.abs());

    // 3) 末端竖直虚线（落到 0 线）+ 三色端点
    final lx = xOf(last);
    final lastPoint = points.last;
    _dashedLine(canvas, Offset(lx, yOf(lastPoint.totalAssets)),
        Offset(lx, bottom), Color(0x806BA7E8));
    canvas.drawCircle(
        Offset(lx, yOf(lastPoint.totalAssets)), 4.5,
        Paint()..color = _kAssetColor);
    canvas.drawCircle(
        Offset(lx, yOf(lastPoint.netWorth)), 4.5,
        Paint()..color = _kNetWorthColor);
    canvas.drawCircle(
        Offset(lx, yOf(lastPoint.totalDebt.abs())), 4.5,
        Paint()..color = _kDebtColor);

    // 4) X 轴两端日期
    _drawXLabel(canvas, first, left, bottom, TextAlign.left);
    _drawXLabel(canvas, last, right, bottom, TextAlign.right);
  }

  void _drawStepLine(
    Canvas canvas,
    List<TrendPoint> pts,
    double left,
    double right,
    double Function(DateTime) xOf,
    double Function(double) yOf,
    Color color,
    double Function(TrendPoint) value,
  ) {
    final path = Path();
    path.moveTo(left, yOf(value(pts.first)));
    for (var i = 0; i < pts.length; i++) {
      final x = xOf(pts[i].time);
      path.lineTo(x, yOf(value(pts[i])));
      if (i < pts.length - 1) {
        path.lineTo(x, yOf(value(pts[i + 1])));
      }
    }
    path.lineTo(right, yOf(value(pts.last)));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Color color) {
    const dash = 4.0;
    const gap = 3.0;
    final d = b - a;
    final len = d.distance;
    if (len <= 0) return;
    final dir = d / len;
    var at = 0.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    while (at < len) {
      final end = (at + dash).clamp(0.0, len);
      canvas.drawLine(a + dir * at, a + dir * end, paint);
      at += dash + gap;
    }
  }

  void _drawXLabel(
      Canvas canvas, DateTime t, double x, double y, TextAlign align) {
    final label =
        '${(t.year % 100).toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')}';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(fontSize: 11, color: AppPalette.c(0xFF9AA8A2)),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = align == TextAlign.left ? 0.0 : -tp.width;
    tp.paint(canvas, Offset(x + dx, y + 7));
  }

  static double _niceStep(double raw) {
    if (raw <= 0) return 10000;
    final exp = (math.log(raw) / math.ln10).floor();
    final base = math.pow(10, exp).toDouble();
    final f = raw / base;
    final nf = f <= 1
        ? 1.0
        : (f <= 2 ? 2.0 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5.0 : 10.0)));
    return nf * base;
  }

  static String _axisLabel(double v) {
    if (v == 0) return '0';
    if (v >= 10000) {
      final w = v / 10000;
      return '${w.toStringAsFixed(w == w.roundToDouble() ? 0 : 1)}万';
    }
    return v.round().toString();
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.points.length != points.length;
}
