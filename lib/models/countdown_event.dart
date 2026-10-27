import 'dart:convert';

/// 倒数日事件。
/// - 日期类型：纪念日 / 资产日
/// - 目的日可为过去或未来：未来 → 倒数，过去 → 正数
/// - 循环：到期后进入下一年的该月该日倒计时，卡片加红色描边
class CountdownEvent {
  final String id;
  String icon;
  String name;
  DateTime target; // 目的日（仅日期部分有效）
  String type; // 纪念日 | 资产日
  bool loop; // 是否循环
  bool pinned; // 是否置顶

  CountdownEvent({
    required this.id,
    required this.icon,
    required this.name,
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

  /// 仅日期部分
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 今天（仅日期）
  static DateTime today() => dateOnly(DateTime.now());

  /// 是否已到期（不循环且目的日已过 → 停止计数、卡片置灰）
  bool get expired => !loop && dateOnly(target).isBefore(today());

  /// 是否正在「当天」（今天 = 目的日；循环模式下为今年的该月该日）
  bool get isDueToday => daysLeft == 0;

  /// 循环模式下，取今年或明年的目标日
  DateTime _loopTarget(DateTime from) {
    final t = dateOnly(target);
    var candidate = DateTime(from.year, t.month, t.day);
    if (candidate.isBefore(dateOnly(from))) {
      candidate = DateTime(from.year + 1, t.month, t.day);
    }
    return candidate;
  }

  /// 目标日（循环模式自动推进到下一年的该月该日）
  DateTime get effectiveTarget {
    if (!loop) return dateOnly(target);
    return _loopTarget(DateTime.now());
  }

  /// 距目的日天数：未来为正（倒数），过去为负（正数计数）
  int get daysLeft {
    final t = effectiveTarget;
    return t.difference(today()).inDays;
  }

  /// 卡片展示文案
  String get displayText {
    if (expired) return '已结束';
    final d = daysLeft;
    if (d == 0) return '就是今天';
    if (d > 0) return '还有 $d 天';
    return '已过去 ${-d} 天';
  }

  /// 循环模式到期后是否应显示红色描边（已过目的日、进入下一年倒计时）
  bool get loopHighlight {
    if (!loop) return false;
    final t = dateOnly(target);
    // 今年该月该日已过 → 说明已进入下一年的倒计时
    final thisYearTarget = DateTime(DateTime.now().year, t.month, t.day);
    return dateOnly(DateTime.now()).isAfter(thisYearTarget);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'icon': icon,
        'name': name,
        'target': target.toIso8601String(),
        'type': type,
        'loop': loop,
        'pinned': pinned,
      };

  factory CountdownEvent.fromJson(Map<String, dynamic> j) => CountdownEvent(
        id: j['id'] as String? ?? '',
        icon: j['icon'] as String? ?? '🎂',
        name: j['name'] as String? ?? '',
        target: DateTime.tryParse(j['target'] as String? ?? '') ??
            DateTime.now(),
        type: j['type'] as String? ?? '纪念日',
        loop: j['loop'] as bool? ?? false,
        pinned: j['pinned'] as bool? ?? false,
      );
}
