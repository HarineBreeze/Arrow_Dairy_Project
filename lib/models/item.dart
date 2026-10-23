class Item {
  String id;
  String name;
  String category;
  String icon;
  double price;
  DateTime acquiredDate;
  DateTime? lostDate;
  int calcMethod; // 0=价格/天数, 1=价格/使用次数
  int usageCount;

  Item({
    required this.id,
    this.name = '',
    this.category = '数码设备',
    this.icon = '📱',
    this.price = 0,
    required this.acquiredDate,
    this.lostDate,
    this.calcMethod = 0,
    this.usageCount = 0,
  });

  int get acquiredDays {
    final end = lostDate ?? DateTime.now();
    final days = end.difference(acquiredDate).inDays;
    return days < 1 ? 1 : days;
  }

  double get unitPrice {
    if (calcMethod == 1) {
      final n = usageCount < 1 ? 1 : usageCount;
      return price / n;
    }
    return price / acquiredDays;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'icon': icon,
        'price': price,
        'acquiredDate': acquiredDate.toIso8601String(),
        'lostDate': lostDate?.toIso8601String(),
        'calcMethod': calcMethod,
        'usageCount': usageCount,
      };

  factory Item.fromJson(Map<String, dynamic> json) => Item(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        category: json['category'] as String? ?? '数码设备',
        icon: json['icon'] as String? ?? '📱',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        acquiredDate: DateTime.parse(json['acquiredDate'] as String),
        lostDate: json['lostDate'] != null
            ? DateTime.parse(json['lostDate'] as String)
            : null,
        calcMethod: json['calcMethod'] as int? ?? 0,
        usageCount: json['usageCount'] as int? ?? 0,
      );
}
