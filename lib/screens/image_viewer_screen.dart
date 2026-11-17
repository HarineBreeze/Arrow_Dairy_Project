import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/app_icons.dart';

/// 图片全屏查看页。
///
/// 交互约定（与主流相册一致）：
/// - 双指捏合缩放（1×~4×），放大后单指拖动查看局部；
/// - 未放大时下拉 → 图片跟随手指下移、背景渐隐，松手超过阈值即关闭；
/// - 单击任意处关闭；
/// - 右上角常驻关闭按钮（放大状态下也能一键退出）。
///
/// 手势用 [Listener] 原始指针事件实现，而不是 GestureDetector：
/// [InteractiveViewer] 内部用 ScaleGestureRecognizer 参与手势竞技场，
/// 再叠一层垂直拖拽识别器容易互相抢手势（表现为「下拉没反应」或
/// 「放大后拖不动」）。Listener 不参与竞技场，两者可以共存。
class ImageViewerScreen extends StatefulWidget {
  final String path;

  /// 与来源页 Hero 一致的标签，用于共享元素过渡
  final String heroTag;

  const ImageViewerScreen({
    Key? key,
    required this.path,
    required this.heroTag,
  }) : super(key: key);

  /// 带淡入淡出的透明路由：底层页面保持可见，关闭时原位飞回
  static Route<void> route({
    required String path,
    required String heroTag,
  }) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: const Color(0xFF000000),
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) =>
          ImageViewerScreen(path: path, heroTag: heroTag),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final TransformationController _tc = TransformationController();

  /// 下拉位移（仅在未放大时生效）
  double _dragY = 0;
  int _pointers = 0;
  double _downY = 0;
  DateTime _downAt = DateTime.now();
  bool _dragging = false;
  bool _moved = false;

  /// 关闭阈值：下移超过该距离松手即退出
  static const double _dismissAt = 110;

  bool get _zoomed => _tc.value.getMaxScaleOnAxis() > 1.01;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _onDown(PointerDownEvent e) {
    _pointers++;
    if (_pointers == 1) {
      _downY = e.position.dy;
      _downAt = DateTime.now();
      _dragging = false;
      _moved = false;
    } else {
      // 第二根手指落下：进入缩放，取消下拉
      _dragging = false;
      if (_dragY != 0) setState(() => _dragY = 0);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (_pointers != 1 || _zoomed) return;
    final dy = e.position.dy - _downY;
    if (dy.abs() > 6) _moved = true;
    if (dy <= 0) {
      if (_dragging) setState(() => _dragY = 0);
      _dragging = false;
      return;
    }
    if (!_dragging && dy < 8) return;
    _dragging = true;
    setState(() => _dragY = dy);
  }

  void _onUp(PointerUpEvent e) {
    _pointers = math.max(0, _pointers - 1);
    if (_dragging) {
      if (_dragY > _dismissAt) {
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _dragY = 0);
    }
    _dragging = false;
    // 单击（未拖动、未缩放）→ 关闭
    if (!_moved && !_zoomed && _pointers == 0) {
      final ms = DateTime.now().difference(_downAt).inMilliseconds;
      if (ms < 320) Navigator.of(context).maybePop();
    }
  }

  void _onCancel(PointerCancelEvent e) {
    _pointers = math.max(0, _pointers - 1);
    _dragging = false;
    if (_dragY != 0) setState(() => _dragY = 0);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragY / 320).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(1 - 0.55 * progress),
      body: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              // opaque：整屏都能收到底层指针事件（图片本身可能只占中间）
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              onPointerCancel: _onCancel,
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, _dragY),
                  child: Hero(
                    tag: widget.heroTag,
                    child: InteractiveViewer(
                      transformationController: _tc,
                      minScale: 1,
                      maxScale: 4,
                      child: Image.file(
                        File(widget.path),
                        fit: BoxFit.contain,
                        // 全屏查看用原图分辨率，不额外降采样
                        errorBuilder: (_, __, ___) => Padding(
                          padding: const EdgeInsets.all(32),
                          child: AppIcon(
                            AppIcons.image,
                            size: 64,
                            color: const Color(0xFF8FA09A),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 常驻关闭按钮：放大后下拉被禁用，仍可一键退出
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: IconButton(
                  key: const ValueKey('image_viewer_close'),
                  tooltip: '关闭',
                  icon: const AppIcon(AppIcons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
