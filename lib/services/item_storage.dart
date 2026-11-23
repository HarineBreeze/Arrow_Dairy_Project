import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import '../models/item.dart';

class ItemStorage {
  /// 仅测试用注入：非 null 时 [load] / [save] 走内存替身，绕开真实 IO。
  /// 生产环境恒为 null，零行为变化。
  @visibleForTesting
  static Future<List<Item>> Function()? loadOverride;

  @visibleForTesting
  static Future<void> Function(List<Item> items)? saveOverride;

  @visibleForTesting
  static void resetOverride() {
    loadOverride = null;
    saveOverride = null;
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/items.json');
  }

  static Future<List<Item>> load() async {
    final override = loadOverride;
    if (override != null) return override();
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
    final override = saveOverride;
    if (override != null) return override(items);
    final file = await _file();
    final list = items.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(list));
  }
}
