/// 正文里的行级列表标记（数字 / 圆点）。
///
/// 设计取舍：标记就是正文中的真实字符（`1. ` / `· ` / `　a. `），
/// 不额外存元数据。好处是导出、复制、浏览页都天然带序号，
/// 旧笔记不需要迁移；代价是每行只能靠语法前缀识别，
/// 因此所有规则都必须在纯文本层面自洽。
///
/// 层级定义：
/// - 一级：`1. ` 与 `· `
/// - 二级：一级前缀前加一个全角空格（正好一个汉字宽）
///   - 数字一级 → `　a. ` / `　b. `
///   - 圆点一级 → `　· `（仍是圆点）
/// 
/// 工具栏上的列表操作。
enum ListAction {
  /// 变成 / 保持一级数字列表
  number,

  /// 变成 / 保持一级圆点列表
  bullet,

  /// 退回正文（清标记 + 清格式）
  plain,

  /// 升一级（二级 → 一级）
  up,

  /// 降一级（一级 → 二级）
  down,
}

/// 一行上的列表标记。
class ListMark {
  /// 该行首字符的绝对偏移
  final int lineStart;

  /// 标记（含缩进与尾随空格）结束处，即正文起点
  final int markEnd;

  /// 1 = 一级，2 = 二级
  final int level;

  /// true = `1.` / `a.`，false = `·`
  final bool ordered;

  /// 有序行的 1 基序号（圆点行恒为 0）
  final int ordinal;

  const ListMark({
    required this.lineStart,
    required this.markEnd,
    required this.level,
    required this.ordered,
    required this.ordinal,
  });

  /// 标记本身占用的字符数
  int get length => markEnd - lineStart;
}

/// 一次文本替换（用于把光标位置映射到新文本）。
class TextEdit {
  final int start;
  final int removed;
  final int inserted;
  const TextEdit(this.start, this.removed, this.inserted);
}

/// [ListText.normalize] 的结果：新文本 + 各处改动。
class NormalizeResult {
  final String text;
  final List<TextEdit> edits;
  const NormalizeResult(this.text, this.edits);

  /// 把旧文本里的一个偏移映射到新文本。
  int mapOffset(int pos) {
    var p = pos;
    for (final e in edits) {
      if (p < e.start) break;
      if (p >= e.start + e.removed) {
        p += e.inserted - e.removed;
      } else {
        p = e.start + e.inserted;
      }
    }
    return p < 0 ? 0 : p;
  }
}

class ListText {
  static const String bullet = '·';

  /// 二级缩进：一个全角空格 = 一个汉字宽
  static const String indent = '\u3000';

  static final RegExp _ol1 = RegExp(r'^(\d{1,3})\. ');
  static final RegExp _ol2 = RegExp('^$indent' + r'([a-z])\. ');
  static final RegExp _ul1 = RegExp('^$bullet ');
  static final RegExp _ul2 = RegExp('^$indent$bullet ');

  /// 序号转字母：1→a，26→z，27→a（循环）
  static String alphaLabel(int ordinal) {
    final i = (ordinal - 1) % 26;
    return String.fromCharCode(97 + (i < 0 ? 0 : i));
  }

  /// 解析单行（[lineStart] 为该行在全文中的偏移）。
  static ListMark? parseLine(String line, int lineStart) {
    var m = _ol1.firstMatch(line);
    if (m != null) {
      return ListMark(
        lineStart: lineStart,
        markEnd: lineStart + m.end,
        level: 1,
        ordered: true,
        ordinal: int.tryParse(m.group(1)!) ?? 1,
      );
    }
    m = _ol2.firstMatch(line);
    if (m != null) {
      return ListMark(
        lineStart: lineStart,
        markEnd: lineStart + m.end,
        level: 2,
        ordered: true,
        ordinal: m.group(1)!.codeUnitAt(0) - 96,
      );
    }
    m = _ul1.firstMatch(line);
    if (m != null) {
      return ListMark(
        lineStart: lineStart,
        markEnd: lineStart + m.end,
        level: 1,
        ordered: false,
        ordinal: 0,
      );
    }
    m = _ul2.firstMatch(line);
    if (m != null) {
      return ListMark(
        lineStart: lineStart,
        markEnd: lineStart + m.end,
        level: 2,
        ordered: false,
        ordinal: 0,
      );
    }
    return null;
  }

  /// 扫出全文所有列表行。
  static List<ListMark> scan(String text) {
    final out = <ListMark>[];
    var start = 0;
    while (true) {
      final nl = text.indexOf('\n', start);
      final end = nl < 0 ? text.length : nl;
      final mark = parseLine(text.substring(start, end), start);
      if (mark != null) out.add(mark);
      if (nl < 0) break;
      start = nl + 1;
    }
    return out;
  }

  static int lineStartOf(String text, int pos) {
    final p = pos.clamp(0, text.length);
    if (p == 0) return 0;
    final nl = text.lastIndexOf('\n', p - 1);
    return nl < 0 ? 0 : nl + 1;
  }

  static int lineEndOf(String text, int pos) {
    final p = pos.clamp(0, text.length);
    final nl = text.indexOf('\n', p);
    return nl < 0 ? text.length : nl;
  }

  /// 光标所在行的标记（没有则 null）。
  static ListMark? markAt(String text, int pos) {
    final s = lineStartOf(text, pos);
    final e = lineEndOf(text, pos);
    return parseLine(text.substring(s, e), s);
  }

  /// 指定类型 + 层级的前缀（序号先按 1 生成，随后由 [normalize] 校正）。
  static String label({
    required bool ordered,
    required int level,
    int ordinal = 1,
  }) {
    final String body;
    if (ordered) {
      body = level == 1
          ? '$ordinal. '
          : '$indent${alphaLabel(ordinal)}. ';
    } else {
      body = level == 1 ? '$bullet ' : '$indent$bullet ';
    }
    return body;
  }

  /// 下一行应使用的同类型前缀（换行续号）。
  static String continuationOf(ListMark mark) {
    if (!mark.ordered) return label(ordered: false, level: mark.level);
    return label(
      ordered: true,
      level: mark.level,
      ordinal: mark.ordinal + 1,
    );
  }

  /// 重排有序列表段：段首沿用用户写下的序号，段内强制连续，
  /// 遇正文行即断开、下一段重新起算。
  ///
  /// 段首之所以不强行改成 1，是因为用户可能就想从「3.」开始；
  /// 而段内出现 `1. / 3.` 这种断裂时会被收拢成 `1. / 2.`。
  static NormalizeResult normalize(String text) {
    if (text.isEmpty) return NormalizeResult(text, const []);
    final lines = text.split('\n');
    final out = <String>[];
    final edits = <TextEdit>[];
    var olBase = 0;
    var olCount = 0;
    var alBase = 0;
    var alCount = 0;
    var offset = 0;
    for (final line in lines) {
      final mark = parseLine(line, 0);
      if (mark == null) {
        olBase = 0;
        olCount = 0;
        alBase = 0;
        alCount = 0;
        out.add(line);
        offset += line.length + 1;
        continue;
      }
      String? expected;
      if (mark.level == 1) {
        alBase = 0;
        alCount = 0;
        if (mark.ordered) {
          if (olBase == 0) olBase = mark.ordinal;
          olCount++;
          expected = '${olBase + olCount - 1}. ';
        }
      } else {
        if (mark.ordered) {
          if (alBase == 0) alBase = mark.ordinal;
          alCount++;
          expected = '$indent${alphaLabel(alBase + alCount - 1)}. ';
        }
      }
      final actual = line.substring(0, mark.length);
      if (expected != null && expected != actual) {
        edits.add(TextEdit(offset, actual.length, expected.length));
        out.add(expected + line.substring(actual.length));
      } else {
        out.add(line);
      }
      offset += line.length + 1;
    }
    return NormalizeResult(out.join('\n'), edits);
  }

  /// 把光标所在行设为指定类型 / 层级；已是该形态则原样返回。
  static String setMark(
    String text,
    int pos, {
    required bool ordered,
    required int level,
  }) {
    final start = lineStartOf(text, pos);
    final end = lineEndOf(text, pos);
    final mark = parseLine(text.substring(start, end), start);
    final prefix = label(ordered: ordered, level: level);
    if (mark != null) {
      return text.replaceRange(start, mark.markEnd, prefix);
    }
    return text.replaceRange(start, start, prefix);
  }

  /// 去掉标记，回到正文。
  static String clearMark(String text, int pos) {
    final mark = markAt(text, pos);
    if (mark == null) return text;
    return text.replaceRange(mark.lineStart, mark.markEnd, '');
  }

  /// 升级（1）/ 降级（2）；非列表行不动。
  static String setLevel(String text, int pos, int level) {
    final mark = markAt(text, pos);
    if (mark == null) return text;
    return setMark(text, pos,
        ordered: mark.ordered, level: level.clamp(1, 2));
  }

  /// 光标是否停在该行标记的「尾部」——此时一次退格应当整段退回正文。
  static bool atMarkTail(String text, int pos) {
    final mark = markAt(text, pos);
    return mark != null && pos == mark.markEnd;
  }

  /// 该行是否只有标记、没有正文（回车应退出列表）。
  static bool isEmptyItem(String text, int pos) {
    final mark = markAt(text, pos);
    if (mark == null) return false;
    final end = lineEndOf(text, pos);
    return text.substring(mark.markEnd, end).trim().isEmpty;
  }
}
