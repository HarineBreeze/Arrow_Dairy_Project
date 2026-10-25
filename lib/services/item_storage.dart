import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/item.dart';

class ItemStorage {

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/items.json');
  }

  static Future<List<Item>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => Item.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Item> items) async {
    final file = await _file();
    final list = items.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }
}
