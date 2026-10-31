/// 资产卡片。amount 为正 = 资产，为负 = 负债（信用卡/欠款）。
class Asset {
  String id;
  String icon; // 自定义 emoji
  String note; // 备注（如：工资卡）
  String type; // 银行储蓄 / 货币基金 / 基金 / 黄金 / 股票 / 信用卡 / 欠款 / 账单
  double amount;

  /// 用户拖拽排序后的展示位置（越小越靠前）。每次拖拽结束由存储层归一化为 0..n-1。
  /// 旧数据（无该字段）由 [AssetStorage.load] 按文件原顺序补齐。
  int order;

  Asset({
    required this.id,
    this.icon = '💰',
    this.note = '',
    this.type = '银行储蓄',
    this.amount = 0,
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'icon': icon,
        'note': note,
        'type': type,
        'amount': amount,
        'order': order,
      };

  factory Asset.fromJson(Map<String, dynamic> j) => Asset(
        id: j['id'] as String,
        icon: (j['icon'] as String?) ?? '💰',
        note: (j['note'] as String?) ?? '',
        type: (j['type'] as String?) ?? '银行储蓄',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        order: (j['order'] as num?)?.toInt() ?? -1,
      );

  /// 资产类型清单（单选项）
  static const List<String> types = [
    '银行储蓄',
    '货币基金',
    '基金',
    '黄金',
    '股票',
    '信用卡',
    '欠款',
    '账单',
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
      case '基金':
      case '理财': // 旧数据兼容
        return '📈';
      case '黄金':
        return '🪙';
      case '股票':
        return '📊';
      case '信用卡':
        return '💳';
      case '欠款':
        return '🧾';
      case '账单':
        return '📋';
    }
    return '💰';
  }
}
