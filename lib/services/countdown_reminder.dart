import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/countdown_event.dart';

/// 倒数日提醒：注册系统精确闹钟（Android 原生通道）。
/// 到目的日当天上午 9:00 弹通知；循环事件同时注册明年同日。
class CountdownReminder {
  static const MethodChannel _ch = MethodChannel('vector_diary/countdown');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// 重新注册全部事件的提醒（幂等：先清空再按需注册）
  static Future<void> syncAll(List<CountdownEvent> events) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('cancelAll');
      for (final e in events) {
        await _scheduleOne(e);
      }
    } catch (_) {
      // 通道异常（如旧系统/权限）不影响主流程
    }
  }

  /// 取消单个事件的提醒（删除事件时用，避免整表重排造成的卡顿）
  static Future<void> cancelOne(String eventId) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('cancel', {'id': _stableId(eventId)});
    } catch (_) {}
  }

  static Future<void> _scheduleOne(CountdownEvent e) async {
    final id = _stableId(e.id);
    final now = DateTime.now();
    final hh = e.target.hour;
    final mm = e.target.minute;

    // 提醒时刻 = 目标日 − 提前天数，时分沿用用户设定
    DateTime remindAt(DateTime due) {
      final d = due.subtract(Duration(days: e.remindBeforeDays));
      return DateTime(d.year, d.month, d.day, hh, mm);
    }

    // 本次目标日：重复事件由模型按规则算出；一次性事件取原日期
    var due = e.loop ? e.effectiveTarget : CountdownEvent.dateOnly(e.target);
    var at = remindAt(due);

    // 已过期（含提前天数导致提醒时刻已过）→ 重复事件再推一个周期
    if (at.isBefore(now)) {
      if (!e.loop) return; // 一次性且已过 → 不再提醒
      final probe = CountdownEvent(
        id: e.id,
        icon: e.icon,
        name: e.name,
        target: due.add(Duration(days: _periodDays(e.repeat, due))),
        type: e.type,
        repeat: e.repeat,
        remindBeforeDays: e.remindBeforeDays,
      );
      due = probe.effectiveTarget;
      at = remindAt(due);
      if (at.isBefore(now)) return;
    }

    await _register(id, e, at);

    // 重复事件：顺带注册下一个周期，保证长期提醒不断档
    if (e.loop) {
      final nextProbe = CountdownEvent(
        id: e.id,
        icon: e.icon,
        name: e.name,
        target: due.add(Duration(days: _periodDays(e.repeat, due))),
        type: e.type,
        repeat: e.repeat,
        remindBeforeDays: e.remindBeforeDays,
      );
      await _register(id, e, remindAt(nextProbe.effectiveTarget));
    }
  }

  /// 一个重复周期的近似天数（仅用于把日期推过当前点，实际日期由模型对齐）
  static int _periodDays(RepeatRule r, DateTime from) {
    switch (r) {
      case RepeatRule.weekly:
        return 7;
      case RepeatRule.monthly:
        return 28;
      case RepeatRule.yearly:
      case RepeatRule.none:
        return 365;
    }
  }

  static Future<void> _register(
      int id, CountdownEvent e, DateTime at) async {
    try {
      await _ch.invokeMethod('schedule', {
        'id': id,
        'emoji': e.icon,
        'title': e.name,
        'at': at.millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  /// 字符串 id → 稳定正整数（避免哈希随机化）
  static int _stableId(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x3FFFFFFF;
    }
    return h % 2000;
  }
}
