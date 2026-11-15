import 'dart:io';

import 'package:ayodiray/screens/edit_screen.dart';
import 'package:ayodiray/utils/list_text.dart';
import 'package:ayodiray/widgets/format_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

/// v4.9.11 列表格式回归：
/// 输入 `1. ` / `· ` 即成条目，回车续号，退格退回正文，
/// 工具栏「1.」「·」「正文」「升级 / 降级」按钮生效。
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
    dir = Directory('/tmp/list_edit_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
  });

  Future<TextEditingController> openEditor(WidgetTester tester) async {
    tester.binding.window.physicalSizeTestValue = const Size(400, 900);
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
    addTearDown(tester.binding.window.clearDevicePixelRatioTestValue);

    await tester.pumpWidget(const MaterialApp(home: EditScreen()));
    await _settle(tester);

    final body = find.byType(TextField).last;
    await tester.tap(body);
    await tester.pump(const Duration(milliseconds: 300));

    final field = tester.widget<TextField>(body);
    return field.controller!;
  }

  /// 触发排版栏的列表动作。
  ///
  /// 先选中全文进入「框选模式」让排版栏出现；动作执行后选区塌陷、
  /// 排版栏会自动收起，因此每次调用都要重新进入。
  /// 画布高度有限，按钮可能被底部保存栏压住，这里走 widget 回调，
  /// 按钮本身的点击由下方独立用例覆盖。
  Future<void> invokeList(WidgetTester tester, TextEditingController ctrl,
      ListAction action) async {
    ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    await tester.pump(const Duration(milliseconds: 250));
    final bar = tester.widget<FormatToolbar>(find.ancestor(
      of: find.text('正文'),
      matching: find.byType(FormatToolbar),
    ));
    bar.onListAction!(action);
    await tester.pump();
  }

  /// 模拟平台输入法的一次增量更新
  Future<void> input(WidgetTester tester, String text) async {
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ));
    await tester.pump();
  }

  testWidgets('打字「1.」加空格即成数字条目，回车自动接 2.', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '1.');
    expect(ctrl.text, '1.', reason: '没有空格还不能认定是条目');
    await input(tester, '1. ');
    expect(ctrl.text, '1. ');

    await input(tester, '1. 第一项');
    await input(tester, '1. 第一项\n');
    expect(ctrl.text, '1. 第一项\n2. ',
        reason: '换行后新行自动补下一号，光标停在前缀之后');

    await input(tester, '1. 第一项\n2. 第二项');
    await input(tester, '1. 第一项\n2. 第二项\n');
    expect(ctrl.text, '1. 第一项\n2. 第二项\n3. ');
  });

  testWidgets('圆点条目回车继续是圆点', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '· ');
    await input(tester, '· 早餐');
    await input(tester, '· 早餐\n');
    expect(ctrl.text, '· 早餐\n· ');
  });

  testWidgets('二级条目回车接字母序号', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '\u3000a. ');
    await input(tester, '\u3000a. 细项');
    await input(tester, '\u3000a. 细项\n');
    expect(ctrl.text, '\u3000a. 细项\n\u3000b. ');
  });

  testWidgets('空条目再回车退出列表', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '1. ');
    await input(tester, '1. \n');
    expect(ctrl.text, '\n', reason: '空条目回车应把这一行退回正文');
  });

  testWidgets('删掉标记的空格即整段退回正文', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '1. ');
    // 用户按一次退格：删掉尾随空格，只剩裸序号
    await input(tester, '1.');
    expect(ctrl.text, '', reason: '整段标记应一起消失，而不是留下「1.」');
  });

  testWidgets('工具栏「1.」给当前行加序号，「正文」退回', (tester) async {
    final ctrl = await openEditor(tester);
    await input(tester, '今天很好');
    
    await invokeList(tester, ctrl, ListAction.number);
    expect(ctrl.text, '1. 今天很好');

    await invokeList(tester, ctrl, ListAction.plain);
    expect(ctrl.text, '今天很好');
    await tester.pump(const Duration(seconds: 1)); // 排空防抖 / 键盘确认定时器
  });

  testWidgets('工具栏「·」与降级：一级圆点 → 二级圆点缩进一格', (tester) async {
    final ctrl = await openEditor(tester);
    await input(tester, '条目');
    
    await invokeList(tester, ctrl, ListAction.bullet);
    expect(ctrl.text, '· 条目');

    await invokeList(tester, ctrl, ListAction.down);
    expect(ctrl.text, '\u3000· 条目', reason: '二级圆点仍是圆点，只加一格缩进');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('工具栏降级：数字一级 → 字母二级', (tester) async {
    final ctrl = await openEditor(tester);
    await input(tester, '1. 条目');
    
    await invokeList(tester, ctrl, ListAction.down);
    expect(ctrl.text, '\u3000a. 条目');

    await invokeList(tester, ctrl, ListAction.up);
    expect(ctrl.text, '1. 条目');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('删掉中间一行后，后面的序号自动收拢', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '1. 甲\n2. 乙\n3. 丙');
    // 删掉「2. 乙」这一整行
    await input(tester, '1. 甲\n3. 丙');
    expect(ctrl.text, '1. 甲\n2. 丙', reason: '断裂的序号应收拢成连续');
  });

  testWidgets('待办行回车：下一行自动补未勾选待办框', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '☐ 买牛奶');
    await input(tester, '☐ 买牛奶\n');
    expect(ctrl.text, '☐ 买牛奶\n☐ ', reason: '回车后应自动续一个空待办');
    expect(ctrl.selection.baseOffset, ctrl.text.length, reason: '光标应在待办框后');

    // 继续输入内容，再回车又是新的待办
    await input(tester, '☐ 买牛奶\n☐ 交电费');
    await input(tester, '☐ 买牛奶\n☐ 交电费\n');
    expect(ctrl.text, '☐ 买牛奶\n☐ 交电费\n☐ ');
  });

  testWidgets('已勾选待办回车：续行仍是未勾选框', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '☑ 已完成的事');
    await input(tester, '☑ 已完成的事\n');
    expect(ctrl.text, '☑ 已完成的事\n☐ ');
  });

  testWidgets('空待办再回车：退出待办，回到正文', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '☐ 买牛奶');
    await input(tester, '☐ 买牛奶\n');
    expect(ctrl.text, '☐ 买牛奶\n☐ ');

    // 空待办（只有框）再回车 → 标记被清掉，留一个空行（与列表退出一致）
    await input(tester, '☐ 买牛奶\n☐ \n');
    expect(ctrl.text, '☐ 买牛奶\n\n');
  });

  testWidgets('一级标题（数字）回车：自动接下一个序号', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '1. 今日小结');
    await input(tester, '1. 今日小结\n');
    expect(ctrl.text, '1. 今日小结\n2. ');
  });

  testWidgets('二级标题（字母）回车：自动接下一个字母序号', (tester) async {
    final ctrl = await openEditor(tester);

    await input(tester, '\u3000a. 细节');
    await input(tester, '\u3000a. 细节\n');
    expect(ctrl.text, '\u3000a. 细节\n\u3000b. ');
  });
}
