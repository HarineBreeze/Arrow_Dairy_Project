import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// v4.9.37 未来信件「开封横幅」已提醒记录。
///
/// 一封未来信件到期（进入可见日期）后，App 内上方横幅只弹一次。
/// 记录为已提醒的笔记 id 集合，按笔记 id 去重；删掉该笔记后记录自然残留、
/// 不影响任何逻辑（同 id 不会复用）。
class FutureLetterNoticeLog {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/future_letter_notice.json');
  }

  static Future<Set<String>> shown() async {
    try {
      final f = await _file();
      if (!await f.exists()) return <String>{};
      final map = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return (map['ids'] as List<dynamic>? ?? []).whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> markShown(String noteId) async {
    try {
      final ids = await shown();
      ids.add(noteId);
      final f = await _file();
      await f.writeAsString(jsonEncode({'ids': ids.toList()}));
    } catch (_) {}
  }
}
