import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';

import '../models/diary_entry.dart';
import '../models/item.dart';
import '../widgets/entry_image.dart';
import '../widgets/share_card.dart';

/// 笔记分享图合成：把浏览页内容渲染成长图 PNG 落盘。
///
/// 流程：预解码封面图 → 在根 Overlay 里离屏挂载 [ShareCard]
/// （位置移出屏幕外，不影响可见 UI）→ 第一遍测量内容自然高度
/// → 按「底部横条 = 整图 1/6」撑高后二次渲染 → RepaintBoundary
/// 截图 → 写入临时目录。失败返回 null，由调用方提示重试。
Future<File?> captureShareCard(
  BuildContext context,
  DiaryEntry entry,
  List<Item> items,
) async {
  final OverlayState? overlay = Overlay.of(context, rootOverlay: true);
  if (overlay == null) return null;

  // 封面图预解码：走 EntryImage 同一条 ResizeImage 路径，
  // 保证预解码结果被卡片内首次渲染直接命中，避免截图瞬间图片还没解出来
  if (entry.imagePath.isNotEmpty && File(entry.imagePath).existsSync()) {
    try {
      await precacheImage(
        EntryImage.provider(context, entry.imagePath, 335),
        context,
      );
    } catch (_) {
      // 图片读取失败时继续，卡片内 EntryImage 会自行为空占位
    }
  }

  final contentKey = GlobalKey();
  final boundaryKey = GlobalKey();
  double footerHeight = 0;
  double? contentHeight;

  late final OverlayEntry host;
  host = OverlayEntry(
    builder: (ctx) => Positioned(
      // 移出屏幕外：参与布局与绘制但不被用户看见
      left: -4000,
      top: 0,
      child: MediaQuery(
        // 分享图排版与系统字号设置解耦，长图永远按默认字号渲染
        data: MediaQuery.of(ctx).copyWith(textScaleFactor: 1.0),
        child: RepaintBoundary(
          key: boundaryKey,
          child: Material(
            color: Colors.white,
            child: ShareCard(
              entry: entry,
              items: items,
              footerHeight: footerHeight,
              contentHeight: contentHeight,
              contentKey: contentKey,
            ),
          ),
        ),
      ),
    ),
  );

  overlay.insert(host);
  try {
    // 1) 等内容区完成布局，拿到自然高度
    double natural = 0;
    for (var i = 0; i < 120; i++) {
      await WidgetsBinding.instance.endOfFrame;
      final ctx = contentKey.currentContext;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize && box.size.height > 0) {
          natural = box.size.height;
          break;
        }
      }
    }
    if (natural <= 0) return null;

    // 2) 按「横条 = 整图 1/6」撑高内容区、补出横条，等渲染稳定
    contentHeight = ShareCard.stretchedHeightFor(natural);
    footerHeight = ShareCard.footerHeightFor(natural);
    host.markNeedsBuild();
    for (var i = 0; i < 30; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!SchedulerBinding.instance.hasScheduledFrame) break;
    }

    // 3) 截图：整图越高像素比越保守，避免超出 GPU 纹理上限
    final totalLogical = contentHeight + footerHeight;
    final pixelRatio = totalLogical <= 2400
        ? 3.0
        : (totalLogical <= 3600 ? 2.0 : 1.5);
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    final bytes = byteData.buffer.asUint8List();

    // 4) 写入临时目录
    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final path =
        '${dir.path}/阿尤日记_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}.png';
    final file = File(path);
    await file.writeAsBytes(bytes);
    return file;
  } catch (_) {
    return null;
  } finally {
    host.remove();
  }
}
