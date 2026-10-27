import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// App 内横幅提醒的「已提醒」记录。
///
/// 目的：倒数日到期当天，不管用户一天内打开 App 多少次，
/// 同一个事件的横幅只弹一次（每天限一次）。
/// 记录形如 `{"date": "2026-10-27", "ids": ["e1", "e2"]}`；
/// 日期变化即视为新的一天，记录自动失效，无需清理历史。
class CountdownBannerLog {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/countdown_banner_log.json');
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// 今天已经弹过横幅的事件 id 集合
  static Future<Set<String>> shownToday() async {
    try {
      final f = await _file();
      if (!await f.exists()) return <String>{};
      final map =
          jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (map['date'] != _today()) return <String>{};
      return (map['ids'] as List<dynamic>? ?? [])
          .whereType<String>()
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// 记录某事件今天已弹过（仅保留当天的记录）
  static Future<void> markShown(String id) async {
    try {
      final ids = await shownToday();
      ids.add(id);
      final f = await _file();
      await f.writeAsString(
          jsonEncode({'date': _today(), 'ids': ids.toList()}));
    } catch (_) {}
  }
}
