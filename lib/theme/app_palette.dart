import 'package:flutter/material.dart';

/// 主题模式偏好：跟随系统 / 始终浅色 / 始终深色。
///
/// 持久化到 app_settings.json 的 `themeMode` 字段（值为 name）。
enum AppThemeMode { system, light, dark }

/// 全局语义调色板。
///
/// 设计要点（v4.9.24 深色模式）：
/// - 项目里大量颜色是写死的 `const Color(0xFFxxxx)`，且浅色外观有大量
///   widget 测试做**精确颜色断言**。若直接把字面量改成语义字段，浅色下
///   只要有一个值与原值不符，既有测试就会失败。
/// - 因此这里采用「按浅色字面量查表」的 `c()`：浅色模式原样返回
///   `Color(argb)`，保证与改造前**逐字节一致**；深色模式查 [darkMap]
///   得到深色对应值；未登记的颜色（主色竹青、红色、身份牌色、图表色、
///   半透明遮罩等品牌/语义色）在深色下**保持原值**，跨主题一致。
/// - `surface` 专用于「白色卡片/容器背景」；顶栏或主色块上的白色文字、
///   图标属于前景，保持 `Colors.white`，深色下依旧清晰。
/// - `topBar` 专用于顶部导航栏的实心主色背景；半透明顶栏色块
///   （0xB3/0xCC/0xE6 开头的 3E8E6D）走 `c()` 映射，深色下统一为深墨绿，
///   避免「深色页面顶着一块亮绿色」—— 这正是本次需求点名不能漏的区域。
class AppPalette {
  AppPalette._();

  /// 当前是否深色。由 DiaryApp 每次构建时按「模式 + 系统亮度」计算后写入，
  /// 与 MaterialApp 的 theme/darkTheme 选择保持一致。
  static bool dark = false;

  /// 语义取色：浅色原样返回，深色查表转换，未登记保持原值。
  static Color c(int argb) {
    if (!dark) return Color(argb);
    return Color(darkMap[argb] ?? argb);
  }

  /// 白色卡片 / 容器 / 弹窗背景。深色下为深灰绿卡片。
  /// 注意：`0xFFFFFFFF` 必须登记进 [darkMap]（项目里 84 处白卡片都走
  /// `c(0xFFFFFFFF)`），否则深色模式只是把页面底变黑、卡片仍是刺眼白块。
  static Color get surface => c(0xFFFFFFFF);

  /// 顶部导航栏实心主色背景（浅色为竹青，深色为深墨绿）。
  static Color get topBar =>
      dark ? const Color(0xFF22342C) : const Color(0xFF3E8E6D);

  /// 浅色字面量 → 深色字面量。只登记「中性 / 背景 / 文字 / 边框 / 顶栏色块」，
  /// 品牌色与语义色（绿 3E8E6D、红 CB5C50、橙 F08C3A、身份牌色、图表色、
  /// 渐变色、半透明黑/白遮罩）一律不登记，深色下保持原值。
  static const Map<int, int> darkMap = <int, int>{
    // —— 页面底 / 卡片底 ——
    // 纯白卡片/容器/弹窗底：项目里 84 处 c(0xFFFFFFFF) 全是背景，
    // 深色下与 ThemeData.cardColor / canvasColor / dialogBackgroundColor
    // 统一为深灰绿，避免「深色页面顶着一堆白块」。
    0xFFFFFFFF: 0xFF18221E,
    // 置顶/加密卡上的半透明白遮罩：深色下改半透明深墨，避免亮块残留
    0xE6FFFFFF: 0xE618221E,
    0xCCFFFFFF: 0xCC101613,
    0xB3FFFFFF: 0xB3101613,
    0x99FFFFFF: 0x99101613,
    0xFFF5FAF7: 0xFF101613, // 页面主背景
    0xFFF2F6F4: 0xFF18221E, // 卡片次级底
    0xFFEFF5F1: 0xFF18211D,
    0xFFEEF4F0: 0xFF17201C, // 斜纹卡底
    0xFFEFF2F0: 0xFF19211E,
    0xFFECF2EE: 0xFF17201C,
    0xFFFDEEF3: 0xFF2A1E24, // 粉色提示底
    0xFFFBE3E8: 0xFF2E2026,
    0xFFFBE9EC: 0xFF2A1E22,
    0xFFF0CBD4: 0xFF3A2630,
    // —— 浅绿底纹 / 选中态 / 边框 ——
    0xFFE4F2EB: 0xFF233A2F, // 浅绿底纹 / 选中
    0xFFE4EDE8: 0xFF22322A,
    0xFFE1ECE6: 0xFF213029,
    0xFFDFEAE5: 0xFF25352D,
    0xFFD5E2DB: 0xFF26362F,
    0xFFD5DDEA: 0xFF242C34,
    0xFFE8EDF5: 0xFF242C33, // 分隔线 / 淡边框
    0xFFC6D6CD: 0xFF3A4C42, // 淡图标 / 箭头 / 边框
    0xFFC2D4C9: 0xFF3A4A41,
    0xFFC2CFC8: 0xFF3A4740,
    // —— 文字 / 图标（浅色为墨绿灰，深色翻为浅色系）——
    0xFF24382F: 0xFFE9F2EB, // 主文字
    0xFF273830: 0xFFDDE9E1, // 默认图标墨色
    0xFF647A70: 0xFFA8BCB0, // 次要文字
    0xFF7C8F86: 0xFF9DB1A4,
    0xFF8FA09A: 0xFF90A69A, // 提示 / 辅助文字
    0xFFB2C2BA: 0xFF82978B, // 更淡的文字 / 版本号
    0xFFB2C4BA: 0xFF849A8D,
    0xFFAFBFB8: 0xFF809488,
    // —— 顶部导航栏分区色块（半透明主色）——
    0xB33E8E6D: 0xFF22342C,
    0xCC3E8E6D: 0xFF22342C,
    0xE63E8E6D: 0xFF22342C,
    // —— 极淡主色底纹 ——
    0x593E8E6D: 0x1F59B189,
    0x1A3E8E6D: 0x1A59B189,
  };
}
