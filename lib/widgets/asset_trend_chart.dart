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

  /// 当前选中的点在 [points] 中的索引（点击折线图定位最近日）。
  int? _selectedIndex;

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
          _buildInfoBar(),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final chartWidth = constraints.maxWidth;
              return SizedBox(
                height: 240,
                child: points.isEmpty
                    ? Center(
                        child: Text('该时间段暂无资产变动记录',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppPalette.c(0xFF8FA09A))),
                      )
                    : GestureDetector(
                        key: const Key('asset_trend_chart_tap'),
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (d) {
                          final idx = _nearestIndex(
                              d.localPosition.dx, chartWidth, points);
                          setState(() => _selectedIndex =
                              _selectedIndex == idx ? null : idx);
                        },
                        child: Stack(
                          children: [
                            // v5.0.17 修复：Stack 给非定位 child 的是松散约束，
                            // CustomPaint 无 child 也无 size 时会塌缩成 Size.zero，
                            // 导致折线图完全不显示。用 Positioned.fill 给紧约束撑满。
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  painter: _TrendPainter(points: points),
                                ),
                              ),
                            ),
                            if (_selectedIndex != null &&
                                _selectedIndex! < points.length)
                              Positioned(
                                left: _tooltipLeft(
                                    points[_selectedIndex!], chartWidth),
                                top: 2,
                                child: _buildTooltip(points[_selectedIndex!]),
                              ),
                          ],
                        ),
                      ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildRangeSelector(),
        ],
      ),
    );
  }

  /// 顶部图例：只显示颜色代表的类型，不写具体金额。
  /// 具体金额改为点击折线图某日的点后，在小窗中预览。
  Widget _buildInfoBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      // v5.0.20：底纹改用主题色浅底纹 0xFFE4F2EB（深色下 darkMap 翻为
      // 0xFF233A2F），常规/深色都随主题色一起换，与全 App 选项底一致
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFE4F2EB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _legendLabel(_kAssetColor, '全资产'),
          _legendLabel(_kNetWorthColor, '净资产'),
          _legendLabel(_kDebtColor, '负债'),
        ],
      ),
    );
  }

  /// 图例单项：色块 + 类型名（无金额）。
  Widget _legendLabel(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 14, height: 3, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 12, color: AppPalette.c(0xFF24382F))),
      ],
    );
  }

  /// 根据点击的横坐标，找到时间上最近的点索引。
  /// 坐标口径与 [_TrendPainter] 一致：leftPad=46 / rightPad=14。
  int _nearestIndex(double dx, double width, List<TrendPoint> pts) {
    final left = _TrendPainter.leftPad;
    final right = width - _TrendPainter.rightPad;
    final plotW = right - left;
    final first = pts.first.time;
    final span = pts.last.time.difference(first).inMilliseconds.toDouble();
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      // v5.0.18：与 painter 的 xOf 口径一致——单点(span<=0)时最新节点在最右。
      final x = span <= 0
          ? right
          : left + pts[i].time.difference(first).inMilliseconds / span * plotW;
      final dist = (x - dx).abs();
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    return best;
  }

  /// tooltip 水平位置：跟随选中点、并夹在图表可视区内。
  double _tooltipLeft(TrendPoint p, double width) {
    const cardW = 156.0;
    final left = _TrendPainter.leftPad;
    final right = width - _TrendPainter.rightPad;
    final plotW = right - left;
    final first = _visible.first.time;
    final span = _visible.last.time.difference(first).inMilliseconds.toDouble();
    // v5.0.18：与 painter 的 xOf 口径一致——单点(span<=0)时节点在最右。
    final x = span <= 0
        ? right
        : left + p.time.difference(first).inMilliseconds / span * plotW;
    return (x - cardW / 2).clamp(0.0, (width - cardW).clamp(0.0, double.infinity));
  }

  /// 点击某日点后弹出的小窗：该日三类资产的具体金额。
  Widget _buildTooltip(TrendPoint p) {
    final date =
        '${p.time.month.toString().padLeft(2, '0')}-${p.time.day.toString().padLeft(2, '0')}';
    return Container(
      width: 156,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(date,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.c(0xFF24382F))),
          const SizedBox(height: 5),
          _tipRow(_kAssetColor, '全资产', p.totalAssets),
          const SizedBox(height: 3),
          _tipRow(_kNetWorthColor, '净资产', p.netWorth),
          const SizedBox(height: 3),
          _tipRow(_kDebtColor, '负债', p.totalDebt),
        ],
      ),
    );
  }

  Widget _tipRow(Color color, String label, double value) {
    return Row(
      children: [
        Container(width: 8, height: 3, color: color),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(fontSize: 10, color: AppPalette.c(0xFF647A70))),
        const Spacer(),
        Text(_thousands(value),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppPalette.c(0xFF24382F))),
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
              onTap: () => setState(() {
                _range = r;
                _selectedIndex = null;
              }),
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
        // v5.0.20：选中底纹改用主题色浅底纹 0xFFE4F2EB，随主题色/深色自适应
        decoration: BoxDecoration(
          color: selected ? AppPalette.c(0xFFE4F2EB) : Colors.transparent,
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

    // v5.0.18：最新（时间最晚）的节点始终钉在图表最右侧 right。
    // span>0 时 last 本就映射到 right（保持不变）；只有一天数据（span<=0）
    // 时把唯一节点也放最右，避免"最新资产节点跑到最左边"。
    double xOf(DateTime t) => span <= 0
        ? right
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

    // 2) 三条阶梯线：全资产（蓝，虚线）、净资产（红，实线）、负债（绿，虚线）
    // v5.0.18：全资产与负债由实线改为虚线，净资产仍为实线以便一眼区分。
    _drawStepLine(canvas, points, left, right, xOf, yOf, _kAssetColor,
        (p) => p.totalAssets, dashed: true);
    _drawStepLine(canvas, points, left, right, xOf, yOf, _kNetWorthColor,
        (p) => p.netWorth);
    _drawStepLine(canvas, points, left, right, xOf, yOf, _kDebtColor,
        (p) => p.totalDebt.abs(), dashed: true);

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
    double Function(TrendPoint) value, {
    bool dashed = false,
  }) {
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
    if (dashed) {
      // v5.0.18：全资产/负债改虚线——沿阶梯 path 逐段截取 dash 绘制，
      // computeMetrics 保留阶梯拐角，虚线段沿线走而非两点直连。
      const dash = 6.0;
      const gap = 4.0;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      for (final metric in path.computeMetrics()) {
        var at = 0.0;
        while (at < metric.length) {
          final end = (at + dash).clamp(0.0, metric.length);
          canvas.drawPath(metric.extractPath(at, end), paint);
          at += dash + gap;
        }
      }
      return;
    }
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
