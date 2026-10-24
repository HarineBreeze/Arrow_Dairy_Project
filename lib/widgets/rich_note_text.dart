import 'package:flutter/material.dart';
import '../utils/rich_text.dart';

/// 只读富文本：正文中 `@物品` 蓝色且可点击（回调物品名），`#话题` 蓝色不可交互。
/// 点击命中通过 TextPainter 定位，不依赖 TapGestureRecognizer，Web/Android 均可靠。
class RichNoteText extends StatefulWidget {
  final String text;
  final Set<String> itemNames;
  final void Function(String itemName)? onTapMention;
  final TextStyle style;

  const RichNoteText({
    Key? key,
    required this.text,
    required this.itemNames,
    this.onTapMention,
    required this.style,
  }) : super(key: key);

  @override
  State<RichNoteText> createState() => _RichNoteTextState();
}

class _RichNoteTextState extends State<RichNoteText> {
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
      final hit = pos.offset >= offset && (pos.offset < end || (isLast && pos.offset <= end));
      if (hit) {
        if (s.type == 'mention') {
          widget.onTapMention?.call(s.value);
        }
        return;
      }
      offset = end;
    }
  }

  List<RichSegment> _segments = const [];

  TextSpan _buildSpan() {
    return TextSpan(
      style: widget.style,
      children: _segments.map((s) {
        if (s.type == 'mention' || s.type == 'topic') {
          return TextSpan(
            text: s.text,
            style: const TextStyle(color: Color(0xFF3B6FE0)),
          );
        }
        return TextSpan(text: s.text);
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    _segments = RichTextParser.parse(widget.text, widget.itemNames);
    return GestureDetector(
      onTapUp: _handleTapUp,
      child: Text.rich(_buildSpan()),
    );
  }
}
