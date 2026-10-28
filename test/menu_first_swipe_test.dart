import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/screens/home_screen.dart';
import 'package:diary_app/screens/side_menu.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// 回归测试：首次右滑即应滑出菜单侧边栏。
///
/// 曾出现的 bug：菜单打开瞬间遮罩层按 `_menuAnim.value > 0` 条件增删，
/// 首次拖拽跨越 0 时改变 Stack 子节点结构，打断手势层识别器，导致
/// 第一次滑动只挪动一点点就「卡住」、无 onPanEnd/onPanCancel，需第二次
/// 滑动才能正常拉出。修复后遮罩层常驻树中（IgnorePointer 控制是否响应），
/// 首次滑动即全程跟手并滑出。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首次右滑即滑出菜单侧边栏', (tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(400, 800);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

    final dir =
        Directory('/tmp/menu_first_swipe_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    addTearDown(() {
      dir.deleteSync(recursive: true);
      PathProviderPlatform.instance = MethodChannelPathProvider();
    });

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));

    double menuLeft() {
      final el = tester.element(find.byType(SideMenu));
      final box = el.renderObject! as RenderBox;
      return box.localToGlobal(Offset.zero).dx;
    }

    // 关闭状态：SideMenu 完全移出屏幕左侧（x = -menuWidth = -300）
    expect(menuLeft(), closeTo(-300, 0.1));

    // 第一次右滑（150px / 250ms，贴近真实甩动）
    await tester.timedDragFrom(const Offset(30, 400), const Offset(150, 0),
        const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    // 修复前这里只会挪动 ~28px（x≈-271）并卡住；修复后应完全滑出（x=0）
    expect(menuLeft(), closeTo(0, 0.1),
        reason: '首次右滑即应滑出菜单，而不是卡住后需二次滑动');
  });
}
