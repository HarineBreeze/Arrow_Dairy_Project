/// UI 插画资源路径（集中管理，避免代码里散落硬编码字符串）。
///
/// 全部为扁平风、抹茶绿配色的 WebP，无内嵌文字；需要在图上显示的文案
/// 由调用方用 Flutter 组件叠加（Stack + Positioned），不要依赖图片里的字。
///
/// 资源文件位于 assets/images/，已在 pubspec.yaml 的 flutter.assets 登记。
class AppAssets {
  AppAssets._();

  static const String imageDir = 'assets/images';

  /// 顶部欢迎横幅（1536×1024，左侧留白供叠文字）
  static const String bannerWelcome = '$imageDir/banner_welcome.webp';

  /// 四模块卡片配图（1024×1024）
  static const String cardDiary = '$imageDir/card_diary.webp';
  static const String cardItem = '$imageDir/card_item.webp';
  static const String cardAsset = '$imageDir/card_asset.webp';
  static const String cardCountdown = '$imageDir/card_countdown.webp';

  /// 空状态插画（1024×1024）
  static const String cardEmpty = '$imageDir/card_empty.webp';

  /// 全部新增插画，便于批量校验
  static const List<String> all = <String>[
    bannerWelcome,
    cardDiary,
    cardItem,
    cardAsset,
    cardCountdown,
    cardEmpty,
  ];
}
