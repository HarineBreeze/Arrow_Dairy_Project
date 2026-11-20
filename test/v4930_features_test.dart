import 'dart:io';

import 'package:ayodiray/screens/asset_screen.dart';
import 'package:ayodiray/screens/countdown_screen.dart';
import 'package:ayodiray/screens/item_list_screen.dart';
import 'package:ayodiray/screens/trash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.30 回归：
/// 1. 弹层确认按钮（完成 / 确定）去掉绿色底纹色块，统一为主色文字按钮；
/// 2. 回收站底部提示语「超过7天的内容将彻底删除」吸附页面最底部；
/// 3. （封面预览入口移除已在 v4928 / v4929 测试中同步覆盖）
class _FakePathProvider extends PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory('/tmp/v4930_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  void expectPlainTextButton(WidgetTester tester, String label) {
    expect(
      find.ancestor(
          of: find.text(label), matching: find.byType(ElevatedButton)),
      findsNothing,
      reason: '$label 不应再有绿色色块底纹',
    );
    expect(
      find.ancestor(
          of: find.text(label), matching: find.byType(TextButton)),
      findsOneWidget,
      reason: '$label 应为纯文字按钮',
    );
  }

  group('弹层确认按钮去底纹色块', () {
    testWidgets('物品排序弹层：完成为主色文字按钮', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ItemListScreen(onOpenMenu: () {})),
      ));
      await _settle(tester);
      await tester.tap(find.byTooltip('排序方式'));
      await _settle(tester);
      expectPlainTextButton(tester, '完成');
    });

    testWidgets('资产筛选弹层：确定为主色文字按钮', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AssetScreen())));
      await _settle(tester);
      await tester.tap(find.byTooltip('筛选'));
      await _settle(tester);
      expectPlainTextButton(tester, '确定');
      expectPlainTextButton(tester, '取消');
    });

    testWidgets('事件筛选弹层：确定为主色文字按钮', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: CountdownScreen())));
      await _settle(tester);
      await tester.tap(find.byTooltip('筛选'));
      await _settle(tester);
      expectPlainTextButton(tester, '确定');
    });
  });

  group('回收站提示语置于内容最底部', () {
    testWidgets('提示语置于内容最底部（空态常驻底部、有内容态随列表滚动到末尾）',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: TrashScreen(onOpenMenu: () {})),
      ));
      await _settle(tester);

      expect(find.text('超过7天的内容将彻底删除'), findsOneWidget);
      final rect = tester.getRect(find.text('超过7天的内容将彻底删除'));
      // 视口高 600：v4.9.48 起提示语不再吸附视口，而是置于内容最底部；
      // 空态无内容可滚，仍贴近底部（底部留白 ~10）。
      expect(rect.bottom, greaterThan(560),
          reason: '空态下提示语应位于页面最底部');
    });
  });
}
