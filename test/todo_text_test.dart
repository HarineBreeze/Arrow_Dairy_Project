import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/utils/text_format.dart';
import 'package:diary_app/utils/todo_text.dart';

void main() {
  group('待办文本解析', () {
    test('识别 [ ] / [x]，并给出所在行与文字', () {
      const text = '今天要做的事\n[ ] 买牛奶\n[x] 交电费';
      final all = TodoText.parseAll(text);
      expect(all.length, 2);
      expect(all[0].done, isFalse);
      expect(all[0].text, '买牛奶');
      expect(all[1].done, isTrue);
      expect(all[1].text, '交电费');
    });

    test('普通文本行不会被误判为待办', () {
      expect(TodoText.parseAll('今天天气不错\n[abc] 不是待办'), isEmpty);
      expect(TodoText.isTodoLine('笔记 [ ] 中间出现的方括号'), isFalse);
    });

    test('允许缩进与 [X] 大写', () {
      final t = TodoText.parseLine('  [X] 已完成', 0)!;
      expect(t.done, isTrue);
      expect(t.text, '已完成');
    });
  });

  group('待办勾选切换', () {
    test('只翻转一个字符，其它内容与位置不变', () {
      const text = '开头\n[ ] 第一项\n[x] 第二项\n结尾';
      final next = TodoText.toggleAt(text, 1);
      expect(next, '开头\n[x] 第一项\n[x] 第二项\n结尾');
      expect(next.length, text.length);

      final back = TodoText.toggleAt(next, 2);
      expect(back, '开头\n[x] 第一项\n[ ] 第二项\n结尾');
    });

    test('非待办行 / 越界行号原样返回', () {
      const text = '普通一行\n[ ] 待办';
      expect(TodoText.toggleAt(text, 0), text);
      expect(TodoText.toggleAt(text, 9), text);
    });

    test('切换后格式区间偏移完全不受影响', () {
      const text = '[ ] 买 #牛奶';
      final formats = [
        const TextFormat(start: 4, end: 7, bold: true),
      ];
      final next = TodoText.toggleAt(text, 0);
      // 字符数不变 → 偏移仍指向「#牛奶」
      expect(next.length, text.length);
      expect(next.substring(4, 7), text.substring(4, 7));
      expect(formats.first.start, 4);
    });
  });
}
