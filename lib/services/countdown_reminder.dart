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
    final t = CountdownEvent.dateOnly(e.target);
    final now = DateTime.now();

    // 本次目标日（未过则为原日期，已过且循环则推算到今年/明年），提醒时刻取用户设定时分
    final due = e.loop ? e.effectiveTarget : t;
    final hh = e.target.hour;
    final mm = e.target.minute;
    final at = DateTime(due.year, due.month, due.day, hh, mm);
    if (at.isBefore(now)) {
      if (!e.loop) return; // 不循环且已过 → 不再提醒
      // 循环：注册明年的该月该日
      await _register(
          id, e, DateTime(due.year + 1, due.month, due.day, hh, mm));
      return;
    }
    await _register(id, e, at);
    // 循环事件：顺带注册下一年（长期提醒）；不循环只注册一次
    if (e.loop) {
      await _register(
          id, e, DateTime(at.year + 1, at.month, at.day, hh, mm));
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
