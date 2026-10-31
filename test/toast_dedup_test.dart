import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/utils/app_toast.dart';
import 'package:diary_app/widgets/save_bar.dart';
import 'package:diary_app/widgets/save_done_button.dart';

/// 「反复点完成会不停弹同一句提示」的回归测试。
///
/// 关键点：SnackBar 会以动画形式进入/退出，单靠 `find.text(msg)` 数不出
/// 「弹了几次」。这里改用 [SnackBar] 的插入次数计数 —— 每调用一次
/// `showSnackBar` 就会新建一个 SnackBar 元素，重复弹出必然计数增加。

void main() {
  setUp(AppToast.resetForTest);

  /// 数当前树上的 SnackBar 个数（含正在退场的）
  int snackCount(WidgetTester tester) => tester
      .widgetList(find.byType(SnackBar, skipOffstage: false))
      .length;

  /// 数「真正显示过的条数」：每条 SnackBar 落进树里算一次。
  ///
  /// 只看屏幕上的 Text 数不出来 —— 退场动画期间旧条还在树上，
  /// 而连点时新条也会叠进去；用曾经出现过的文案集合更稳定。
  Future<void> settle(WidgetTester tester) async {
    // 退场动画约 250ms，留足余量；分步推进让定时器按时触发
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> pumpHost(WidgetTester tester,
      {required String? Function() validate, VoidCallback? onTap}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: const SizedBox.shrink(),
        bottomNavigationBar: SaveBar(
          saveKey: GlobalKey<SaveDoneButtonState>(),
          color: const Color(0xFF3B6FE0),
          onCancel: () {},
          validate: validate,
          onSave: onTap ?? () {},
          onDone: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('连点完成：同一句提示只弹一次，不会反复堆叠', (tester) async {
    var saves = 0;
    await pumpHost(
      tester,
      validate: () => '请填写物品名称',
      onTap: () => saves++,
    );

    // 连点 6 次
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.text('完成'));
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(saves, 0, reason: '校验未通过不应触发保存');
    expect(snackCount(tester), 1,
        reason: '反复点击只应存在一条提示，实际 ${snackCount(tester)}');

    // 展示期内继续连点，仍然只有一条
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('完成'));
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(snackCount(tester), 1,
        reason: '提示仍在展示期，不应再弹新的');
  });

  testWidgets('提示消失后再次点击，可以正常再弹一次', (tester) async {
    await pumpHost(tester, validate: () => '请填写物品名称');

    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(snackCount(tester), 1);

    // 等提示播完并退场（停留时长 + 入/退场动画），分步推进
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await settle(tester);
    expect(snackCount(tester), 0, reason: '提示应在停留时长后自动消失');

    // 此时用户再点，应该重新提示（不能永久静音）
    // 测试里墙钟不随 pump 前进，显式把记录标记为已过期
    AppToast.markExpiredForTest();
    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(snackCount(tester), 1, reason: '展示期结束后应能重新提示');
  });

  testWidgets('提示内容变了：立即换成新的一句，不排队', (tester) async {
    var msg = '请填写事件名称';
    await pumpHost(tester, validate: () => msg);

    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('请填写事件名称'), findsOneWidget);

    // 用户补上名称后，又缺日期 —— 提示应当立刻换成新的那句
    msg = '请选择事件日';
    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('请选择事件日'), findsOneWidget);
    expect(find.text('请填写事件名称'), findsNothing,
        reason: '旧提示应被替换掉，而不是排在后面慢慢播');
    expect(snackCount(tester), 1, reason: '同一时刻只应存在一条提示');
  });

  testWidgets('校验通过时点击进入保存流程（不弹提示）', (tester) async {
    var saves = 0;
    await pumpHost(tester, validate: () => null, onTap: () => saves++);

    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 60));

    expect(saves, 1);
    expect(snackCount(tester), 0);
  });
}
