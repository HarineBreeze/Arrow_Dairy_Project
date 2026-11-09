import 'package:ayodiray/utils/list_text.dart';
import 'package:flutter_test/flutter_test.dart';

/// 列表语法（数字 / 圆点 / 二级）纯逻辑回归。
void main() {
  group('识别', () {
    test('一级与二级、数字与圆点四种前缀', () {
      final marks = ListText.scan(
          '1. 一\n· 二\n\u3000a. 三\n\u3000· 四\n正文');
      expect(marks.length, 4);
      expect(marks[0].level, 1);
      expect(marks[0].ordered, isTrue);
      expect(marks[0].ordinal, 1);
      expect(marks[1].level, 1);
      expect(marks[1].ordered, isFalse);
      expect(marks[2].level, 2);
      expect(marks[2].ordered, isTrue);
      expect(marks[2].ordinal, 1, reason: 'a 应识别为 1');
      expect(marks[3].level, 2);
      expect(marks[3].ordered, isFalse);
    });

    test('数字后没有空格不算列表（普通正文）', () {
      expect(ListText.scan('1.没有空格'), isEmpty);
      expect(ListText.scan('1.'), isEmpty);
      expect(ListText.scan('第 1. 条'), isEmpty);
    });

    test('markAt 定位光标所在行的标记', () {
      const text = '正文行\n2. 第二项\n后一行';
      final mark = ListText.markAt(text, 6);
      expect(mark, isNotNull);
      expect(mark!.ordinal, 2);
      expect(mark.lineStart, 4);
      expect(mark.markEnd, 7);
    });
  });

  group('自动编号', () {
    test('连续段重排为 1..n', () {
      final r = ListText.normalize('1. a\n1. b\n7. c');
      expect(r.text, '1. a\n2. b\n3. c');
    });

    test('遇正文行即断开，下一段重新起算', () {
      final r = ListText.normalize('1. a\n2. b\n正文\n5. c\n6. d');
      expect(r.text, '1. a\n2. b\n正文\n5. c\n6. d',
          reason: '第二段的 5 是用户自己写的起点，段内 6 保持连续');
    });

    test('段内断裂会被收拢，段首自定义序号保留', () {
      final r = ListText.normalize('3. a\n9. b\n1. c');
      expect(r.text, '3. a\n4. b\n5. c',
          reason: '段首 3 保留，后面的乱序按 4、5 接上');
    });

    test('二级接续字母，遇到新的一级后重新起算', () {
      final r = ListText.normalize(
          '1. 一\n\u3000a. x\n\u3000c. y\n2. 二\n\u3000b. z');
      expect(r.text, '1. 一\n\u3000a. x\n\u3000b. y\n2. 二\n\u3000b. z',
          reason: '第二组从 b 开始，组内保持连续');
    });

    test('二级下方出现一级时，一级接续而不是重置', () {
      final r = ListText.normalize('1. 一\n\u3000a. x\n5. 二');
      expect(r.text, '1. 一\n\u3000a. x\n2. 二');
    });

    test('圆点行不参与编号，但会打断有序序列的字母计数', () {
      final r = ListText.normalize('1. a\n· b\n2. c');
      expect(r.text, '1. a\n· b\n2. c');
    });

    test('mapOffset 把光标映射到重排后的位置', () {
      final r = ListText.normalize('9. a\n9. b');
      expect(r.text, '9. a\n10. b', reason: '段首 9 保留，第二行接 10');
      expect(r.mapOffset(0), 0, reason: '段首前缀没变，行首光标不动');
      expect(r.mapOffset(8), 9,
          reason: '前缀 "9. " → "10. " 变宽 1，行内文字随之后移');
    });
  });

  group('按钮操作', () {
    test('setMark 给正文行加一级数字前缀', () {
      final t = ListText.setMark('今天很好', 0, ordered: true, level: 1);
      expect(t, '1. 今天很好');
    });

    test('setMark 把圆点换成数字并保持正文', () {
      final t = ListText.setMark('· 条目', 0, ordered: true, level: 1);
      expect(t, '1. 条目');
    });

    test('setLevel 一级 → 二级：数字变字母并缩进一格', () {
      final t = ListText.setLevel('3. 条目', 0, 2);
      expect(t, '\u3000a. 条目');
      final r = ListText.normalize(t);
      expect(r.text, '\u3000a. 条目');
    });

    test('setLevel 圆点二级仍是圆点，只加缩进', () {
      final t = ListText.setLevel('· 条目', 0, 2);
      expect(t, '\u3000· 条目');
    });

    test('clearMark 退回正文', () {
      expect(ListText.clearMark('2. 条目', 3), '条目');
      expect(ListText.clearMark('\u3000· 条目', 4), '条目');
      expect(ListText.clearMark('正文', 1), '正文');
    });

    test('continuationOf 续号', () {
      final num = ListText.parseLine('3. a', 0)!;
      expect(ListText.continuationOf(num), '4. ');
      final alpha = ListText.parseLine('\u3000b. a', 0)!;
      expect(ListText.continuationOf(alpha), '\u3000c. ');
      final dot = ListText.parseLine('\u3000· a', 0)!;
      expect(ListText.continuationOf(dot), '\u3000· ');
    });

    test('空条目判定：只有标记没有正文', () {
      expect(ListText.isEmptyItem('1. ', 3), isTrue);
      expect(ListText.isEmptyItem('1. 有字', 3), isFalse);
      expect(ListText.isEmptyItem('正文', 1), isFalse);
    });

    test('atMarkTail 判定光标是否贴着标记末尾（退格整段退回）', () {
      const t = '1. 条目';
      expect(ListText.atMarkTail(t, 3), isTrue);
      expect(ListText.atMarkTail(t, 4), isFalse);
    });
  });
}
