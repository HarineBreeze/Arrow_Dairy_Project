import 'package:flutter/material.dart';
import '../utils/rich_text.dart';
import '../utils/text_format.dart';
import '../utils/todo_text.dart';

/// 只读富文本：正文中 `@物品` 蓝色且可点击（回调物品名），`#话题` 蓝色不可交互。
/// 同时支持用户自定义排版（加粗/斜体/下划线/删除线/高亮/字号/居中）。
/// 点击命中通过 TextPainter 定位，不依赖 TapGestureRecognizer，Web/Android 均可靠。
class RichNoteText extends StatefulWidget {
  final String text;
  final Set<String> itemNames;
  final List<TextFormat> formats;
  final void Function(String itemName)? onTapMention;
  final TextStyle style;

  /// v4.9.27：全局搜索带入的关键词，命中区间加浅底纹、深墨字（深色模式可见）。
  /// 空字符串不产生任何高亮，兼容所有既有调用。
  final String searchQuery;

  /// 当前定位到第几个命中（-1 = 不高亮当前项）。仅影响底纹深浅。
  final int currentHit;

  const RichNoteText({
    Key? key,
    required this.text,
    required this.itemNames,
    this.formats = const [],
    this.onTapMention,
    required this.style,
    this.searchQuery = '',
    this.currentHit = -1,
  }) : super(key: key);

  /// 统计 text 中 query 的非重叠命中次数（大小写不敏感），供浏览页显示「N 处匹配」。
  static int countHits(String text, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return 0;
    final lower = text.toLowerCase();
    var count = 0;
    var from = 0;
    while (true) {
      final i = lower.indexOf(q, from);
      if (i < 0) break;
      count++;
      from = i + q.length;
    }
    return count;
  }

  @override
  State<RichNoteText> createState() => _RichNoteTextState();
}

class _RichNoteTextState extends State<RichNoteText> {
  List<RichSegment> _segments = const [];

  /// 搜索命中的原文区间（start, end），非重叠，按出现顺序排列。
  List<_HitRange> _hits = const [];

  /// 计算搜索命中区间。
  void _computeHits() {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) {
      _hits = const [];
      return;
    }
    final lower = widget.text.toLowerCase();
    final hits = <_HitRange>[];
    var from = 0;
    while (true) {
      final i = lower.indexOf(q, from);
      if (i < 0) break;
      hits.add(_HitRange(i, i + q.length));
      from = i + q.length;
    }
    _hits = hits;
  }

  /// 某原文位置落在第几个命中区间内；不在命中中返回 -1。
  int _hitIndexAt(int pos) {
    for (var i = 0; i < _hits.length; i++) {
      if (pos >= _hits[i].start && pos < _hits[i].end) return i;
    }
    return -1;
  }

  void _handleTapUp(TapUpDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // 点击定位基于「渲染文本」（不含被待办卡接管的行），
    // 命中后再映射回原文偏移，供片段解析使用
    final infos = _buildRenderLines();
    final span = TextSpan(
      style: widget.style,
      children: [
        for (final l in infos) ...[
          ...l.spans,
          const TextSpan(text: '\n'),
        ],
      ],
    );
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: box.size.width);
    final pos = painter.getPositionForOffset(details.localPosition);

    final source = _renderToSource(infos, pos.offset);
    if (source < 0) return;

    int offset = 0;
    for (int i = 0; i < _segments.length; i++) {
      final s = _segments[i];
      final end = offset + s.text.length;
      final isLast = i == _segments.length - 1;
      final hit = source >= offset &&
          (source < end || (isLast && source <= end));
      if (hit) {
        if (s.type == 'mention') {
          widget.onTapMention?.call(s.value);
        }
        return;
      }
      offset = end;
    }
  }

  /// 渲染偏移 → 原文偏移（每行带 sourceStart/renderStart，行内差值恒定）
  int _renderToSource(List<_RenderLine> infos, int renderOffset) {
    for (final l in infos) {
      final lineLen =
          l.spans.fold<int>(0, (sum, t) => sum + t.text!.length);
      if (renderOffset >= l.renderStart &&
          renderOffset <= l.renderStart + lineLen + 1) {
        return l.sourceStart +
            (renderOffset - l.renderStart).clamp(0, lineLen);
      }
    }
    return -1;
  }

  TextStyle? _styleAt(int pos) {
    TextStyle? st;
    bool highlighted = false;
    for (final f in widget.formats) {
      if (pos < f.start || pos >= f.end) continue;
      final decos = <TextDecoration>[];
      if (f.underline == true) decos.add(TextDecoration.underline);
      if (f.strike == true) decos.add(TextDecoration.lineThrough);
      if (f.highlight != null) highlighted = true;
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
    // v4.9.25：高亮文字字色固定为深墨色，深色模式下不随正文翻浅（浅底深字
    // 才清晰）；优先级低于 @物品 / #话题 链接蓝。
    if (highlighted) {
      st = (st ?? const TextStyle()).copyWith(color: const Color(0xFF24382F));
    }
    // @物品 / #话题 统一蓝色（无论是否设置了自定义字体/排版）
    final link = _linkColorAt(pos);
    if (link != null) {
      st = (st ?? const TextStyle()).copyWith(color: link);
    }
    // v4.9.27：搜索命中区间加浅底纹 + 深墨字；当前命中底纹加深。
    // 字色固定 0xFF24382F（浅底深字），深色模式下同样清晰；
    // 链接蓝优先级更高——命中落在链接上时保留蓝字、仅叠加底纹。
    final hit = _hitIndexAt(pos);
    if (hit >= 0) {
      final isCurrent = hit == widget.currentHit;
      st = (st ?? const TextStyle()).copyWith(
        backgroundColor:
            isCurrent ? _searchCurrentBg : _searchHitBg,
        color: link ?? const Color(0xFF24382F),
      );
    }
    return st;
  }

  static const Color _searchHitBg = Color(0xFFFFF0B3); // 命中：浅黄
  static const Color _searchCurrentBg = Color(0xFFFFD866); // 当前命中：深黄

  static Color _parseColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFFFE58A);
  }

  /// 命中 @物品 / #话题 时返回其高亮色，否则 null。
  /// 逐行渲染（_buildRenderLines）按位置单独处理蓝色。
  Color? _linkColorAt(int pos) {
    int offset = 0;
    for (final s in _segments) {
      final end = offset + s.text.length;
      if (pos >= offset && pos < end) {
        if (s.type == 'mention' || s.type == 'topic') {
          return const Color(0xFF3E8E6D);
        }
        return null;
      }
      offset = end;
    }
    return null;
  }

  bool _sameStyle(TextStyle? a, TextStyle? b) =>
      a?.fontWeight == b?.fontWeight &&
      a?.fontStyle == b?.fontStyle &&
      a?.decoration == b?.decoration &&
      a?.backgroundColor == b?.backgroundColor &&
      a?.fontSize == b?.fontSize &&
      a?.color == b?.color;

  /// 逐行生成渲染用的 TextSpan。
  ///
  /// 待办行（☐ / ☑ / [ ] / [x] 开头）**不渲染**——它们由浏览页的
  /// 待办卡（TodoCard）接管，避免同一件事在正文和卡片里出现两遍。
  /// 每行记录原文偏移与渲染偏移，供点击命中映射回原文。
  List<_RenderLine> _buildRenderLines() {
    final text = widget.text;
    final out = <_RenderLine>[];
    var sourceStart = 0;
    var renderStart = 0;

    for (final line in text.split('\n')) {
      final todo = TodoText.parseLine(line, sourceStart);
      if (todo == null) {
        final spans = <TextSpan>[];
        final buf = StringBuffer();
        TextStyle? bufStyle;

        void flush() {
          if (buf.isEmpty) return;
          spans.add(TextSpan(text: buf.toString(), style: bufStyle));
          buf.clear();
        }

        for (var i = 0; i < line.length; i++) {
          final st = _styleAt(sourceStart + i);
          if (!_sameStyle(bufStyle, st)) {
            flush();
            bufStyle = st;
          }
          buf.write(line[i]);
        }
        flush();
        out.add(_RenderLine(
          sourceStart: sourceStart,
          renderStart: renderStart,
          spans: spans,
        ));
        renderStart += line.length + 1; // +1 是行尾换行
      }
      // 待办行：不渲染，renderStart 不推进（原文偏移照常累加）
      sourceStart += line.length + 1;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    _segments = RichTextParser.parse(widget.text, widget.itemNames);
    if (widget.text.isEmpty) return const SizedBox.shrink();
    _computeHits();

    final lines = _buildRenderLines();
    final widgets = <Widget>[
      for (final line in lines)
        Text.rich(
          TextSpan(style: widget.style, children: line.spans),
          textAlign: TextAlign.start,
        ),
    ];
    // 正文全是待办行时，文本区为空，只留待办卡
    if (widgets.isEmpty) return const SizedBox.shrink();

    return GestureDetector(
      onTapUp: _handleTapUp,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widgets,
      ),
    );
  }
}

/// 一个搜索命中区间在原文中的 [start, end)，end 不含。
class _HitRange {
  final int start;
  final int end;
  const _HitRange(this.start, this.end);
}

/// 一条渲染行：spans + 它在原文 / 渲染文本中的起始偏移
class _RenderLine {
  final int sourceStart;
  final int renderStart;
  final List<TextSpan> spans;
  const _RenderLine({
    required this.sourceStart,
    required this.renderStart,
    required this.spans,
  });
}
