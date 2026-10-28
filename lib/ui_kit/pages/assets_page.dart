import 'package:flutter/material.dart';
import '../theme.dart';
import '../scaffold.dart';

/// 资产全景主页骨架：净资产看板（含绿/红结构条）→ 资产卡列表
class UiAssetsPage extends StatelessWidget {
  final UiTheme theme;
  final VoidCallback onOpenMenu;

  const UiAssetsPage({Key? key, required this.theme, required this.onOpenMenu})
      : super(key: key);

  static const _assets = [
    _Asset('🏦', '工资卡', '银行储蓄', 32500, true),
    _Asset('📈', '指数基金', '基金', 18400, true),
    _Asset('🪙', '黄金积存', '黄金', 9600, true),
    _Asset('💳', '信用卡', '信用卡', -4200, false),
    _Asset('📄', '本月账单', '账单', -1800, false),
  ];

  @override
  Widget build(BuildContext context) {
    return UiScaffold(
      theme: theme,
      title: '资产全景',
      subtitle: 'ASSETS',
      onOpenMenu: onOpenMenu,
      actions: const [
        UiHeaderAction(icon: Icons.filter_list_rounded),
        UiHeaderAction(icon: Icons.settings_outlined),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
        children: [
          _buildOverview(),
          const SizedBox(height: 14),
          for (final a in _assets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildCard(a),
            ),
        ],
      ),
    );
  }

  Widget _buildOverview() {
    const pos = 60500.0;
    const neg = 6000.0;
    final net = pos - neg;
    final netColor = net >= 0 ? theme.positive : theme.danger;

    // A 方案沿用白字渐变看板，其余方案用卡片底 + 主题色强调
    final onGradient = theme.headerStyle == UiHeaderStyle.gradientBleed;
    final bg = onGradient ? null : theme.cardBg;
    final labelColor = onGradient ? Colors.white70 : theme.textTertiary;
    final valueColor = onGradient ? Colors.white : theme.textPrimary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        gradient: onGradient ? theme.headerGradient : null,
        borderRadius: BorderRadius.circular(theme.cardRadius + 2),
        border: theme.cardBorder == null
            ? null
            : Border.all(color: theme.cardBorder!),
        boxShadow: theme.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(onGradient ? 0.12 : 0.05),
                  blurRadius: onGradient ? 18 : 12,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('净资产', style: TextStyle(fontSize: 12.5, color: labelColor)),
              const Spacer(),
              Icon(Icons.visibility_outlined,
                  size: 16, color: labelColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '¥${(net >= 0 ? '' : '-')}${(net.abs() / 10000).toStringAsFixed(2)} 万',
            style: TextStyle(
              fontSize: 30,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 14),
          // 正/负资产结构条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 7,
              child: Row(
                children: [
                  Expanded(
                    flex: (pos / (pos + neg) * 1000).round(),
                    child: ColoredBox(
                      color: onGradient
                          ? const Color(0xFF7CE0A8)
                          : theme.positive,
                    ),
                  ),
                  Expanded(
                    flex: (neg / (pos + neg) * 1000).round(),
                    child: ColoredBox(
                      color: onGradient
                          ? const Color(0xFFFFA3AE)
                          : theme.danger,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                flex: 4,
                child: _legend('正资产', '¥${pos.toStringAsFixed(0)}',
                    onGradient ? Colors.white : theme.positive, labelColor),
              ),
              const SizedBox(width: 10),
              Flexible(
                flex: 4,
                child: _legend('负资产', '¥${neg.toStringAsFixed(0)}',
                    onGradient ? Colors.white70 : theme.danger, labelColor),
              ),
              const SizedBox(width: 10),
              Flexible(
                flex: 3,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text('净${net >= 0 ? '盈' : '亏'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 11, color: labelColor)),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${net >= 0 ? '+' : '-'}${(net.abs() / 10000).toStringAsFixed(2)}w',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: onGradient ? Colors.white : netColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(String label, String value, Color dot, Color labelColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: labelColor),
          ),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: dot,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(_Asset a) {
    final positive = a.amount >= 0;
    final color = positive ? theme.positive : theme.danger;
    return UiCard(
      theme: theme,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(theme.cardRadius),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 3.5, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 13, 14, 13),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color.withOpacity(theme.isDark ? 0.18 : 0.10),
                          borderRadius:
                              BorderRadius.circular(theme.cardRadius - 4),
                        ),
                        alignment: Alignment.center,
                        child:
                            Text(a.icon, style: const TextStyle(fontSize: 19)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: theme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              a.type,
                              style: TextStyle(
                                  fontSize: 11, color: theme.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${positive ? '' : '-'}¥${a.amount.abs().toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Asset {
  final String icon;
  final String note;
  final String type;
  final double amount;
  final bool positive;
  const _Asset(this.icon, this.note, this.type, this.amount, this.positive);
}
