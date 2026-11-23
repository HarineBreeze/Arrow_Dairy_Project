import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 隐私锁类型：密码 / 九宫格手势。
enum AppLockType { password, gesture }

/// App 启动锁存储。独立于资产密码：这是「整个 App 冷启动」的锁。
/// 本地离线 App，密码/手势只做简单混淆（防顺手翻看，非防专业破解）。
/// 锁文件不存在即为「未开启隐私锁」。
class AppLockStorage {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_lock.json');
  }

  static String _obfuscate(String raw) {
    final bytes = raw.codeUnits;
    return bytes.map((b) => (b ^ 0x5A).toRadixString(16).padLeft(2, '0')).join();
  }

  /// 是否已开启隐私锁
  static Future<bool> hasLock() async {
    try {
      final file = await _file();
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// 当前锁类型；未开启时默认 password。
  static Future<AppLockType> loadType() async {
    try {
      final file = await _file();
      if (!await file.exists()) return AppLockType.password;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map['type'] == 'gesture'
          ? AppLockType.gesture
          : AppLockType.password;
    } catch (_) {
      return AppLockType.password;
    }
  }

  /// 保存锁。密码与手势二选一：password 时传 pin，gesture 时传 pattern。
  /// 密保问题与答案必填（由 UI 层保证，这里再次容忍空值以稳妥）。
  static Future<void> saveLock({
    required AppLockType type,
    String pin = '',
    String pattern = '',
    required String question,
    required String answer,
  }) async {
    final file = await _file();
    await file.writeAsString(jsonEncode({
      'type': type.name,
      'pin': pin.isEmpty ? '' : _obfuscate(pin),
      'pattern': pattern.isEmpty ? '' : _obfuscate(pattern),
      'q': question.trim(),
      'a': answer.trim(),
    }));
  }

  /// 校验密码
  static Future<bool> verifyPin(String pin) async {
    try {
      final file = await _file();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map['pin'] == _obfuscate(pin) && (map['pin'] as String).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 校验手势：pattern 为逗号分隔的点序号，如 "0,1,2,5,8"
  static Future<bool> verifyPattern(String pattern) async {
    try {
      final file = await _file();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final stored = map['pattern'] as String? ?? '';
      return stored.isNotEmpty && stored == _obfuscate(pattern);
    } catch (_) {
      return false;
    }
  }

  /// 密保答案是否正确（忽略大小写与首尾空格）
  static Future<bool> verifyAnswer(String answer) async {
    try {
      final file = await _file();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (map['a'] as String? ?? '').trim().toLowerCase() ==
          answer.trim().toLowerCase();
    } catch (_) {
      return false;
    }
  }

  /// 读取密保问题（忘记密码时展示）
  static Future<String> getQuestion() async {
    try {
      final file = await _file();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map['q'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 忘记密码：通过密保验证后重设密码/手势
  static Future<void> reset({
    required AppLockType type,
    String pin = '',
    String pattern = '',
  }) async {
    try {
      final file = await _file();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      map['type'] = type.name;
      map['pin'] = pin.isEmpty ? '' : _obfuscate(pin);
      map['pattern'] = pattern.isEmpty ? '' : _obfuscate(pattern);
      await file.writeAsString(jsonEncode(map));
    } catch (_) {}
  }

  /// 关闭隐私锁（删除锁文件）
  static Future<void> clearLock() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
