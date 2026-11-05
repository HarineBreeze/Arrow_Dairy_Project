import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 可选字体目录（id 即 Flutter family 名）。
/// 全部为开源 OFL 授权，已裁剪至常用字集并打包进 APK，离线可用。
class FontCatalog {
  static const List<Map<String, String>> fonts = [
    {'id': '', 'name': '默认字体', 'desc': '跟随系统'},
    {'id': 'LXGWWenKai', 'name': '霞鹜文楷', 'desc': '楷体阅读'},
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

  // ---------------- 「可使用天数」参数 ----------------

  /// 总资产（用户手填，null 表示未设置 → 不显示「可使用 x 天」）
  ///
  /// 刻意不跟随看板的净资产：一是用户可能想按「可用现金」而非「净资产」
  /// 来估算；二是净资产为负时公式无意义。留空就是明确的不显示。
  static double? _usableTotal;
  static double? get usableTotal => _usableTotal;

  /// 月消费，默认 0（为 0 时无法计算，等同未设置）
  static double _usableMonthlyCost = 0;
  static double get usableMonthlyCost => _usableMonthlyCost;

  /// 每月天数，默认 30
  static double _usableDaysPerMonth = 30;
  static double get usableDaysPerMonth => _usableDaysPerMonth;

  /// 年化利率（百分比数值，如 3 表示 3%），默认 3
  static double _annualRate = 3;
  static double get annualRate => _annualRate;

  /// 通胀率（百分比数值，如 2 表示 2%），默认 2
  static double _inflationRate = 2;
  static double get inflationRate => _inflationRate;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  /// 读取后写回：统一走这里，避免各 setter 互相覆盖字段
  static Future<void> _persist() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(toJson()));
    } catch (_) {}
  }

  /// 当前设置的可序列化快照
  static Map<String, dynamic> toJson() => {
        'fontFamily': fontFamilyId,
        if (_usableTotal != null) 'usableTotal': _usableTotal,
        'usableMonthlyCost': _usableMonthlyCost,
        'usableDaysPerMonth': _usableDaysPerMonth,
        'annualRate': _annualRate,
        'inflationRate': _inflationRate,
      };

  static Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      // 兼容旧版手写体开关：true 视作手写字体（现已移除 → 回落默认）
      if (map.containsKey('fontFamily')) {
        _fontFamily = map['fontFamily'] as String?;
      } else if (map['handwriting'] == true) {
        _fontFamily = '';
      }
      // 所选字体若已从 App 中移除，回落默认
      if (_fontFamily != null &&
          _fontFamily!.isNotEmpty &&
          FontCatalog.nameOf(_fontFamily) == null) {
        _fontFamily = '';
      }

      // 「可使用天数」参数：缺字段时保留默认值
      final total = map['usableTotal'];
      _usableTotal = total is num ? total.toDouble() : null;
      final cost = map['usableMonthlyCost'];
      if (cost is num) _usableMonthlyCost = cost.toDouble();
      final days = map['usableDaysPerMonth'];
      if (days is num && days > 0) _usableDaysPerMonth = days.toDouble();
      final rate = map['annualRate'];
      if (rate is num) _annualRate = rate.toDouble();
      final infl = map['inflationRate'];
      if (infl is num) _inflationRate = infl.toDouble();
    } catch (_) {
      _fontFamily = null;
    }
  }

  static Future<void> setFontFamily(String id) async {
    _fontFamily = id;
    await _persist();
  }

  /// 保存「可使用天数」的全部参数（一次性写入，避免多次落盘）
  static Future<void> setUsableParams({
    required double? total,
    required double monthlyCost,
    required double daysPerMonth,
    required double annualRate,
    required double inflationRate,
  }) async {
    _usableTotal = total;
    _usableMonthlyCost = monthlyCost;
    _usableDaysPerMonth = daysPerMonth;
    _annualRate = annualRate;
    _inflationRate = inflationRate;
    await _persist();
  }
}
