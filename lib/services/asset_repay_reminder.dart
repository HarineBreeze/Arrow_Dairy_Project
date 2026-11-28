import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/asset.dart';

/// v5.0.21 负资产还款提醒。
///
/// 复用与倒数日/未来信件一致的「MethodChannel → Android 精确闹钟 →
/// BroadcastReceiver → 通知栏」链路，走独立通道与独立 id 段，
/// 避免和事件/信件提醒互相 cancel。
/// 到期当天 9:00 推一条通知栏消息；App 内另由横幅补一次提示。
/// 所有异常都吞掉 —— 提醒是附加能力，不影响资产读写。
class AssetRepayReminder {
  static const MethodChannel _ch = MethodChannel('vector_diary/asset_repay');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// 通知正文（含还款对象）
  static String bodyOf(Asset a) {
    final who = a.owner.isEmpty ? '' : '${a.owner}的';
    final date = a.repayDate;
    final day = date == null
        ? ''
        : '${date.year}年${date.month}月${date.day}日';
    return '$day $who${a.type}该还款啦，记得及时处理～';
  }

  /// 重新注册全部「待还款」资产的闹钟（幂等：先清空再逐条注册）。
  /// 仅负资产（信用卡/欠款/账单）且设了还款时间的才注册。
  static Future<void> syncAll(
    List<Asset> assets, {
    DateTime? now,
  }) async {
    if (!_supported) return;
    final t = now ?? DateTime.now();
    try {
      await _ch.invokeMethod('cancelAll');
      for (final a in assets) {
        final d = a.repayDate;
        if (d == null) continue;
        final isLiability = a.type == '信用卡' || a.type == '欠款' || a.type == '账单';
        if (!isLiability) continue;
        final at = DateTime(d.year, d.month, d.day, 9, 0);
        // 到期日 9 点已过 → 短延迟立即提醒（与信件同策略）
        final fireAt = at.isAfter(t) ? at : t.add(const Duration(seconds: 5));
        await _ch.invokeMethod('schedule', {
          'id': _stableId(a.id),
          'body': bodyOf(a),
          'at': fireAt.millisecondsSinceEpoch,
        });
      }
    } catch (_) {}
  }

  /// 立即发一条通知（App 内检测到今天到期、但闹钟可能已错过时兜底）
  static Future<void> notifyNow(Asset a) async {
    if (!_supported) return;
    try {
      await _ch.invokeMethod('show', {'body': bodyOf(a)});
    } catch (_) {}
  }

  /// 字符串 id → 稳定正整数（与既有通道同算法）
  static int _stableId(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x3FFFFFFF;
    }
    return h % 2000;
  }
}

/// App 内「还款到期横幅」已提醒记录：按资产 id + 日期去重，
/// 同一天多次打开 App 只弹一次。
class AssetRepayBannerLog {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/asset_repay_banner_log.json');
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static Future<Set<String>> shownToday() async {
    try {
      final f = await _file();
      if (!await f.exists()) return <String>{};
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (map['date'] != _today()) return <String>{};
      return (map['ids'] as List<dynamic>? ?? []).whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> markShown(String id) async {
    try {
      final ids = await shownToday();
      ids.add(id);
      final f = await _file();
      await f.writeAsString(jsonEncode({'date': _today(), 'ids': ids.toList()}));
    } catch (_) {}
  }
}
