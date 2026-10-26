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
  final bool? center; // 该段落居中（作用于所在行）

  const TextFormat({
    required this.start,
    required this.end,
    this.bold,
    this.italic,
    this.underline,
    this.strike,
    this.highlight,
    this.size,
    this.center,
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
        if (center != null) 'c': center,
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
        center: j['c'] as bool?,
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
        center: o.center ?? center,
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
    bool? center,
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
        center: center ?? this.center,
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
      center: patch.center,
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
      case 'center':
        return f.center;
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
          center: f.center,
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
          center: f.center,
        );
      case 'center':
        return f.copyWith(center: v as bool? ?? false);
    }
    return f;
  }

  /// 文本变化后同步调整格式位置。
  /// 插入（newLen>oldLen，发生在末尾）：末尾之后的整体顺延，触及末尾的延伸；
  /// 删除（newLen<oldLen）：末尾之后的顺延，跨越末尾的截断。
  static List<TextFormat> adjust(
      List<TextFormat> source, int oldLen, int newLen) {
    if (oldLen == newLen) return source;
    final diff = newLen - oldLen;
    return source.map((f) {
      var s = f.start;
      var e = f.end;
      if (s >= oldLen) {
        // 整体在变更点之后 → 平移
        s += diff;
        e += diff;
      } else if (diff > 0 && e >= oldLen) {
        // 插入且格式触及末尾 → 延伸（继续在格式末尾打字）
        e += diff;
      } else if (e >= oldLen) {
        // 触及变更点：插入→延伸，删除→截断
        if (diff > 0) {
          e += diff;
        } else {
          e = newLen;
        }
      }
      return f.copyWith(start: s, end: e);
    }).where((f) => f.end > f.start).toList();
  }

  /// 判断某位置是否有指定格式（用于工具栏高亮状态）。
  static bool hasAt(List<TextFormat> list, int pos, String key, dynamic value) {
    for (final f in list) {
      if (pos < f.start || pos >= f.end) continue;
      if (_get(f, key) == value) return true;
    }
    return false;
  }

  /// 段落是否居中（找出覆盖该行的格式）。
  static bool isLineCentered(List<TextFormat> list, int lineStart, int lineEnd) {
    for (final f in list) {
      if (f.center != true) continue;
      if (f.start <= lineStart && f.end >= lineEnd) return true;
    }
    return false;
  }
}
