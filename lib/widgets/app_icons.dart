import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 全站图标库 · 细线方案（Fine）
///
/// ## 设计规范（后续新增图标必须遵守）
/// - 画布 **24×24**，主体落在 **20×20 安全区**，四周恒定 2px 留白
/// - 线宽 **1.6**，端点 **圆头**，转角 **圆角**（strokeLineJoin.round）
/// - 只用一种笔画：等粗线条 + 圆头端点；不做粗细变化、不加尖角
/// - 每个图标最多 **3 个部件**（一个主体 + 至多两个附属）
/// - 只允许 **0° / 45° / 90°** 三种走向，斜线固定 45°
/// - 部件间隙 ≥ 2px，闭合形状内轮廓离边 ≥ 2px
/// - 开关类必须成对：置顶/取消、显示/隐藏、加密/解锁、展开/收起，
///   **只允许一处不同**，其余完全一致
///
/// ## 路径写法约定
/// - 标准 SVG path 语法，支持 `M L H V C S Q T A Z` 及对应小写相对形式
/// - `|` 把一条路径切成两段：前半段按 1.6 描边；后半段按 2.6 描边，
///   用来表达「实心的一笔」（如 [pinOn] 已置顶的针杆）
/// - 同一图标里路径各段之间也可用 `Z M` 断开，各自独立描边
///
/// ## 用法
/// ```dart
/// AppIcon(AppIcons.search)                       // 默认 24px / 深墨色
/// AppIcon(AppIcons.trash, size: 22, color: Colors.white)
/// ```
/// 富文本工具栏等需要更粗笔画的场景，传 `strokeWidth: 2.0`。
class AppIcons {
  AppIcons._();

  // ---------------- 导航 ----------------
  static const String search =
      'M4 10.5a6.5 6.5 0 1 0 13 0 6.5 6.5 0 1 0-13 0Z M15.4 15.4L20.6 20.6';
  static const String diary =
      'M4.4 4.4h5.2A2.4 2.4 0 0 1 12 6.8a2.4 2.4 0 0 1 2.4-2.4h5.2v14.2h-5.2'
      'A2.4 2.4 0 0 0 12 21a2.4 2.4 0 0 0-2.4-2.4H4.4Z M12 6.8V21';
  static const String book = diary;
  static const String items =
      'M6.4 8.4h11.2l1.2 10.4a2.2 2.2 0 0 1-2.2 2.4H7.4a2.2 2.2 0 0 1-2.2-2.4Z'
      ' M9 8.4V7.2a3 3 0 0 1 6 0v1.2';
  static const String event =
      'M6.6 5.4h10.8a3 3 0 0 1 3 3v8.2a3 3 0 0 1-3 3H6.6a3 3 0 0 1-3-3V8.4'
      'a3 3 0 0 1 3-3Z M3.6 10.4h16.8 M8.2 3.2v3.4 M15.8 3.2v3.4';
  static const String asset =
      'M6.4 9h11.2a2.4 2.4 0 0 1 2.4 2.4v7.2a2.4 2.4 0 0 1-2.4 2.4H6.4'
      'A2.4 2.4 0 0 1 4 18.6v-7.2A2.4 2.4 0 0 1 6.4 9Z'
      ' M4 9l1.8-4.4h12.4L20 9 M9.4 13.2h5.2';
  static const String trash =
      'M4.2 7h15.6 M9.4 7V4.8h5.2V7'
      ' M6.5 7l.9 12.6a2 2 0 0 0 2 1.9h5.2a2 2 0 0 0 2-1.9L17.5 7';

  // ---------------- 加密 / 解密（成对，只差锁梁） ----------------
  static const String lock =
      'M4.6 10.2h14.8v7.2a2.6 2.6 0 0 1-2.6 2.6H7.2a2.6 2.6 0 0 1-2.6-2.6Z'
      ' M8.4 10.2V7.6a3.6 3.6 0 0 1 7.2 0v2.6';
  static const String unlock =
      'M4.6 10.2h14.8v7.2a2.6 2.6 0 0 1-2.6 2.6H7.2a2.6 2.6 0 0 1-2.6-2.6Z'
      ' M8.4 10.2V7.6a3.6 3.6 0 0 1 6.8-1.8';

  // ---------------- 通用操作 ----------------
  static const String menu = 'M4 7.2h16 M4 12h16 M4 16.8h16';
  static const String back = 'M20 12H4.4 M11 5.6L4.4 12l6.6 6.4';
  static const String close = 'M6 6l12 12 M18 6L6 18';
  static const String check = 'M4.8 12.6l4.6 4.6L19.2 6.8';
  static const String plus = 'M12 4.6v14.8 M4.6 12h14.8';
  static const String minus = 'M4.6 12h14.8';
  static const String chevR = 'M9.4 5.4L16 12l-6.6 6.6';
  static const String chevL = 'M14.6 5.4L8 12l6.6 6.6';
  static const String chevD = 'M5.4 9.4L12 16l6.6-6.6';
  static const String chevU = 'M5.4 14.6L12 8l6.6 6.6';
  static const String arrowUp = 'M12 19.4V4.6 M5.6 11L12 4.6l6.4 6.4';
  static const String arrowDn = 'M12 4.6v14.8 M5.6 13l6.4 6.4 6.4-6.4';

  /// 上下双向箭头：切换升降序
  static const String swapV =
      'M8 19.4V4.6 M4.8 8L8 4.6 11.2 8 M16 4.6v14.8 M12.8 16L16 19.4 19.2 16';

  // ---------------- 功能 ----------------
  static const String filter = 'M3.8 5.6h16.4l-6.3 7.6v6.2l-3.8 2.2v-8.4Z';
  static const String sort =
      'M7 19.4V4.6 M3.8 8L7 4.6 10.2 8 M17 4.6v14.8 M13.8 16l3.2 3.4 3.2-3.4';
  static const String settings =
      'M4 7.2h2.9 M11.1 7.2H20 M4 12h8.9 M17.1 12H20 M4 16.8h4.9 M13.1 16.8H20'
      ' M11 7.2a1.9 1.9 0 1 1-3.8 0 1.9 1.9 0 0 1 3.8 0Z'
      ' M17 12a1.9 1.9 0 1 1-3.8 0 1.9 1.9 0 0 1 3.8 0Z'
      ' M13 16.8a1.9 1.9 0 1 1-3.8 0 1.9 1.9 0 0 1 3.8 0Z';
  static const String eyeOn =
      'M2.8 12S6.4 6.4 12 6.4 21.2 12 21.2 12 17.6 17.6 12 17.6 2.8 12 2.8 12Z'
      ' M14.8 12a2.8 2.8 0 1 1-5.6 0 2.8 2.8 0 0 1 5.6 0Z';
  static const String eyeOff =
      'M2.8 12S6.4 6.4 12 6.4 21.2 12 21.2 12 17.6 17.6 12 17.6 2.8 12 2.8 12Z'
      ' M14.8 12a2.8 2.8 0 1 1-5.6 0 2.8 2.8 0 0 1 5.6 0Z M4.4 19.6L19.6 4.4';
  static const String pin = 'M9.4 3.6h5.2l-.7 5.2 3.2 3.2H6.9l3.2-3.2Z M12 12v8.4';
  /// 「已置顶」：与 [pin] 同一份路径，`|fill` 后的针杆画成加粗实心
  static const String pinOn =
      'M9.4 3.6h5.2l-.7 5.2 3.2 3.2H6.9l3.2-3.2Z|fill M12 12v8.4';
  static const String edit =
      'M16.4 3.6a2.2 2.2 0 0 1 3.1 3.1L8.4 17.8 4 19l1.2-4.4Z';
  static const String delete =
      'M4.2 7h15.6 M9.4 7V4.8h5.2V7'
      ' M6.5 7l.9 12.6a2 2 0 0 0 2 1.9h5.2a2 2 0 0 0 2-1.9L17.5 7';
  static const String restore = 'M19.4 12a7.6 7.6 0 1 1-2.9-5.9 M19.6 3.8v4.4h-4.4';
  static const String empty =
      'M4.4 8h9.2 M4.4 12h9.2 M4.4 16h6 M16.8 14.6l4.2 4.2 M21 14.6l-4.2 4.2';
  static const String tag =
      'M12 3.6l7.6 7.6a2 2 0 0 1 0 2.8l-5.6 5.6a2 2 0 0 1-2.8 0L3.6 12V3.6Z'
      ' M9.5 8.2a1.3 1.3 0 1 1-2.6 0 1.3 1.3 0 0 1 2.6 0Z';
  static const String todo =
      'M7.2 4.2h9.6a3 3 0 0 1 3 3v9.6a3 3 0 0 1-3 3H7.2a3 3 0 0 1-3-3V7.2'
      'a3 3 0 0 1 3-3Z M8.4 12.2l2.6 2.6 4.8-5.2';
  static const String camera =
      'M6.6 7.4h1.2a1.6 1.6 0 0 0 1.4-.9l.5-1.1h4.6l.5 1.1a1.6 1.6 0 0 0 1.4.9'
      'h1.2a2.6 2.6 0 0 1 2.6 2.6v8a2.6 2.6 0 0 1-2.6 2.6H6.6A2.6 2.6 0 0 1 4 17.6'
      'v-8a2.6 2.6 0 0 1 2.6-2.6Z M15.2 13.6a3.2 3.2 0 1 1-6.4 0 3.2 3.2 0 0 1 6.4 0Z';
  static const String download =
      'M12 3.8v11 M7.6 10.6L12 15l4.4-4.4 M4.6 19.6h14.8';
  static const String share = 'M12 15.2V3.8 M8 7.8l4-4 4 4 M5 13.6v6h14v-6';
  static const String warn =
      'M12 3.6a8.4 8.4 0 1 0 0 16.8 8.4 8.4 0 0 0 0-16.8Z M12 7.6v5.2 M12 15.8v.8';
  static const String success =
      'M12 3.6a8.4 8.4 0 1 0 0 16.8 8.4 8.4 0 0 0 0-16.8Z'
      ' M8.2 12.2l2.6 2.6 5-5.4';
  static const String currency = 'M7 5l5 6.6L17 5 M12 11.6v8.4 M8 13.6h8 M8 16.6h8';
  static const String hr = 'M3.6 12h16.8';

  // ---------------- 补齐批次（替换残余 Material 图标） ----------------

  /// 双左箭头：日历快捷跳转
  static const String dblChevL = 'M11.4 6L5.4 12l6 6 M18.6 6l-6 6 6 6';
  /// 双右箭头：日历快捷跳转
  static const String dblChevR = 'M12.6 6l6 6-6 6 M5.4 6l6 6-6 6';

  /// 单选圆点（成对）
  static const String radioOff = 'M12 4.8a7.2 7.2 0 1 0 0 14.4 7.2 7.2 0 0 0 0-14.4Z';
  static const String radioOn =
      'M12 4.8a7.2 7.2 0 1 0 0 14.4 7.2 7.2 0 0 0 0-14.4Z'
      ' M12 9.4a2.6 2.6 0 1 1 0 5.2 2.6 2.6 0 0 1 0-5.2Z';

  /// 字体选择（T 字形）
  static const String fontType =
      'M4.6 6.6V4.4h14.8v2.2 M12 4.4v15.2 M8.8 19.6h6.4';

  /// 振动
  static const String vibrate =
      'M9.6 4.8h4.8a1.8 1.8 0 0 1 1.8 1.8v10.8a1.8 1.8 0 0 1-1.8 1.8H9.6'
      'a1.8 1.8 0 0 1-1.8-1.8V6.6a1.8 1.8 0 0 1 1.8-1.8Z'
      ' M4.8 9.4v5.2 M19.2 9.4v5.2';

  /// 位置
  static const String mapPin =
      'M12 21.2s6.2-5.7 6.2-10.6a6.2 6.2 0 1 0-12.4 0C5.8 15.5 12 21.2 12 21.2Z'
      ' M12 7.4a2.9 2.9 0 1 0 0 5.8 2.9 2.9 0 0 0 0-5.8Z';

  /// 撤销 / 重做（成对，镜像）
  static const String undo =
      'M4.8 8.4h9.6a4.8 4.8 0 0 1 0 9.6H8 M4.8 8.4l4-4 M4.8 8.4l4 4';
  static const String redo =
      'M19.2 8.4H9.6a4.8 4.8 0 0 0 0 9.6h6.4 M19.2 8.4l-4-4 M19.2 8.4l-4 4';

  /// 更多（横排三点）
  static const String moreH = 'M6.4 12v.01 M12 12v.01 M17.6 12v.01';

  /// 无搜索结果（放大镜 + 圆内叉）
  static const String searchX =
      'M4 10.5a6.5 6.5 0 1 0 13 0 6.5 6.5 0 1 0-13 0Z M15.4 15.4L20.6 20.6'
      ' M8.3 8.3l4.4 4.4 M12.7 8.3l-4.4 4.4';

  /// 时钟
  static const String clock =
      'M12 3.8a8.2 8.2 0 1 0 0 16.4 8.2 8.2 0 0 0 0-16.4Z'
      ' M12 7.4V12l3.2 1.9';

  /// 收起键盘
  static const String keyboardHide =
      'M4.2 6.6h15.6a1.6 1.6 0 0 1 1.6 1.6v7.6a1.6 1.6 0 0 1-1.6 1.6H4.2'
      'a1.6 1.6 0 0 1-1.6-1.6V8.2a1.6 1.6 0 0 1 1.6-1.6Z'
      ' M6.4 10v.01 M9.6 10v.01 M12.8 10v.01 M16 10v.01 M8.6 14.6h6.8';

  // ---------------- 富文本工具栏（线宽 2.0，见 [AppIcon.strokeWidth]） ----------------
  static const String bold =
      'M7 4.6h6.2a4.2 4.2 0 0 1 0 8.4H7Z M7 13h7a4.4 4.4 0 0 1 0 8.8H7Z';
  static const String italic = 'M10.6 4.6h7 M6.4 19.4h7 M14.4 4.6l-4.8 14.8';
  static const String underline = 'M7 4.6v6.8a5 5 0 0 0 10 0V4.6 M5.6 20h12.8';
  static const String strike =
      'M4.4 12h15.2 M8 8.2a4 4 0 0 1 8 0 M16 15.8a4 4 0 0 1-8 0';
  static const String code = 'M9 7.4L3.8 12 9 16.6 M15 7.4L20.2 12 15 16.6';
  static const String quote =
      'M4.6 4.6h1.8v14.8H4.6Z M9.4 8h10 M9.4 12h10 M9.4 16h6';
  static const String alignLeft = 'M4 6.4h16 M4 10.4h10 M4 14.4h16 M4 18.4h10';
  static const String alignCenter = 'M4 6.4h16 M7 10.4h10 M4 14.4h16 M7 18.4h10';
  static const String alignRight = 'M4 6.4h16 M10 10.4h10 M4 14.4h16 M10 18.4h10';
  static const String listBullet =
      'M8.4 7h11.6 M8.4 12h11.6 M8.4 17h11.6 M5.5 7v.1 M5.5 12v.1 M5.5 17v.1';
  static const String listNumber =
      'M9 7h11 M9 12h11 M9 17h11 M4.4 5.4v3.4h3 M4.4 12.4v3.6h3 M4.4 19.4h3v2.4h-3';

  /// 全部图标的路径表（按名称索引），用于遍历 / 导出 / 覆盖率测试
  static const Map<String, String> all = {
    'search': search,
    'diary': diary,
    'items': items,
    'event': event,
    'asset': asset,
    'trash': trash,
    'lock': lock,
    'unlock': unlock,
    'menu': menu,
    'back': back,
    'close': close,
    'check': check,
    'plus': plus,
    'minus': minus,
    'chevR': chevR,
    'chevL': chevL,
    'chevD': chevD,
    'chevU': chevU,
    'arrowUp': arrowUp,
    'arrowDn': arrowDn,
    'swapV': swapV,
    'filter': filter,
    'sort': sort,
    'settings': settings,
    'eyeOn': eyeOn,
    'eyeOff': eyeOff,
    'pin': pin,
    'pinOn': pinOn,
    'edit': edit,
    'delete': delete,
    'restore': restore,
    'empty': empty,
    'tag': tag,
    'todo': todo,
    'camera': camera,
    'download': download,
    'share': share,
    'warn': warn,
    'success': success,
    'currency': currency,
    'hr': hr,
    'dblChevL': dblChevL,
    'dblChevR': dblChevR,
    'radioOff': radioOff,
    'radioOn': radioOn,
    'fontType': fontType,
    'vibrate': vibrate,
    'mapPin': mapPin,
    'undo': undo,
    'redo': redo,
    'moreH': moreH,
    'searchX': searchX,
    'clock': clock,
    'keyboardHide': keyboardHide,
    'bold': bold,
    'italic': italic,
    'underline': underline,
    'strike': strike,
    'code': code,
    'quote': quote,
    'alignLeft': alignLeft,
    'alignCenter': alignCenter,
    'alignRight': alignRight,
    'listBullet': listBullet,
    'listNumber': listNumber,
  };

  static String? pathOf(String name) => all[name];
}

/// 细线图标组件。
///
/// 任意尺寸按 24×24 网格等比缩放。线宽不跟着尺寸线性缩 ——
/// 16px 及以下自动补偿到 1.8px，否则细线在小尺寸下会发虚。
class AppIcon extends StatelessWidget {
  final String path;
  final double size;
  final Color color;

  /// 覆盖线宽（富文本工具栏等需要更粗笔画的场景传 2.0）
  final double? strokeWidth;

  const AppIcon(
    this.path, {
    Key? key,
    this.size = 24,
    this.color = const Color(0xFF273830),
    this.strokeWidth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final w = strokeWidth ?? (size <= 16 ? 1.8 : 1.6);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _IconPainter(path, color, w, size / 24),
        isComplex: false,
        willChange: false,
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  final String path;
  final Color color;
  final double strokeWidth;
  final double scale;

  _IconPainter(this.path, this.color, this.strokeWidth, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);
    _paintTo(canvas, path, color, strokeWidth);
    canvas.restore();
  }

  static void _paintTo(Canvas canvas, String raw, Color color, double w) {
    final fillIdx = raw.indexOf('|fill');
    final strokePart = fillIdx < 0 ? raw : raw.substring(0, fillIdx);
    canvas.drawPath(
      parseIconPath(strokePart),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
    if (fillIdx >= 0) {
      // 「填充段」在图标库里基本都是细长的一笔（图钉针杆、不可见基座等），
      // 用 fill 画会因为面积过小或未闭合而消失，改用「加粗描边」等效实现：
      // 线宽取 2.6，末端圆头，视觉上就是一根实心针。
      canvas.drawPath(
        parseIconPath(raw.substring(fillIdx + 5)),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true,
      );
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.path != path || old.color != color || old.strokeWidth != strokeWidth;
}

/// 极简 SVG path 解析器。
///
/// 支持本图标库用到的全部指令：M m L l H h V v C c S s Q q T t A a Z z。
/// 之所以自己解析而不引 flutter_svg：图标库只有几 KB，
/// 引一个完整 SVG 渲染库会让 APK 多出数百 KB，且我们不需要
/// 渐变、filter、文本等特性。
///
/// 遇到不支持的指令会抛异常而不是静默跳过 —— 静默跳过会
/// 把整段路径变成空路径，画面上只表现为「图标没显示」，很难查。
Path parseIconPath(String d) {
  final p = Path();
  final tk = _tokenize(d);
  var i = 0;
  var cmd = '';
  var cur = Offset.zero;
  var sub = Offset.zero; // 当前子路径起点（Z 回到这里）
  var lastC2 = Offset.zero; // 上一个三次曲线的第二控制点（供 S/s 镜像）
  var lastQ = Offset.zero; // 上一个二次曲线的控制点（供 T/t 镜像）
  String prevCmd = '';
  double nx() => double.parse(tk[i++].text);
  bool hasNum() => i < tk.length && tk[i].isNum;

  while (i < tk.length) {
    if (!tk[i].isNum) {
      cmd = tk[i++].text;
      if (cmd == 'Z' || cmd == 'z') {
        p.close();
        cur = sub;
        continue;
      }
    }
    if (!hasNum()) continue; // 指令后无参数，跳过
    final rel = cmd == cmd.toLowerCase();
    final up = cmd.toUpperCase();
    switch (up) {
      case 'M':
        // 第一对是 moveto，后续坐标对按 lineto 处理（SVG 规范）
        final mx = nx(), my = nx();
        cur = rel ? cur + Offset(mx, my) : Offset(mx, my);
        sub = cur;
        p.moveTo(cur.dx, cur.dy);
        cmd = rel ? 'l' : 'L';
        break;
      case 'L':
        final lx = nx(), ly = nx();
        cur = rel ? cur + Offset(lx, ly) : Offset(lx, ly);
        p.lineTo(cur.dx, cur.dy);
        break;
      case 'H':
        final x = nx();
        cur = Offset(rel ? cur.dx + x : x, cur.dy);
        p.lineTo(cur.dx, cur.dy);
        break;
      case 'V':
        final y = nx();
        cur = Offset(cur.dx, rel ? cur.dy + y : y);
        p.lineTo(cur.dx, cur.dy);
        break;
      case 'C':
        final c1x = nx(), c1y = nx();
        final c2x = nx(), c2y = nx();
        final ex = nx(), ey = nx();
        final a1 = rel ? cur + Offset(c1x, c1y) : Offset(c1x, c1y);
        final a2 = rel ? cur + Offset(c2x, c2y) : Offset(c2x, c2y);
        final a3 = rel ? cur + Offset(ex, ey) : Offset(ex, ey);
        p.cubicTo(a1.dx, a1.dy, a2.dx, a2.dy, a3.dx, a3.dy);
        lastC2 = a2;
        cur = a3;
        break;
      case 'S':
        // 第一控制点 = 上一个三次曲线第二控制点关于当前点的镜像
        final sc1 = (prevCmd == 'C' || prevCmd == 'S')
            ? Offset(cur.dx * 2 - lastC2.dx, cur.dy * 2 - lastC2.dy)
            : cur;
        final sc2x = nx(), sc2y = nx();
        final sex = nx(), sey = nx();
        final sc2 = rel ? cur + Offset(sc2x, sc2y) : Offset(sc2x, sc2y);
        final se = rel ? cur + Offset(sex, sey) : Offset(sex, sey);
        p.cubicTo(sc1.dx, sc1.dy, sc2.dx, sc2.dy, se.dx, se.dy);
        lastC2 = sc2;
        cur = se;
        break;
      case 'Q':
        final qcx = nx(), qcy = nx();
        final qex = nx(), qey = nx();
        final qc = rel ? cur + Offset(qcx, qcy) : Offset(qcx, qcy);
        final qe = rel ? cur + Offset(qex, qey) : Offset(qex, qey);
        p.quadraticBezierTo(qc.dx, qc.dy, qe.dx, qe.dy);
        lastQ = qc;
        cur = qe;
        break;
      case 'T':
        final tc = (prevCmd == 'Q' || prevCmd == 'T')
            ? Offset(cur.dx * 2 - lastQ.dx, cur.dy * 2 - lastQ.dy)
            : cur;
        final tex = nx(), tey = nx();
        final te = rel ? cur + Offset(tex, tey) : Offset(tex, tey);
        p.quadraticBezierTo(tc.dx, tc.dy, te.dx, te.dy);
        lastQ = tc;
        cur = te;
        break;
      case 'A':
        // 半径与前两个角度参数
        final arx = nx();
        final ary = nx();
        final arot = nx();
        // flags 只能取 0 或 1，且允许紧贴后续数字连写（a6 6 0 1 0-12 0）
        final alarge = _flag(tk[i++].text) != 0;
        final asweep = _flag(tk[i++].text) != 0;
        final aex = nx(), aey = nx();
        final aend = rel ? cur + Offset(aex, aey) : Offset(aex, aey);
        _arcTo(p, cur, arx, ary, arot, alarge, asweep, aend);
        cur = aend;
        break;
      case 'Z':
        p.close();
        cur = sub;
        break;
      default:
        throw FormatException(
          '图标路径含不支持的指令「$cmd」，请改用 M/L/H/V/C/S/Q/T/A/Z：\n$d',
        );
    }
    prevCmd = up;
  }
  return p;
}

/// `parseIconPath` 的辅助：只解析标志位，其余走 `double.parse`。
int _flag(String s) {
  if (s == '0' || s == '1') return s == '1' ? 1 : 0;
  final v = double.tryParse(s);
  return (v == null || v == 0) ? 0 : 1;
}

/// 椭圆弧转贝塞尔（SVG 1.1 附录 F.6.5 端点参数 → 中心参数）
void _arcTo(Path p, Offset from, double rx, double ry, double rot, bool large,
    bool sweep, Offset to) {
  if (rx == 0 || ry == 0) {
    p.lineTo(to.dx, to.dy);
    return;
  }
  rx = rx.abs();
  ry = ry.abs();
  final phi = rot * math.pi / 180;
  final cp = math.cos(phi), sp = math.sin(phi);
  final dx = (from.dx - to.dx) / 2, dy = (from.dy - to.dy) / 2;
  final x1 = cp * dx + sp * dy;
  final y1 = -sp * dx + cp * dy;
  var rx2 = rx * rx, ry2 = ry * ry;
  final lambda = x1 * x1 / rx2 + y1 * y1 / ry2;
  if (lambda > 1) {
    final s = math.sqrt(lambda);
    rx *= s;
    ry *= s;
    rx2 = rx * rx;
    ry2 = ry * ry;
  }
  var num = rx2 * ry2 - rx2 * y1 * y1 - ry2 * x1 * x1;
  if (num < 0) num = 0;
  final den = rx2 * y1 * y1 + ry2 * x1 * x1;
  final coef = (large == sweep ? -1 : 1) *
      math.sqrt(den == 0 ? 0 : num / den);
  final cx1 = coef * rx * y1 / ry;
  final cy1 = -coef * ry * x1 / rx;
  final cx = cp * cx1 - sp * cy1 + (from.dx + to.dx) / 2;
  final cy = sp * cx1 + cp * cy1 + (from.dy + to.dy) / 2;

  double angle(double ux, double uy, double vx, double vy) {
    final dot = ux * vx + uy * vy;
    final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
    var a = math.acos((dot / (len == 0 ? 1 : len)).clamp(-1.0, 1.0));
    if (ux * vy - uy * vx < 0) a = -a;
    return a;
  }

  final ux = (x1 - cx1) / rx, uy = (y1 - cy1) / ry;
  final vx = (-x1 - cx1) / rx, vy = (-y1 - cy1) / ry;
  final t1 = angle(1, 0, ux, uy);
  var dt = angle(ux, uy, vx, vy);
  if (!sweep && dt > 0) dt -= 2 * math.pi;
  if (sweep && dt < 0) dt += 2 * math.pi;

  final segs = math.max(1, (dt.abs() / (math.pi / 2)).ceil());
  final delta = dt / segs;
  final t = 4 / 3 * math.tan(delta / 4);

  // 在「未旋转的椭圆参数空间」把控制点算好，再统一旋转 + 平移到画布坐标。
  // 参数点：P(θ) = (rx·cosθ, ry·sinθ)；导数：P'(θ) = (-rx·sinθ, ry·cosθ)
  // 控制点：C1 = P(θ) + t·P'(θ)，C2 = P(θ+Δ) - t·P'(θ+Δ)
  Offset map(double x, double y) =>
      Offset(cx + cp * x - sp * y, cy + sp * x + cp * y);

  var theta = t1;
  for (var k = 0; k < segs; k++) {
    final t2 = theta + delta;
    final ct = math.cos(theta), st = math.sin(theta);
    final c2t = math.cos(t2), s2t = math.sin(t2);

    final p2 = map(rx * c2t, ry * s2t);
    final a1 = map(
      rx * ct - t * rx * st,
      ry * st + t * ry * ct,
    );
    final a2 = map(
      rx * c2t + t * rx * s2t,
      ry * s2t - t * ry * c2t,
    );
    p.cubicTo(a1.dx, a1.dy, a2.dx, a2.dy, p2.dx, p2.dy);
    theta = t2;
  }
}

class _Tok {
  final String text;
  final bool isNum;
  const _Tok(this.text, this.isNum);
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

/// SVG path 分词器。
///
/// 关键规则（比「按空格切」复杂得多，必须处理紧凑写法）：
/// - 指令字母：MmLlHhVvCcSsQqTtAaZz
/// - 数字可连写：`10-5` 是 `10` 和 `-5`；`1.5.5` 是 `1.5` 和 `.5`
/// - `-` / `+` 出现在数字中间时一定是新数字的开始
/// - `.` 只在当前数字尚未出现小数点时才算数字的一部分
/// - 弧指令的 flags（large-arc / sweep）是单字符 0/1，可紧贴后续数字：`a6 6 0 1 0-12 0`
///   这里的 `0-12` 要拆成 flag `0` 和数字 `-12`
List<_Tok> _tokenize(String d) {
  const cmds = 'MmLlHhVvCcSsQqTtAaZz';
  final out = <_Tok>[];
  final buf = StringBuffer();
  var seenDot = false;

  void flush() {
    if (buf.isNotEmpty) {
      out.add(_Tok(buf.toString(), true));
      buf.clear();
      seenDot = false;
    }
  }

  for (var i = 0; i < d.length; i++) {
    final c = d[i];
    if (c == ' ' || c == ',' || c == '\n' || c == '\t' || c == '\r') {
      flush();
      continue;
    }
    if (cmds.contains(c)) {
      flush();
      out.add(_Tok(c, false));
      continue;
    }
    if (c == '-') {
      // 负号：无论前后是什么，都是一个新数字的开头
      flush();
      buf.write('-');
      continue;
    }
    if (c == '+') {
      flush();
      continue;
    }
    if (c == '.') {
      if (seenDot) {
        flush(); // 形如 1.5.5 的第二个点，开启新数字
      }
      buf.write('.');
      seenDot = true;
      continue;
    }
    if (_isDigit(c)) {
      buf.write(c);
      continue;
    }
    // 未知字符：丢弃，避免死循环
  }
  flush();
  return out;
}
