import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/diary_entry.dart';
import '../models/item.dart';
import '../models/user_profile.dart';
import 'diary_storage.dart';
import 'item_storage.dart';
import 'user_storage.dart';

class BackupData {
  final List<DiaryEntry> entries;
  final List<Item> items;
  final UserProfile profile;

  BackupData({
    required this.entries,
    required this.items,
    required this.profile,
  });
}

class BackupService {
  /// 收集当前全部数据（含头像）
  static Future<BackupData> collect() async {
    final entries = await DiaryStorage.load();
    final items = await ItemStorage.load();
    final profile = await UserStorage.load();
    return BackupData(entries: entries, items: items, profile: profile);
  }

  /// 生成备份 JSON 文件（临时目录），返回文件路径
  static Future<String> exportToFile() async {
    final entries = await DiaryStorage.load();
    final items = await ItemStorage.load();
    final profile = await UserStorage.load();

    String? avatarB64;
    if (profile.avatarPath.isNotEmpty) {
      final f = File(profile.avatarPath);
      if (await f.exists()) {
        avatarB64 = base64Encode(await f.readAsBytes());
      }
    }

    final map = {
      'app': 'vector-diary',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'diaries': entries.map((e) => e.toJson()).toList(),
      'items': items.map((e) => e.toJson()).toList(),
      'profile': profile.toJson(),
      'avatarData': avatarB64,
    };

    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    final name =
        '矢量日记备份_${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}.json';
    final file = File('${dir.path}/$name');
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(map));
    return file.path;
  }

  /// 从文件读取并校验，返回解析出的数据（不写盘）
  static Future<BackupData> parseBackupFile(String path) async {
    final file = File(path);
    if (!await file.exists()) throw '文件不存在';
    final content = await file.readAsString();
    final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw '不是有效的 JSON 文件';
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != 'vector-diary') {
      throw '不是「矢量日记」的备份文件';
    }
    final entries = <DiaryEntry>[];
    if (decoded['diaries'] is List) {
      for (final e in decoded['diaries'] as List) {
        try {
          entries.add(DiaryEntry.fromJson(e as Map<String, dynamic>));
        } catch (_) {}
      }
    }
    final items = <Item>[];
    if (decoded['items'] is List) {
      for (final e in decoded['items'] as List) {
        try {
          items.add(Item.fromJson(e as Map<String, dynamic>));
        } catch (_) {}
      }
    }
    UserProfile profile = UserProfile();
    if (decoded['profile'] is Map<String, dynamic>) {
      try {
        profile = UserProfile.fromJson(decoded['profile']);
      } catch (_) {}
    }
    // 恢复头像
    final avatarB64 = decoded['avatarData'];
    if (avatarB64 is String && avatarB64.isNotEmpty) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final newPath =
            '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(newPath).writeAsBytes(base64Decode(avatarB64));
        profile.avatarPath = newPath;
      } catch (_) {}
    }
    return BackupData(entries: entries, items: items, profile: profile);
  }

  /// 用解析出的数据覆盖本地存储
  static Future<void> applyBackup(BackupData data) async {
    await DiaryStorage.save(data.entries);
    await ItemStorage.save(data.items);
    await UserStorage.save(data.profile);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
