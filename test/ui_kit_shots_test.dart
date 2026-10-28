import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/ui_kit/theme.dart';
import 'package:diary_app/ui_kit/static_wrappers.dart';

/// 把四套方案的 5 个界面各渲染成 PNG，人工检查视觉是否有问题
void main() {
  const w = 248.0;
  const h = 496.0;

  Future<void> shoot(WidgetTester tester, String file, Widget child) async {
    final key = GlobalKey();
    tester.binding.window.physicalSizeTestValue = const Size(1440, 2880);
    tester.binding.window.devicePixelRatioTestValue = 4.0;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: Container(
                width: w,
                height: h,
                color: Colors.white,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final f = File(file);
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  for (final t in UiTheme.all) {
    testWidgets('渲染 ${t.id}', (tester) async {
      await shoot(tester, '/workspace/shots/${t.id}_menu.png',
          UiSideBarStatic(theme: t));
      await shoot(tester, '/workspace/shots/${t.id}_diary.png',
          DiaryPageStatic(theme: t));
      await shoot(tester, '/workspace/shots/${t.id}_items.png',
          ItemsPageStatic(theme: t));
      await shoot(tester, '/workspace/shots/${t.id}_countdown.png',
          CountdownPageStatic(theme: t));
      await shoot(tester, '/workspace/shots/${t.id}_assets.png',
          AssetsPageStatic(theme: t));
    });
  }
}
