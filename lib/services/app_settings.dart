import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Brightness;
import 'package:path_provider/path_provider.dart';
import '../theme/app_palette.dart';
import '../utils/haptics.dart';

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
  /// App 全局字体，'' 或 null = 系统默认
  static String? _fontFamily;
  static String? get fontFamily =>
      (_fontFamily == null || _fontFamily!.isEmpty) ? null : _fontFamily;
  static String get fontFamilyId => _fontFamily ?? '';

  /// 字体变更通知：MaterialApp 监听后重建主题，实现全局换字体。
  /// 值为当前字体 family（null = 默认字体）。
  static final ValueNotifier<String?> fontNotifier =
      ValueNotifier<String?>(null);

  // ---------------- 深色模式 ----------------

  /// 主题模式偏好，默认跟随系统。持久化到 app_settings.json 的 themeMode。
  static AppThemeMode _themeMode = AppThemeMode.system;
  static AppThemeMode get themeMode => _themeMode;

  /// 主题模式变更通知：MaterialApp 监听后重建，实现全局换肤。
  static final ValueNotifier<AppThemeMode> themeModeNotifier =
      ValueNotifier<AppThemeMode>(AppThemeMode.system);

  /// 按「模式 + 当前系统亮度」解析出实际是否深色。
  /// 跟随系统时由调用方传入 platformBrightness；手动模式忽略系统亮度。
  static bool resolveDark(AppThemeMode mode, Brightness platformBrightness) {
    switch (mode) {
      case AppThemeMode.light:
        return false;
      case AppThemeMode.dark:
        return true;
      case AppThemeMode.system:
        return platformBrightness == Brightness.dark;
    }
  }

  static Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    themeModeNotifier.value = mode;
    await _persist();
  }

  // ---------------- 主题色（v4.9.43） ----------------

  /// 当前主题色 id，默认竹青。持久化到 app_settings.json 的 accentId。
  static String _accentId = 'bamboo';
  static String get accentId => _accentId;

  /// 主题色变更通知：MaterialApp 监听后重建主题与各页面。
  static final ValueNotifier<String> accentNotifier =
      ValueNotifier<String>('bamboo');

  /// 切换主题色：同步全局色板 + 通知重建 + 落盘。
  static Future<void> setAccentId(String id) async {
    _accentId = AccentCatalog.byId(id).id;
    AppPalette.accent = AccentCatalog.byId(_accentId);
    accentNotifier.value = _accentId;
    await _persist();
  }

  // ---------------- 震动反馈 ----------------

  /// 全局震动开关，默认开启。持久化到 app_settings.json 的 hapticsEnabled。
  static bool _hapticsEnabled = true;
  static bool get hapticsEnabled => _hapticsEnabled;

  /// 开关变更通知：设置页开关与 [Haptics.enabled] 同步。
  static final ValueNotifier<bool> hapticsNotifier = ValueNotifier<bool>(true);

  /// 切换全局震动，并立刻下发到 [Haptics]（无需重启 App）。
  static Future<void> setHapticsEnabled(bool value) async {
    _hapticsEnabled = value;
    Haptics.enabled = value;
    hapticsNotifier.value = value;
    await _persist();
  }

  // ---------------- 「可使用天数」参数 ----------------

  /// 总资产。null 表示用户没手动设过 —— 此时自动取看板的净资产。
  ///
  /// 只在用户**主动填写并保存**后才落成固定值；这样净资产变化时
  /// 看板上的天数会跟着变，不会停留在某次手填的旧数上。
  static double? _usableTotal;
  static double? get usableTotal => _usableTotal;

  /// 实际参与计算的总资产：手填值优先，否则回落到 [netWorthFallback]。
  ///
  /// [netWorthFallback] 由调用方（资产页）传入当前净资产；
  /// 为空或为负时返回 null —— 净资产为负，公式算出来没有意义。
  static double? resolveTotal({double? netWorthFallback}) {
    if (_usableTotal != null) return _usableTotal;
    if (netWorthFallback == null) return null;
    if (!netWorthFallback.isFinite || netWorthFallback <= 0) return null;
    return netWorthFallback;
  }

  /// 月消费，默认 3000
  static double _usableMonthlyCost = 3000;
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

  /// 持久化写入的注入替身（仅供测试）。
  ///
  /// widget test 跑在 FakeAsync 环境里，任何真实文件 IO 都会让 `await`
  /// 永久挂起；测试把它设成内存 no-op 即可绕开落盘，同时保留内存状态、
  /// `toJson()` 快照与 notifier 通知的完整逻辑。生产环境恒为 null。
  static Future<void> Function()? persistOverride;

  /// 读取后写回：统一走这里，避免各 setter 互相覆盖字段
  static Future<void> _persist() async {
    final override = persistOverride;
    if (override != null) {
      await override();
      return;
    }
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
        'themeMode': _themeMode.name,
        'accentId': _accentId,
        'hapticsEnabled': _hapticsEnabled,
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

      // 主题模式：兼容旧档缺字段（默认跟随系统）；非法值回落 system
      final tm = map['themeMode'];
      _themeMode = AppThemeMode.values.firstWhere(
        (m) => m.name == tm,
        orElse: () => AppThemeMode.system,
      );

      // 主题色：兼容旧档缺字段（默认竹青）；非法值回落竹青
      final accent = map['accentId'];
      _accentId = AccentCatalog.byId(accent is String ? accent : null).id;

      // 震动开关：旧档缺字段默认开启
      _hapticsEnabled = map['hapticsEnabled'] != false;
    } catch (_) {
      _fontFamily = null;
    }
    // 启动时也要同步一次，避免首帧与已存设置不一致
    fontNotifier.value = fontFamily;
    themeModeNotifier.value = _themeMode;
    AppPalette.accent = AccentCatalog.byId(_accentId);
    accentNotifier.value = _accentId;
    Haptics.enabled = _hapticsEnabled;
    hapticsNotifier.value = _hapticsEnabled;
  }

  static Future<void> setFontFamily(String id) async {
    _fontFamily = id;
    fontNotifier.value = fontFamily;
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
