import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/models/countdown_event.dart';

/// 复刻编辑页切换类型时的图标判定（与 countdown_edit_screen.dart 内逻辑一致）
String switchType({
  required String prevType,
  required String nextType,
  required String currentIcon,
  required bool touched,
}) {
  final cur = currentIcon.trim();
  final oldDefault = CountdownEvent.defaultIconFor(prevType);
  final newDefault = CountdownEvent.defaultIconFor(nextType);
  final followType =
      !touched || cur.isEmpty || cur == oldDefault || cur == newDefault;
  return followType ? newDefault : cur;
}

void main() {
  test('资产日 → 纪念日：未手动改过图标 → 变 🎂', () {
    expect(
      switchType(
          prevType: '资产日',
          nextType: '纪念日',
          currentIcon: '💰',
          touched: false),
      '🎂',
    );
  });

  test('纪念日 → 资产日：未手动改过图标 → 变 💰', () {
    expect(
      switchType(
          prevType: '纪念日',
          nextType: '资产日',
          currentIcon: '🎂',
          touched: false),
      '💰',
    );
  });

  test('来回切换保持跟随类型', () {
    var icon = '💰';
    var type = '资产日';
    for (final next in ['纪念日', '资产日', '纪念日']) {
      icon = switchType(
          prevType: type, nextType: next, currentIcon: icon, touched: false);
      type = next;
      expect(icon, CountdownEvent.defaultIconFor(next));
    }
  });

  test('用户手动选过图标 → 切换类型保留自定义图标', () {
    expect(
      switchType(
          prevType: '资产日',
          nextType: '纪念日',
          currentIcon: '🏠',
          touched: true),
      '🏠',
    );
  });

  test('图标为空 → 跟随类型默认', () {
    expect(
      switchType(
          prevType: '纪念日',
          nextType: '资产日',
          currentIcon: '',
          touched: true),
      '💰',
    );
  });

  test('fromJson：空图标按类型回落', () {
    final e = CountdownEvent.fromJson({
      'id': '1',
      'icon': '',
      'name': 'x',
      'target': '2026-01-01T00:00:00.000',
      'type': '资产日',
    });
    expect(e.icon, '💰');
  });

  test('clone 隔离：改副本不影响原件', () {
    final a = CountdownEvent(
      id: '1',
      icon: '💰',
      name: 'x',
      target: DateTime(2026, 1, 1),
      type: '资产日',
    );
    final b = a.clone()..icon = '🎂';
    expect(a.icon, '💰');
    expect(b.icon, '🎂');
  });
}
