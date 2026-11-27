import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// v5.0.11：资产页 / 事件页（倒计时页）预览卡片图标放大。
/// 两处卡片图标容器 46→56、EntryIcon size 24→34。
/// 采用源码静态断言，避免为拿到卡片本体做复杂的数据注入。
void main() {
  final root = Directory.current.path;
  final assetSrc =
      File('$root/lib/screens/asset_screen.dart').readAsStringSync();
  final eventSrc =
      File('$root/lib/screens/countdown_screen.dart').readAsStringSync();

  group('v5.0.11 预览卡片图标放大', () {
    test('资产卡片图标容器 56×56、EntryIcon size 34', () {
      expect(assetSrc, contains('width: 56,'),
          reason: '资产卡片图标容器宽度应为 56');
      expect(assetSrc, contains('height: 56,'),
          reason: '资产卡片图标容器高度应为 56');
      expect(assetSrc, contains('EntryIcon(a.icon, size: 34)'),
          reason: '资产卡片图标应放大到 34');
    });

    test('事件卡片图标容器 56×56、EntryIcon size 34', () {
      expect(eventSrc, contains('width: 56,'),
          reason: '事件卡片图标容器宽度应为 56');
      expect(eventSrc, contains('height: 56,'),
          reason: '事件卡片图标容器高度应为 56');
      expect(eventSrc, contains('size: 34,'),
          reason: '事件卡片图标应放大到 34');
    });

    test('旧的 46 容器 / size 24 图标已从两处移除', () {
      expect(assetSrc, isNot(contains('width: 46,')),
          reason: '资产卡片不应再留 46 容器');
      expect(assetSrc, isNot(contains('EntryIcon(a.icon, size: 24)')),
          reason: '资产卡片不应再留 size 24 图标');
      expect(eventSrc, isNot(contains('size: 24,')),
          reason: '事件卡片不应再留 size 24 图标');
    });
  });
}
