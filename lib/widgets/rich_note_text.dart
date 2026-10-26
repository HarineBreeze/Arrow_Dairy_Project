import 'package:flutter/material.dart';
import '../utils/rich_text.dart';
import '../utils/text_format.dart';

/// 只读富文本：正文中 `@物品` 蓝色且可点击（回调物品名），`#话题` 蓝色不可交互。
/// 同时支持用户自定义排版（加粗/斜体/下划线/删除线/高亮/字号/居中）。
/// 点击命中通过 TextPainter 定位，不依赖 TapGestureRecognizer，Web/Android 均可靠。
class RichNoteText extends StatefulWidget {
  final String text;
  final Set<String> itemNames;
  final List<TextFormat> formats;
  final void Function(String itemName)? onTapMention;
  final TextStyle style;

  const RichNoteText({
    Key? key,
    required this.text,
    required this.itemNames,
    this.formats = const [],
    this.onTapMention,
    required this.style,
  }) : super(key: key);

  @override
  State<RichNoteText> createState() => _RichNoteTextState();
}

class _RichNoteTextState extends State<RichNoteText> {
  List<RichSegment> _segments = const [];

  void _handleTapUp(TapUpDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final span = _buildSpan();
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: box.size.width);
    final pos = painter.getPositionForOffset(details.localPosition);

    int offset = 0;
    for (int i = 0; i < _segments.length; i++) {
      final s = _segments[i];
      final end = offset + s.text.length;
      final isLast = i == _segments.length - 1;
      final hit =
          pos.offset >= offset && (pos.offset < end || (isLast && pos.offset <= end));
      if (hit) {
        if (s.type == 'mention') {
          widget.onTapMention?.call(s.value);
        }
        return;
      }
      offset = end;
    }
  }

  TextStyle? _styleAt(int pos) {
    TextStyle? st;
    for (final f in widget.formats) {
      if (pos < f.start || pos >= f.end) continue;
      final decos = <TextDecoration>[];
      if (f.underline == true) decos.add(TextDecoration.underline);
      if (f.strike == true) decos.add(TextDecoration.lineThrough);
      st = (st ?? const TextStyle()).copyWith(
        fontWeight: f.bold == true ? FontWeight.w700 : null,
        fontStyle: f.italic == true ? FontStyle.italic : null,
        decoration: decos.isEmpty
            ? null
            : (decos.length == 1 ? decos.first : TextDecoration.combine(decos)),
        backgroundColor:
            f.highlight != null ? _parseColor(f.highlight!) : null,
        fontSize: f.size,
      );
    }
    return st;
  }

  static Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFFFE58A);
  }

  /// 段落是否整体居中（覆盖该行的格式为 center）。
  bool _isParagraphCentered(int start, int end) {
    for (final f in widget.formats) {
      if (f.center != true) continue;
      if (f.start <= start && f.end >= end) return true;
    }
    return false;
  }

  TextSpan _buildSpan() {
    final children = <TextSpan>[];
    int cursor = 0;
    for (final s in _segments) {
      final segStart = cursor;
      cursor += s.text.length;
      if (s.type == 'mention' || s.type == 'topic') {
        final base = _styleAt(segStart) ?? const TextStyle();
        children.add(TextSpan(
          text: s.text,
          style: base.copyWith(color: const Color(0xFF3B6FE0)),
        ));
        continue;
      }
      // 按样式切分普通文本
      int i = 0;
      while (i < s.text.length) {
        final st = _styleAt(segStart + i);
        int j = i + 1;
        while (j < s.text.length && _sameStyle(st, _styleAt(segStart + j))) {
          j++;
        }
        children.add(TextSpan(text: s.text.substring(i, j), style: st));
        i = j;
      }
    }
    return TextSpan(style: widget.style, children: children);
  }

  bool _sameStyle(TextStyle? a, TextStyle? b) =>
      a?.fontWeight == b?.fontWeight &&
      a?.fontStyle == b?.fontStyle &&
      a?.decoration == b?.decoration &&
      a?.backgroundColor == b?.backgroundColor &&
      a?.fontSize == b?.fontSize;

  /// 判断某一行是否居中（该行的字符区间被 center 格式覆盖）。
  bool _lineCentered(int start, int end) {
    if (end <= start) return false;
    for (final f in widget.formats) {
      if (f.center != true) continue;
      if (f.start <= start && f.end >= end) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    _segments = RichTextParser.parse(text, widget.itemNames);

    // 按 '\n' 切行，逐行渲染并决定对齐方式
    final spans = _buildSpan().children ?? const <InlineSpan>[];

    // 为每行收集对应的 InlineSpan 片段
    final lines = <List<InlineSpan>>[];
    var currentLine = <InlineSpan>[];
    var globalPos = 0;

    for (final span in spans) {
      if (span is! TextSpan) continue;
      final t = span.text ?? '';
      var remaining = t;
      while (remaining.isNotEmpty) {
        final nl = remaining.indexOf('\n');
        if (nl < 0) {
          currentLine.add(TextSpan(text: remaining, style: span.style));
          globalPos += remaining.length;
          remaining = '';
        } else {
          final head = remaining.substring(0, nl);
          if (head.isNotEmpty) {
            currentLine.add(TextSpan(text: head, style: span.style));
          }
          globalPos += head.length + 1;
          lines.add(currentLine);
          currentLine = <InlineSpan>[];
          remaining = remaining.substring(nl + 1);
        }
      }
    }
    lines.add(currentLine);

    // 计算每行的起始偏移，用于判断是否居中
    final widgets = <Widget>[];
    var lineStart = 0;
    for (final line in lines) {
      var lineLen = 0;
      for (final sp in line) {
        if (sp is TextSpan) lineLen += (sp.text ?? '').length;
      }
      final lineEnd = lineStart + lineLen;
      final centered = _lineCentered(lineStart, lineEnd);
      widgets.add(
        Text.rich(
          TextSpan(style: widget.style, children: line),
          textAlign: centered ? TextAlign.center : TextAlign.start,
        ),
      );
      lineStart = lineEnd + 1; // +1 为换行符
    }

    return GestureDetector(
      onTapUp: _handleTapUp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
      ),
    );
  }
}
