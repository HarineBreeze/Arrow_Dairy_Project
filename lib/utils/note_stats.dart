import '../models/diary_entry.dart';

/// 笔记主页数据栏统计结果。
///
/// - [totalCount]：全部笔记篇数。
/// - [totalChars]：全部笔记正文字数总和（按 Unicode 字符计，含空白与标点）。
/// - [streak]：当前连续记录天数（今天或昨天有记录才算延续，否则为 0 = 已断更）。
/// - [longest]：历史最长连续记录天数。
/// - [isCurrent]：是否处于连续状态（true 显示「连续记录」，false 显示「最长记录」）。
class NoteStats {
  final int totalCount;
  final int totalChars;
  final int streak;
  final int longest;
  final bool isCurrent;

  const NoteStats({
    required this.totalCount,
    required this.totalChars,
    required this.streak,
    required this.longest,
    required this.isCurrent,
  });

  /// 显示用文案：
  /// - 连续中：标题「连续记录」+ 值「已连续 X 天」；
  /// - 断更：标题「最长记录」+ 值「X 天」。
  String get streakLabel => isCurrent ? '连续记录' : '最长记录';
  String get streakValue => isCurrent ? '$streak天' : '$longest天';

  /// 基于全部笔记计算统计数据。
  ///
  /// [now] 可注入便于测试；默认取当前时间。
  /// 连续天数以「自然日」为单位，按 publishDate 归集；同一天多篇只算一天。
  factory NoteStats.compute(List<DiaryEntry> entries, {DateTime? now}) {
    final totalCount = entries.length;
    final totalChars = entries.fold<int>(0, (sum, e) => sum + e.content.length);

    // 归一到自然日（当地零点），去重
    final days = <DateTime>{};
    for (final e in entries) {
      final d = e.publishDate;
      days.add(DateTime(d.year, d.month, d.day));
    }
    if (days.isEmpty) {
      return const NoteStats(
          totalCount: 0, totalChars: 0, streak: 0, longest: 0, isCurrent: false);
    }

    final sorted = days.toList()..sort();
    // 历史最长连续段
    var longest = 1;
    var run = 1;
    for (var i = 1; i < sorted.length; i++) {
      final diff = sorted[i].difference(sorted[i - 1]).inDays;
      if (diff == 1) {
        run++;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
    }

    final today = now ?? DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final set = days.toSet();

    // 当前连续：以今天为锚，今天没写则允许从昨天起算（今天尚未结束，不算断更）。
    var anchor = t0;
    if (!set.contains(anchor)) {
      final yesterday = t0.subtract(const Duration(days: 1));
      if (set.contains(yesterday)) {
        anchor = yesterday;
      } else {
        // 今天、昨天都没写 → 已断更
        return NoteStats(
            totalCount: totalCount,
            totalChars: totalChars,
            streak: 0,
            longest: longest,
            isCurrent: false);
      }
    }

    var streak = 0;
    var cursor = anchor;
    while (set.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return NoteStats(
      totalCount: totalCount,
      totalChars: totalChars,
      streak: streak,
      longest: longest,
      isCurrent: true,
    );
  }
}
