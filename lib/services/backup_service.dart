import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/asset.dart';
import '../models/countdown_event.dart';
import '../models/diary_entry.dart';
import '../models/item.dart';
import '../models/user_profile.dart';
import 'app_settings.dart';
import 'asset_storage.dart';
import 'countdown_storage.dart';
import 'countdown_reminder.dart';
import 'diary_storage.dart';
import 'item_storage.dart';
import 'user_storage.dart';

class BackupData {
  final List<DiaryEntry> entries;
  final List<Item> items;
  final UserProfile profile;
  final List<Asset> assets; // 资产全景（v2 备份起包含）
  final List<CountdownEvent> countdowns; // 事件（v3 备份起包含）
  final String? fontFamilyId; // 笔记字体设置（v2 备份起包含）

  BackupData({
    required this.entries,
    required this.items,
    required this.profile,
    this.assets = const [],
    this.countdowns = const [],
    this.fontFamilyId,
  });
}

class BackupService {
  /// 收集当前全部数据（含头像）
  static Future<BackupData> collect() async {
    final entries = await DiaryStorage.load();
    final items = await ItemStorage.load();
    final profile = await UserStorage.load();
    final assets = await AssetStorage.load();
    final countdowns = await CountdownStorage.load();
    return BackupData(
      entries: entries,
      items: items,
      profile: profile,
      assets: assets,
      countdowns: countdowns,
    );
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

    final assets = await AssetStorage.load();
    final countdowns = await CountdownStorage.load();
    final map = {
      'app': 'vector-diary',
      'version': 3,
      'exportedAt': DateTime.now().toIso8601String(),
      'diaries': entries.map((e) => e.toJson()).toList(),
      'items': items.map((e) => e.toJson()).toList(),
      'profile': profile.toJson(),
      'avatarData': avatarB64,
      'assets': assets.map((e) => e.toJson()).toList(),
      'countdowns': countdowns.map((e) => e.toJson()).toList(),
      'settings': {'fontFamily': AppSettings.fontFamilyId},
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
    // 资产全景 + 设置（v2 备份起包含；旧备份为空，导入时跳过）
    final assets = <Asset>[];
    if (decoded['assets'] is List) {
      for (final e in decoded['assets'] as List) {
        try {
          assets.add(Asset.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
    }
    // 事件（v3 备份起包含；旧备份为空）
    final countdowns = <CountdownEvent>[];
    if (decoded['countdowns'] is List) {
      for (final e in decoded['countdowns'] as List) {
        try {
          countdowns.add(
              CountdownEvent.fromJson(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
    }
    String? fontFamilyId;
    if (decoded['settings'] is Map<String, dynamic>) {
      fontFamilyId = decoded['settings']['fontFamily'] as String?;
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
    return BackupData(
      entries: entries,
      items: items,
      profile: profile,
      assets: assets,
      countdowns: countdowns,
      fontFamilyId: fontFamilyId,
    );
  }

  /// 用解析出的数据覆盖本地存储
  static Future<void> applyBackup(BackupData data) async {
    await DiaryStorage.save(data.entries);
    await ItemStorage.save(data.items);
    await UserStorage.save(data.profile);
    await AssetStorage.save(data.assets);
    await CountdownStorage.save(data.countdowns);
    await CountdownReminder.syncAll(data.countdowns);
    if (data.fontFamilyId != null) {
      await AppSettings.setFontFamily(data.fontFamilyId!);
    }
  }

  /// 把备份数据「增添合并」进本地存储（保留本地已有内容）：
  /// - id 相同：日记有 updatedAt，取更新的一方；物品 / 资产 / 事件没有
  ///   时间戳，一律保留本地（本地才是用户正在维护的数据）；
  /// - id 不同：直接追加；
  /// - 个人信息、字体设置：保留本地，合并不改变当前使用中的外观。
  ///
  /// 返回合并统计（各项合计的新增 / 更新条数）。
  static Future<MergeResult> mergeBackup(BackupData incoming) async {
    int added = 0;
    int updated = 0;

    // 日记：按 id 对齐，updatedAt 较新的为准
    final localEntries = await DiaryStorage.load();
    final entryIndex = {for (var i = 0; i < localEntries.length; i++) localEntries[i].id: i};
    for (final e in incoming.entries) {
      final idx = entryIndex[e.id];
      if (idx == null) {
        localEntries.add(e);
        entryIndex[e.id] = localEntries.length - 1;
        added++;
      } else if (e.updatedAt.isAfter(localEntries[idx].updatedAt)) {
        localEntries[idx] = e;
        updated++;
      }
    }
    await DiaryStorage.save(localEntries);

    // 物品：无时间戳，同 id 保留本地
    final localItems = await ItemStorage.load();
    final itemIds = localItems.map((e) => e.id).toSet();
    for (final e in incoming.items) {
      if (itemIds.add(e.id)) {
        localItems.add(e);
        added++;
      }
    }
    await ItemStorage.save(localItems);

    // 资产：无时间戳，同 id 保留本地
    final localAssets = await AssetStorage.load();
    final assetIds = localAssets.map((e) => e.id).toSet();
    for (final e in incoming.assets) {
      if (assetIds.add(e.id)) {
        localAssets.add(e);
        added++;
      }
    }
    await AssetStorage.save(localAssets);

    // 事件：无时间戳，同 id 保留本地
    final localCountdowns = await CountdownStorage.load();
    final countdownIds = localCountdowns.map((e) => e.id).toSet();
    for (final e in incoming.countdowns) {
      if (countdownIds.add(e.id)) {
        localCountdowns.add(e);
        added++;
      }
    }
    await CountdownStorage.save(localCountdowns);
    // 合并后重排原生提醒（只对新增的事件真正新增，旧的会被覆盖重排）
    await CountdownReminder.syncAll(localCountdowns);

    return MergeResult(added: added, updated: updated);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// 导入方式
enum ImportMode {
  /// 完全覆盖：清空本地，全部替换为备份内容
  overwrite,

  /// 增添合并：保留本地，只补充备份里多出来的条目
  merge,
}

/// 合并结果统计
class MergeResult {
  /// 新增条数（本地原本没有的）
  final int added;

  /// 更新条数（同 id 且备份更新的，目前仅日记可能出现）
  final int updated;

  const MergeResult({required this.added, required this.updated});

  bool get isEmpty => added == 0 && updated == 0;

  @override
  String toString() =>
      isEmpty ? '没有可合并的新内容' : '新增 $added 条，更新 $updated 条';
}
