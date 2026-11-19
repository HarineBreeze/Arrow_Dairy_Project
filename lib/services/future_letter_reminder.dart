import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/diary_entry.dart';

/// v4.9.37「未来信件」系统通知：到期当天上午 9:00 推送一条通知栏消息。
///
/// 复用与倒数日一致的「 MethodChannel → Android 精确闹钟 → BroadcastReceiver → 通知」链路，
/// 但走独立通道与独立 id 段，避免和事件提醒互相 cancel。
///
/// 所有异常都吞掉 —— 通知是附加提醒，不能影响笔记本身的读写。
class FutureLetterReminder {
  static const MethodChannel _ch = MethodChannel('vector_diary/future_letter');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// 到期当天这条通知的固定文案（正文由日期拼出）
  static String bodyOf(DateTime revealAt) =>
      '${revealAt.year}年${revealAt.month}月${revealAt.day}日，你给未来写的信请查收～';

  /// 重新注册全部「仍在封存期」的未来信件通知（幂等：先清空再逐条注册）。
  /// 已开封的信件不再注册 —— 开封提醒由 App 内横幅负责。
  static Future<void> syncAll(
    List<DiaryEntry> entries, {
    DateTime? now,
  }) async {
    if (!_supported) return;
    final t = now ?? DateTime.now();
    try {
      await _ch.invokeMethod('cancelAll');
      for (final e in entries) {
        final r = e.revealAt;
        if (r == null) continue;
        if (!e.isSealedAt(t)) continue; // 已到期：不再预约系统通知
        final at = DateTime(r.year, r.month, r.day, 9, 0);
        // 若到期日 9 点已过（极少：如当天首次打开），安排一个短延迟立即提醒
        final fireAt = at.isAfter(t) ? at : t.add(const Duration(seconds: 5));
        await _ch.invokeMethod('schedule', {
          'id': _stableId(e.id),
          'body': bodyOf(r),
          'at': fireAt.millisecondsSinceEpoch,
        });
      }
    } catch (_) {}
  }

  /// 立即发一条通知（用于 App 内检测到「今天开封、但闹钟可能已错过」时兜底）
  static Future<void> notifyNow(DateTime revealAt) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('show', {'body': bodyOf(revealAt)});
    } catch (_) {}
  }

  /// 字符串 id → 稳定正整数（与事件提醒同算法，但原生侧用独立 id 段）
  static int _stableId(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x3FFFFFFF;
    }
    return h % 2000;
  }
}
