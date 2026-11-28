import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:ayodiray/models/asset_history.dart';
import 'package:ayodiray/screens/asset_trend_screen.dart';
import 'package:ayodiray/services/asset_history_storage.dart';

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

AssetHistoryEntry _entry({
  required String id,
  required DateTime time,
  required double assets,
  required double debt,
}) =>
    AssetHistoryEntry(
      id: id,
      time: time,
      changes: [
        AssetChange(name: '微信', type: '银行储蓄', amount: assets),
        AssetChange(name: '支付宝', type: '银行储蓄', amount: debt),
      ],
      totalAssets: assets,
      totalDebt: debt,
      netWorth: assets + debt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AssetHistoryStorage.resetForTest());
  tearDown(() => AssetHistoryStorage.resetForTest());

  testWidgets('Bug1: 折线图 CustomPaint 有非零绘制尺寸', (tester) async {
    final now = DateTime.now();
    AssetHistoryStorage.loadOverride = [
      _entry(id: 'a', time: now.subtract(const Duration(days: 2)), assets: 100, debt: 0),
      _entry(id: 'b', time: now.subtract(const Duration(days: 1)), assets: 200, debt: -50),
      _entry(id: 'c', time: now, assets: 300, debt: -80),
    ];
    await tester.pumpWidget(MaterialApp(
      home: AssetTrendScreen(
        loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
        loadAssetsOverride: () async => [],
      ),
    ));
    await tester.pumpAndSettle();

    final cpFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.toString().contains('TrendPainter'),
    );
    expect(cpFinder, findsOneWidget, reason: '应有一个趋势图 painter');
    final size = tester.renderObject<RenderCustomPaint>(cpFinder).size;
    expect(size.width, greaterThan(100), reason: '折线图宽度不应为 0');
    expect(size.height, greaterThan(100), reason: '折线图高度不应为 0');
  });

  testWidgets('Bug2a: 长按单行按条删除真正生效', (tester) async {
    final now = DateTime.now();
    AssetHistoryStorage.loadOverride = [
      _entry(id: 'a', time: now, assets: 100, debt: -20),
    ];
    expect(AssetHistoryStorage.loadOverride!.first.changes.length, 2);

    await tester.pumpWidget(MaterialApp(
      home: AssetTrendScreen(
        loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
        loadAssetsOverride: () async => [],
      ),
    ));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('微信'));
    await tester.pumpAndSettle();
    expect(find.text('删除这笔改动记录？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(AssetHistoryStorage.loadOverride!.length, 1);
    expect(AssetHistoryStorage.loadOverride!.first.changes.length, 1,
        reason: '长按第一笔后应只剩一笔');
    expect(AssetHistoryStorage.loadOverride!.first.changes.first.name, '支付宝');
  });

  testWidgets('Bug2c: 点击显式删除按钮即时删除（真机主路径）', (tester) async {
    final now = DateTime.now();
    AssetHistoryStorage.loadOverride = [
      _entry(id: 'a', time: now, assets: 100, debt: -20),
    ];
    await tester.pumpWidget(MaterialApp(
      home: AssetTrendScreen(
        loadHistoryOverride: () async => AssetHistoryStorage.loadOverride!,
        loadAssetsOverride: () async => [],
      ),
    ));
    await tester.pumpAndSettle();

    // 每行都有显式删除按钮，点第一个删掉「微信」
    expect(find.byKey(const Key('asset_trend_delete_change')), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('asset_trend_delete_change')).first);
    await tester.pumpAndSettle();
    expect(find.text('删除这笔改动记录？'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // UI 即时更新：界面上不再有「微信」
    expect(find.text('微信'), findsNothing, reason: '删除后 UI 应立即移除该笔');
    expect(AssetHistoryStorage.loadOverride!.first.changes.length, 1);
    expect(AssetHistoryStorage.loadOverride!.first.changes.first.name, '支付宝');
  });

  test('Bug2b: 文件模式 removeChange 删除后不复活', () async {
    final dir = await Directory.systemTemp.createTemp('asset_hist_');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    // 已有 seed 标记，_load 里 seedIfEmpty 不应重新生成
    File('${dir.path}/asset_history_seeded').writeAsStringSync('1');
    final now = DateTime.now();
    final e = _entry(id: 'x', time: now, assets: 100, debt: -20);
    await AssetHistoryStorage.append(e);
    expect((await AssetHistoryStorage.load()).length, 1);

    await AssetHistoryStorage.removeChange('x', 0);
    // 模拟页面 _load 的 seedIfEmpty
    await AssetHistoryStorage.seedIfEmpty([]);
    final after = await AssetHistoryStorage.load();
    expect(after.length, 1, reason: '删 1 笔后仍应有 1 条 entry');
    expect(after.first.changes.length, 1, reason: '应只剩 1 笔');
    expect(after.first.changes.first.name, '支付宝', reason: '删掉的应是微信');

    await AssetHistoryStorage.removeChange('x', 0);
    await AssetHistoryStorage.seedIfEmpty([]);
    expect(await AssetHistoryStorage.load(), isEmpty,
        reason: '删空后整条移除，且不应被 seed 复活');
    dir.deleteSync(recursive: true);
  });
}
