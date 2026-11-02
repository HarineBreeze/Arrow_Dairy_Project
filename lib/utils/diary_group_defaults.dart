/// 笔记主页「默认展开哪些日期分组」的规则。
///
/// 单独抽出来是为了能精确测边界（跨月、跨年、闰日）：
/// 页面里依赖存储和异步加载，直接测 UI 拿不到这些场景。
class DiaryGroupDefaults {
  DiaryGroupDefaults._();

  /// 日视图默认展开的天数：最近 7 个自然日（含今天）
  static const int recentDays = 7;

  /// 返回 [now] 往前数 [days] 天（含当天）的日期，新的在前。
  ///
  /// 用 `DateTime(y, m, d - i)` 而不是 `subtract(Duration(days: i))`：
  /// 前者按日历日回退，`d - i` 为 0 或负数时 Dart 会自动进位到上个月
  /// （甚至上一年）；后者是固定 24 小时，遇到夏令时切换会偏一小时，
  /// 导致日期串到前天或停在前天。
  static List<DateTime> recentDates([DateTime? now, int days = recentDays]) {
    final base = now ?? DateTime.now();
    return [
      for (var i = 0; i < days; i++)
        DateTime(base.year, base.month, base.day - i),
    ];
  }

  /// 日期分组 key，与主页分组用的格式一致：`yyyy-MM-dd`
  static String dateKey(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 默认展开的分组 key 列表
  static List<String> expandedKeys([DateTime? now, int days = recentDays]) =>
      [for (final d in recentDates(now, days)) dateKey(d)];
}
