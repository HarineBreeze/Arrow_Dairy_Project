import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_platform_interface/src/method_channel_path_provider.dart';

import 'package:ayodiray/models/asset.dart';
import 'package:ayodiray/models/diary_entry.dart';
import 'package:ayodiray/models/user_profile.dart';
import 'package:ayodiray/screens/asset_screen.dart';
import 'package:ayodiray/screens/edit_screen.dart';
import 'package:ayodiray/screens/note_view_screen.dart';
import 'package:ayodiray/services/asset_storage.dart';
import 'package:ayodiray/services/reward_service.dart';
import 'package:ayodiray/services/user_storage.dart';
import 'package:ayodiray/utils/stationery.dart';
import 'package:ayodiray/widgets/stationery_paper.dart';

/// 信纸与资产排序回归：
/// 1. 信纸样式常量（4 款全 VIP，仅经典免费）与按 id 查询；
/// 2. DiaryEntry.stationery 落盘/读回，旧数据零迁移，下架样式回退经典；
/// 3. 浏览页按信纸渲染，经典保持原背景；
/// 4. 编辑页「更多」的信纸入口 + 抽屉：VIP灰化提示、过期保留、仅标题；
/// 5. 资产拖拽排序：把卡片拖到最顶层（newIndex==1）不再被误杀。
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
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory('/tmp/v4940_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  });
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    PathProviderPlatform.instance = MethodChannelPathProvider();
    UserStorage.revision.value = 0;
    EditScreen.lastSavedId = null;
  });

  void writeProfile(UserProfile p) {
    File('${dir.path}/user_profile.json')
        .writeAsStringSync(jsonEncode(p.toJson()));
  }

  DiaryEntry entryWith({String stationery = '', String content = '正文内容'}) {
    final now = DateTime(2026, 11, 19, 10);
    return DiaryEntry(
      id: 'e1',
      title: '一封日记',
      content: content,
      stationery: stationery,
      createdAt: now,
      updatedAt: now,
      publishDate: now,
    );
  }

  // ---------- 1. 信纸常量 ----------
  group('信纸样式常量', () {
    test('共 3 款，全部 VIP；仅经典（无信纸）免费', () {
      expect(stationeryStyles.length, 3);
      final free = stationeryStyles.where((s) => !s.vip).map((s) => s.id).toSet();
      final vip = stationeryStyles.where((s) => s.vip).map((s) => s.id).toSet();
      expect(free, isEmpty);
      expect(vip, {'grid', 'night', 'kraft'});
      for (final s in stationeryStyles) {
        expect(isVipStationery(s.id), isTrue);
      }
    });

    test('已下架样式查询为空（含抹茶横纹）', () {
      expect(stationeryById('lined'), isNull);
      expect(stationeryById('washi'), isNull);
      expect(stationeryById('botanical'), isNull);
      expect(isValidStationery('lined'), isFalse);
      expect(isValidStationery('washi'), isFalse);
      expect(isValidStationery('botanical'), isFalse);
    });

    test('按 id 查询与 VIP 判定；经典命名', () {
      expect(stationeryById('grid')?.name, '手账方格');
      expect(stationeryById('kraft')?.name, '牛皮旧信');
      expect(stationeryById('night')?.name, '星夜来信');
      expect(isVipStationery('night'), isTrue);
      expect(isVipStationery('grid'), isTrue);
      expect(stationeryById('nope'), isNull);
      expect(isValidStationery(''), isFalse); // 空 = 经典
      expect(stationeryName(''), '经典');
    });
  });

  // ---------- 2. 数据模型 ----------
  group('DiaryEntry.stationery', () {
    test('落盘与读回保留信纸 id', () {
      final e = entryWith(stationery: 'night');
      final map = e.toJson();
      expect(map['stationery'], 'night');
      final back = DiaryEntry.fromJson(map);
      expect(back.stationery, 'night');
    });

    test('旧数据无 stationery 字段 → 经典（空串）', () {
      final e = entryWith();
      final map = e.toJson()..remove('stationery');
      expect(DiaryEntry.fromJson(map).stationery, '');
    });

    test('已下架样式（抹茶横纹/和风信笺/花间私语）读回 → 回退经典', () {
      for (final legacy in ['lined', 'washi', 'botanical', 'nope']) {
        final e = entryWith(stationery: legacy);
        final back = DiaryEntry.fromJson(e.toJson());
        expect(back.stationery, '', reason: '$legacy 应回退经典');
      }
    });
  });

  // ---------- 3. 渲染 ----------
  group('浏览页信纸渲染', () {
    testWidgets('设置 VIP 信纸后正文有信纸绘制层', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(entry: entryWith(stationery: 'night')),
      ));
      await _settle(tester);
      expect(find.byType(StationeryPaper), findsWidgets);
      expect(find.text('一封日记'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('普通信纸仍用普通背景（Unsigned 不报错）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(entry: entryWith(stationery: '')),
      ));
      await _settle(tester);
      expect(find.text('一封日记'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('星夜来信：浏览页背景压暗（与信纸不割裂）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(entry: entryWith(stationery: 'night')),
      ));
      await _settle(tester);
      final scaffold =
          tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFF1A201C));
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('经典：浏览页背景保持默认', (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 1200));
      await tester.pumpWidget(MaterialApp(
        home: NoteViewScreen(entry: entryWith(stationery: 'grid')),
      ));
      await _settle(tester);
      final scaffold =
          tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, isNull);
      await tester.binding.setSurfaceSize(null);
    });
  });

  // ---------- 4. 编辑页信纸入口 ----------
  group('编辑页信纸入口', () {
    Future<void> openMore(WidgetTester tester) async {
      await tester.tap(find.text('更多'));
      await tester.pump(const Duration(milliseconds: 350));
    }

    Future<void> pumpEditor(WidgetTester tester, UserProfile profile) async {
      writeProfile(profile);
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      await tester.pumpWidget(const MaterialApp(home: EditScreen()));
      await _settle(tester);
    }

    testWidgets('更多面板含「信纸」项，默认显示经典', (tester) async {
      await pumpEditor(tester, UserProfile());
      await openMore(tester);
      expect(find.text('信纸'), findsOneWidget);
      expect(find.text('经典'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('经典身份：全部信纸款均 VIP 灰化，点击提示充值', (tester) async {
      await pumpEditor(tester, UserProfile());
      await openMore(tester);
      // 直接触发「信纸」ListTile 的 onTap（面板行可能被挤出屏幕外）
      final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text('信纸'), matching: find.byType(ListTile)));
      tile.onTap!();
      await tester.pump(const Duration(milliseconds: 350));

      // 抽屉：经典 + 3 款信纸（均 VIP）
      expect(find.text('经典'), findsOneWidget);
      expect(find.text('手账方格'), findsOneWidget);
      expect(find.text('星夜来信'), findsOneWidget);
      expect(find.text('牛皮旧信'), findsOneWidget);
      expect(find.text('抹茶横纹'), findsNothing);
      expect(find.text('和风信笺'), findsNothing);
      expect(find.text('花间私语'), findsNothing);
      // 副标题与图标已移除，仅保留标题
      expect(find.text('不加信纸'), findsNothing);
      expect(find.text('未解锁'), findsNothing);
      expect(find.text('使用中'), findsNothing);
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byIcon(Icons.check), findsNothing);

      // 点击信纸款触发提示（找到含「星夜来信」的 ListTile）
      final vipTile = tester.widget<ListTile>(find
          .ancestor(of: find.text('星夜来信'), matching: find.byType(ListTile)));
      vipTile.onTap!();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('星夜来信是VIP专属信纸，请充值后再尝试～'), findsOneWidget);
      // 清理 AppToast Timer
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('VIP 身份：信纸可选', (tester) async {
      final vip = UserProfile(
          badge: UserProfile.badgeVip,
          ownedBadges: [UserProfile.badgeNormal, UserProfile.badgeVip]);
      await pumpEditor(tester, vip);
      await openMore(tester);
      final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text('信纸'), matching: find.byType(ListTile)));
      tile.onTap!();
      await tester.pump(const Duration(milliseconds: 350));
      // 选中一款信纸
      final vipTile = tester.widget<ListTile>(find
          .ancestor(of: find.text('牛皮旧信'), matching: find.byType(ListTile)));
      vipTile.onTap!();
      await tester.pump(const Duration(milliseconds: 350));
      // 抽屉关闭后，更多面板里信纸项显示新名字（重开更多）
      await openMore(tester);
      expect(find.text('牛皮旧信'), findsOneWidget);
      // 编辑页正文落在信纸上（所见即所得）
      expect(find.byType(StationeryPaper), findsWidgets);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('星夜来信：编辑页背景与文字同步压暗/提亮', (tester) async {
      // 已设置 night 的笔记，用 VIP 身份打开编辑
      final now = DateTime(2026, 11, 19, 10);
      File('${dir.path}/diaries.json').writeAsStringSync(jsonEncode([
        DiaryEntry(
          id: 'old2',
          title: '夜信',
          content: '夜色',
          stationery: 'night',
          createdAt: now,
          updatedAt: now,
          publishDate: now,
        ).toJson()
      ]));
      final vip = UserProfile(
          badge: UserProfile.badgeVip,
          ownedBadges: [UserProfile.badgeNormal, UserProfile.badgeVip]);
      writeProfile(vip);
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      await tester.pumpWidget(MaterialApp(home: EditScreen(
        entry: DiaryEntry.fromJson(
            jsonDecode(File('${dir.path}/diaries.json').readAsStringSync())[0]),
      )));
      await _settle(tester);
      final scaffold =
          tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFF1A201C));
      // 正文落在信纸上
      expect(find.byType(StationeryPaper), findsWidgets);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('VIP 过期（当前已设信纸）：保留当前、可切经典、不可换其它款',
        (tester) async {
      // 已设置 'night' 的旧笔记；当前档案为普通身份（已过期）
      final now = DateTime(2026, 11, 19, 10);
      File('${dir.path}/diaries.json').writeAsStringSync(jsonEncode([
        DiaryEntry(
          id: 'old',
          title: '星星信',
          content: 'x',
          stationery: 'night',
          createdAt: now,
          updatedAt: now,
          publishDate: now,
        ).toJson()
      ]));
      writeProfile(UserProfile());
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      await tester.pumpWidget(MaterialApp(home: EditScreen(
        entry: DiaryEntry.fromJson(
            jsonDecode(File('${dir.path}/diaries.json').readAsStringSync())[0]),
      )));
      await _settle(tester);
      await openMore(tester);
      expect(find.text('星夜来信'), findsOneWidget); // 当前信纸名

      final tile = tester.widget<ListTile>(
          find.ancestor(of: find.text('信纸'), matching: find.byType(ListTile)));
      tile.onTap!();
      await tester.pump(const Duration(milliseconds: 350));

      // 当前已设的 night 保留（抽屉可见），经典可点（切回经典）
      expect(find.text('星夜来信'), findsOneWidget);
      final normalTile = tester.widget<ListTile>(find
          .ancestor(of: find.text('经典'), matching: find.byType(ListTile)));
      normalTile.onTap!();
      await tester.pump(const Duration(milliseconds: 350));
      await openMore(tester);
      expect(find.text('经典'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });

  // ---------- 5. 资产拖拽置顶 bug ----------
  group('资产拖拽排序', () {
    Future<void> pumpAsset(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AssetScreen())));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    List<String> visibleOrder(WidgetTester tester, List<String> notes) {
      final present = notes.where((n) => find.text(n).evaluate().isNotEmpty);
      return present.toList()
        ..sort((a, b) => tester
            .getTopLeft(find.text(a))
            .dy
            .compareTo(tester.getTopLeft(find.text(b)).dy));
    }

    testWidgets('把最后一张卡拖到最顶层成功（newIndex==1 不被误杀）', (tester) async {
      File('${dir.path}/assets.json').writeAsStringSync(jsonEncode([
        Asset(id: 'a1', icon: '🏦', note: '工资卡', type: '银行储蓄', amount: 100,
            order: 0).toJson(),
        Asset(id: 'a2', icon: '💳', note: '信用卡', type: '银行储蓄', amount: 200,
            order: 1).toJson(),
        Asset(id: 'a3', icon: '📈', note: '基金账户', type: '投资', amount: 300,
            order: 2).toJson(),
      ]));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await pumpAsset(tester);

      const notes = ['工资卡', '信用卡', '基金账户'];
      expect(visibleOrder(tester, notes), notes);

      // 长按最后一张卡（基金账户）→ 向上拖到最顶 → 松手
      final start = tester.getCenter(find.text('基金账户'));
      final topCard = tester.getCenter(find.text('工资卡'));
      final dy = topCard.dy - start.dy; // 负值：向上
      expect(dy, lessThan(0));

      final g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 700)); // 越过 500ms 阈值
      await tester.pump(const Duration(milliseconds: 100));
      final steps = 14;
      for (var i = 0; i < steps; i++) {
        await g.moveBy(Offset(0, dy / steps));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(visibleOrder(tester, notes).first, '基金账户',
          reason: '拖到最顶层应生效，不能被 newIndex<=1 拦截');
    });
  });
}
