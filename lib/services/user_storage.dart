import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/user_profile.dart';

class UserStorage {
  /// 档案变更通知：积分 / 铭牌在别处（设置页兑换、发布奖励）更新后，
  /// 主页与侧边栏据此重新读取，避免显示旧值。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user_profile.json');
  }

  static Future<UserProfile> load() async {
    try {
      final file = await _file();
      // 首次启动：生成用户 ID 与注册日并立刻落盘，保证 ID 稳定不漂移
      if (!await file.exists()) {
        final fresh = UserProfile();
        await file.writeAsString(jsonEncode(fresh.toJson()));
        return fresh;
      }
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final profile = UserProfile.fromJson(json);
      // v4.9.21 及以前的档案没有 userId / registeredAt：首次读档时补上并
      // 回写固化。否则每次 load 都会 fromJson 出一个新的随机 ID。
      if ((json['userId'] as String? ?? '').isEmpty ||
          (json['registeredAt'] as String? ?? '').isEmpty) {
        await save(profile);
      }
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
