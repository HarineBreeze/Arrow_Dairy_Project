import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/screens/asset_screen.dart';
import 'package:diary_app/widgets/pressable.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 回归：长按拖拽结束后，卡片按压缩放必须回到 1.0。
///
/// 背景：排查「拖拽浮层与邻卡叠成嵌套卡片」反馈时补的断言——
/// 拖拽浮层里的 Pressable 会在 initState 时短暂接管共享的 PressableHandle，
/// 若时序处理不当，原卡片可能永远卡在按压缩放（90%）不再回弹。
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

/// 读某张卡片 Pressable 当前缩放
double scaleOf(WidgetTester tester, String note) {
  final cardFinder = find.ancestor(
    of: find.text(note),
    matching: find.byType(Pressable),
  );
  final t = tester.widget<Transform>(
    find.descendant(of: cardFinder, matching: find.byType(Transform)),
  );
  return t.transform.storage[0];
}

void main() {
  testWidgets('拖拽结束后卡片缩放必须回到 1.0', (tester) async {
    final dir = Directory(
        '/tmp/ghost_seed_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    final assets = [
      {'id': 'a1', 'icon': '🏦', 'note': '借张三', 'type': '欠款', 'amount': -500},
      {'id': 'a2', 'icon': '💳', 'note': '日常支出', 'type': '信用卡', 'amount': -2000},
      {'id': 'a3', 'icon': '🏦', 'note': '工资卡', 'type': '银行储蓄', 'amount': 3000},
    ];
    File('${dir.path}/assets.json').writeAsStringSync(jsonEncode(assets));
    PathProviderPlatform.instance = _FakePathProvider(dir.path);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: AssetScreen()),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      if (!tester.allWidgets
          .any((w) => w.runtimeType.toString() == 'ListSkeleton')) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 300));

    expect(scaleOf(tester, '借张三'), closeTo(1.0, 1e-6), reason: '初始应为 100%');

    // —— 模拟一次完整的长按拖拽 ——
    final start = tester.getCenter(find.text('借张三'));
    final target = tester.getCenter(find.text('工资卡'));
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 700)); // 触发拖拽
    await tester.pump(const Duration(milliseconds: 100));
    // 拖拽应已开始：屏幕上应存在拖拽代理（无法直接找），但原卡应处于按下态
    // ignore: avoid_print
    print('DBG mid-drag scale(借张三)=${scaleOf(tester, '借张三')}');
    final gap = target.dy - start.dy;
    for (var i = 1; i <= 12; i++) {
      await g.moveBy(Offset(0, gap / 12));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final s1 = scaleOf(tester, '借张三');
    final s2 = scaleOf(tester, '日常支出');
    final s3 = scaleOf(tester, '工资卡');
    // ignore: avoid_print
    print('DBG scales after drop: 借张三=$s1 日常支出=$s2 工资卡=$s3');
    List<String> order() {
      final notes = ['借张三', '日常支出', '工资卡'];
      final present = notes.where((n) => find.text(n).evaluate().isNotEmpty);
      return present.toList()
        ..sort((a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy));
    }
    // ignore: avoid_print
    print('DBG order after drop: ${order()}');
    expect(s1, closeTo(1.0, 1e-3),
        reason: '拖拽结束后「借张三」应回到 100%');
    expect(s2, closeTo(1.0, 1e-3));
    expect(s3, closeTo(1.0, 1e-3));
  });
}
