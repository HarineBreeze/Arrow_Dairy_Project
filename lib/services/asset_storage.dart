import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/asset.dart';

/// 资产图景存储：资产列表 + 访问密码（含密保）。
/// 密码只存明文哈希前的简单混淆值 —— 本地离线 App，防「顺手翻看」而非防专业破解。
class AssetStorage {
  static Future<File> _assetsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/assets.json');
  }

  static Future<File> _pinFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/asset_pin.json');
  }

  // ---------- 资产 ----------

  static Future<List<Asset>> load() async {
    try {
      final file = await _assetsFile();
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      return list
          .map((e) => Asset.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Asset> assets) async {
    final file = await _assetsFile();
    await file.writeAsString(jsonEncode(assets.map((e) => e.toJson()).toList()));
  }

  // ---------- 密码 ----------

  static String _obfuscate(String pin) {
    // 简单混淆：非明文存储即可
    final bytes = pin.codeUnits;
    return bytes.map((b) => (b ^ 0x5A).toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<bool> hasPin() async {
    try {
      final file = await _pinFile();
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  static Future<void> savePin({
    required String pin,
    required String question,
    required String answer,
  }) async {
    final file = await _pinFile();
    await file.writeAsString(jsonEncode({
      'pin': _obfuscate(pin),
      'q': question,
      'a': answer.trim(),
    }));
  }

  static Future<bool> verifyPin(String pin) async {
    try {
      final file = await _pinFile();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map['pin'] == _obfuscate(pin);
    } catch (_) {
      return false;
    }
  }

  /// 密保答案是否正确（忽略大小写与首尾空格）
  static Future<bool> verifyAnswer(String answer) async {
    try {
      final file = await _pinFile();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (map['a'] as String? ?? '').trim().toLowerCase() ==
          answer.trim().toLowerCase();
    } catch (_) {
      return false;
    }
  }

  static Future<String> getQuestion() async {
    try {
      final file = await _pinFile();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return map['q'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 忘记密码时通过密保重置
  static Future<void> resetPin(String newPin) async {
    try {
      final file = await _pinFile();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      map['pin'] = _obfuscate(newPin);
      await file.writeAsString(jsonEncode(map));
    } catch (_) {}
  }
}
