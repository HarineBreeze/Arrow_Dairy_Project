import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 可选字体目录（id 即 Flutter family 名）。
/// 全部为开源 OFL 授权，已裁剪至常用字集并打包进 APK，离线可用。
class FontCatalog {
  static const List<Map<String, String>> fonts = [
    {'id': '', 'name': '默认字体', 'desc': '跟随系统'},
    {'id': 'ZhiMangXing', 'name': '芝麻行', 'desc': '手写行书'},
    {'id': 'MaShanZheng', 'name': '马善政', 'desc': '毛笔楷行'},
    {'id': 'LongCang', 'name': '龙藏', 'desc': '毛笔行草'},
    {'id': 'LiuJianMaoCao', 'name': '刘建毛草', 'desc': '硬笔草书'},
    {'id': 'LXGWWenKai', 'name': '霞鹜文楷', 'desc': '楷体阅读'},
    {'id': 'LXGWMarkerGothic', 'name': '霞鹜漫黑', 'desc': '马克笔手写'},
    {'id': 'ZCOOLKuaiLe', 'name': '站酷快乐体', 'desc': '圆润活泼'},
    {'id': 'ZCOOLQingKeHuangYou', 'name': '站酷庆科黄油', 'desc': '粗黑醒目'},
    {'id': 'ZCOOLXiaoWei', 'name': '站酷小薇', 'desc': '细宋文艺'},
    {'id': 'NotoSansSC', 'name': '思源黑体', 'desc': '现代黑体'},
    {'id': 'NotoSerifSC', 'name': '思源宋体', 'desc': '传统宋体'},
  ];

  static String? nameOf(String? id) {
    for (final f in fonts) {
      if (f['id'] == id) return f['name'];
    }
    return null;
  }
}

/// App 全局设置。持久化到 documents/app_settings.json。
/// 内存缓存，启动时 load 后即可同步读取。
class AppSettings {
  /// 浏览页正文字体，'' 或 null = 系统默认
  static String? _fontFamily;
  static String? get fontFamily =>
      (_fontFamily == null || _fontFamily!.isEmpty) ? null : _fontFamily;
  static String get fontFamilyId => _fontFamily ?? '';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  static Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // 兼容旧版手写体开关：true 视作芝麻行
      if (map.containsKey('fontFamily')) {
        _fontFamily = map['fontFamily'] as String?;
      } else if (map['handwriting'] == true) {
        _fontFamily = 'ZhiMangXing';
      }
    } catch (_) {
      _fontFamily = null;
    }
  }

  static Future<void> setFontFamily(String id) async {
    _fontFamily = id;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({'fontFamily': id}));
    } catch (_) {}
  }
}
