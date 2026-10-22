import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/diary_entry.dart';

class DiaryStorage {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/diaries.json');
  }

  static Future<List<DiaryEntry>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => DiaryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<DiaryEntry> entries) async {
    final file = await _file();
    final list = entries.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }
}
