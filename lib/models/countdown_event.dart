import 'dart:convert';

/// 倒数日事件。
/// - 日期类型：纪念日 / 资产日
/// - 目的日含时分；未来 → 倒数，过去 → 正数
/// - 循环：到期后进入下一年的该月该日倒计时，仅当日加红色描边
class CountdownEvent {
  final String id;
  String icon;
  String name;
  String note; // 事件备注（15 字以内）
  DateTime target; // 目的日（含时分）
  String type; // 纪念日 | 资产日
  bool loop; // 是否循环
  bool pinned; // 是否置顶

  CountdownEvent({
    required this.id,
    required this.icon,
    required this.name,
    this.note = '',
    required this.target,
    required this.type,
    this.loop = false,
    this.pinned = false,
  });

  static const List<String> types = ['纪念日', '资产日'];

  /// 编辑页快捷图标（与资产图景同款排版规则：一排 7 个 + 「...」更多）
  static const List<String> quickIcons = [
    '🎂', '💝', '🎓', '🏠', '✈️', '💍', '🎉',
    '📅', '⭐', '🌸', '🎁', '🏥', '💼', '🐣', '🌙', '❤️',
  ];

  static String defaultIconFor(String type) =>
      type == '资产日' ? '💰' : '🎂';

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime today() => dateOnly(DateTime.now());

  /// 是否尚未到达（未来）
  bool get isFuture => target.isAfter(DateTime.now());

  /// 不循环且目的日已过 → 停止计数、卡片置灰
  bool get expired => !loop && target.isBefore(DateTime.now());

  /// 今天是否为目的日当天
  bool get isDueToday => daysLeft == 0;

  /// 循环模式：取今年或明年的目标日（保持时分）。
  /// 注意只比较「日期」：目的日就是今天时不能因时刻差几毫秒而跳到明年。
  DateTime _loopTarget(DateTime from) {
    final t = dateOnly(target);
    final f = dateOnly(from);
    var candidate =
        DateTime(f.year, t.month, t.day, target.hour, target.minute);
    if (dateOnly(candidate).isBefore(f)) {
      candidate = DateTime(
          f.year + 1, t.month, t.day, target.hour, target.minute);
    }
    return candidate;
  }

  DateTime get effectiveTarget {
    if (!loop) return target;
    return _loopTarget(DateTime.now());
  }

  /// 距目的日天数：未来为正（倒数），过去为负（正数）
  int get daysLeft => dateOnly(effectiveTarget).difference(today()).inDays;

  /// 卡片主文案。到期（已结束）后主文案留空，只由副标题承担计数展示：
  /// - 纪念日 → 「已过去 x 天」
  /// - 资产日 → 「已拥有 x 天」
  String get displayText {
    final d = daysLeft;
    if (d == 0) return '就是今天';
    if (d > 0) return '还有 $d 天';
    return ''; // 已过去：交给副标题显示，避免重复
  }

  /// 循环事件仅在当日需要红色描边
  bool get loopHighlight => loop && isDueToday;

  /// 副标题。
  /// - 已结束（不循环且已过目的日）：纪念日「已过去 x 天」/ 资产日「已拥有 x 天」
  /// - 资产日：目的日已到 → 「已拥有 x 天」
  /// - 纪念日：目的日已过 → 「已过去 x 天」
  /// 未来日返回 null（不显示副标题）
  String? get subtitle {
    final t = dateOnly(target);
    final now = today();
    if (t.isAfter(now)) return null;
    final diff = now.difference(t).inDays;
    if (type == '资产日') return '已拥有 $diff 天';
    return '已过去 $diff 天';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'icon': icon,
        'name': name,
        'note': note,
        'target': target.toIso8601String(),
        'type': type,
        'loop': loop,
        'pinned': pinned,
      };

  factory CountdownEvent.fromJson(Map<String, dynamic> j) => CountdownEvent(
        id: j['id'] as String? ?? '',
        icon: j['icon'] as String? ?? '🎂',
        name: j['name'] as String? ?? '',
        note: j['note'] as String? ?? '',
        target: DateTime.tryParse(j['target'] as String? ?? '') ??
            DateTime.now(),
        type: j['type'] as String? ?? '纪念日',
        loop: j['loop'] as bool? ?? false,
        pinned: j['pinned'] as bool? ?? false,
      );
}
