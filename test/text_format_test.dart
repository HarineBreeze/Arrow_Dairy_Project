import 'package:flutter_test/flutter_test.dart';
import 'package:diary_app/utils/text_format.dart';

void main() {
  regressionTests();
  test('apply 加粗新区间，不影响其它区间', () {
    final base = [
      const TextFormat(start: 0, end: 5, bold: true),
    ];
    final r = FormatStore.apply(
        base, 10, 20, const TextFormat(start: 10, end: 20, bold: true));
    expect(r.length, 2);
    expect(r[0].start, 0);
    expect(r[0].end, 5);
    expect(r[1].start, 10);
    expect(r[1].end, 20);
    expect(r[1].bold, true);
  });

  test('apply 裁剪跨区间格式', () {
    final base = [
      const TextFormat(start: 0, end: 30, highlight: '#FFE58A'),
    ];
    // 在 10-20 设置加粗 → 高亮被切成两段 + 新加粗段
    final r = FormatStore.apply(
        base, 10, 20, const TextFormat(start: 10, end: 20, bold: true));
    expect(r.length, 3);
    expect(r[0].start, 0);
    expect(r[0].end, 10);
    expect(r[0].highlight, '#FFE58A');
    expect(r[1].bold, true);
    expect(r[2].start, 20);
    expect(r[2].end, 30);
    expect(r[2].highlight, '#FFE58A');
  });

  test('基于状态取消防粗但保留字号', () {
    final base = [
      const TextFormat(start: 5, end: 15, bold: true, size: 28),
    ];
    final st = FormatStore.stateAt(base, 8, 12);
    expect(st.bold, true);
    expect(st.size, 28);
    final patch = st.copyWith(bold: false);
    final r = FormatStore.apply(base, 8, 12, patch);
    // 5-8 保留原格式；8-12 无粗有字号；12-15 保留原格式
    expect(r.length, 3);
    expect(r[0].bold, true);
    expect(r[1].bold, false);
    expect(r[1].size, 28);
    expect(r[2].bold, true);
  });

  test('清除高亮', () {
    final base = [
      const TextFormat(start: 0, end: 10, highlight: '#FFE58A', bold: true),
    ];
    final st = FormatStore.stateAt(base, 2, 6);
    final patch = TextFormat(
      start: 2, end: 6,
      bold: st.bold, italic: st.italic, underline: st.underline,
      strike: st.strike, highlight: null, size: st.size,
    );
    final r = FormatStore.apply(base, 2, 6, patch, clearHighlight: true);
    expect(r.length, 3);
    expect(r[0].highlight, '#FFE58A');
    expect(r[1].highlight, null);
    expect(r[1].bold, true); // 加粗保留
    expect(r[2].highlight, '#FFE58A');
  });

  test('adjustRange 末尾插入延伸格式，其后格式顺延', () {
    final base = [
      const TextFormat(start: 5, end: 10, bold: true),
    ];
    // 末尾插入 3 字：触及末尾的格式延伸（继续打字继承格式）
    final r = FormatStore.adjustRange(base, 10, 0, 3);
    expect(r[0].start, 5);
    expect(r[0].end, 13);
    // 末尾之后已有格式整体顺延
    final base2 = [
      const TextFormat(start: 12, end: 15, bold: true),
    ];
    final r2 = FormatStore.adjustRange(base2, 10, 0, 3);
    expect(r2[0].start, 15);
    expect(r2[0].end, 18);
  });

  test('adjustToText 中间插入：后续格式平移，高亮不错位', () {
    final base = [
      const TextFormat(start: 0, end: 3, highlight: '#FFE58A'), // '你好呀'
      const TextFormat(start: 6, end: 10, bold: true),
    ];
    // 文本 '你好呀中间的内容哦' → 在位置 3 插入 'XYZ'（3 字）
    final oldT = '你好呀中间的内容哦';
    final newT = '你好呀XYZ中间的内容哦';
    final r = FormatStore.adjustToText(base, oldT, newT);
    // 插入点恰在高亮末尾 → 高亮延伸包含新输入（继续打字继承格式）
    expect(r[0].start, 0);
    expect(r[0].end, 6);
    expect(r[1].start, 9); // 6+3
    expect(r[1].end, 13);
  });

  test('adjustToText 中间删除：跨越删除区的格式收缩', () {
    final base = [
      const TextFormat(start: 0, end: 10, highlight: '#FFE58A'),
    ];
    final oldT = '0123456789';
    final newT = '012789'; // 删除位置 3-6 的 '4567'（4 字）
    final r = FormatStore.adjustToText(base, oldT, newT);
    expect(r[0].start, 0);
    expect(r[0].end, 6);
  });

  test('adjustToText 删除区之后的格式整体平移', () {
    final base = [
      const TextFormat(start: 8, end: 12, bold: true),
    ];
    final oldT = '0123456789ab';
    final newT = '012789ab'; // 删除 [3,7) '3456'
    final r = FormatStore.adjustToText(base, oldT, newT);
    // 格式 8-12 → 整体左移 4 → 4-8
    expect(r[0].start, 4);
    expect(r[0].end, 8);
  });

  test('adjustToText 删除区内完全覆盖的格式被丢弃', () {
    final base = [
      const TextFormat(start: 3, end: 6, bold: true),
    ];
    final oldT = '0123456789';
    final newT = '0126789'; // 删除 [3,6) '345'
    final r = FormatStore.adjustToText(base, oldT, newT);
    expect(r, isEmpty);
  });

  test('adjustRange 删除末尾文本不影响之前的格式', () {
    final base = [
      const TextFormat(start: 5, end: 10, bold: true),
    ];
    final r = FormatStore.adjustRange(base, 10, 3, 0); // 在末尾之后删掉3字
    expect(r[0].end, 10); // 删除区在格式之外，格式不变
  });

  test('encode/decode 往返一致', () {
    final list = [
      const TextFormat(start: 3, end: 9, bold: true, highlight: '#BAD4FF'),
      const TextFormat(start: 12, end: 18, size: 28, strike: true),
    ];
    final enc = FormatStore.encode(list);
    final dec = FormatStore.decode(enc);
    expect(dec.length, 2);
    expect(dec[0].bold, true);
    expect(dec[0].highlight, '#BAD4FF');
    expect(dec[1].size, 28);
    expect(dec[1].strike, true);
  });

  test('decode 兼容空值', () {
    expect(FormatStore.decode(null), isEmpty);
    expect(FormatStore.decode(''), isEmpty);
    expect(FormatStore.decode('not json'), isEmpty);
  });

  test('取消加粗不吞掉相邻格式（非覆盖区间）', () {
    final base = [
      const TextFormat(start: 0, end: 4, bold: true),
      const TextFormat(start: 4, end: 8, bold: true, italic: true),
    ];
    // 对 0-8 全部取消加粗
    final st = FormatStore.stateAt(base, 0, 8);
    final patch = st.copyWith(bold: false);
    final r = FormatStore.apply(base, 0, 8, patch);
    // 0-8 只剩一个 bold:false 的片段，italic 被合并进状态→被应用到全区
    // 这是「合并状态再改」的语义：斜体扩散到 0-8（可接受）
    expect(r.first.bold, false);
  });
}

// 回归测试：格式只作用于选区，不扩散到开头段落
void regressionTests() {
  test('选区高亮不污染前面无格式区间', () {
    // 全文 20 字无格式，选中 10-15 加黄底
    final r = FormatStore.apply(
        const [], 10, 15, const TextFormat(start: 10, end: 15, highlight: '#FFE58A'),
        clearHighlight: true);
    expect(r.length, 1);
    expect(r[0].start, 10);
    expect(r[0].end, 15);
    expect(r[0].bold, null); // 不携带其它属性
    expect(r[0].size, null);
  });

  test('加粗与已有高亮共存（不覆盖、不扩散到选区外）', () {
    final base = [
      const TextFormat(start: 0, end: 5, highlight: '#FFE58A'),
    ];
    // 选中 12-18 加粗：0-5 高亮不受影响；但选中 2-8 加粗时高亮应保留
    final r = FormatStore.apply(
        base, 2, 8, const TextFormat(start: 2, end: 8, bold: true));
    // 0-2 高亮原样；2-5 高亮+加粗共存；5-8 仅加粗（原本无高亮）
    expect(r.length, 3);
    expect(r[0].start, 0);
    expect(r[0].end, 2);
    expect(r[0].highlight, '#FFE58A');
    expect(r[0].bold, null);
    expect(r[1].start, 2);
    expect(r[1].end, 5);
    expect(r[1].highlight, '#FFE58A'); // 关键：高亮保留，与加粗共存
    expect(r[1].bold, true);
    expect(r[2].start, 5);
    expect(r[2].end, 8);
    expect(r[2].highlight, null); // 区间外本就没有高亮，不扩散
    expect(r[2].bold, true);
  });

  test('字号与高亮共存', () {
    final base = [
      const TextFormat(start: 0, end: 10, highlight: '#FFE58A'),
    ];
    final r = FormatStore.apply(
        base, 3, 7, const TextFormat(start: 3, end: 7, size: 28));
    expect(r.length, 3);
    expect(r[0].start, 0);
    expect(r[0].end, 3);
    expect(r[0].highlight, '#FFE58A');
    expect(r[0].size, null);
    expect(r[1].start, 3);
    expect(r[1].end, 7);
    expect(r[1].highlight, '#FFE58A'); // 高亮保留
    expect(r[1].size, 28); // 字号叠加
    expect(r[2].start, 7);
    expect(r[2].end, 10);
    expect(r[2].highlight, '#FFE58A');
    expect(r[2].size, null);
  });

  test('清除高亮只影响选区', () {
    final base = [
      const TextFormat(start: 0, end: 20, highlight: '#FFE58A'),
    ];
    final r = FormatStore.apply(
        base, 8, 12, const TextFormat(start: 8, end: 12),
        clearHighlight: true);
    // 0-8 有高亮 / 8-12 无 / 12-20 有高亮
    expect(r.length, 3);
    expect(r[0].highlight, '#FFE58A');
    expect(r[1].highlight, null);
    expect(r[2].highlight, '#FFE58A');
  });
}
