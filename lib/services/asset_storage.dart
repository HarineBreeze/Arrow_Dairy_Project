import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/asset.dart';

/// 资产全景存储：资产列表 + 访问密码（含密保）。
/// 密码只存明文哈希前的简单混淆值 —— 本地离线 App，防「顺手翻看」而非防专业破解。
/// 加密访问为可选项：未设置密码时可直接查看，密码文件不存在即为「未加密」。
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
      final assets = list.map((e) {
        final a = Asset.fromJson(Map<String, dynamic>.from(e));
        // 旧版本「理财」类型统一迁移为「基金」
        if (a.type == '理财') a.type = '基金';
        return a;
      }).toList();
      // 排序：有 order 的按 order 升序；无 order 的（旧数据）保持文件原顺序，
      // 且排在已排序项之后 —— 这样老用户升级后看到的顺序与升级前完全一致。
      final n = assets.length;
      for (var i = 0; i < n; i++) {
        if (assets[i].order < 0) assets[i].order = n + i;
      }
      assets.sort((a, b) => a.order.compareTo(b.order));
      for (var i = 0; i < n; i++) {
        assets[i].order = i;
      }
      return assets;
    } catch (_) {
      return [];
    }
  }

  /// 保存并按当前列表顺序归一化 order（0..n-1）
  static Future<void> save(List<Asset> assets) async {
    for (var i = 0; i < assets.length; i++) {
      assets[i].order = i;
    }
    final file = await _assetsFile();
    await file.writeAsString(jsonEncode(assets.map((e) => e.toJson()).toList()));
  }

  /// 拖拽排序结果写盘：list 为排序后的完整列表
  static Future<void> saveOrder(List<Asset> ordered) => save(ordered);

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

  /// 修改密码（设置页调用）。可选同时更新密保问题与答案。
  static Future<bool> updatePin({
    required String newPin,
    String? question,
    String? answer,
  }) async {
    try {
      final file = await _pinFile();
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      map['pin'] = _obfuscate(newPin);
      if (question != null && question.trim().isNotEmpty) {
        map['q'] = question.trim();
      }
      if (answer != null && answer.trim().isNotEmpty) {
        map['a'] = answer.trim();
      }
      await file.writeAsString(jsonEncode(map));
      return true;
    } catch (_) {
      return false;
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

  /// 取消加密访问（删除密码与密保记录）
  static Future<void> clearPin() async {
    try {
      final file = await _pinFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
