/// 笔记正文里的「待办清单」。
///
/// ## 为什么存成一行文本而不是独立结构
/// 正文目前就是一个纯字符串，排版（[TextFormat]）、撤销重做、`@物品` /
/// `#话题` 解析都建立在「字符位置」之上。待办若另存一份结构，每次编辑
/// 都要同步两套偏移量，一处算错就全乱。所以待办直接写进正文：
///
/// ```
/// [ ] 买牛奶
/// [x] 交电费
/// ```
///
/// 「是否勾选」就写在 `[ ]` / `[x]` 这一个字符上。浏览页切换勾选 = 改正文
/// 里的一个字符，其余内容与格式分毫不动；编辑页把它当普通文本渲染，
/// 撤销、光标、选区全部自然可用。
class TodoLine {
  /// 该行在正文中的起始偏移（含）
  final int start;

  /// 该行结束偏移（不含，不含换行符）
  final int end;

  /// 是否已勾选
  final bool done;

  /// 待办文字（不含 `[ ]` 前缀）
  final String text;

  const TodoLine({
    required this.start,
    required this.end,
    required this.done,
    required this.text,
  });
}

class TodoText {
  TodoText._();

  /// 行首标记：允许前面有缩进空格
  static final RegExp _marker = RegExp(r'^(\s*)\[( |x|X)\]\s?(.*)$');

  /// 待办前缀（插入时用）
  static const String uncheckedPrefix = '[ ] ';
  static const String checkedPrefix = '[x] ';

  /// 解析第 [line] 行；不是待办则返回 null。
  static TodoLine? parseLine(String line, int start) {
    final m = _marker.firstMatch(line);
    if (m == null) return null;
    final done = m.group(2)!.toLowerCase() == 'x';
    return TodoLine(
      start: start,
      end: start + line.length,
      done: done,
      text: m.group(3) ?? '',
    );
  }

  /// 找出正文里所有待办行。
  static List<TodoLine> parseAll(String text) {
    final out = <TodoLine>[];
    var start = 0;
    for (final line in text.split('\n')) {
      final t = parseLine(line, start);
      if (t != null) out.add(t);
      start += line.length + 1;
    }
    return out;
  }

  /// 某一行是否是待办
  static bool isTodoLine(String line) => _marker.hasMatch(line);

  /// 切换第 [index] 行的勾选状态，返回新的整篇正文。
  ///
  /// 只改动 `[` 与 `]` 之间的那一个字符，其他字符（含缩进、空格）原样保留，
  /// 因此不会影响任何既有的格式区间偏移。
  static String toggleAt(String text, int lineIndex) {
    // 用 split 而不是正则替换：需要精确落到第 N 行
    final parts = text.split('\n');
    if (lineIndex < 0 || lineIndex >= parts.length) return text;
    final line = parts[lineIndex];
    final m = _marker.firstMatch(line);
    if (m == null) return text;
    final indent = m.group(1)!;
    final done = m.group(2)!.toLowerCase() == 'x';
    final rest = m.group(3) ?? '';
    final open = line.indexOf('[', indent.length);
    final close = open < 0 ? -1 : line.indexOf(']', open);
    if (open < 0 || close < 0) return text;
    parts[lineIndex] =
        '${line.substring(0, open)}[${done ? ' ' : 'x'}]${line.substring(close + 1)}';
    return parts.join('\n');
  }

  /// 渲染预览用的那一行文字（去掉 `[ ]` 前缀）
  static String displayOf(String line) {
    final m = _marker.firstMatch(line);
    if (m == null) return line;
    return m.group(3) ?? '';
  }
}
