import 'dart:io';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayodiray/widgets/app_icons.dart';
import 'package:ayodiray/widgets/lucide_icons.dart';

/// 把 Lucide 图标库全部渲染成一张 PNG 画廊（/tmp/lucide_gallery.png），
/// 供人工目检 path 是否解析正确（arc flag 归一化等的回归检查）。
Future<void> main() async {
  test('渲染 Lucide 图标画廊', () async {
    final names = Lucide.paths.keys.toList()..sort();
    const cell = 56.0;
    const cols = 8;
    final rows = (names.length / cols).ceil();
    final w = cols * cell;
    final h = rows * cell;

    Directory('/tmp/lucide_cells').createSync(recursive: true);
    for (var i = 0; i < names.length; i++) {
      final name = names[i];
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec, ui.Offset.zero & const ui.Size(48, 48));
      c.scale(48 / 24 - 0.8);
      c.drawPath(
        parseIconPath(Lucide.paths[name]!),
        ui.Paint()
          ..color = const Color(0xFF24382F)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = ui.StrokeCap.round
          ..strokeJoin = ui.StrokeJoin.round
          ..isAntiAlias = true,
      );
      final img = await rec.endRecording().toImage(48, 48);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('/tmp/lucide_cells/$name.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    }
    // ignore: avoid_print
    print('gallery saved: ${names.length} icons, ${w.round()}x${h.round()}');
  });
}
