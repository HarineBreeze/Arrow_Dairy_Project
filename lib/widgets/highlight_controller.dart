import 'package:flutter/material.dart';
import '../utils/rich_text.dart';
import '../utils/text_format.dart';

/// 在输入框中实时将 `@物品` 与 `#话题` 渲染为蓝色的控制器，
/// 并支持用户自定义排版（加粗/斜体/下划线/删除线/高亮/字号/居中）。
class HighlightEditingController extends TextEditingController {
  /// 当前物资清单中的物品名集合，可随时更新。
  Set<String> itemNames;

  /// 富文本格式列表（对 [text] 的 [start, end) 区间生效）。
  List<TextFormat> formats;

  /// 基准字号，用于计算相对字号。
  double baseSize;

  HighlightEditingController({
    required this.itemNames,
    String? text,
    List<TextFormat>? formats,
    this.baseSize = 16,
  })  : formats = formats ?? [],
        super(text: text);

  /// 更新格式并触发重绘。
  void setFormats(List<TextFormat> list) {
    formats = list;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final segments = RichTextParser.parse(text, itemNames);
    final children = <TextSpan>[];
    int cursor = 0;

    TextSpan buildPlain(String raw, int start) {
      // 对普通文本按格式区间切分
      final result = <TextSpan>[];
      int i = 0;
      while (i < raw.length) {
        final globalPos = start + i;
        final st = _styleAt(globalPos);
        // 找到相同样式的连续区间
        int j = i + 1;
        while (j < raw.length && _sameStyle(st, _styleAt(start + j))) {
          j++;
        }
        result.add(TextSpan(text: raw.substring(i, j), style: st));
        i = j;
      }
      return TextSpan(children: result);
    }

    for (final s in segments) {
      final segStart = cursor;
      cursor += s.text.length;
      if (s.type == 'mention' || s.type == 'topic') {
        final base = _styleAt(segStart) ?? const TextStyle();
        children.add(TextSpan(
          text: s.text,
          style: base.copyWith(color: const Color(0xFF3B6FE0)),
        ));
      } else {
        children.add(buildPlain(s.text, segStart));
      }
    }

    return TextSpan(style: style, children: children);
  }

  bool _sameStyle(TextStyle? a, TextStyle? b) {
    return a?.fontWeight == b?.fontWeight &&
        a?.fontStyle == b?.fontStyle &&
        a?.decoration == b?.decoration &&
        a?.backgroundColor == b?.backgroundColor &&
        a?.fontSize == b?.fontSize;
  }

  TextStyle? _styleAt(int pos) {
    bool bold = false, italic = false, underline = false, strike = false;
    String? highlight;
    double? size;
    bool any = false;
    for (final f in formats) {
      if (pos < f.start || pos >= f.end) continue;
      any = true;
      if (f.bold == true) bold = true;
      if (f.italic == true) italic = true;
      if (f.underline == true) underline = true;
      if (f.strike == true) strike = true;
      if (f.highlight != null) highlight = f.highlight;
      if (f.size != null) size = f.size;
    }
    if (!any) return null;

    // 只写「非默认」的属性，避免覆盖父级样式
    final decos = <TextDecoration>[];
    if (underline) decos.add(TextDecoration.underline);
    if (strike) decos.add(TextDecoration.lineThrough);

    return TextStyle(
      fontWeight: bold ? FontWeight.w700 : null,
      fontStyle: italic ? FontStyle.italic : null,
      decoration: decos.isEmpty
          ? null
          : (decos.length == 1 ? decos.first : TextDecoration.combine(decos)),
      backgroundColor: highlight != null ? _parseColor(highlight) : null,
      fontSize: size,
    );
  }

  TextDecoration? _decoration(TextFormat f) {
    final list = <TextDecoration>[];
    if (f.underline == true) list.add(TextDecoration.underline);
    if (f.strike == true) list.add(TextDecoration.lineThrough);
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first;
    return TextDecoration.combine(list);
  }

  static Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFFFE58A);
  }
}
