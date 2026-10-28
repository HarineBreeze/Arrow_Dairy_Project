import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter_test/flutter_test.dart';

/// 手势竞技场优先级自检：复刻主页结构——
/// 底层内容区带横向功能（HorizontalDrag 识别器，18px 声明），
/// 顶层菜单手势层（translucent GestureDetector + pan 识别器，36px 声明）。
/// 验证：二者绝不同时触发；页面功能优先，页面没有手势的区域菜单接管。
class _MenuHarness extends StatefulWidget {
  const _MenuHarness({this.pageDragArea = true, this.pageVerticalOnly = false});
  final bool pageDragArea;

  /// 页面只有纵向滚动（如普通列表）的场景
  final bool pageVerticalOnly;

  @override
  State<_MenuHarness> createState() => _MenuHarnessState();
}

class _MenuHarnessState extends State<_MenuHarness> {
  int pageDrags = 0;
  int menuDrags = 0;
  double menuDx = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 底层：页面内容
        Positioned.fill(
          child: widget.pageVerticalOnly
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => setState(() => pageDrags++),
                  child: const ColoredBox(color: Colors.white),
                )
              : widget.pageDragArea
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) =>
                          setState(() => pageDrags++),
                      child: const ColoredBox(color: Colors.white),
                    )
                  : const ColoredBox(color: Colors.white),
        ),
        // 顶层：菜单手势层（与主页实现一致：translucent + pan + down）
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (_) => setState(() => menuDrags++),
            onPanUpdate: (d) => setState(() => menuDx += d.delta.dx),
          ),
        ),
      ],
    );
  }
}

void main() {
  Future<_MenuHarnessState> pump(WidgetTester tester, _MenuHarness harness) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: harness)));
    return tester.state<_MenuHarnessState>(find.byType(_MenuHarness));
  }

  testWidgets('页面有横向功能时：功能执行，菜单不参与（不同时触发）',
      (tester) async {
    await pump(tester, const _MenuHarness());

    // 横向滑动（超过 pan 的 36px 声明阈值）
    await tester.dragFrom(const Offset(100, 300), const Offset(120, 0));
    await tester.pumpAndSettle();

    final s = tester.state<_MenuHarnessState>(find.byType(_MenuHarness));
    expect(s.pageDrags, 1, reason: '页面横向功能应执行');
    expect(s.menuDrags, 0, reason: '菜单不得同时触发');
  });

  testWidgets('页面只有纵向滚动时：纵向滑动归列表，横向滑动归菜单',
      (tester) async {
    await pump(tester, const _MenuHarness(pageVerticalOnly: true));

    // 纵向滑动 → 列表
    await tester.dragFrom(const Offset(100, 300), const Offset(0, -120));
    await tester.pumpAndSettle();
    var s = tester.state<_MenuHarnessState>(find.byType(_MenuHarness));
    expect(s.pageDrags, 1, reason: '纵向滑动应由列表处理');
    expect(s.menuDrags, 0, reason: '纵向滑动不应拉出菜单');

    // 横向滑动 → 菜单
    await tester.dragFrom(const Offset(100, 300), const Offset(120, 0));
    await tester.pumpAndSettle();
    s = tester.state<_MenuHarnessState>(find.byType(_MenuHarness));
    expect(s.menuDrags, 1, reason: '横向滑动在无横向功能区域应拉出菜单');
  });

  testWidgets('页面无手势的区域：菜单正常接管', (tester) async {
    await pump(
        tester, const _MenuHarness(pageDragArea: false, pageVerticalOnly: false));

    await tester.dragFrom(const Offset(100, 300), const Offset(120, 0));
    await tester.pumpAndSettle();

    final s = tester.state<_MenuHarnessState>(find.byType(_MenuHarness));
    expect(s.menuDrags, 1, reason: '其余场景菜单应正常触发');
    expect(s.pageDrags, 0);
  });

  testWidgets('空白区第一次滑动：跟手距离不丢失 36px 声明阈值', (tester) async {
    await pump(
        tester, const _MenuHarness(pageDragArea: false, pageVerticalOnly: false));

    // 第一次滑动即应跟手全程：pan 的 36px 声明阈值不得被丢弃，
    // 否则卡片只出来一点点、需要二次滑动才能正常拉出。
    await tester.dragFrom(const Offset(100, 300), const Offset(120, 0));
    await tester.pumpAndSettle();

    final s = tester.state<_MenuHarnessState>(find.byType(_MenuHarness));
    expect(s.menuDrags, 1);
    expect(s.menuDx, greaterThan(110),
        reason: '首次滑动应累计接近 120px 全程位移，而非丢失 36px 阈值后只剩 ~84px');
  });
}
