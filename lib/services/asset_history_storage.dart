import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../models/asset.dart';
import '../models/asset_history.dart';

/// 资产变更历史存储（`asset_history.json`）。
///
/// - [append] 追加一条调整快照，最新在前；
/// - [removeById] 供「更新记录」长按删除某次调整；
/// - [seedIfEmpty] 在历史为空且已有资产时写入一条当日基线，让折线图有起点；
/// - 所有读写异常都吞掉，绝不影响资产主流程（历史是附加能力）。
class AssetHistoryStorage {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/asset_history.json');
  }

  /// 基线已建立的标记文件。删除基线记录后不再重复生成。
  static Future<File> _seededFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/asset_history_seeded');
  }

  // ---------- 测试注入钩子（与项目其它 storage 同款惯例）----------

  static List<AssetHistoryEntry>? loadOverride;
  static Future<void> Function(List<AssetHistoryEntry>)? saveOverride;

  /// 仅供测试：注入 seed 行为，跳过 isSeeded()/标记文件（dart:io）。
  static Future<bool> Function(List<Asset>)? seedOverride;

  static void resetForTest() {
    loadOverride = null;
    saveOverride = null;
    seedOverride = null;
  }

  // ---------- 读写 ----------

  /// 读取历史，最新在前。
  static Future<List<AssetHistoryEntry>> load() async {
    if (loadOverride != null) return List.unmodifiable(loadOverride!);
    try {
      final f = await _file();
      if (!await f.exists()) return const [];
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      final result = list
          .map((e) => AssetHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      result.sort((a, b) => b.time.compareTo(a.time));
      return result;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _write(List<AssetHistoryEntry> entries) async {
    if (saveOverride != null) {
      await saveOverride!(entries);
      return;
    }
    // 测试内存模式：loadOverride 注入时，写回也落到内存，避免触碰 dart:io。
    if (loadOverride != null) {
      loadOverride = entries;
      return;
    }
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  /// 追加一条快照（最新放最前）。
  static Future<void> append(AssetHistoryEntry entry) async {
    final list = await load();
    await _write([entry, ...list]);
  }

  /// 按 id 删除某条调整记录（保留兼容，整条删除用）。
  static Future<void> removeById(String id) async {
    final list = await load();
    await _write(list.where((e) => e.id != id).toList());
  }

  /// 按条删除：删除某条记录里的第 [changeIndex] 笔改动。
  /// 若该记录的 changes 被删空，则整条移除。
  /// 历史快照（totalAssets/totalDebt/netWorth）不重算——它记录的是当时时点，
  /// 删除只影响「更新记录」展示，不代表撤销那笔资产变动。
  static Future<void> removeChange(String entryId, int changeIndex) async {
    final list = await load();
    final result = <AssetHistoryEntry>[];
    for (final e in list) {
      if (e.id != entryId) {
        result.add(e);
        continue;
      }
      final changes = List<AssetChange>.from(e.changes);
      if (changeIndex < 0 || changeIndex >= changes.length) {
        result.add(e);
        continue;
      }
      changes.removeAt(changeIndex);
      if (changes.isEmpty) continue; // 删空则整条移除
      result.add(AssetHistoryEntry(
        id: e.id,
        time: e.time,
        changes: changes,
        totalAssets: e.totalAssets,
        totalDebt: e.totalDebt,
        netWorth: e.netWorth,
        source: e.source,
      ));
    }
    await _write(result);
  }

  /// 基线是否曾建立过（用于避免删除后重复生成）。
  static Future<bool> isSeeded() async {
    try {
      return await (await _seededFile()).exists();
    } catch (_) {
      return false;
    }
  }

  /// 历史为空且当前有资产时，写入一条当日基线，保证折线图有起点。
  /// 一旦建立过（[isSeeded]），即使记录被删空也不再重复生成。
  /// 返回是否真的写入了基线。
  static Future<bool> seedIfEmpty(List<Asset> assets) async {
    if (seedOverride != null) return seedOverride!(assets);
    if (await isSeeded()) return false;
    final list = await load();
    if (list.isNotEmpty || assets.isEmpty) return false;
    final totalAssets = assets.fold<double>(
        0, (s, a) => a.amount > 0 ? s + a.amount : s);
    final totalDebt = assets.fold<double>(
        0, (s, a) => a.amount < 0 ? s + a.amount : s);
    final entry = AssetHistoryEntry(
      id: 'seed-${DateTime.now().microsecondsSinceEpoch}',
      time: DateTime.now(),
      changes: assets
          .map((a) => AssetChange(
                name: a.note.trim().isEmpty ? a.type : a.note.trim(),
                type: a.type,
                amount: a.amount,
              ))
          .toList(),
      totalAssets: totalAssets,
      totalDebt: totalDebt,
      netWorth: totalAssets + totalDebt,
      source: AssetHistoryEntry.sourceSeed,
    );
    await _write([entry]);
    try {
      await (await _seededFile()).writeAsString('1');
    } catch (_) {}
    return true;
  }

  /// 仅供测试：重置基线标记。
  static Future<void> resetSeededForTest() async {
    try {
      final f = await _seededFile();
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
