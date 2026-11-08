import 'dart:io';

import 'package:ayodiray/screens/edit_screen.dart';
import 'package:ayodiray/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.9 回归：无图时「添加封面图」提示语去掉「· 4:3」，图标与文字整体居中
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
  for (var i = 0; i < 10; i++) {
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
    dir = Directory('/tmp/cover_hint_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  testWidgets('提示语为「添加封面图」，图标与文字整体居中', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

    await tester.pumpWidget(const MaterialApp(home: EditScreen()));
    await _settle(tester);

    final label = find.text('添加封面图');
    expect(label, findsOneWidget);
    expect(find.textContaining('4:3'), findsNothing,
        reason: '提示语不再带比例后缀');
    expect(find.textContaining('·'), findsNothing, reason: '分隔点应一并删除');

    final icon = find.byWidgetPredicate(
        (w) => w is AppIcon && w.path == AppIcons.image);
    expect(icon, findsOneWidget);

    // 图标 + 文字这一组的水平中点应落在 180 宽封面框的中线上
    final row = find.ancestor(of: label, matching: find.byType(Row)).first;
    final rowRect = tester.getRect(row);
    final iconRect = tester.getRect(icon);
    final textRect = tester.getRect(label);
    final groupCenter = (iconRect.left + textRect.right) / 2;
    expect(groupCenter, closeTo(rowRect.center.dx, 1.5),
        reason: '图标与文字整体应居中，组中点 $groupCenter vs 框中线 ${rowRect.center.dx}');
    // 图标在文字左侧，间距 6
    expect(iconRect.right, lessThanOrEqualTo(textRect.left));
    expect(textRect.left - iconRect.right, closeTo(6, 1));
  });
}
