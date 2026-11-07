import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/utils/app_toast.dart';
import 'package:ayodiray/widgets/save_bar.dart';
import 'package:ayodiray/widgets/save_done_button.dart';

/// 「反复点完成会不停弹同一句提示」的回归测试。
///
/// AppToast 现在以**模态底部抽屉**呈现（带遮罩、从下至上滑入）：
/// - 同一句提示在展示期内只弹一次（去重）；
/// - 内容变化时旧的立刻关闭、新的顶上（同一时刻至多一条）；
/// - 停留时长到点自动收回；点遮罩 / 点提示本身可提前关闭；
/// - 展示期结束后同类提示可以正常再弹（不会永久静音）。
void main() {
  setUp(AppToast.resetForTest);

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox.shrink(),
        bottomNavigationBar: SaveBar(
          saveKey: GlobalKey<SaveDoneButtonState>(),
          color: const Color(0xFF3E8E6D),
          onCancel: () {},
          validate: () => null,
          onSave: () {},
          onDone: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// 直接走根 Navigator 的 context 调 show，等价于页面里
  /// 各处 AppToast.show(context, …) 的真实路径。
  Future<void> trigger(WidgetTester tester, String msg) async {
    final ctx = tester.state(find.byType(Navigator)).context;
    AppToast.show(ctx, msg);
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets('同一句提示展示期内只弹一次，不会反复堆叠', (tester) async {
    await pumpHost(tester);

    await trigger(tester, '请填写物品名称');
    await trigger(tester, '请填写物品名称');
    await trigger(tester, '请填写物品名称');

    // 同一句在展示期内被去重：屏幕上只有一条抽屉
    expect(find.text('请填写物品名称'), findsOneWidget,
        reason: '同一句提示展示期内只弹一次');

    // 停留时长过后自动收回（模态路由整体退出）
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('请填写物品名称'), findsNothing,
        reason: '提示应在停留时长后自动收回');
  });

  testWidgets('提示消失后再次触发，可以正常再弹一次', (tester) async {
    await pumpHost(tester);

    await trigger(tester, '请填写物品名称');
    expect(find.text('请填写物品名称'), findsOneWidget);

    // 等待自动收回
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('请填写物品名称'), findsNothing);

    // 测试里墙钟不随 pump 前进，显式把去重记录标记为已过期
    AppToast.markExpiredForTest();
    await trigger(tester, '请填写物品名称');
    expect(find.text('请填写物品名称'), findsOneWidget,
        reason: '展示期结束后应能重新提示');

    // 等第二次提示自动收回，避免留下 pending timer
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('请填写物品名称'), findsNothing);
  });

  testWidgets('提示内容变了：立即换成新的一句，不排队', (tester) async {
    await pumpHost(tester);

    await trigger(tester, '请填写事件名称');
    expect(find.text('请填写事件名称'), findsOneWidget);

    // 内容变化：旧的立即关闭、新的顶上
    await trigger(tester, '请选择事件日');

    // 等旧提示退场动画播完
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('请选择事件日'), findsOneWidget,
        reason: '新提示应立即出现');
    expect(find.text('请填写事件名称'), findsNothing,
        reason: '旧提示应被立即替换掉，而不是排在后面慢慢播');

    // 等新提示自动收回，避免留下 pending timer
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('点遮罩可以提前关闭提示', (tester) async {
    await pumpHost(tester);

    await trigger(tester, '请填写物品名称');
    expect(find.text('请填写物品名称'), findsOneWidget);

    // 遮罩在提示条上方，点屏幕中上部命中 ModalBarrier
    await tester.tapAt(const Offset(200, 120));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('请填写物品名称'), findsNothing,
        reason: '点遮罩应提前关闭提示');

    // 遮罩关闭已取消自动收回 timer；再泵几帧确认无残留
    await tester.pump(const Duration(milliseconds: 100));
  });
}
