import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/utils/diary_group_defaults.dart';

/// 「笔记主页默认展开最近 7 天」的规则测试。
///
/// 重点全在边界上：跨月、跨年、闰日、月末 31 号。这些场景靠手点
/// UI 验证成本极高，抽成纯函数后可以精确断言。
void main() {
  group('最近 7 天', () {
    test('从今天往前数 7 天，含今天，新的在前', () {
      final now = DateTime(2026, 11, 2, 20, 45);
      final days = DiaryGroupDefaults.recentDates(now);
      expect(days.length, 7);
      expect(days.first, DateTime(2026, 11, 2));
      expect(days.last, DateTime(2026, 10, 27));
    });

    test('key 格式为 yyyy-MM-dd，月日补零', () {
      final keys = DiaryGroupDefaults.expandedKeys(DateTime(2026, 11, 2));
      expect(keys, [
        '2026-11-02',
        '2026-11-01',
        '2026-10-31',
        '2026-10-30',
        '2026-10-29',
        '2026-10-28',
        '2026-10-27',
      ]);
    });

    test('跨月：11 月 2 号回退要正确落到 10 月', () {
      final keys = DiaryGroupDefaults.expandedKeys(DateTime(2026, 11, 2));
      expect(keys.where((k) => k.startsWith('2026-10')), hasLength(5));
    });

    test('跨年：1 月 3 号回退要落到上一年 12 月', () {
      final keys = DiaryGroupDefaults.expandedKeys(DateTime(2026, 1, 3));
      expect(keys, [
        '2026-01-03',
        '2026-01-02',
        '2026-01-01',
        '2025-12-31',
        '2025-12-30',
        '2025-12-29',
        '2025-12-28',
      ]);
    });

    test('闰日：3 月 1 号（闰年）要包含 2 月 29 日', () {
      final keys = DiaryGroupDefaults.expandedKeys(DateTime(2024, 3, 1));
      expect(keys, contains('2024-02-29'));
      expect(keys.contains('2024-02-28'), isTrue);
    });

    test('平年 3 月 1 号没有 2 月 29 日，落到 2 月 28 日', () {
      final keys = DiaryGroupDefaults.expandedKeys(DateTime(2026, 3, 1));
      expect(keys, isNot(contains('2026-02-29')));
      expect(keys, contains('2026-02-23'));
    });

    test('月末 31 号不出 0 日这种非法日期', () {
      final keys = DiaryGroupDefaults.expandedKeys(DateTime(2026, 5, 31));
      // 5/31 往前 7 天：5/31 … 5/25，不该出现「4 月 31 日」
      expect(keys, [
        '2026-05-31',
        '2026-05-30',
        '2026-05-29',
        '2026-05-28',
        '2026-05-27',
        '2026-05-26',
        '2026-05-25',
      ]);
      expect(keys.any((k) => k.contains('-00')), isFalse);
      expect(keys.any((k) => k.contains('2026-04-31')), isFalse);
    });

    test('月初 1 号要回退到上个月最后一天', () {
      final keys = DiaryGroupDefaults.expandedKeys(DateTime(2026, 5, 1));
      expect(keys, contains('2026-04-30'));
      expect(keys.last, '2026-04-25');
    });

    test('2 月末 3 月 1 号在平年回退到 2 月 22 日', () {
      final keys = DiaryGroupDefaults.expandedKeys(DateTime(2026, 3, 1));
      expect(keys.last, '2026-02-23');
    });

    test('结果无重复、无乱序', () {
      final days = DiaryGroupDefaults.recentDates(DateTime(2026, 11, 2));
      expect(days.toSet(), hasLength(days.length));
      for (var i = 1; i < days.length; i++) {
        expect(days[i].isBefore(days[i - 1]), isTrue,
            reason: '第 $i 项应比前一项早');
      }
    });

    test('天数可配置：传 1 只有今天，传 30 覆盖整月', () {
      final now = DateTime(2026, 11, 2);
      expect(DiaryGroupDefaults.expandedKeys(now, 1), ['2026-11-02']);
      expect(DiaryGroupDefaults.expandedKeys(now, 30), hasLength(30));
      expect(DiaryGroupDefaults.expandedKeys(now, 30).last, '2026-10-04');
    });

    test('不再包含「只展开今天和昨天」的旧行为', () {
      // 回归断言：旧实现返回 2 个 key，现在是 7 个
      final keys = DiaryGroupDefaults.expandedKeys(DateTime(2026, 11, 2));
      expect(keys.length, isNot(2));
      expect(keys.length, 7);
    });
  });

  group('dateKey 与页面分组格式一致', () {
    test('个位数月份日期补零，共 10 个字符', () {
      expect(DiaryGroupDefaults.dateKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(DiaryGroupDefaults.dateKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect(DiaryGroupDefaults.dateKey(DateTime(2026, 1, 5)).length, 10);
    });

    test('忽略时分秒，只看日期', () {
      expect(
        DiaryGroupDefaults.dateKey(DateTime(2026, 11, 2, 23, 59, 59)),
        DiaryGroupDefaults.dateKey(DateTime(2026, 11, 2, 0, 0, 1)),
      );
    });
  });
}
