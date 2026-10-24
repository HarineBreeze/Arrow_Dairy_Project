import 'package:flutter/material.dart';
import '../utils/rich_text.dart';

/// 在输入框中实时将 `@物品` 与 `#话题` 渲染为蓝色的控制器。
class HighlightEditingController extends TextEditingController {
  /// 当前物资清单中的物品名集合，可随时更新。
  Set<String> itemNames;

  HighlightEditingController({
    required this.itemNames,
    String? text,
  }) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final segments = RichTextParser.parse(text, itemNames);
    return TextSpan(
      style: style,
      children: segments.map((s) {
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
}
