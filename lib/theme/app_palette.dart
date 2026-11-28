import 'package:flutter/material.dart';

/// 主题模式偏好：跟随系统 / 始终浅色 / 始终深色。
///
/// 持久化到 app_settings.json 的 `themeMode` 字段（值为 name）。
enum AppThemeMode { system, light, dark }

/// 一套主题色（v4.9.43）。
///
/// 默认「竹青」的 [rgb] / [tintRgb] / [pageRgb] / [darkTop] / [darkTint]
/// 与原写死值逐字节一致——这样既有 widget 测试的精确颜色断言全部不受影响；
/// 选中其它主题色时，[AppPalette.c] 会把整个「绿色家族」重映射到这套值，
/// 做到一处切换、按钮/标签/置顶边框/页面底/高亮字/图标底纹一起换色。
class AccentStyle {
  final String id;
  final String name;
  /// 浅色主色（0xRRGGBB，不含 alpha）：按钮、高亮字、置顶边框、图标色
  final int rgb;
  /// 浅底纹（对应原 0xFFE4F2EB）：图标底纹、标签底、选中态底
  final int tintRgb;
  /// 页面底（对应原 0xFFF5FAF7）：带极淡主题色调的页面背景
  final int pageRgb;
  /// 深色顶栏色
  final int darkTop;
  /// 深色极淡底纹色（半透明主色块）
  final int darkTint;
  /// 深色页面底（对应 darkMap 的 0xFF101613 一系）
  final int darkPage;
  /// 深色卡片/容器底（对应 0xFF18221E 一系）
  final int darkSurface;
  /// 深色选中/底色底纹（对应浅绿底纹 0xFF233A2F 一系）
  final int darkTintBg;
  /// 是否 VIP 专属
  final bool vip;

  /// v5.0.5：是否需要在「灵感杂货店」兑换后才能使用（暖棕）。
  /// 与 [vip] 互斥：兑换型是永久买断，走灵感而非 VIP 权益。
  final bool needsShop;

  const AccentStyle({
    required this.id,
    required this.name,
    required this.rgb,
    required this.tintRgb,
    required this.pageRgb,
    required this.darkTop,
    required this.darkTint,
    required this.darkPage,
    required this.darkSurface,
    required this.darkTintBg,
    required this.vip,
    this.needsShop = false,
  });
}

/// 主题色注册表。
///
/// v5.0.5 起：竹青 / 墨灰免费；暖棕改为「灵感杂货店」1400 点永久兑换；
/// 藕粉 / 雾蓝 / 霞紫仍为 VIP 权益。
class AccentCatalog {
  AccentCatalog._();

  static const String bamboo = 'bamboo';

  /// 顺序（v5.0.5）：竹青 → 墨灰 → 暖棕（兑换）→ 藕粉 → 雾蓝 → 霞紫。
  /// 暖棕从「紧跟竹青」移到墨灰与藕粉之间，并改为杂货店兑换型。
  static const List<AccentStyle> styles = <AccentStyle>[
    AccentStyle(
        id: 'bamboo',
        name: '竹青',
        rgb: 0x3E8E6D,
        tintRgb: 0xE4F2EB, // 原浅绿底纹，逐字节不变
        pageRgb: 0xF5FAF7, // 原页面底，逐字节不变
        darkTop: 0x22342C,
        darkTint: 0x59B189,
        darkPage: 0x101613, // 原深色页面底，逐字节不变
        darkSurface: 0x18221E, // 原深色卡片底
        darkTintBg: 0x233A2F, // 原深色底纹
        vip: false),
    AccentStyle(
        id: 'ink',
        name: '墨灰',
        rgb: 0x5B6B66,
        tintRgb: 0xE7ECEA,
        pageRgb: 0xF5F7F6,
        darkTop: 0x222A27,
        darkTint: 0x8A9C95,
        darkPage: 0x141816,
        darkSurface: 0x1E241F,
        darkTintBg: 0x2B332E,
        vip: false),
    // v5.0.5：暖棕从免费改为「灵感杂货店」1400 点永久兑换，位置移到墨灰之后。
    AccentStyle(
        id: 'amber',
        name: '暖棕',
        rgb: 0xB07D4F,
        tintRgb: 0xF4EADA,
        pageRgb: 0xFBF6F0,
        darkTop: 0x33261C,
        darkTint: 0xC9A47A,
        darkPage: 0x1A1510,
        darkSurface: 0x261E16,
        darkTintBg: 0x372A1D,
        vip: false,
        needsShop: true),
    AccentStyle(
        id: 'lotus',
        name: '藕粉',
        rgb: 0xD9788C,
        tintRgb: 0xFBE8ED,
        pageRgb: 0xFDF4F6,
        darkTop: 0x3A2228,
        darkTint: 0xD992A3,
        darkPage: 0x1C1216,
        darkSurface: 0x271A20,
        darkTintBg: 0x3A232C,
        vip: true),
    AccentStyle(
        id: 'ocean',
        name: '雾蓝',
        rgb: 0x4A7FB5,
        tintRgb: 0xE4EDF7,
        pageRgb: 0xF4F8FC,
        darkTop: 0x1E2C3A,
        darkTint: 0x7BA7D2,
        darkPage: 0x101720,
        darkSurface: 0x18222E,
        darkTintBg: 0x22303F,
        vip: true),
    // v5.0.0：新增紫色系「霞紫」，常规/深色全套配套，VIP 专属
    AccentStyle(
        id: 'violet',
        name: '霞紫',
        rgb: 0x9068B5,
        tintRgb: 0xF1E9F8,
        pageRgb: 0xFAF6FD,
        darkTop: 0x2E2340,
        darkTint: 0xAC8BCB,
        darkPage: 0x161020,
        darkSurface: 0x211930,
        darkTintBg: 0x322645,
        vip: true),
  ];

  static AccentStyle byId(String? id) => styles.firstWhere(
        (s) => s.id == id,
        orElse: () => styles.first,
      );

  static bool isVip(String? id) => byId(id).vip;

  /// v5.0.5：该主题色是否需要在灵感杂货店兑换（暖棕）。
  static bool needsShop(String? id) => byId(id).needsShop;
}

/// 全局语义调色板。
///
/// 设计要点（v4.9.24 深色模式）：
/// - 项目里大量颜色是写死的 `const Color(0xFFxxxx)`，且浅色外观有大量
///   widget 测试做**精确颜色断言**。若直接把字面量改成语义字段，浅色下
///   只要有一个值与原值不符，既有测试就会失败。
/// - 因此这里采用「按浅色字面量查表」的 `c()`：浅色模式原样返回
///   `Color(argb)`，保证与改造前**逐字节一致**；深色模式查 [darkMap]
///   得到深色对应值；未登记的颜色（主色竹青、红色、身份色、图表色、
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

  /// 当前主题色（v4.9.43）。默认竹青：与改造前的写死值逐字节一致。
  /// 由 AppSettings 在 load / 切换时同步写入。
  static AccentStyle accent = AccentCatalog.styles.first;

  /// 主色族：c() 里这些「浅色字面量」在选中非默认主题色时需要重映射。
  /// 只收主色家族（绿 3E8E6D 及其半透明变体），语义色（红/橙/身份色）不动。
  static const Set<int> _accentRgbArgs = <int>{
    0xFF3E8E6D, 0xB33E8E6D, 0xCC3E8E6D, 0xE63E8E6D,
    0x593E8E6D, 0x1A3E8E6D,
  };

  /// 浅底纹族：图标底纹、标签底、选中态底（原浅绿 E4F2EB 一系）。
  /// v4.9.44：随主题色换成对应的淡色 [AccentStyle.tintRgb]。
  static const Set<int> _tintArgs = <int>{
    0xFFE4F2EB, 0xFFE4EDE8, 0xFFE1ECE6, 0xFFDFEAE5,
  };

  /// 页面底族：页面主背景、卡片底（原浅灰绿 F5FAF7 一系）。
  /// v4.9.44：随主题色换成对应的极淡色 [AccentStyle.pageRgb]。
  static const Set<int> _pageArgs = <int>{
    0xFFF5FAF7, 0xFFF2F6F4,
  };

  /// v4.9.46：深色下 darkMap 映射出的「深墨绿」中性色，选非竹青主题时
  /// 也要随主题色换成对应的深色配套，避免深色模式里顶栏换了色、
  /// 页面底/卡片底/底纹却仍是竹青墨绿。按用途分三族。
  static const Set<int> _darkPageMapped = <int>{
    0xFF101613, // 页面主背景
    0xFF18211D, 0xFF17201C, 0xFF19211E, // 斜纹卡/次级底
  };
  static const Set<int> _darkSurfaceMapped = <int>{
    0xFF18221E, // 卡片/容器/白底
  };
  static const Set<int> _darkTintBgMapped = <int>{
    0xFF233A2F, 0xFF22322A, 0xFF213029, 0xFF25352D, 0xFF26362F,
  };

  /// 语义取色：浅色原样返回，深色查表转换，未登记保持原值。
  ///
  /// v4.9.43：若当前主题色非竹青，主色家族会被换成对应色（保留 alpha），
  /// 让顶栏、底纹、描边等随主题色一起变；默认竹青时原样返回，零行为变化。
  /// v4.9.44：浅底纹族 / 页面底族也纳入重映射，做到「按钮、标签、置顶边框、
  /// 页面底、高亮字、图标底纹」一整套一起换色。
  static Color c(int argb) {
    final themed = accent.id != AccentCatalog.bamboo;
    if (!dark) {
      if (themed) {
        final alpha = argb >> 24;
        if (_accentRgbArgs.contains(argb)) return Color((alpha << 24) | accent.rgb);
        if (_tintArgs.contains(argb)) return Color((alpha << 24) | accent.tintRgb);
        if (_pageArgs.contains(argb)) return Color((alpha << 24) | accent.pageRgb);
      }
      return Color(argb);
    }
    final mapped = darkMap[argb] ?? argb;
    if (themed) {
      // 深色主色：顶栏不透明墨绿 / 极淡底纹半透明，按当前主题色替换
      if (mapped == 0xFF22342C) return Color(0xFF000000 | accent.darkTop);
      if (mapped == 0x1F59B189 || mapped == 0x1A59B189) {
        return Color((argb & 0xFF000000) | accent.darkTint);
      }
      // 不透明主色本身（按钮/高亮字/置顶边框/图标色）深色下也跟随主题色
      if (argb == 0xFF3E8E6D) return Color(0xFF000000 | accent.rgb);
      // v4.9.46：深色中性色（页面底/卡片底/底纹）随主题色换成对应深色
      if (_darkTintBgMapped.contains(mapped)) {
        return Color(0xFF000000 | accent.darkTintBg);
      }
      if (_darkSurfaceMapped.contains(mapped)) {
        return Color(0xFF000000 | accent.darkSurface);
      }
      if (_darkPageMapped.contains(mapped)) {
        return Color(0xFF000000 | accent.darkPage);
      }
    }
    return Color(mapped);
  }

  /// 白色卡片 / 容器 / 弹窗背景。深色下为深灰绿卡片。
  /// 注意：`0xFFFFFFFF` 必须登记进 [darkMap]（项目里 84 处白卡片都走
  /// `c(0xFFFFFFFF)`），否则深色模式只是把页面底变黑、卡片仍是刺眼白块。
  static Color get surface => c(0xFFFFFFFF);

  /// 顶部导航栏实心主色背景（浅色为当前主题色，深色为对应深墨绿）。
  static Color get topBar => dark
      ? Color(0xFF000000 | accent.darkTop)
      : Color(0xFF000000 | accent.rgb);

  /// 当前主题色的实心 Color（供 Material swatch / 强调文字使用）。
  static Color get accentColor => Color(0xFF000000 | accent.rgb);

  /// 底部滑入警示语（AppToast）的深色背景：深底白字。
  /// 竹青沿用原值逐字节不变；其它主题色用各自的深色顶栏色，
  /// 让常规模式与深色模式下警示语都随主题色换色。
  static Color get toastBg => accent.id == AccentCatalog.bamboo
      ? const Color(0xFF24382F)
      : Color(0xFF000000 | accent.darkTop);

  /// 浅色字面量 → 深色字面量。只登记「中性 / 背景 / 文字 / 边框 / 顶栏色块」，
  /// 品牌色与语义色（绿 3E8E6D、红 CB5C50、橙 F08C3A、身份色、图表色、
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
    // v5.0.4：隐私锁/密码向导「未选中项」底色原用 0xFFF5F8F6（未登记），
    // 深色模式下保持亮灰白、过于亮眼。登记为深墨绿底纹（属 _darkTintBgMapped，
    // 会随主题色变成各主题暗底纹），浅色观感原样不变。
    0xFFF5F8F6: 0xFF233A2F,
    0xFFE4EDE8: 0xFF22322A,
    0xFFE1ECE6: 0xFF213029,
    0xFFDFEAE5: 0xFF25352D,
    0xFFD5E2DB: 0xFF26362F,
    0xFFD5DDEA: 0xFF242C34,
    0xFFE8EDF5: 0xFF242C33, // 分隔线 / 淡边框
    // v5.0.15：资产趋势图新增底纹——浅色下为淡蓝/淡灰，深色下翻为深底，
    // 否则汇总条/选中胶囊的底纹保持浅色、上面的文字却翻成浅色导致看不清。
    0xFFEDF3FD: 0xFF212A33, // 汇总条淡蓝底 → 深蓝灰
    0xFFE4E8EB: 0xFF2B3530, // 时间胶囊选中底 → 深灰
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
