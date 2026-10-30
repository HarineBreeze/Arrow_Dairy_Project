import 'dart:convert';

/// 重复规则：
/// - none  一次性（到期后停止计数）
/// - yearly 每年同日（生日 / 纪念日）
/// - monthly 每月同日
/// - weekly 每周同日
enum RepeatRule { none, yearly, monthly, weekly }

extension RepeatRuleX on RepeatRule {
  String get label {
    switch (this) {
      case RepeatRule.none:
        return '不重复';
      case RepeatRule.yearly:
        return '每年';
      case RepeatRule.monthly:
        return '每月';
      case RepeatRule.weekly:
        return '每周';
    }
  }

  String get keyName => name;

  static RepeatRule fromKey(String? key) {
    switch (key) {
      case 'yearly':
        return RepeatRule.yearly;
      case 'monthly':
        return RepeatRule.monthly;
      case 'weekly':
        return RepeatRule.weekly;
      default:
        return RepeatRule.none;
    }
  }
}

/// 倒数日事件。
/// - 日期类型：纪念日 / 资产日
/// - 目的日含时分；未来 → 倒数，过去 → 正数
/// - 重复：支持每年 / 每月 / 每周 / 一次性，到期后进入下一个周期的倒计时
class CountdownEvent {
  final String id;
  String icon;
  String name;
  String note; // 事件备注（15 字以内）
  DateTime target; // 目的日（含时分）
  String type; // 纪念日 | 资产日
  RepeatRule repeat; // 重复规则
  int remindBeforeDays; // 提前几天提醒（0 = 当天）
  bool pinned; // 是否置顶

  CountdownEvent({
    required this.id,
    required this.icon,
    required this.name,
    this.note = '',
    required this.target,
    required this.type,
    RepeatRule? repeat,
    bool loop = false, // 兼容旧参数：loop=true 等价每年重复
    this.remindBeforeDays = 0,
    this.pinned = false,
  }) : repeat = repeat ??
            (loop ? RepeatRule.yearly : RepeatRule.none);

  /// 是否循环（非一次性）
  bool get loop => repeat != RepeatRule.none;

  /// 重复规则的中文描述（列表卡片副标题用）
  String get repeatLabel => repeat.label;

  static const List<String> types = ['纪念日', '资产日'];

  /// 编辑页快捷图标（与资产全景同款排版规则：一排 7 个 + 「...」更多）
  static const List<String> quickIcons = [
    '🎂', '💝', '🎓', '🏠', '✈️', '💍', '🎉',
    '📅', '⭐', '🌸', '🎁', '🏥', '💼', '🐣', '🌙', '❤️',
  ];

  static String defaultIconFor(String type) =>
      type == '资产日' ? '💰' : '🎂';

  /// 深拷贝（编辑页隔离用：放弃修改不影响列表里的实例）
  CountdownEvent clone() => CountdownEvent.fromJson(toJson());

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime today() => dateOnly(DateTime.now());

  /// 是否尚未到达（未来）
  bool get isFuture => target.isAfter(DateTime.now());

  /// 不循环且目的日已过 → 停止计数、卡片置灰
  bool get expired => !loop && target.isBefore(DateTime.now());

  /// 今天是否为目的日当天
  bool get isDueToday => daysLeft == 0;

  /// 按重复规则推算 `from` 之后（含当天）的下一个目标日，保持时分。
  /// 一次性事件直接返回原 target。
  DateTime _nextTarget(DateTime from) {
    final t = dateOnly(target);
    final f = dateOnly(from);
    final hh = target.hour, mm = target.minute;
    switch (repeat) {
      case RepeatRule.none:
        return target;
      case RepeatRule.yearly:
        var y = f.year;
        var candidate = DateTime(y, t.month, t.day, hh, mm);
        if (dateOnly(candidate).isBefore(f)) {
          y += 1;
          candidate = DateTime(y, t.month, t.day, hh, mm);
        }
        return candidate;
      case RepeatRule.monthly:
        // 逐月推进，处理 31 号在小月的情况（落到该月最后一天）
        var y = f.year, m = f.month;
        for (var i = 0; i < 24; i++) {
          final lastDay = DateTime(y, m + 1, 0).day;
          final d = t.day > lastDay ? lastDay : t.day;
          final candidate = DateTime(y, m, d, hh, mm);
          if (!dateOnly(candidate).isBefore(f)) return candidate;
          m += 1;
          if (m > 12) {
            m = 1;
            y += 1;
          }
        }
        return DateTime(f.year, f.month, f.day, hh, mm);
      case RepeatRule.weekly:
        // 以原目标日的星期为准，推进到本周或下周的同一天
        final base = DateTime(f.year, f.month, f.day, hh, mm);
        final offset = (t.weekday - f.weekday) % 7;
        var candidate = base.add(Duration(days: offset));
        if (offset == 0 && DateTime(f.year, f.month, f.day, hh, mm)
            .isBefore(DateTime.now()) &&
            hh * 60 + mm <= DateTime.now().hour * 60 + DateTime.now().minute) {
          candidate = candidate.add(const Duration(days: 7));
        }
        return candidate;
    }
  }

  DateTime get effectiveTarget {
    if (!loop) return target;
    return _nextTarget(DateTime.now());
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
        'repeat': repeat.keyName,
        'loop': loop, // 兼容旧版本读取
        'remindBeforeDays': remindBeforeDays,
        'pinned': pinned,
      };

  factory CountdownEvent.fromJson(Map<String, dynamic> j) {
    final type = j['type'] as String? ?? '纪念日';
    // 新数据读 repeat；旧数据只有 loop 布尔 → 等价每年
    var repeat = RepeatRuleX.fromKey(j['repeat'] as String?);
    if (repeat == RepeatRule.none && (j['loop'] as bool? ?? false)) {
      repeat = RepeatRule.yearly;
    }
    return CountdownEvent(
      id: j['id'] as String? ?? '',
      icon: (j['icon'] as String? ?? '').trim().isEmpty
          ? defaultIconFor(type)
          : j['icon'] as String,
      name: j['name'] as String? ?? '',
      note: j['note'] as String? ?? '',
      target:
          DateTime.tryParse(j['target'] as String? ?? '') ?? DateTime.now(),
      type: type,
      repeat: repeat,
      remindBeforeDays: (j['remindBeforeDays'] as num?)?.toInt() ?? 0,
      pinned: j['pinned'] as bool? ?? false,
    );
  }
}
