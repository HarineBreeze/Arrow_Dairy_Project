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
      if (!await file.exists()) return UserProfile();
      final content = await file.readAsString();
      return UserProfile.fromJson(
          jsonDecode(content) as Map<String, dynamic>);
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
