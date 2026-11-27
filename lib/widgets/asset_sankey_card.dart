import 'package:flutter/material.dart';

import '../models/asset.dart';
import '../theme/app_palette.dart';

/// 桑基图右侧「金融资产」包含的类型（基金 / 黄金 / 股票）。
const Set<String> kSankeyFinanceTypes = {'基金', '黄金', '股票'};

/// 右侧「固定资产」：银行储蓄 / 货币基金（以及任何未归入金融的正数类型兜底）。
const Set<String> kSankeyFixedTypes = {'银行储蓄', '货币基金'};

const Color _kDebtColor = Color(0xFFB7C3BD);
const Color _kNetColor = Color(0xFF3E8E6D);
const Color _kFinanceColor = Color(0xFF3E7BD6);
const Color _kFixedColor = Color(0xFFA9C7E8);

/// 桑基图上的一个端点节点。
class SankeyNode {
  final String label;
  final double amount; // 展示用的正数金额
  final int count;
  final Color color;

  const SankeyNode({
    required this.label,
    required this.amount,
    required this.count,
    required this.color,
  });
}

/// 资产构成桑基图的四端点数据。
///
/// 守恒关系：`净资产 + |负债| = 总资产 = 金融资产 + 固定资产`。
/// 左侧从上到下为「负债、净资产」，右侧为「金融资产、固定资产」。
class SankeyData {
  final SankeyNode debt;
  final SankeyNode net;
  final SankeyNode finance;
  final SankeyNode fixed;
  final double total; // 总资产（正资产之和）

  const SankeyData({
    required this.debt,
    required this.net,
    required this.finance,
    required this.fixed,
    required this.total,
  });

  /// 净资产为负（资不抵债）或无总资产时不适合画带宽守恒的桑基图。
  bool get isValid => total > 0 && net.amount > 0;
}

/// 把资产列表聚合成桑基图四端点。
///
/// - 负债：金额 < 0 的记录（信用卡 / 欠款 / 账单），绝对值累加；
/// - 金融资产：基金 / 黄金 / 股票；
/// - 固定资产：银行储蓄 / 货币基金，以及未知正数类型兜底；
/// - 净资产 = 总资产 - 负债。
SankeyData buildSankeyData(List<Asset> assets) {
  var finance = 0.0;
  var fixed = 0.0;
  var debt = 0.0;
  var financeCount = 0;
  var fixedCount = 0;
  var debtCount = 0;

  for (final a in assets) {
    if (a.amount < 0) {
      debt += -a.amount;
      debtCount++;
    } else if (a.amount > 0) {
      if (kSankeyFinanceTypes.contains(a.type)) {
        finance += a.amount;
        financeCount++;
      } else {
        // 银行储蓄 / 货币基金 / 未知正数类型 → 固定资产兜底
        fixed += a.amount;
        fixedCount++;
      }
    }
  }

  final total = finance + fixed;
  final net = total - debt;

  return SankeyData(
    debt: SankeyNode(
        label: '$debtCount项负债',
        amount: debt,
        count: debtCount,
        color: _kDebtColor),
    net: SankeyNode(
        label: '净资产', amount: net, count: 0, color: _kNetColor),
    finance: SankeyNode(
        label: '$financeCount项金融资产',
        amount: finance,
        count: financeCount,
        color: _kFinanceColor),
    fixed: SankeyNode(
        label: '$fixedCount项固定资产',
        amount: fixed,
        count: fixedCount,
        color: _kFixedColor),
    total: total,
  );
}

/// 一条流带：源/目标的上下沿 y 坐标与配色。
class _Flow {
  final double sl;
  final double sh;
  final double dl;
  final double dh;
  final Color from;
  final Color to;

  const _Flow(this.sl, this.sh, this.dl, this.dh, this.from, this.to);
}

/// 一次布局算出的所有几何量，painter 与标签共用同一套坐标。
class _Geom {
  final double leftX;
  final double rightX;
  final double barW;
  final double debtTop;
  final double debtH;
  final double netTop;
  final double netH;
  final double finTop;
  final double finH;
  final double fixTop;
  final double fixH;
  final List<_Flow> flows;

  _Geom({
    required this.leftX,
    required this.rightX,
    required this.barW,
    required this.debtTop,
    required this.debtH,
    required this.netTop,
    required this.netH,
    required this.finTop,
    required this.finH,
    required this.fixTop,
    required this.fixH,
    required this.flows,
  });
}

_Geom _layout(SankeyData d, double w, double h) {
  const padY = 6.0;
  const barGap = 6.0;
  const barW = 9.0;
  final availH = h - 2 * padY - barGap;
  final leftX = w * 0.34;
  final rightX = w * 0.64;
  final t = d.total;

  final hDebt = d.debt.amount / t * availH;
  final hNet = d.net.amount / t * availH;
  final hFin = d.finance.amount / t * availH;
  final hFix = d.fixed.amount / t * availH;

  final debtTop = padY;
  final netTop = padY + hDebt + barGap;
  final finTop = padY;
  final fixTop = padY + hFin + barGap;

  // 按矩阵比例分配四条流：源金额 × 目标金额 / 总资产。
  double hh(double amount) => amount / t * availH;
  final debtToFin = d.debt.amount * d.finance.amount / t;
  final debtToFix = d.debt.amount * d.fixed.amount / t;
  final netToFin = d.net.amount * d.finance.amount / t;
  final netToFix = d.net.amount * d.fixed.amount / t;

  final flows = <_Flow>[
    _Flow(debtTop, hh(debtToFin), finTop, hh(debtToFin), _kDebtColor,
        _kFinanceColor),
    _Flow(debtTop + hh(debtToFin), hh(debtToFix), fixTop, hh(debtToFix),
        _kDebtColor, _kFixedColor),
    _Flow(netTop, hh(netToFin), finTop + hh(debtToFin), hh(netToFin),
        _kNetColor, _kFinanceColor),
    _Flow(netTop + hh(netToFin), hh(netToFix), fixTop + hh(debtToFix),
        hh(netToFix), _kNetColor, _kFixedColor),
  ]..removeWhere((f) => f.sh < 0.01);

  return _Geom(
    leftX: leftX,
    rightX: rightX,
    barW: barW,
    debtTop: debtTop,
    debtH: hDebt,
    netTop: netTop,
    netH: hNet,
    finTop: finTop,
    finH: hFin,
    fixTop: fixTop,
    fixH: hFix,
    flows: flows,
  );
}

/// 画流带与两侧端点柱。
class _SankeyPainter extends CustomPainter {
  final SankeyData data;
  final _Geom g;
  final double progress;

  _SankeyPainter({
    required this.data,
    required this.g,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // 先画流带（在下），再画端点柱（在上）。
    for (final f in g.flows) {
      final sx = g.leftX + g.barW;
      final ex = g.rightX;
      final c = (ex - sx) * 0.46;
      final path = Path()
        ..moveTo(sx, f.sl)
        ..cubicTo(sx + c, f.sl, ex - c, f.dl, ex, f.dl)
        ..lineTo(ex, f.dl + f.dh)
        ..cubicTo(ex - c, f.dl + f.dh, sx + c, f.sl + f.sh, sx, f.sl + f.sh)
        ..close();
      final shader = LinearGradient(
        colors: [
          f.from.withOpacity(0.32 * progress),
          f.to.withOpacity(0.32 * progress),
        ],
        begin: Alignment(2 * g.leftX / size.width - 1, 0),
        end: Alignment(2 * g.rightX / size.width - 1, 0),
      ).createShader(rect);
      canvas.drawPath(path, Paint()..shader = shader);
    }

    _bar(canvas, g.leftX, g.debtTop, g.debtH, data.debt.color, progress);
    _bar(canvas, g.leftX, g.netTop, g.netH, data.net.color, progress);
    _bar(canvas, g.rightX, g.finTop, g.finH, data.finance.color, progress);
    _bar(canvas, g.rightX, g.fixTop, g.fixH, data.fixed.color, progress);
  }

  void _bar(Canvas canvas, double x, double top, double fullH, Color color,
      double progress) {
    if (fullH <= 0) return;
    final h = fullH * progress;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, g.barW, h),
        Radius.circular(g.barW / 2),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_SankeyPainter old) =>
      old.progress != progress || old.data.total != data.total;
}

/// 资产构成桑基图卡片（看板堆叠的第三张）。
class AssetSankeyCard extends StatefulWidget {
  final SankeyData data;

  /// 金额格式化（与看板同一套，内部已处理隐藏数字）。
  final String Function(double) money;

  const AssetSankeyCard({
    Key? key,
    required this.data,
    required this.money,
  }) : super(key: key);

  @override
  State<AssetSankeyCard> createState() => _AssetSankeyCardState();
}

class _AssetSankeyCardState extends State<AssetSankeyCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
  }

  @override
  void didUpdateWidget(AssetSankeyCard old) {
    super.didUpdateWidget(old);
    if (old.data.total != widget.data.total ||
        old.data.net.amount != widget.data.net.amount) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('资产构成',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.c(0xFF24382F))),
          const SizedBox(height: 10),
          if (!widget.data.isValid)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text('净资产为负，暂不展示构成图',
                    style: TextStyle(
                        fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const h = 150.0;
                final w = constraints.maxWidth;
                final g = _layout(widget.data, w, h);
                return SizedBox(
                  height: h,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: _c,
                            builder: (_, __) => CustomPaint(
                              painter: _SankeyPainter(
                                data: widget.data,
                                g: g,
                                progress: Curves.easeOutCubic.transform(
                                    _c.value),
                              ),
                            ),
                          ),
                        ),
                      ),
                      _label(
                        label: widget.data.debt.label,
                        amount: widget.money(-widget.data.debt.amount),
                        centerY: g.debtTop + g.debtH / 2,
                        w: w,
                        h: h,
                        leftX: g.leftX,
                        rightX: g.rightX,
                        barW: g.barW,
                        isLeft: true,
                      ),
                      _label(
                        label: widget.data.net.label,
                        amount: widget.money(widget.data.net.amount),
                        centerY: g.netTop + g.netH / 2,
                        w: w,
                        h: h,
                        leftX: g.leftX,
                        rightX: g.rightX,
                        barW: g.barW,
                        isLeft: true,
                      ),
                      _label(
                        label: widget.data.finance.label,
                        amount: widget.money(widget.data.finance.amount),
                        centerY: g.finTop + g.finH / 2,
                        w: w,
                        h: h,
                        leftX: g.leftX,
                        rightX: g.rightX,
                        barW: g.barW,
                        isLeft: false,
                      ),
                      _label(
                        label: widget.data.fixed.label,
                        amount: widget.money(widget.data.fixed.amount),
                        centerY: g.fixTop + g.fixH / 2,
                        w: w,
                        h: h,
                        leftX: g.leftX,
                        rightX: g.rightX,
                        barW: g.barW,
                        isLeft: false,
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _label({
    required String label,
    required String amount,
    required double centerY,
    required double w,
    required double h,
    required double leftX,
    required double rightX,
    required double barW,
    required bool isLeft,
  }) {
    final cross = isLeft ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // 标签块（两行文字 + 间距）约 32px 高。以节点中心对齐，但把 top 夹在
    // 图表区内，避免顶部/底部节点的文字溢出卡片边框被裁切。
    const labelH = 32.0;
    final top = (centerY - labelH / 2).clamp(0.0, (h - labelH).clamp(0.0, h));
    return Positioned(
      top: top,
      left: isLeft ? 0 : rightX + barW + 8,
      right: isLeft ? w - leftX + 8 : 0,
      child: Column(
        crossAxisAlignment: cross,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppPalette.c(0xFF8FA09A))),
          const SizedBox(height: 2),
          Text(amount,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.c(0xFF24382F))),
        ],
      ),
    );
  }
}
