/// App 版本信息（单一来源）。
///
/// 发版时同时更新：
/// - 这里 [displayVersion]（设置页底部展示，形如 `V4.3.3`）
/// - `pubspec.yaml` 的 `version:`（构建号）
/// 两者保持一致，避免设置页显示的版本与安装包不符。
class AppVersion {
  AppVersion._();

  /// 展示用版本号（设置页底部灰色小字）
  static const String displayVersion = 'V4.3.3';

  /// 是否为内测版（菜单侧边栏昵称后展示「内测版」铭牌）
  static const bool isBeta = true;
}
