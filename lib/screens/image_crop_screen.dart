import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/haptics.dart';
import '../widgets/app_icons.dart';

/// 固定 4:3 比例（宽 / 高）
const double kCropRatio = 4 / 3;

/// 裁剪框最小宽（显示坐标）
const double kCropMinSize = 60;

/// 裁剪几何辅助（纯函数，供页面与单测共用）
/// 图片以 contain 方式放进可用区域后的显示尺寸
Size cropFitSize(Size constraint, int imgW, int imgH) {
  final double scale =
      math.min(constraint.width / imgW, constraint.height / imgH);
  return Size(imgW * scale, imgH * scale);
}

/// 显示区内初始裁剪框：最大 4:3 居中
Rect initialCropRect(Size disp) {
  double w, h;
  if (disp.width / disp.height > kCropRatio) {
    h = disp.height;
    w = h * kCropRatio;
  } else {
    w = disp.width;
    h = w / kCropRatio;
  }
  return Rect.fromCenter(
    center: Offset(disp.width / 2, disp.height / 2),
    width: w,
    height: h,
  );
}

/// 平移后把裁剪框夹回显示区
Rect clampCropRect(Rect r, Size disp) {
  final left = r.left.clamp(0.0, disp.width - r.width);
  final top = r.top.clamp(0.0, disp.height - r.height);
  return Rect.fromLTWH(left, top, r.width, r.height);
}

/// 角缩放：anchor 为固定对角，拖动点决定新尺寸，比例锁定 4:3。
/// index：0=左上 1=右上 2=左下 3=右下；dragPoint 为图片显示区坐标系内的点
Rect resizeCropRect(Rect rect, int index, Offset dragPoint, Size disp) {
  final anchor = Offset(
    index == 0 || index == 2 ? rect.right : rect.left,
    index == 0 || index == 1 ? rect.bottom : rect.top,
  );
  final dx = (dragPoint.dx - anchor.dx).abs();
  final dy = (dragPoint.dy - anchor.dy).abs();

  // 取宽高里换算后更大的那个方向为准，避免角先到边界时比例被压缩
  double w = dx >= dy * kCropRatio ? dx : dy * kCropRatio;
  // 可用范围：距显示区边缘 + 最小尺寸
  final maxW = (index == 0 || index == 2
          ? anchor.dx
          : disp.width - anchor.dx)
      .clamp(kCropMinSize, double.infinity);
  w = w.clamp(kCropMinSize, maxW);
  final h = w / kCropRatio;

  final left = index == 0 || index == 2 ? anchor.dx - w : anchor.dx;
  final top = index == 0 || index == 1 ? anchor.dy - h : anchor.dy;
  return Rect.fromLTWH(left, top, w, h);
}

/// 按原图像素裁剪并写 PNG 到 [dirPath]，返回新文件路径
Future<String> writeCroppedImage(
    ui.Image image, Rect srcRect, String dirPath) async {
  final outW = srcRect.width.round().clamp(1, image.width);
  final outH = srcRect.height.round().clamp(1, image.height);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(
    image,
    srcRect,
    Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    Paint(),
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(outW, outH);
  final data = await out.toByteData(format: ui.ImageByteFormat.png) as ByteData;
  final path = '$dirPath/note_${DateTime.now().millisecondsSinceEpoch}_crop.png';
  await File(path).writeAsBytes(data.buffer.asUint8List());
  return path;
}

/// 固定 4:3 比例的自由裁剪页。
///
/// 交互：
/// - 裁剪框可在图片显示区内拖动移动；
/// - 拖动四角手柄缩放，宽高比始终锁定 4:3；
/// - 「完成」后按显示坐标映射回原图像素，用 dart:ui 裁剪并导出 PNG。
///
/// 返回值：裁剪成功返回新文件路径（写入应用文档目录）；取消返回 null。
class ImageCropScreen extends StatefulWidget {
  final String imagePath;

  const ImageCropScreen({super.key, required this.imagePath});

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  static const double _handleSize = 28; // 角手柄点击/拖动热区

  ui.Image? _image;
  bool _failed = false;
  bool _saving = false;
  final GlobalKey _stackKey = GlobalKey(); // 图片显示区，用于手势坐标换算

  late Size _dispSize; // 图片显示尺寸
  Rect _rect = Rect.zero; // 裁剪框（图片显示坐标系内）

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final image = await decodeImageFromList(bytes);
      if (!mounted) return;
      setState(() => _image = image);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  /// 图片以 contain 方式放进可用区域后的显示尺寸
  Size _fitSize(Size constraint, int imgW, int imgH) {
    final double scale =
        math.min(constraint.width / imgW, constraint.height / imgH);
    return Size(imgW * scale, imgH * scale);
  }

  void _initRect(Size disp) {
    _rect = initialCropRect(disp);
  }

  void _clampRect() {
    _rect = clampCropRect(_rect, _dispSize);
  }

  void _onMove(DragUpdateDetails d) {
    setState(() {
      _rect = _rect.translate(d.delta.dx, d.delta.dy);
      _clampRect();
    });
  }

  /// 角缩放：anchor 为固定对角，拖动点决定新尺寸，比例锁定 4:3。
  /// index：0=左上 1=右上 2=左下 3=右下
  void _onResize(int index, DragUpdateDetails d) {
    final renderObj = _stackKey.currentContext?.findRenderObject();
    if (renderObj is! RenderBox) return;
    // 手柄热区很小，localPosition 是热区局部坐标；
    // 用 globalPosition 换算回图片显示区坐标
    final drag = renderObj.globalToLocal(d.globalPosition);
    setState(() {
      _rect = resizeCropRect(_rect, index, drag, _dispSize);
    });
  }

  Future<void> _save() async {
    if (_image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final img = _image!;
      final sx = img.width / _dispSize.width;
      final sy = img.height / _dispSize.height;
      final src = Rect.fromLTWH(
        _rect.left * sx,
        _rect.top * sy,
        _rect.width * sx,
        _rect.height * sy,
      );
      final dir = await getApplicationDocumentsDirectory();
      final path = await writeCroppedImage(img, src, dir.path);
      if (!mounted) return;
      Navigator.pop(context, path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      Haptics.medium();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('裁剪失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('自由裁剪',
            style: TextStyle(fontSize: 17, color: Colors.white)),
        centerTitle: true,
        actions: [
          if (!_failed)
            TextButton(
              onPressed: _image == null || _saving ? null : _save,
              child: Text(_saving ? '处理中…' : '完成',
                  style: const TextStyle(fontSize: 15, color: Color(0xFF7FC9A8))),
            ),
        ],
      ),
      body: _failed
          ? const Center(
              child: Text('图片加载失败',
                  style: TextStyle(fontSize: 15, color: Colors.white54)))
          : _image == null
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF7FC9A8)))
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(
                      builder: (ctx, box) {
                        final disp = cropFitSize(
                            box.biggest, _image!.width, _image!.height);
                        _dispSize = disp;
                        if (_rect.width == 0) _initRect(disp);
                        return Center(
                          child: SizedBox(
                            key: _stackKey,
                            width: disp.width,
                            height: disp.height,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(File(widget.imagePath),
                                    fit: BoxFit.fill),
                                _buildOverlay(),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
      bottomNavigationBar: _image == null || _failed
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const AppIcon(AppIcons.image,
                        size: 14, color: Colors.white38),
                    const SizedBox(width: 6),
                    const Text('拖动裁剪框调整区域，比例固定 4:3',
                        style: TextStyle(fontSize: 13, color: Colors.white38)),
                  ],
                ),
              ),
            ),
    );
  }

  /// 暗遮罩 + 裁剪框边线 + 三分线 + 四角手柄
  Widget _buildOverlay() {
    final r = _rect;
    return Stack(
      children: [
        // 框外四块暗遮罩
        Positioned(left: 0, top: 0, width: _dispSize.width, height: r.top, child: const ColoredBox(color: Color(0x88000000))),
        Positioned(left: 0, top: r.bottom, width: _dispSize.width, height: _dispSize.height - r.bottom, child: const ColoredBox(color: Color(0x88000000))),
        Positioned(left: 0, top: r.top, width: r.left, height: r.height, child: const ColoredBox(color: Color(0x88000000))),
        Positioned(left: r.right, top: r.top, width: _dispSize.width - r.right, height: r.height, child: const ColoredBox(color: Color(0x88000000))),
        // 框体拖动
        Positioned.fromRect(
          rect: r,
          child: GestureDetector(
            onPanUpdate: _onMove,
            child: CustomPaint(
              painter: _CropFramePainter(),
              size: Size(r.width, r.height),
            ),
          ),
        ),
        // 四角手柄（热区大于视觉圆点）
        _handle(0, r.topLeft, r),
        _handle(1, r.topRight, r),
        _handle(2, r.bottomLeft, r),
        _handle(3, r.bottomRight, r),
      ],
    );
  }

  Widget _handle(int index, Offset corner, Rect r) {
    final hs = _handleSize;
    return Positioned(
      left: corner.dx - hs / 2,
      top: corner.dy - hs / 2,
      width: hs,
      height: hs,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => _onResize(index, d),
        child: Center(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFF3E8E6D), width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

/// 裁剪框：白色边线 + 三分参考线
class _CropFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, line);
    final grid = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 0.8;
    // 三分线
    canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), grid);
    canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), grid);
    canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), grid);
    canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), grid);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
