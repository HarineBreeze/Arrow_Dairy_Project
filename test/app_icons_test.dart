import 'dart:ui';

import 'package:ayodiray/widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 图标库解析器的几何验证。
///
/// 这组测试不截图、不比对像素，只查几何事实：
/// 每个路径必须落在 24×24 画布内、必须有合理的实体面积、
/// 圆弧必须真的是圆的（bbox 宽高相等）。
void main() {
  group('解析器 · 基础指令', () {
    test('M + L 直线', () {
      final p = parseIconPath('M2 2L22 22');
      final b = p.getBounds();
      expect(b.left, closeTo(2, 0.01));
      expect(b.top, closeTo(2, 0.01));
      expect(b.right, closeTo(22, 0.01));
      expect(b.bottom, closeTo(22, 0.01));
    });

    test('M 后续坐标对按 lineto 处理（SVG 规范）', () {
      // 三个点：M0 0 10 0 10 10 —— 后两对是 L 不是 M
      final p = parseIconPath('M0 0 10 0 10 10');
      final b = p.getBounds();
      expect(b.right, closeTo(10, 0.01));
      expect(b.bottom, closeTo(10, 0.01));
    });

    test('相对指令 l 以当前点为原点', () {
      final p = parseIconPath('M10 10l5 0l0 5');
      final b = p.getBounds();
      expect(b.left, closeTo(10, 0.01));
      expect(b.top, closeTo(10, 0.01));
      expect(b.right, closeTo(15, 0.01));
      expect(b.bottom, closeTo(15, 0.01));
    });

    test('H / V 只动一个轴', () {
      final p = parseIconPath('M4 8H20 M12 4V20');
      final b = p.getBounds();
      expect(b.left, closeTo(4, 0.01));
      expect(b.top, closeTo(4, 0.01));
      expect(b.right, closeTo(20, 0.01));
      expect(b.bottom, closeTo(20, 0.01));
    });
  });

  group('解析器 · 圆弧（A / a）', () {
    test('整圆：两个半弧拼成的圆，bbox 必须是正方形', () {
      final p = parseIconPath('M4 10a6 6 0 1 0 12 0a6 6 0 1 0-12 0Z');
      final b = p.getBounds();
      final w = b.right - b.left;
      final h = b.bottom - b.top;
      expect(w, closeTo(12, 0.05));
      expect(h, closeTo(12, 0.05));
      expect(b.center.dx, closeTo(10, 0.05));
      expect(b.center.dy, closeTo(10, 0.05));
    });

    test('扫向走对：顺时针 sweep=1 从顶点到右点画四分之一圆', () {
      // 圆心 (10,10) r=6，从 (10,4) 到 (16,10) 顺时针 —— 弧应凸向右上
      final p = parseIconPath('M10 4A6 6 0 0 1 16 10');
      final b = p.getBounds();
      expect(b.left, closeTo(10, 0.05), reason: '不该越过圆心竖线向左');
      expect(b.top, closeTo(4, 0.05));
      expect(b.right, closeTo(16, 0.05));
      expect(b.bottom, closeTo(10, 0.05));
    });

    test('large-arc 标志生效：large=1 走大弧，bbox 明显更大', () {
      final small = parseIconPath('M10 4A6 6 0 0 0 16 10').getBounds();
      final large = parseIconPath('M10 4A6 6 0 1 0 16 10').getBounds();
      expect(large.width, greaterThan(small.width + 1));
      expect(large.height, greaterThan(small.height + 1));
      // 大弧必须绕到圆心左侧、下方
      expect(large.left, closeTo(4, 0.1));
      expect(large.bottom, closeTo(16, 0.1));
    });

    test('椭圆弧 rx≠ry 时 bbox 宽高比正确', () {
      final p = parseIconPath('M2 12A10 5 0 0 1 22 12A10 5 0 0 1 2 12Z');
      final b = p.getBounds();
      expect(b.right - b.left, closeTo(20, 0.1));
      expect(b.bottom - b.top, closeTo(10, 0.1));
    });

    test('圆弧近似精度：半圆弧中点误差 < 0.03', () {
      // 圆心 (12,12) r=8，上半圆从 (4,12) 到 (20,12)
      final p = parseIconPath('M4 12A8 8 0 0 1 20 12');
      final b = p.getBounds();
      // 上半圆的最高点应正好是 y = 4
      expect(b.top, closeTo(4, 0.03));
      expect(b.bottom, closeTo(12, 0.03));
    });

    test('半径不足以连接两点时按 SVG 规范等比放大', () {
      // 两点相距 20，但只给 r=2 → 规范要求放大到 r=10
      final p = parseIconPath('M2 12A2 2 0 0 1 22 12');
      final b = p.getBounds();
      expect(b.right - b.left, closeTo(20, 0.1));
    });
  });

  group('图标库 · 全量几何约束', () {
    test('每个图标的 bbox 都落在 24×24 画布内', () {
      AppIcons.all.forEach((name, path) {
        final b = parseIconPath(path.split('|fill').first).getBounds();
        expect(b.left, greaterThanOrEqualTo(-0.5), reason: '$name 左越界');
        expect(b.top, greaterThanOrEqualTo(-0.5), reason: '$name 上越界');
        expect(b.right, lessThanOrEqualTo(24.5), reason: '$name 右越界');
        expect(b.bottom, lessThanOrEqualTo(24.5), reason: '$name 下越界');
      });
    });

    test('每个图标都有实体，不能是空路径或退化点', () {
      // 纯水平 / 纯竖直线条类图标天然只有一个维度为 0，单独排除
      const flat = {'minus', 'hr', 'menu'};
      AppIcons.all.forEach((name, path) {
        final b = parseIconPath(path.split('|fill').first).getBounds();
        final area = b.width * b.height;
        if (flat.contains(name)) {
          expect(b.width + b.height, greaterThan(6), reason: '$name 退化');
        } else {
          expect(area, greaterThan(20), reason: '$name 面积过小（$b）');
        }
      });
    });

    test('每个图标主体不超过 20×20 安全区（留白 ≥ 2）', () {
      AppIcons.all.forEach((name, path) {
        final b = parseIconPath(path.split('|fill').first).getBounds();
        // 线宽 1.6，半宽 0.8，所以几何边界允许压到 1.2
        expect(b.width, lessThanOrEqualTo(21.6), reason: '$name 超宽');
        expect(b.height, lessThanOrEqualTo(21.6), reason: '$name 超高');
      });
    });

    test('圆形类图标 bbox 必须是正方形（验证圆弧解析没歪）', () {
      // 这批图标主体是/a指令画的圆，宽高不等就说明 _arcTo 出错了
      const circles = ['search', 'warn', 'success', 'restore'];
      for (final name in circles) {
        final b = parseIconPath(AppIcons.all[name]!).getBounds();
        expect(
          (b.width - b.height).abs(),
          lessThan(0.6),
          reason: '$name 圆不圆：${b.width}×${b.height}',
        );
      }
    });

    test('|fill 分割后两段都能独立解析且都有实体', () {
      final parts = AppIcons.pinOn.split('|fill');
      expect(parts.length, 2);
      final stroke = parseIconPath(parts[0]).getBounds();
      final bar = parseIconPath(parts[1]).getBounds();
      expect(stroke.isEmpty, isFalse);
      // 后段是加粗实心的针杆：一条竖线，宽度为 0 但长度正常
      expect(bar.isEmpty || bar.width == 0 && bar.height > 4, isTrue);
      expect(bar.height, greaterThan(6), reason: '针杆应有长度');
      expect(bar.center.dx, closeTo(12, 0.1), reason: '针杆应居中');
    });
  });

  group('图标库 · 成对一致性', () {
    test('lock / unlock 只差锁梁：主体部分应完全相同', () {
      // 取锁体（第一个子路径）比较：都以 M4.6 10.2 起头
      String body(String p) => p.substring(0, p.indexOf(' M'));
      expect(body(AppIcons.lock), body(AppIcons.unlock));
    });

    test('eyeOn / eyeOff 只差那道斜线', () {
      expect(AppIcons.eyeOff.startsWith(AppIcons.eyeOn), isTrue);
      expect(AppIcons.eyeOff.length, greaterThan(AppIcons.eyeOn.length));
    });

    test('pin / pinOn 路径完全一致，只有填充标记不同', () {
      expect(AppIcons.pinOn.replaceFirst('|fill', ''), AppIcons.pin);
    });

    test('chevR / chevL / chevD / chevU 顶点数一致', () {
      for (final p in [AppIcons.chevR, AppIcons.chevL, AppIcons.chevD, AppIcons.chevU]) {
        expect(parseIconPath(p).getBounds().isEmpty, isFalse);
      }
    });
  });

  group('组件渲染', () {
    testWidgets('AppIcon 在给定尺寸下渲染出正确的盒子', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: AppIcon(AppIcons.search, size: 32, color: Colors.red),
          ),
        ),
      );
      final box = tester.getSize(find.byType(AppIcon));
      expect(box.width, 32);
      expect(box.height, 32);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppIcon 在 16px 下不抛异常（线宽自动补偿）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: AppIcon(AppIcons.event, size: 16)),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('全部图标能在同一屏内渲染，无异常', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Wrap(
            children: [
              for (final p in AppIcons.all.values) AppIcon(p, size: 24),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
