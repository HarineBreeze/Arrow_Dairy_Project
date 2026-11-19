import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/asset.dart';
import '../models/countdown_event.dart';
import '../models/diary_entry.dart';
import '../models/item.dart';
import '../models/user_profile.dart';
import 'asset_storage.dart';
import 'countdown_storage.dart';
import 'diary_storage.dart';
import 'item_storage.dart';
import 'reward_service.dart';
import 'user_storage.dart';

/// 回收站条目类型
enum TrashKind { diary, item, event, asset }

extension TrashKindX on TrashKind {
  String get label {
    switch (this) {
      case TrashKind.diary:
        return '笔记';
      case TrashKind.item:
        return '物品';
      case TrashKind.event:
        return '事件';
      case TrashKind.asset:
        return '资产';
    }
  }

  String get keyName {
    switch (this) {
      case TrashKind.diary:
        return 'diary';
      case TrashKind.item:
        return 'item';
      case TrashKind.event:
        return 'event';
      case TrashKind.asset:
        return 'asset';
    }
  }

  static TrashKind fromKey(String key) {
    switch (key) {
      case 'diary':
        return TrashKind.diary;
      case 'item':
        return TrashKind.item;
      case 'event':
        return TrashKind.event;
      default:
        return TrashKind.asset;
    }
  }
}

/// 一条回收站记录：原始 JSON 原样保存，还原时按类型重建对象。
class TrashEntry {
  final String id; // 回收站记录 id（与业务对象 id 区分，避免重复删除冲突）
  final TrashKind kind;
  final Map<String, dynamic> data; // 原始 toJson()
  final DateTime deletedAt; // 删除时间
  final String title; // 列表展示标题（加密笔记只显示副标题）
  final String subtitle; // 列表展示副标题
  /// 保留天数：删除时是权益身份则 30 天，否则 7 天。旧记录缺省 7。
  final int keepDays;

  TrashEntry({
    required this.id,
    required this.kind,
    required this.data,
    required this.deletedAt,
    required this.title,
    required this.subtitle,
    this.keepDays = 7,
  });

  /// 剩余保存天数（按本条目的保留期倒计时），已过期返回 0
  int get daysLeft {
    final expire = deletedAt.add(Duration(days: keepDays));
    final left = expire.difference(DateTime.now()).inSeconds;
    if (left <= 0) return 0;
    return (left / 86400).ceil();
  }

  DateTime get expireAt => deletedAt.add(Duration(days: keepDays));

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.keyName,
        'data': data,
        'deletedAt': deletedAt.toIso8601String(),
        'title': title,
        'subtitle': subtitle,
        'keepDays': keepDays,
      };

  factory TrashEntry.fromJson(Map<String, dynamic> j) => TrashEntry(
        id: j['id'] as String,
        kind: TrashKindX.fromKey((j['kind'] as String?) ?? 'diary'),
        data: Map<String, dynamic>.from(j['data'] as Map),
        deletedAt: DateTime.tryParse((j['deletedAt'] as String?) ?? '') ??
            DateTime.now(),
        title: (j['title'] as String?) ?? '',
        subtitle: (j['subtitle'] as String?) ?? '',
        keepDays: (j['keepDays'] as int?) ?? 7,
      );
}

/// 回收站：统一保存笔记 / 物品 / 事件 / 资产的删除记录。
/// 最长保留 7 天，超期自动清理；支持还原与彻底删除。
class TrashStorage {
  /// 最长保存时长（7 天）
  static const Duration keepDuration = Duration(days: 7);

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/trash.json');
  }

  static Future<List<TrashEntry>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      // 旧版本记录可能没有 deletedAt 字段：用文件修改时间兜底并回写固化。
      // 否则 fromJson 里 tryParse 失败会回退成 DateTime.now()，
      // 倒计时每次启动都重置回 7 天，永远不会递减。
      final fallback = (await file.stat()).modified;
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      var changed = false;
      final entries = list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        if ((m['deletedAt'] as String?) == null) {
          m['deletedAt'] = fallback.toIso8601String();
          changed = true;
        }
        return TrashEntry.fromJson(m);
      }).toList();
      // 旧版本把 mood 表情拼进了日记副标题（如「2026.11.10 · 😀」）。
      // 表情功能已下线，读档时就地重算副标题并回写，避免历史记录继续显示。
      for (var i = 0; i < entries.length; i++) {
        final fixed = _fixedSubtitle(entries[i]);
        if (fixed != null && fixed != entries[i].subtitle) {
          entries[i] = TrashEntry(
            id: entries[i].id,
            kind: entries[i].kind,
            data: entries[i].data,
            deletedAt: entries[i].deletedAt,
            title: entries[i].title,
            subtitle: fixed,
            keepDays: entries[i].keepDays,
          );
          changed = true;
        }
      }
      if (changed) await _write(entries);
      // 读取时顺带清理过期项（7 天到期即彻底消失）
      final alive = entries.where((e) => e.daysLeft > 0).toList();
      if (alive.length != entries.length) {
        await _write(alive);
      }
      alive.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
      return alive;
    } catch (_) {
      return [];
    }
  }

  /// 日记记录的规范副标题：日期（加密笔记再加「已加密」）。
  /// 非日记记录返回 null 表示无需处理。
  static String? _fixedSubtitle(TrashEntry e) {
    if (e.kind != TrashKind.diary) return null;
    final rawDate = e.data['publishDate'] as String?;
    final d = rawDate != null
        ? DateTime.tryParse(rawDate)
        : DateTime.tryParse((e.data['createdAt'] as String?) ?? '');
    if (d == null) return null;
    final encrypted = e.data['encrypted'] == true;
    return _dateLabel(d) + (encrypted ? ' · 已加密' : '');
  }

  static Future<void> _write(List<TrashEntry> entries) async {
    final file = await _file();
    await file.writeAsString(
        jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  /// 放入回收站。幂等：同一业务对象重复删除只保留一条。
  static Future<void> addDiary(DiaryEntry e) async {
    await _add(
      TrashKind.diary,
      e.id,
      e.toJson(),
      // 加密笔记在回收站里只显示副标题，避免泄露正文标题；
      // 未来信件同理——未到查看时间前不能暴露真实标题，统一显示「未来信件」
      title: e.isFutureLetter
          ? '未来信件'
          : (e.encrypted
              ? (e.subtitle.isNotEmpty ? e.subtitle : '加密笔记')
              : (e.title.isNotEmpty ? e.title : '（无标题）')),
      // 只显示日期：mood / weather 表情早已下线，旧笔记里残留的 emoji
      // 不应再出现在回收站副标题里
      subtitle: _dateLabel(e.publishDate) + (e.encrypted ? ' · 已加密' : ''),
    );
  }

  /// `yyyy.MM.dd` 日期标签（回收站副标题统一格式）
  static String _dateLabel(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  static Future<void> addItem(Item e) async {
    await _add(
      TrashKind.item,
      e.id,
      e.toJson(),
      title: e.name.isNotEmpty ? e.name : '（未命名物品）',
      subtitle: '${e.category} · ¥${e.actualPrice.toStringAsFixed(2)}',
    );
  }

  static Future<void> addEvent(CountdownEvent e) async {
    final t = e.target;
    await _add(
      TrashKind.event,
      e.id,
      e.toJson(),
      title: e.name.isNotEmpty ? e.name : '（未命名事件）',
      subtitle:
          '${t.year}.${t.month.toString().padLeft(2, '0')}.${t.day.toString().padLeft(2, '0')} · ${e.type}',
    );
  }

  static Future<void> addAsset(Asset e) async {
    await _add(
      TrashKind.asset,
      e.id,
      e.toJson(),
      title: e.note.isNotEmpty ? e.note : e.type,
      subtitle: '${e.type} · ${e.amount < 0 ? '负债' : '资产'}',
    );
  }

  static Future<void> _add(
    TrashKind kind,
    String bizId,
    Map<String, dynamic> data, {
    required String title,
    required String subtitle,
  }) async {
    final list = await load();
    // 权益身份（内测版/VIP/终身VIP）在权益生效期间删除 → 保留 30 天；
    // 否则 7 天。该保留期固化在条目上，日后过期也不变。
    int keepDays = 7;
    try {
      final profile = await UserStorage.load();
      if (RewardService.hasVipPrivilege(profile)) keepDays = 30;
    } catch (_) {}
    // 同一对象重复删除：先移除旧记录，保证只有一条
    list.removeWhere((t) =>
        t.kind == kind && (t.data['id'] as String?) == bizId);
    list.insert(
      0,
      TrashEntry(
        id: '${kind.keyName}_${bizId}_${DateTime.now().microsecondsSinceEpoch}',
        kind: kind,
        data: data,
        deletedAt: DateTime.now(),
        title: title,
        subtitle: subtitle,
        keepDays: keepDays,
      ),
    );
    await _write(list);
  }

  /// 彻底删除指定记录
  static Future<void> remove(String trashId) async {
    final list = await load();
    list.removeWhere((t) => t.id == trashId);
    await _write(list);
  }

  /// 批量彻底删除（选择模式「确认删除」用）
  static Future<void> removeMany(Iterable<String> trashIds) async {
    final ids = trashIds.toSet();
    if (ids.isEmpty) return;
    final list = await load();
    list.removeWhere((t) => ids.contains(t.id));
    await _write(list);
  }

  /// 清空全部（可限定某类）
  static Future<void> clear([TrashKind? kind]) async {
    if (kind == null) {
      await _write(const []);
      return;
    }
    final list = await load();
    list.removeWhere((t) => t.kind == kind);
    await _write(list);
  }

  /// 还原一条记录：写回对应存储（同 id 已存在则跳过，避免覆盖新数据）
  static Future<void> restore(TrashEntry entry) async {
    switch (entry.kind) {
      case TrashKind.diary:
        final list = await DiaryStorage.load();
        final obj = DiaryEntry.fromJson(entry.data);
        if (!list.any((e) => e.id == obj.id)) list.add(obj);
        await DiaryStorage.save(list);
        break;
      case TrashKind.item:
        final list = await ItemStorage.load();
        final obj = Item.fromJson(entry.data);
        if (!list.any((e) => e.id == obj.id)) list.add(obj);
        await ItemStorage.save(list);
        break;
      case TrashKind.event:
        final list = await CountdownStorage.load();
        final obj = CountdownEvent.fromJson(entry.data);
        if (!list.any((e) => e.id == obj.id)) list.add(obj);
        await CountdownStorage.save(list);
        break;
      case TrashKind.asset:
        final list = await AssetStorage.load();
        final obj = Asset.fromJson(entry.data);
        if (!list.any((e) => e.id == obj.id)) list.add(obj);
        await AssetStorage.save(list);
        break;
    }
    await remove(entry.id);
  }

  /// 批量还原（选择模式「确认还原」用）。
  /// 返回成功还原的条数（同 id 已存在时该条仍会移出回收站，计为已处理）。
  static Future<int> restoreMany(List<TrashEntry> entries) async {
    var done = 0;
    for (final e in entries) {
      try {
        await restore(e);
        done++;
      } catch (_) {
        // 单条失败不影响其余条目
      }
    }
    return done;
  }
}
