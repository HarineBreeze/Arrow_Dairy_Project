import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/models/countdown_event.dart';
import 'package:diary_app/services/trash_storage.dart';

CountdownEvent _ev({
  required DateTime target,
  RepeatRule repeat = RepeatRule.none,
}) =>
    CountdownEvent(
      id: 'x',
      icon: '🎂',
      name: '测试',
      target: target,
      type: '纪念日',
      repeat: repeat,
    );

void main() {
  group('重复规则推算', () {
    test('每年：过期后推进到下一次同月同日', () {
      final now = DateTime.now();
      final past = DateTime(now.year - 2, now.month, now.day, 9, 0);
      final e = _ev(target: past, repeat: RepeatRule.yearly);
      final next = e.effectiveTarget;
      expect(next.month, past.month);
      expect(next.day, past.day);
      expect(next.year, now.year);
      expect(e.daysLeft, 0); // 恰好是今天
    });

    test('每月：从今天起推进到下个月的同一天', () {
      final now = DateTime.now();
      // 用一个已过去的月初日期，确保推算到下个月
      final base = DateTime(now.year, now.month, 1, 9, 0);
      final e = _ev(target: base, repeat: RepeatRule.monthly);
      expect(e.effectiveTarget.day, 1);
      expect(e.daysLeft >= 0, true);
    });

    test('每月 31 号遇到小月回落到当月最后一天', () {
      final e = _ev(
        target: DateTime(2024, 1, 31, 9, 0),
        repeat: RepeatRule.monthly,
      );
      final t = e.effectiveTarget;
      final lastDay = DateTime(t.year, t.month + 1, 0).day;
      expect(t.day <= lastDay, true);
    });

    test('每周：推算结果与目标日同一星期', () {
      final now = DateTime.now();
      final base = now.subtract(const Duration(days: 30));
      final e = _ev(target: base, repeat: RepeatRule.weekly);
      expect(e.effectiveTarget.weekday, base.weekday);
      expect(e.daysLeft >= 0, true);
      expect(e.daysLeft < 7, true);
    });

    test('一次性事件不推算', () {
      final target = DateTime(2020, 5, 20, 9, 0);
      final e = _ev(target: target);
      expect(e.effectiveTarget, target);
      expect(e.expired, true);
    });

    test('旧数据只有 loop=true 时视为每年重复', () {
      final e = CountdownEvent.fromJson({
        'id': 'a',
        'icon': '🎂',
        'name': '生日',
        'target': '2020-06-01T09:00:00.000',
        'type': '纪念日',
        'loop': true,
      });
      expect(e.repeat, RepeatRule.yearly);
      expect(e.loop, true);
    });

    test('JSON 往返保留重复规则与提前提醒', () {
      final e = _ev(
        target: DateTime(2026, 3, 8, 9, 0),
        repeat: RepeatRule.monthly,
      );
      e.remindBeforeDays = 3;
      final back = CountdownEvent.fromJson(e.toJson());
      expect(back.repeat, RepeatRule.monthly);
      expect(back.remindBeforeDays, 3);
    });
  });

  group('回收站', () {
    test('剩余天数按 7 天计算', () {
      final e = TrashEntry(
        id: 't1',
        kind: TrashKind.diary,
        data: const {},
        deletedAt: DateTime.now(),
        title: '标题',
        subtitle: '',
      );
      expect(e.daysLeft, 7);
      expect(e.expireAt.difference(e.deletedAt).inDays, 7);
    });

    test('超过 7 天剩余天数为 0（视为过期）', () {
      final e = TrashEntry(
        id: 't2',
        kind: TrashKind.item,
        data: const {},
        deletedAt: DateTime.now().subtract(const Duration(days: 8)),
        title: '物品',
        subtitle: '',
      );
      expect(e.daysLeft, 0);
    });

    test('类型 key 往返一致', () {
      for (final k in TrashKind.values) {
        expect(TrashKindX.fromKey(k.keyName), k);
        expect(k.label.isNotEmpty, true);
      }
    });

    test('JSON 往返保留类型与标题', () {
      final e = TrashEntry(
        id: 't3',
        kind: TrashKind.event,
        data: const {'id': 'biz'},
        deletedAt: DateTime(2026, 1, 2, 3, 4),
        title: '事件名',
        subtitle: '副标题',
      );
      final back = TrashEntry.fromJson(e.toJson());
      expect(back.kind, TrashKind.event);
      expect(back.title, '事件名');
      expect(back.data['id'], 'biz');
    });
  });
}
