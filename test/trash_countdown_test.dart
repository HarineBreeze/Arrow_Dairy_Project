import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:diary_app/models/asset.dart';
import 'package:diary_app/services/trash_storage.dart';

/// 把getApplicationDocumentsDirectory指到临时目录，便于真实读写 trash.json
class _TmpPathPlatform extends PathProviderPlatform {
  final String path;
  _TmpPathPlatform(this.path);
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('trash_test');
    PathProviderPlatform.instance = _TmpPathPlatform(tmp.path);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('回收站 7 天倒计时', () {
    test('刚删除的记录显示 7 天后到期', () async {
      await TrashStorage.addAsset(Asset(
        id: 'a1',
        type: '信用卡',
        amount: -2000,
        note: '日常支出',
      ));
      final list = await TrashStorage.load();
      expect(list, hasLength(1));
      expect(list.first.daysLeft, 7);
    });

    test('删除满一天后剩余天数递减（实时进度）', () async {
      await TrashStorage.addAsset(Asset(
        id: 'a2',
        type: '信用卡',
        amount: -2000,
        note: '旧卡',
      ));
      // 手工把 deletedAt 拨回 25 小时前
      final file = File('${tmp.path}/trash.json');
      final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
      final m = Map<String, dynamic>.from(raw.first as Map);
      m['deletedAt'] =
          DateTime.now().subtract(const Duration(hours: 25)).toIso8601String();
      await file.writeAsString(jsonEncode([m]));

      final list = await TrashStorage.load();
      expect(list.first.daysLeft, 6);
    });

    test('旧版本记录缺少 deletedAt：用文件修改时间兜底并回写固化', () async {
      // 模拟旧版本写入的记录：没有 deletedAt 字段
      final file = File('${tmp.path}/trash.json');
      await file.writeAsString(jsonEncode([
        {
          'id': 'legacy_1',
          'kind': 'asset',
          'data': Asset(
            id: 'a3',
            type: '信用卡',
            amount: -2000,
            note: '旧格式记录',
          ).toJson(),
          'title': '旧格式记录',
          'subtitle': '信用卡 · 负债',
        }
      ]));
      // 把文件时间拨回 3 天前，验证兜底时间来源是文件本身
      final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
      await file.setLastModified(threeDaysAgo);

      // 第一次 load：兜底 + 回写
      final list = await TrashStorage.load();
      expect(list, hasLength(1));
      expect(list.first.daysLeft, lessThan(7));
      expect(list.first.daysLeft, greaterThan(3));

      // 回写后 deletedAt 已固化：再次把文件时间改成现在，
      // 剩余天数不应被重置回 7（修复前每次启动都会重置）
      await file.setLastModified(DateTime.now());
      final again = await TrashStorage.load();
      expect(again.first.daysLeft, list.first.daysLeft);
      expect(again.first.daysLeft, lessThan(7));
    });

    test('过期项在 load 时被清理', () async {
      final file = File('${tmp.path}/trash.json');
      await file.writeAsString(jsonEncode([
        {
          'id': 'expired_1',
          'kind': 'asset',
          'data': Asset(id: 'a4', type: '信用卡', amount: -1, note: '过期卡')
              .toJson(),
          'deletedAt': DateTime.now()
              .subtract(const Duration(days: 8))
              .toIso8601String(),
          'title': '过期卡',
          'subtitle': '信用卡 · 负债',
        }
      ]));
      final list = await TrashStorage.load();
      expect(list, isEmpty);
      expect(await file.exists(), true);
      expect(jsonDecode(await file.readAsString()), isEmpty);
    });
  });
}
