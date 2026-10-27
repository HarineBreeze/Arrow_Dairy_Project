import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/countdown_event.dart';

/// 倒数日存储（纯本地 JSON）。
class CountdownStorage {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/countdowns.json');
  }

  static Future<List<CountdownEvent>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      return list
          .whereType<Map>()
          .map((e) => CountdownEvent.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<CountdownEvent> events) async {
    final f = await _file();
    await f.writeAsString(
        jsonEncode(events.map((e) => e.toJson()).toList()));
  }
}
