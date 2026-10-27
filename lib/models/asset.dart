/// 资产卡片。amount 为正 = 资产，为负 = 负债（信用卡/欠款）。
class Asset {
  String id;
  String icon; // 自定义 emoji
  String note; // 备注（如：工资卡）
  String type; // 银行储蓄 / 货币基金 / 理财 / 黄金 / 股票 / 信用卡 / 欠款
  double amount;

  Asset({
    required this.id,
    this.icon = '💰',
    this.note = '',
    this.type = '银行储蓄',
    this.amount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'icon': icon,
        'note': note,
        'type': type,
        'amount': amount,
      };

  factory Asset.fromJson(Map<String, dynamic> j) => Asset(
        id: j['id'] as String,
        icon: (j['icon'] as String?) ?? '💰',
        note: (j['note'] as String?) ?? '',
        type: (j['type'] as String?) ?? '银行储蓄',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
      );

  /// 资产类型清单（单选项）
  static const List<String> types = [
    '银行储蓄',
    '货币基金',
    '理财',
    '黄金',
    '股票',
    '信用卡',
    '欠款',
  ];

  /// 现金流统计包含的类型
  static const List<String> cashTypes = ['银行储蓄', '货币基金'];

  /// 银行储蓄/信用卡 等常用默认图标
  static String defaultIconFor(String type) {
    switch (type) {
      case '银行储蓄':
        return '🏦';
      case '货币基金':
        return '💸';
      case '理财':
        return '📈';
      case '黄金':
        return '🪙';
      case '股票':
        return '📊';
      case '信用卡':
        return '💳';
      case '欠款':
        return '🧾';
    }
    return '💰';
  }
}
