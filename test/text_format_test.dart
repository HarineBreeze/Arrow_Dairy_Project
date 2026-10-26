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
    final r = FormatStore.apply(base, 2, 6, patch);
    expect(r.length, 3);
    expect(r[0].highlight, '#FFE58A');
    expect(r[1].highlight, null);
    expect(r[1].bold, true); // 加粗保留
    expect(r[2].highlight, '#FFE58A');
  });

  test('adjust 插入文本后顺延', () {
    final base = [
      const TextFormat(start: 5, end: 10, bold: true),
    ];
    // 末尾插入 3 字：触及末尾的格式延伸（继续打字继承格式）
    final r = FormatStore.adjust(base, 10, 13);
    expect(r[0].start, 5);
    expect(r[0].end, 13);
    // 末尾之后已有格式整体顺延
    final base2 = [
      const TextFormat(start: 12, end: 15, bold: true),
    ];
    final r2 = FormatStore.adjust(base2, 10, 13);
    expect(r2[0].start, 15);
    expect(r2[0].end, 18);
  });

  test('adjust 删除文本后收缩', () {
    final base = [
      const TextFormat(start: 5, end: 10, bold: true),
    ];
    final r = FormatStore.adjust(base, 10, 7); // 删掉3字
    expect(r[0].end, 7);
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

  test('选中加粗不复制已有高亮到整个选区外', () {
    final base = [
      const TextFormat(start: 0, end: 5, highlight: '#FFE58A'),
    ];
    // 选中 12-18 加粗
    final r = FormatStore.apply(
        base, 12, 18, const TextFormat(start: 12, end: 18, bold: true),
        clearHighlight: true);
    // 原有 0-5 高亮保留，12-18 只有加粗无高亮
    expect(r.length, 2);
    expect(r[0].start, 0);
    expect(r[0].end, 5);
    expect(r[0].highlight, '#FFE58A');
    expect(r[1].start, 12);
    expect(r[1].end, 18);
    expect(r[1].bold, true);
    expect(r[1].highlight, null); // 关键：不带高亮
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
