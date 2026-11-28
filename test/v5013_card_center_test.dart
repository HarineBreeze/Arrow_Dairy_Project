import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// v5.0.13：
/// ① 资产构成桑基卡移除左上角「资产构成」标题，图表整体小幅上移、
///    内容垂直居中使上下边距相等；
/// ② 资产数据看板第一张（净资产）卡数据排版不变、整体上下左右居中，
///    上下边距相等、左右边距相等。
/// 采用源码静态断言，避免为拿到卡片本体做复杂的数据注入（项目既有惯例）。
void main() {
  final root = Directory.current.path;
  final sankeySrc =
      File('$root/lib/widgets/asset_sankey_card.dart').readAsStringSync();
  final assetSrc =
      File('$root/lib/screens/asset_screen.dart').readAsStringSync();

  group('v5.0.13 桑基卡移除标题并垂直居中', () {
    test('「资产构成」标题文本已从桑基卡移除', () {
      expect(sankeySrc, isNot(contains("Text('资产构成'")),
          reason: '桑基卡不应再渲染左上角「资产构成」标题');
    });

    test('桑基卡内容列改为垂直居中（上下边距相等）', () {
      // 图表 SizedBox 所在的 Column 使用 center，拉伸后上下留白相等
      expect(sankeySrc, contains('mainAxisAlignment: MainAxisAlignment.center'),
          reason: '桑基卡内容列应垂直居中');
    });
  });

  group('v5.0.13 净资产卡整体上（下）左右居中', () {
    test('padding 上下相等、左右相等', () {
      expect(assetSrc, contains('EdgeInsets.symmetric(horizontal: 16, vertical: 21)'),
          reason: '净资产卡应上下 padding 相等(21)、左右相等(16)');
      expect(assetSrc, isNot(contains('EdgeInsets.fromLTRB(16, 24, 16, 18)')),
          reason: '旧的上下不等 padding 应移除');
    });

    test('内容列垂直居中（上下边距相等）', () {
      expect(assetSrc, contains('mainAxisAlignment: MainAxisAlignment.center'),
          reason: '净资产卡内容列应垂直居中');
      expect(assetSrc, isNot(contains('MainAxisAlignment.spaceBetween')),
          reason: '旧的 spaceBetween 分布应移除');
    });
  });
}
