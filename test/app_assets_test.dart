import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/utils/app_assets.dart';

/// v4.9.34 UI 插画资源校验：
/// 1. 每个 AppAssets 常量对应的文件真实存在于磁盘；
/// 2. 每个路径都已在 pubspec.yaml 的 flutter.assets 里登记；
/// 3. 文件是合法的非空图片（WebP 头）。
void main() {
  // 测试运行于包根目录，pubspec.yaml 与 assets/ 均在此目录下
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('AppAssets 文件真实存在且非空', () {
    for (final path in AppAssets.all) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path 文件不存在');
      expect(file.lengthSync() > 1000, isTrue, reason: '$path 文件异常小');
    }
  });

  test('每个插画都已在 pubspec.yaml 登记', () {
    for (final path in AppAssets.all) {
      expect(pubspec.contains(path), isTrue,
          reason: '$path 未登记到 pubspec.yaml 的 flutter.assets');
    }
  });

  test('插画均为合法 WebP（RIFF....WEBP 头）', () {
    for (final path in AppAssets.all) {
      final bytes = File(path).readAsBytesSync();
      expect(bytes.length >= 12, isTrue, reason: '$path 太短');
      final riff = String.fromCharCodes(bytes.sublist(0, 4));
      final webp = String.fromCharCodes(bytes.sublist(8, 12));
      expect(riff, 'RIFF', reason: '$path 不是 RIFF 文件');
      expect(webp, 'WEBP', reason: '$path 不是 WebP 格式');
    }
  });
}
