import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:diary_app/models/countdown_event.dart';
import 'package:diary_app/screens/countdown_edit_screen.dart';
import 'package:diary_app/screens/item_list_screen.dart';

/// 「把倒数日统一叫事件」「日期 / 时间选择器拆成两步」
/// 「物品清单顶栏加标题」这三件事的回归测试。

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

Directory _seed() {
  final dir = Directory('/tmp/event_copy_${DateTime.now().microsecondsSinceEpoch}');
  dir.createSync(recursive: true);
  PathProviderPlatform.instance = _FakePathProvider(dir.path);
  return dir;
}

Widget _wrap(Widget child) => MaterialApp(home: child);

/// 找到某个文本所在的那一块（三块布局里各自是一层 Container）
Rect _rowBlock(WidgetTester tester, String text) {
  final box = find
      .ancestor(of: find.text(text), matching: find.byType(Container))
      .first;
  return tester.getRect(box);
}

/// 编辑页内容较长：把测试画布调高，保证「日期 / 时间」两行都在首屏内
/// （默认 800x600 会让下面几行落在滚动区外）
Future<void> _tall(WidgetTester tester) =>
    tester.binding.setSurfaceSize(const Size(1080, 2400));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('编辑页文案：统一为「事件」', () {
    testWidgets('新增时标题为「新增事件」，编辑时为「编辑事件」', (tester) async {
      _seed();

      await _tall(tester);
      await tester.pumpWidget(_wrap(const CountdownEditScreen()));
      await tester.pumpAndSettle();
      expect(find.text('新增事件'), findsOneWidget);
      expect(find.text('编辑事件'), findsNothing);
      expect(find.text('新增倒数日'), findsNothing);
      expect(find.text('编辑倒数日'), findsNothing);
      // 图标分区也不该再写「倒数日」
      expect(find.text('倒数日图标'), findsNothing);
      expect(find.text('事件图标'), findsOneWidget);

      final e = CountdownEvent(
        id: 'e1',
        icon: '🎂',
        name: '生日',
        target: DateTime(2030, 5, 1, 9, 0),
        type: '生日',
      );
      await tester.pumpWidget(_wrap(CountdownEditScreen(event: e)));
      await tester.pumpAndSettle();
      expect(find.text('编辑事件'), findsOneWidget);
      expect(find.text('编辑倒数日'), findsNothing);
    });
  });

  group('编辑页日期 / 时间 / 正数倒数：一行三块', () {
    testWidgets('三块同高同行，宽度按 2 : 2 : 1 分配', (tester) async {
      _seed();
      final e = CountdownEvent(
        id: 'e2',
        icon: '🎂',
        name: '生日',
        target: DateTime(2030, 5, 1, 9, 30),
        type: '生日',
      );
      await _tall(tester);
      await tester.pumpWidget(_wrap(CountdownEditScreen(event: e)));
      await tester.pumpAndSettle();

      // 日期块 / 时间块 / 状态块都能在首屏找到
      final dateR = _rowBlock(tester, '2030年5月1日');
      final timeR = _rowBlock(tester, '09:30');
      final tagR = _rowBlock(tester, '倒数');

      // 1) 同一行：垂直中心一致、高度一致
      expect((dateR.center.dy - timeR.center.dy).abs(), lessThan(1),
          reason: '日期与时间必须在同一行');
      expect((dateR.center.dy - tagR.center.dy).abs(), lessThan(1),
          reason: '状态块必须与它们同行');
      expect((dateR.height - tagR.height).abs(), lessThan(1),
          reason: '三块应等高');

      // 2) 从左到右排列
      expect(dateR.right, lessThanOrEqualTo(timeR.left + 0.5));
      expect(timeR.right, lessThanOrEqualTo(tagR.left + 0.5));

      // 3) 宽度 2 : 2 : 1（允许 8px 间距带来的少量误差）
      expect(dateR.width / tagR.width, closeTo(2.0, 0.08),
          reason: '日期块应约为状态块的 2 倍宽，实际 ${dateR.width} vs ${tagR.width}');
      expect(timeR.width / tagR.width, closeTo(2.0, 0.08),
          reason: '时间块应约为状态块的 2 倍宽，实际 ${timeR.width} vs ${tagR.width}');
      expect((dateR.width - timeR.width).abs(), lessThan(1),
          reason: '日期块与时间块应等宽');

      // 4) 两块加起来约占整行的五分之四
      final total = dateR.width + timeR.width + tagR.width;
      expect((dateR.width + timeR.width) / total, closeTo(0.8, 0.06));
    });

    testWidgets('点日期只弹三列、点时间只弹两列，各自独立', (tester) async {
      _seed();
      final e = CountdownEvent(
        id: 'e4',
        icon: '🎂',
        name: '生日',
        target: DateTime(2030, 5, 1, 9, 30),
        type: '生日',
      );
      await _tall(tester);
      await tester.pumpWidget(_wrap(CountdownEditScreen(event: e)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2030年5月1日'));
      await tester.pumpAndSettle();
      expect(find.text('选择日期'), findsOneWidget);
      expect(find.byType(CupertinoPicker), findsNWidgets(3));
      // 页面底部保存栏也有「取消」，这里要点弹层里的那个（最后一个）
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(find.text('09:30'), findsOneWidget, reason: '取消日期不应改动时间');

      await tester.tap(find.text('09:30'));
      await tester.pumpAndSettle();
      expect(find.text('选择时间'), findsOneWidget);
      expect(find.byType(CupertinoPicker), findsNWidgets(2));
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(find.text('09:30'), findsOneWidget);
    });

    testWidgets('编辑已有事件：已存的时分不会被清零', (tester) async {
      _seed();
      final e = CountdownEvent(
        id: 'e3',
        icon: '🎂',
        name: '生日',
        target: DateTime(2030, 5, 1, 20, 15),
        type: '生日',
      );
      await _tall(tester);
      await tester.pumpWidget(_wrap(CountdownEditScreen(event: e)));
      await tester.pumpAndSettle();

      // 进入页面时 _target 必须保留时分（曾用 dateOnly 截断 → 时间行永远 00:00）
      expect(find.text('20:15'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
    });

    testWidgets('没选过日期时三块都是占位文案', (tester) async {
      _seed();
      await _tall(tester);
      await tester.pumpWidget(_wrap(const CountdownEditScreen()));
      await tester.pumpAndSettle();
      // 三块都回到占位态
      expect(find.text('选择日期'), findsOneWidget);
      expect(find.text('选择时间'), findsOneWidget);
      expect(find.text('--'), findsOneWidget);
    });
  });

  group('物品清单顶栏', () {
    testWidgets('菜单键右侧显示「物品清单」标题', (tester) async {
      _seed();
      await tester.pumpWidget(_wrap(
        Scaffold(body: ItemListScreen(onOpenMenu: () {})),
      ));
      // 页面里有骨架屏/加载动画，持续动画会让 pumpAndSettle 超时，只推进有限帧
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('物品清单'), findsOneWidget);
      // 标题在菜单键右侧
      final menu = tester.getCenter(find.byIcon(Icons.menu));
      final title = tester.getCenter(find.text('物品清单'));
      expect(title.dx, greaterThan(menu.dx));
      // 同一行（垂直方向对齐）
      expect((title.dy - menu.dy).abs(), lessThan(6));
    });
  });
}
