/// 一次「资产金额调整」的快照记录。
///
/// 用户在资产编辑页点「完成」保存（新增 / 改金额 / 删除）时由列表页写入一条。
/// 折线图按天取当天最后一条快照的 [totalAssets] / [totalDebt] 打点；
/// 「更新记录」列表则直接展示每条 [changes]（这一改涉及哪些资产、改成多少）。
class AssetHistoryEntry {
  /// 记录来源：'change' = 一次真实调整；'seed' = 启用功能时的存量基线。
  static const String sourceChange = 'change';
  static const String sourceSeed = 'seed';

  /// 唯一 id（毫秒时间戳 + 序号，保证同一毫秒多次保存也能区分）
  final String id;

  /// 调整发生的时间
  final DateTime time;

  /// 这一改涉及的单条变更（资产名 + 调整后金额，正=资产、负=负债）
  final List<AssetChange> changes;

  /// 变更后：全资产（正数之和）
  final double totalAssets;

  /// 变更后：负债（负数之和，带符号）
  final double totalDebt;

  /// 变更后：净资产 = 全资产 + 负债
  final double netWorth;

  /// 来源（见 [sourceChange] / [sourceSeed]）
  final String source;

  const AssetHistoryEntry({
    required this.id,
    required this.time,
    required this.changes,
    required this.totalAssets,
    required this.totalDebt,
    required this.netWorth,
    this.source = sourceChange,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.millisecondsSinceEpoch,
        'changes': changes.map((c) => c.toJson()).toList(),
        'totalAssets': totalAssets,
        'totalDebt': totalDebt,
        'netWorth': netWorth,
        'source': source,
      };

  factory AssetHistoryEntry.fromJson(Map<String, dynamic> j) => AssetHistoryEntry(
        id: j['id'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(j['time'] as int),
        changes: (j['changes'] as List<dynamic>? ?? [])
            .map((e) => AssetChange.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        totalAssets: (j['totalAssets'] as num?)?.toDouble() ?? 0,
        totalDebt: (j['totalDebt'] as num?)?.toDouble() ?? 0,
        netWorth: (j['netWorth'] as num?)?.toDouble() ?? 0,
        source: j['source'] as String? ?? sourceChange,
      );
}

/// 一次调整里单张资产卡片的变更。
class AssetChange {
  final String name; // 卡片名：备注优先，其次类型
  final String type; // 资产类型
  final double amount; // 调整后的金额（带符号）
  final bool deleted; // 本次是否为删除
  final bool autoImported; // 是否自动导入来源（本 App 目前恒 false，预留）

  const AssetChange({
    required this.name,
    required this.type,
    required this.amount,
    this.deleted = false,
    this.autoImported = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'amount': amount,
        'deleted': deleted,
        'autoImported': autoImported,
      };

  factory AssetChange.fromJson(Map<String, dynamic> j) => AssetChange(
        name: j['name'] as String? ?? '',
        type: j['type'] as String? ?? '',
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        deleted: j['deleted'] as bool? ?? false,
        autoImported: j['autoImported'] as bool? ?? false,
      );
}
