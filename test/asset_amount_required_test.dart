import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/models/asset.dart';
import 'package:diary_app/screens/asset_edit_screen.dart';
import 'package:diary_app/utils/app_toast.dart';

/// 「资产金额改为必填项」的回归测试。
///
/// 改动前：金额空着点完成会被 `?? 0` 静默存成 0 元卡片，
/// 首页出现一张「¥0」的资产，用户以为自己没保存成功。
/// 改动后：空金额被拦下并提示，且**不会**触发保存。

void main() {
  setUp(AppToast.resetForTest);

  /// 编辑页内容较长，默认 800×600 会把「完成」按钮挤出屏幕
  Future<void> openEditor(WidgetTester tester, {Asset? asset}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: AssetEditScreen(asset: asset)));
    await tester.pumpAndSettle();
  }

  int snackCount(WidgetTester tester) => tester
      .widgetList(find.byType(SnackBar, skipOffstage: false))
      .length;

  testWidgets('金额为空点完成：提示必填且不返回（不保存）', (tester) async {
    await openEditor(tester);

    await tester.tap(find.text('完成'));
    // SnackBar 入场动画需要推进一点才会把 widget 插进树
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('请输入资产金额'), findsOneWidget);
    expect(snackCount(tester), 1);
    // 页面没有 pop：说明保存流程被拦下了
    expect(find.byType(AssetEditScreen), findsOneWidget);
  });

  testWidgets('金额分区标出必填星号', (tester) async {
    await openEditor(tester);
    expect(find.text('资产金额'), findsOneWidget);
    expect(find.text(' *'), findsOneWidget, reason: '资产金额应带必填标记');
  });

  testWidgets('金额填乱码：提示「请输入正确的金额」', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField).last, 'abc');
    await tester.pump();

    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('请输入正确的金额'), findsOneWidget);
    expect(find.byType(AssetEditScreen), findsOneWidget);
  });

  testWidgets('金额为 0：提示「金额不能为 0」', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField).last, '0');
    await tester.pump();

    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('金额不能为 0'), findsOneWidget);
    expect(find.byType(AssetEditScreen), findsOneWidget);
  });

  testWidgets('填了合法金额：校验放行，进入保存流程', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byType(TextField).last, '1234.56');
    await tester.pump();

    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(snackCount(tester), 0, reason: '校验通过不应弹提示');
    // 按钮进入收缩动画后「完成」文字淡出，证明保存流程已启动
    expect(find.byType(AssetEditScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    // 动画播完会 pop，此时页面应已离开
    await tester.pumpAndSettle();
    expect(find.byType(AssetEditScreen), findsNothing,
        reason: '合法金额应保存并返回上一页');
  });

  testWidgets('编辑已有卡片：金额原样带入，改空后不让保存', (tester) async {
    final a = Asset(
      id: 'x1',
      icon: '🏦',
      note: '工资卡',
      type: '银行储蓄',
      amount: 5000,
    );
    await openEditor(tester, asset: a);

    // 原有金额带进输入框
    expect(find.text('5000'), findsOneWidget);

    // 清空后点完成，应被拦下
    await tester.enterText(find.byType(TextField).last, '');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('请输入资产金额'), findsOneWidget);
    expect(find.byType(AssetEditScreen), findsOneWidget);
  });
}
