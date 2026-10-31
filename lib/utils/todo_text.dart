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

  /// 行首标记：允许前面有缩进空格。
  ///
  /// 支持两种写法：
  /// - 符号式（当前插入用）：`☐ 买牛奶` / `☑ 交电费`
  /// - 括号式（旧格式，继续兼容）：`[ ] 买牛奶` / `[x] 交电费`
  static final RegExp _marker =
      RegExp(r'^(\s*)(\[ \]|\[[xX]\]|☐|☑)\s?(.*)$');

  /// 待办符号（插入时用）：正文里直接就是一个方框字符，
  /// 在编辑框中一眼就能看出「这是一条待办」。
  static const String uncheckedSymbol = '☐';
  static const String checkedSymbol = '☑';
  static const String uncheckedPrefix = '$uncheckedSymbol ';
  static const String checkedPrefix = '$checkedSymbol ';

  static bool _markerDone(String mark) =>
      mark == checkedSymbol || mark.toLowerCase() == '[x]';

  /// 解析第 [line] 行；不是待办则返回 null。
  static TodoLine? parseLine(String line, int start) {
    final m = _marker.firstMatch(line);
    if (m == null) return null;
    return TodoLine(
      start: start,
      end: start + line.length,
      done: _markerDone(m.group(2)!),
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
  /// 只替换行首的标记符号（☐↔☑ 或 [ ]↔[x]），其他字符（含缩进、空格）
  /// 原样保留，因此不会影响任何既有的格式区间偏移。
  static String toggleAt(String text, int lineIndex) {
    final parts = text.split('\n');
    if (lineIndex < 0 || lineIndex >= parts.length) return text;
    final line = parts[lineIndex];
    final m = _marker.firstMatch(line);
    if (m == null) return text;
    final mark = m.group(2)!;
    final String flipped;
    if (mark == uncheckedSymbol) {
      flipped = checkedSymbol;
    } else if (mark == checkedSymbol) {
      flipped = uncheckedSymbol;
    } else {
      flipped = mark.toLowerCase() == '[x]' ? '[ ]' : '[x]';
    }
    // group(2) 紧跟在缩进之后（regex 里 \s* 只匹配空白），可安全推算位置
    final markStart = m.group(1)!.length;
    parts[lineIndex] =
        line.replaceRange(markStart, markStart + mark.length, flipped);
    return parts.join('\n');
  }

  /// 渲染预览用的那一行文字（去掉 `[ ]` 前缀）
  static String displayOf(String line) {
    final m = _marker.firstMatch(line);
    if (m == null) return line;
    return m.group(3) ?? '';
  }
}
