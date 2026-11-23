import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../utils/haptics.dart';

/// 九宫格手势锁视图。
///
/// - 用户在 3×3 点阵上滑动连线，抬起手指时回调经过的点序号（0~8）。
/// - [readOnly] 为 true 时只用于回显某个 pattern（验证成功/设置确认的展示）。
/// - 点序号布局：
///   0 1 2
///   3 4 5
///   6 7 8
class PatternLockView extends StatefulWidget {
  final ValueChanged<List<int>>? onCompleted;
  final bool readOnly;
  final List<int>? displayPattern;
  final double size;

  const PatternLockView({
    Key? key,
    this.onCompleted,
    this.readOnly = false,
    this.displayPattern,
    this.size = 240,
  }) : super(key: key);

  @override
  State<PatternLockView> createState() => _PatternLockViewState();
}

class _PatternLockViewState extends State<PatternLockView> {
  List<int> _path = <int>[];
  Offset? _current;

  static const _radius = 22.0;

  @override
  void initState() {
    super.initState();
    if (widget.readOnly && widget.displayPattern != null) {
      _path = List<int>.from(widget.displayPattern!);
    }
  }

  @override
  void didUpdateWidget(covariant PatternLockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.readOnly && widget.displayPattern != null) {
      setState(() => _path = List<int>.from(widget.displayPattern!));
    }
  }

  /// 3×3 各点在 size×size 方框内的坐标
  Offset _pointAt(int index) {
    final cell = widget.size / 3;
    final col = index % 3;
    final row = index ~/ 3;
    return Offset(cell * (col + 0.5), cell * (row + 0.5));
  }

  int? _hitTest(Offset pos) {
    for (var i = 0; i < 9; i++) {
      if ((pos - _pointAt(i)).distance <= _radius) return i;
    }
    return null;
  }

  void _onStartAt(Offset pos) {
    if (widget.readOnly) return;
    final hit = _hitTest(pos);
    setState(() {
      _path = <int>[];
      _current = pos;
      if (hit != null) _path.add(hit);
    });
  }

  void _onStart(DragStartDetails d) {
    // 已在 onPanDown 里初始化；这里仅在极端情况下路径为空时补一次
    if (widget.readOnly) return;
    if (_path.isEmpty) _onStartAt(d.localPosition);
  }

  void _onUpdate(DragUpdateDetails d) {
    if (widget.readOnly) return;
    final hit = _hitTest(d.localPosition);
    setState(() {
      _current = d.localPosition;
      if (hit != null && !_path.contains(hit)) {
        _path.add(hit);
        Haptics.light();
      }
    });
  }

  void _onEnd(DragEndDetails d) {
    if (widget.readOnly) return;
    setState(() => _current = null);
    final completed = List<int>.from(_path);
    widget.onCompleted?.call(completed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanDown: (d) => _onStartAt(d.localPosition),
      onPanStart: _onStart,
      onPanUpdate: _onUpdate,
      onPanEnd: _onEnd,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _PatternPainter(
            path: _path,
            current: _current,
            pointAt: _pointAt,
            radius: _radius,
            accent: AppPalette.c(0xFF3E8E6D),
            idle: AppPalette.c(0xFFC2D4C9),
          ),
        ),
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  final List<int> path;
  final Offset? current;
  final Offset Function(int) pointAt;
  final double radius;
  final Color accent;
  final Color idle;

  _PatternPainter({
    required this.path,
    required this.current,
    required this.pointAt,
    required this.radius,
    required this.accent,
    required this.idle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = accent.withOpacity(0.85)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 已连线段
    for (var i = 1; i < path.length; i++) {
      canvas.drawLine(pointAt(path[i - 1]), pointAt(path[i]), linePaint);
    }
    // 当前跟随手指的线段
    if (path.isNotEmpty && current != null) {
      canvas.drawLine(pointAt(path.last), current!, linePaint);
    }

    // 九个圆点
    for (var i = 0; i < 9; i++) {
      final c = pointAt(i);
      final selected = path.contains(i);
      if (selected) {
        canvas.drawCircle(c, radius, Paint()..color = accent.withOpacity(0.18));
        canvas.drawCircle(c, radius * 0.42, Paint()..color = accent);
      } else {
        canvas.drawCircle(
            c, radius * 0.28, Paint()..color = idle.withOpacity(0.7));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) =>
      old.path != path || old.current != current;
}

/// 把点序列转成存储字符串
String patternToString(List<int> path) => path.join(',');

/// 手势至少连接 4 个点才算有效
bool isValidPattern(List<int> path) => path.length >= 4;
