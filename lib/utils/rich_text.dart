/// 富文本片段。type 取值：
/// - 'text'    普通文本
/// - 'mention' @物品（value = 物品名，不含 @）
/// - 'topic'   #话题（value = 话题词，不含 #）
class RichSegment {
  final String type;
  final String text;
  final String value;

  const RichSegment({
    required this.type,
    required this.text,
    this.value = '',
  });
}

/// 解析笔记正文中的特殊字段：`@物品名` 与 `#话题词`。
class RichTextParser {
  // 话题词终止标点（中英文常见标点）。
  static const String _punct =
      '，。！？、；：""''（）【】《》…—·,;:!?.()[]{}<>"\'…～~|/';

  static bool _isTopicChar(String c) {
    if (c == '#' || c == '@') return false;
    if (c.trim().isEmpty) return false;
    if (_punct.contains(c)) return false;
    return true;
  }

  /// 将 [text] 解析为片段列表。itemNames 用于识别 @ 后的物品名（最长优先匹配）。
  static List<RichSegment> parse(String text, Set<String> itemNames) {
    final segments = <RichSegment>[];
    if (text.isEmpty) return segments;

    final names = itemNames
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    int i = 0;
    final buf = StringBuffer();

    void flush() {
      if (buf.isNotEmpty) {
        segments.add(RichSegment(type: 'text', text: buf.toString()));
        buf.clear();
      }
    }

    while (i < text.length) {
      final c = text[i];
      if (c == '#') {
        int j = i + 1;
        while (j < text.length && _isTopicChar(text[j])) {
          j++;
        }
        if (j > i + 1) {
          flush();
          final raw = text.substring(i, j);
          segments.add(RichSegment(
            type: 'topic',
            text: raw,
            value: raw.substring(1),
          ));
          i = j;
          continue;
        }
        buf.write(c);
        i++;
      } else if (c == '@') {
        String? matched;
        for (final name in names) {
          if (text.startsWith(name, i + 1)) {
            matched = name;
            break;
          }
        }
        if (matched != null) {
          flush();
          segments.add(RichSegment(
            type: 'mention',
            text: '@$matched',
            value: matched,
          ));
          i += 1 + matched.length;
          continue;
        }
        buf.write(c);
        i++;
      } else {
        buf.write(c);
        i++;
      }
    }
    flush();
    return segments;
  }

  /// 提取文本中出现过的所有话题词（去重，保持出现顺序）。
  static List<String> extractTopics(String text) {
    final seen = <String>{};
    final result = <String>[];
    for (final s in parse(text, const <String>{})) {
      if (s.type == 'topic' && seen.add(s.value)) {
        result.add(s.value);
      }
    }
    return result;
  }
}
