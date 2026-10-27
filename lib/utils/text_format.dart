import 'dart:convert';

/// 文本样式片段。作用于正文 [start, end) 区间。
/// 所有字段可空，null 表示「不在该片段内控制此项」。
class TextFormat {
  final int start;
  final int end;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? strike;
  final String? highlight; // 高亮色值，如 '#FFE58A'
  final double? size; // 字号（相对基准的绝对值，如 16/18/22/28）

  const TextFormat({
    required this.start,
    required this.end,
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.highlight,
    this.size,
  });

  Map<String, dynamic> toJson() => {
        's': start,
        'e': end,
        if (bold != null) 'b': bold,
        if (italic != null) 'i': italic,
        if (underline != null) 'u': underline,
        if (strike != null) 'k': strike,
        if (highlight != null) 'h': highlight,
        if (size != null) 'z': size,
      };

  factory TextFormat.fromJson(Map<String, dynamic> j) => TextFormat(
        start: (j['s'] as num?)?.toInt() ?? 0,
        end: (j['e'] as num?)?.toInt() ?? 0,
        bold: j['b'] as bool?,
        italic: j['i'] as bool?,
        underline: j['u'] as bool?,
        strike: j['k'] as bool?,
        highlight: j['h'] as String?,
        size: (j['z'] as num?)?.toDouble(),
      );

  /// 把另一个片段的样式叠加到本片段（后者优先）。
  TextFormat merge(TextFormat o) => TextFormat(
        start: o.start,
        end: o.end,
        bold: o.bold ?? bold,
        italic: o.italic ?? italic,
        underline: o.underline ?? underline,
        strike: o.strike ?? strike,
        highlight: o.highlight ?? highlight,
        size: o.size ?? size,
      );

  TextFormat copyWith({
    int? start,
    int? end,
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    String? highlight,
    double? size,
  }) =>
      TextFormat(
        start: start ?? this.start,
        end: end ?? this.end,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        underline: underline ?? this.underline,
        strike: strike ?? this.strike,
        highlight: highlight ?? this.highlight,
        size: size ?? this.size,
      );
}

/// 格式列表的序列化 / 合并 / 查询工具。
class FormatStore {
  static String encode(List<TextFormat> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());

  static List<TextFormat> decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((e) => TextFormat.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.end > e.start)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 在 [start, end) 区间应用样式。
  /// - patch 中为 null 的字段：表示「不修改该属性」
  /// - clearHighlight / clearSize：为 true 时强制清除该项（用于点「清除」）
  static List<TextFormat> apply(
    List<TextFormat> source,
    int start,
    int end,
    TextFormat patch, {
    bool clearHighlight = false,
    bool clearSize = false,
  }) {
    if (end <= start) return source;
    final result = <TextFormat>[];
    for (final f in source) {
      if (f.end <= start || f.start >= end) {
        result.add(f);
        continue;
      }
      // 相交：切掉交集部分，两侧保留
      if (f.start < start) {
        result.add(f.copyWith(end: start));
      }
      if (f.end > end) {
        result.add(f.copyWith(start: end));
      }
    }

    result.add(TextFormat(
      start: start,
      end: end,
      bold: patch.bold,
      italic: patch.italic,
      underline: patch.underline,
      strike: patch.strike,
      highlight: clearHighlight ? null : patch.highlight,
      size: clearSize ? null : patch.size,
    ));

    result.removeWhere((f) => f.end <= f.start);
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  /// 从区间内现有格式合并出一个「当前状态」。
  static TextFormat stateAt(
      List<TextFormat> source, int start, int end) {
    TextFormat cur = TextFormat(start: start, end: end);
    for (final f in source) {
      if (f.end <= start || f.start >= end) continue;
      cur = cur.merge(f);
    }
    return cur;
  }

  static dynamic _get(TextFormat f, String key) {
    switch (key) {
      case 'bold':
        return f.bold;
      case 'italic':
        return f.italic;
      case 'underline':
        return f.underline;
      case 'strike':
        return f.strike;
      case 'highlight':
        return f.highlight;
      case 'size':
        return f.size;
    }
    return null;
  }

  static TextFormat _set(TextFormat f, String? key, dynamic v) {
    switch (key) {
      case 'bold':
        return f.copyWith(bold: v as bool? ?? false);
      case 'italic':
        return f.copyWith(italic: v as bool? ?? false);
      case 'underline':
        return f.copyWith(underline: v as bool? ?? false);
      case 'strike':
        return f.copyWith(strike: v as bool? ?? false);
      case 'highlight':
        return TextFormat(
          start: f.start,
          end: f.end,
          bold: f.bold,
          italic: f.italic,
          underline: f.underline,
          strike: f.strike,
          highlight: v as String?,
          size: f.size,
        );
      case 'size':
        return TextFormat(
          start: f.start,
          end: f.end,
          bold: f.bold,
          italic: f.italic,
          underline: f.underline,
          strike: f.strike,
          highlight: f.highlight,
          size: v as double?,
        );
    }
    return f;
  }

  /// 文本变化后同步调整格式位置（基于新旧文本 diff，支持任意位置的插入/删除）。
  static List<TextFormat> adjustToText(
      List<TextFormat> source, String oldText, String newText) {
    if (oldText == newText) return source;
    // 公共前缀
    int p = 0;
    final minLen =
        oldText.length < newText.length ? oldText.length : newText.length;
    while (p < minLen && oldText.codeUnitAt(p) == newText.codeUnitAt(p)) {
      p++;
    }
    // 公共后缀
    int sOld = oldText.length, sNew = newText.length;
    while (sOld > p && sNew > p &&
        oldText.codeUnitAt(sOld - 1) == newText.codeUnitAt(sNew - 1)) {
      sOld--;
      sNew--;
    }
    // 旧文本 [p, sOld) 被删除，新文本在 p 处插入 [p, sNew)
    return adjustRange(source, p, sOld - p, sNew - p);
  }

  /// 在位置 [pos] 处删除 [deleted] 个字符、插入 [inserted] 个字符后，
  /// 平移/延伸/截断各格式区间。
  static List<TextFormat> adjustRange(
      List<TextFormat> source, int pos, int deleted, int inserted) {
    if (deleted == 0 && inserted == 0) return source;
    final delta = inserted - deleted;
    final delEnd = pos + deleted;
    final out = <TextFormat>[];
    for (final f in source) {
      var s = f.start;
      var e = f.end;
      if (deleted > 0 && s >= delEnd) {
        // 完全在删除区之后 → 整体平移
        s += delta;
        e += delta;
      } else if (deleted == 0 && s > pos) {
        // 插入点之前之后（不含插入点）→ 平移
        s += delta;
        e += delta;
      } else if (e <= pos && !(deleted == 0 && e == pos && s < pos)) {
        // 完全在变更点之前 → 不变（纯插入恰好结束于插入点的区间除外）
      } else if (deleted > 0 && e <= delEnd) {
        // 被删除区完全覆盖 → 丢弃
        continue;
      } else {
        // 与变更区相交 → 收缩边界
        if (s >= pos && s < delEnd) s = pos;
        if (e > delEnd) {
          e += delta;
        } else if (deleted > 0 && e > pos) {
          e = pos;
        } else if (deleted == 0 && e == pos && s < pos) {
          e += delta; // 纯插入恰好落在区间末尾 → 延伸（继续打字继承格式）
        }
      }
      if (e > s) out.add(f.copyWith(start: s, end: e));
    }
    return out;
  }

  /// 判断某位置是否有指定格式（用于工具栏高亮状态）。
  static bool hasAt(List<TextFormat> list, int pos, String key, dynamic value) {
    for (final f in list) {
      if (pos < f.start || pos >= f.end) continue;
      if (_get(f, key) == value) return true;
    }
    return false;
  }
}
