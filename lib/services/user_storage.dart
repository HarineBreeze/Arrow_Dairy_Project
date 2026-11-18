import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user_profile.dart';

class UserStorage {
  /// 档案变更通知：灵感 / 铭牌在别处（设置页兑换、发布奖励）更新后，
  /// 主页与侧边栏据此重新读取，避免显示旧值。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user_profile.json');
  }

  /// 用户 ID 自增序列文件：记录「已分配出去的最大序号」。
  /// 与档案分开存，保证档案被删除 / 重建后仍能接着发号，不会退回 10001。
  static Future<File> _seqFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user_id_seq.json');
  }

  static int get _seqStart => UserProfile.userIdStart - 1; // 10000

  static Future<int> _readSeq() async {
    try {
      final f = await _seqFile();
      if (!await f.exists()) return _seqStart;
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final last = (json['last'] as num?)?.toInt() ?? _seqStart;
      return last < _seqStart ? _seqStart : last;
    } catch (_) {
      return _seqStart;
    }
  }

  static Future<void> _writeSeq(int last) async {
    final f = await _seqFile();
    await f.writeAsString(jsonEncode({'last': last}));
  }

  /// 分配下一个顺序用户 ID（`10001`、`10002`…）并固化序列。
  /// 以磁盘序列为准，因此进程内其它临时 UserProfile 构造不会影响正式发号。
  static Future<String> allocateUserId() async {
    final next = (await _readSeq()) + 1;
    await _writeSeq(next);
    UserProfile.seedUserIdSeq(next);
    return '$next';
  }

  /// 合法的顺序 ID：纯数字且不小于起点。
  /// v4.9.22 及以前的 `AYO-xxxx-xxxx` 随机 ID 会被判定为需要迁移。
  static bool isSequentialId(String id) {
    final n = int.tryParse(id);
    return n != null && n >= UserProfile.userIdStart;
  }

  static Future<UserProfile> load() async {
    try {
      final file = await _file();
      final last = await _readSeq();
      UserProfile.seedUserIdSeq(last);

      // 首次启动：按持久化序列发号并立刻落盘，保证 ID 稳定不漂移。
      if (!await file.exists()) {
        final fresh = UserProfile(initialUserId: await allocateUserId());
        await file.writeAsString(jsonEncode(fresh.toJson()));
        return fresh;
      }

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final rawId = json['userId'] as String? ?? '';
      final needsNewId = !isSequentialId(rawId);
      final needsSave =
          needsNewId || (json['registeredAt'] as String? ?? '').isEmpty;

      // 旧格式随机 ID / 缺 ID：先注入新分配的顺序号再交给 fromJson，
      // 避免构造器自己发一个未持久化的号。
      if (needsNewId) json['userId'] = await allocateUserId();
      final profile = UserProfile.fromJson(json);

      if (!needsNewId) {
        // 档案里的号比序列文件大（例如手工迁移过的档案）：同步序列，
        // 保证后续发号不会与已有 ID 撞车。
        final idNum = int.tryParse(rawId) ?? _seqStart;
        if (idNum > last) await _writeSeq(idNum);
        UserProfile.seedUserIdSeq(idNum);
      }
      if (needsSave) await save(profile); // 固化新 ID / 补注册日
      return profile;
    } catch (_) {
      return UserProfile();
    }
  }

  static Future<void> save(UserProfile profile) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(profile.toJson()));
    revision.value++;
  }
}
