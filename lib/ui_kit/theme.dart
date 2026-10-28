import 'package:flutter/material.dart';

/// 四套 UI 方案的主题令牌。
///
/// 四套方案在「排版逻辑」上完全统一（同一骨架、同一间距节奏、同一
/// 组件尺寸），差异只体现在视觉语言：顶部色带形态、卡片形态、
/// 选中态表达、标题排版位置、分组头的样式。
class UiTheme {
  final String id;
  final String name;
  final String tagline;

  // ---- 基础色 ----
  final Color accent; // 主品牌色
  final Color accentAlt; // 主色渐变终点 / 次强调色
  final Color pageBg; // 页面底色
  final Color cardBg; // 卡片底色
  final Color surfaceAlt; // 次级面（统计条、筛选条）
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color danger; // 负值 / 警示
  final Color positive; // 正值
  final Color menuBg;

  // ---- 顶部区域形态 ----
  /// hero: 大标题区（渐变 / 纯色 / 毛玻璃）
  final UiHeaderStyle headerStyle;

  /// 标题排版位置：bar = 顶栏内小号居中，hero = 顶栏下方大标题
  final UiTitleLayout titleLayout;

  // ---- 组件形态 ----
  final double cardRadius;
  final double chipRadius;
  /// 卡片描边（null = 无描边）
  final Color? cardBorder;
  /// 选中的标签胶囊：实心 = 主色填充；描边 = 仅描边
  final bool chipSolid;
  /// 分组头：pill = 药丸底；bar = 左侧色条；plain = 纯文字
  final UiSectionHeaderStyle sectionHeaderStyle;

  const UiTheme({
    required this.id,
    required this.name,
    required this.tagline,
    required this.accent,
    required this.accentAlt,
    required this.pageBg,
    required this.cardBg,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.danger,
    required this.positive,
    required this.menuBg,
    required this.headerStyle,
    required this.titleLayout,
    required this.cardRadius,
    required this.chipRadius,
    required this.cardBorder,
    required this.chipSolid,
    required this.sectionHeaderStyle,
  });

  /// 顶部主色渐变（无渐变方案返回同色）
  Gradient get headerGradient => LinearGradient(
        colors: [accent, accentAlt],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  bool get isDark => menuBg.computeLuminance() < 0.4;

  // ================= A 晨曦 =================
  static const a = UiTheme(
    id: 'a',
    name: 'A · 晨曦',
    tagline: '延续现有蓝调，视觉最稳',
    accent: Color(0xFF3B6FE0),
    accentAlt: Color(0xFF5B8AF0),
    pageBg: Color(0xFFF3F6FB),
    cardBg: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF2A3B52),
    textSecondary: Color(0xFF5A6B82),
    textTertiary: Color(0xFF9AA8BF),
    divider: Color(0xFFE8EDF5),
    danger: Color(0xFFE0576A),
    positive: Color(0xFF2A9D5C),
    menuBg: Color(0xFFFFFFFF),
    headerStyle: UiHeaderStyle.gradientBleed,
    titleLayout: UiTitleLayout.bar,
    cardRadius: 14,
    chipRadius: 999,
    cardBorder: null,
    chipSolid: true,
    sectionHeaderStyle: UiSectionHeaderStyle.bar,
  );

  // ================= B 墨线 =================
  static const b = UiTheme(
    id: 'b',
    name: 'B · 墨线',
    tagline: '冷调纸感，编辑杂志风',
    accent: Color(0xFF33404F),
    accentAlt: Color(0xFF4C5B6D),
    pageBg: Color(0xFFF7F8F7),
    cardBg: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF2F4F3),
    textPrimary: Color(0xFF1E242B),
    textSecondary: Color(0xFF5E6874),
    textTertiary: Color(0xFF9BA4AE),
    divider: Color(0xFFE3E7E5),
    danger: Color(0xFFC9584F),
    positive: Color(0xFF3F7D63),
    menuBg: Color(0xFFFFFFFF),
    headerStyle: UiHeaderStyle.solidFlat,
    titleLayout: UiTitleLayout.hero,
    cardRadius: 4,
    chipRadius: 4,
    cardBorder: Color(0xFFE1E6E3),
    chipSolid: false,
    sectionHeaderStyle: UiSectionHeaderStyle.plain,
  );

  // ================= C 暮光 =================
  static const c = UiTheme(
    id: 'c',
    name: 'C · 暮光',
    tagline: '深色优先，护眼夜间',
    accent: Color(0xFF7C6CF0),
    accentAlt: Color(0xFFA78BFA),
    pageBg: Color(0xFF14161C),
    cardBg: Color(0xFF1E2129),
    surfaceAlt: Color(0xFF232733),
    textPrimary: Color(0xFFECEFF5),
    textSecondary: Color(0xFFA7AEC0),
    textTertiary: Color(0xFF6D7488),
    divider: Color(0xFF2C3140),
    danger: Color(0xFFF0647E),
    positive: Color(0xFF4BC98A),
    menuBg: Color(0xFF1A1D24),
    headerStyle: UiHeaderStyle.glass,
    titleLayout: UiTitleLayout.bar,
    cardRadius: 18,
    chipRadius: 999,
    cardBorder: null,
    chipSolid: true,
    sectionHeaderStyle: UiSectionHeaderStyle.pill,
  );

  // ================= D 纸间 =================
  static const d = UiTheme(
    id: 'd',
    name: 'D · 纸间',
    tagline: '暖米纸感，亲切柔和',
    accent: Color(0xFFC4703F),
    accentAlt: Color(0xFFE0A15C),
    pageBg: Color(0xFFFAF5EE),
    cardBg: Color(0xFFFFFDF9),
    surfaceAlt: Color(0xFFF6EEE2),
    textPrimary: Color(0xFF40372C),
    textSecondary: Color(0xFF7A6C5A),
    textTertiary: Color(0xFFAFA08C),
    divider: Color(0xFFEFE6D9),
    danger: Color(0xFFC9584F),
    positive: Color(0xFF5E8B5A),
    menuBg: Color(0xFFFFFDF9),
    headerStyle: UiHeaderStyle.solidFlat,
    titleLayout: UiTitleLayout.hero,
    cardRadius: 20,
    chipRadius: 999,
    cardBorder: null,
    chipSolid: true,
    sectionHeaderStyle: UiSectionHeaderStyle.pill,
  );

  static const all = <UiTheme>[a, b, c, d];

  static UiTheme byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => a);
}

enum UiHeaderStyle {
  /// 渐变主色铺满顶部区域（含统计条），页面内容白底
  gradientBleed,
  /// 纯色细顶栏 + 页面底色统一，标题在下方大号排版
  solidFlat,
  /// 毛玻璃半透顶栏，深色底
  glass,
}

enum UiTitleLayout { bar, hero }

enum UiSectionHeaderStyle { bar, pill, plain }
