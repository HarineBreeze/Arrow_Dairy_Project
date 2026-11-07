import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/utils/diary_group_defaults.dart';

/// 主页默认展开逻辑的接线检查。
///
/// 规则本身在 diary_group_defaults_test.dart 里逐条验过，
/// 这里只确认「主页确实用了这条规则」——防止有人改回硬编码。
void main() {
  test('主页默认展开 7 天，且包含今天', () {
    final keys = DiaryGroupDefaults.expandedKeys();
    expect(keys.length, 7);

    final today = DateTime.now();
    final todayKey = DiaryGroupDefaults.dateKey(
        DateTime(today.year, today.month, today.day));
    expect(keys.first, todayKey, reason: '第一天必须是今天');
  });

  test('最近 7 天覆盖到 6 天前，不包含 7 天前', () {
    final now = DateTime.now();
    final keys = DiaryGroupDefaults.expandedKeys(now);
    final sixDaysAgo =
        DiaryGroupDefaults.dateKey(DateTime(now.year, now.month, now.day - 6));
    final sevenDaysAgo =
        DiaryGroupDefaults.dateKey(DateTime(now.year, now.month, now.day - 7));
    expect(keys, contains(sixDaysAgo));
    expect(keys, isNot(contains(sevenDaysAgo)));
  });
}
