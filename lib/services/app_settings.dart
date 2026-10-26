import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// App 全局设置。手写字体等开关，持久化到 documents/app_settings.json。
/// 内存缓存 [cached]，跨页面读取无需 await。
class AppSettings {
  static const String handwritingFont = 'ZhiMangXing';

  /// 手写体开关（缓存值，启动时 load 后即可同步读取）
  static bool _handwriting = false;
  static bool get handwriting => _handwriting;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  static Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _handwriting = map['handwriting'] == true;
    } catch (_) {
      _handwriting = false;
    }
  }

  static Future<void> setHandwriting(bool v) async {
    _handwriting = v;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({'handwriting': v}));
    } catch (_) {}
  }
}
