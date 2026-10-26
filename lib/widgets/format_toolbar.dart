import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/text_format.dart';

/// 富文本格式工具栏：选中文字后点击即可应用样式。
class FormatToolbar extends StatefulWidget {
  final TextEditingController controller;
  final List<TextFormat> formats;
  final ValueChanged<List<TextFormat>> onChanged;
  final VoidCallback onClose;
  final bool compact;

  const FormatToolbar({
    Key? key,
    required this.controller,
    required this.formats,
    required this.onChanged,
    required this.onClose,
    this.compact = false,
  }) : super(key: key);

  @override
  State<FormatToolbar> createState() => _FormatToolbarState();
}

class _FormatToolbarState extends State<FormatToolbar> {
  static const List<String> _highlights = [
    '#FFE58A', // 黄
    '#B9F5C7', // 绿
    '#BAD4FF', // 蓝
    '#FFC7DA', // 粉
    '#E2D1FF', // 紫
  ];
  static const List<double> _sizes = [14, 16, 19, 23, 28];
  static const List<String> _sizeLabels = ['小', '常', '中', '大', '特大'];

  TextSelection get _sel => widget.controller.selection;

  bool get _hasSelection => _sel.isValid && !_sel.isCollapsed;

  /// 有效作用区间：有选区用选区，无选区作用于当前行。
  List<int> get _range {
    if (_hasSelection) return [_sel.start, _sel.end];
    final text = widget.controller.text;
    final pos = _sel.isValid ? _sel.baseOffset : text.length;
    int s = text.lastIndexOf('\n', pos == 0 ? 0 : pos - 1);
    if (s < 0) {
      // lastIndexOf('\n', -1) 返回 -1，处理开头
      s = 0;
    } else {
      s = s + 1;
    }
    int e = text.indexOf('\n', pos);
    if (e < 0) e = text.length;
    if (e <= s) {
      s = pos;
      e = (pos + 1).clamp(0, text.length);
    }
    return [s, e];
  }

  bool _isOn(String key, dynamic value) {
    final rg = _range;
    final s = rg[0], e = rg[1];
    if (e <= s) return false;
    // 全部覆盖才认为开启
    for (int i = s; i < e; i++) {
      if (!FormatStore.hasAt(widget.formats, i, key, value)) return false;
    }
    return true;
  }

  void _toggle(String key, dynamic onValue, dynamic offValue) {
    final rg = _range;
    final s = rg[0], e = rg[1];
    if (e <= s) return;
    final st = FormatStore.stateAt(widget.formats, s, e);
    // 基于当前状态做局部修改，保留其它属性
    TextFormat patch;
    switch (key) {
      case 'bold':
        patch = st.copyWith(bold: st.bold != true);
        break;
      case 'italic':
        patch = st.copyWith(italic: st.italic != true);
        break;
      case 'underline':
        patch = st.copyWith(underline: st.underline != true);
        break;
      case 'strike':
        patch = st.copyWith(strike: st.strike != true);
        break;
      case 'center':
        patch = st.copyWith(center: st.center != true);
        break;
      default:
        return;
    }
    final next = FormatStore.apply(widget.formats, s, e, patch);
    widget.onChanged(next);
  }



  void _setHighlight(String? color) {
    final rg = _range;
    final s = rg[0], e = rg[1];
    if (e <= s) return;
    final st = FormatStore.stateAt(widget.formats, s, e);
    // 显式重建，highlight=null 表示清除
    final patch = TextFormat(
      start: s, end: e,
      bold: st.bold, italic: st.italic, underline: st.underline,
      strike: st.strike, highlight: color, size: st.size, center: st.center,
    );
    final next = FormatStore.apply(widget.formats, s, e, patch);
    widget.onChanged(next);
  }

  void _setSize(double? size) {
    final rg = _range;
    final s = rg[0], e = rg[1];
    if (e <= s) return;
    final st = FormatStore.stateAt(widget.formats, s, e);
    final patch = TextFormat(
      start: s, end: e,
      bold: st.bold, italic: st.italic, underline: st.underline,
      strike: st.strike, highlight: st.highlight, size: size, center: st.center,
    );
    final next = FormatStore.apply(widget.formats, s, e, patch);
    widget.onChanged(next);
  }

  void _toggleCenter() {
    final rg = _range;
    final s = rg[0], e = rg[1];
    if (e <= s) return;
    final on = _isOn('center', true);
    final patch = TextFormat(start: 0, end: 0, center: !on);
    final next = FormatStore.apply(widget.formats, s, e, patch);
    widget.onChanged(next);
  }

  Widget _iconBtn({
    required IconData icon,
    required String tip,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF3B6FE0) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 19,
            color: active ? Colors.white : const Color(0xFF2A3B52),
          ),
        ),
      ),
    );
  }

  Widget _textBtn({
    required String label,
    required bool active,
    required VoidCallback onTap,
    TextStyle? style,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 38),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3B6FE0) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: (style ?? const TextStyle(fontSize: 14)).copyWith(
            color: active ? Colors.white : const Color(0xFF2A3B52),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rg = _range;
    final s = rg[0], e = rg[1];

    final children = <Widget>[
      _textBtn(
        label: 'B',
        active: _isOn('bold', true),
        onTap: () => _toggle('bold', true, false),
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
      ),
      _textBtn(
        label: 'I',
        active: _isOn('italic', true),
        onTap: () => _toggle('italic', true, false),
        style: const TextStyle(fontSize: 17, fontStyle: FontStyle.italic),
      ),
      _textBtn(
        label: 'U',
        active: _isOn('underline', true),
        onTap: () => _toggle('underline', true, false),
        style: const TextStyle(
            fontSize: 16, decoration: TextDecoration.underline),
      ),
      _textBtn(
        label: 'S',
        active: _isOn('strike', true),
        onTap: () => _toggle('strike', true, false),
        style: const TextStyle(
            fontSize: 16, decoration: TextDecoration.lineThrough),
      ),
      _divider(),
      _iconBtn(
        icon: Icons.format_align_center,
        tip: '居中',
        active: _isOn('center', true),
        onTap: _toggleCenter,
      ),
      _divider(),
      _highlightBtn(),
      _divider(),
      _sizeBtn(),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE8EDF5))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: children),
                ),
              ),
              InkWell(
                onTap: widget.onClose,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  child: const Icon(Icons.keyboard_hide,
                      size: 20, color: Color(0xFF9AA8BF)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: const Color(0xFFE8EDF5),
      );

  Widget _highlightBtn() {
    final active = _isOn('highlight', _highlights.first);
    return PopupMenuButton<String>(
      tooltip: '高亮',
      offset: const Offset(0, -180),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) => _setHighlight(v == 'none' ? null : v),
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'none',
          child: Row(children: const [
            Icon(Icons.format_color_reset, size: 18),
            SizedBox(width: 8),
            Text('取消高亮', style: TextStyle(fontSize: 14)),
          ]),
        ),
        ..._highlights.map((c) => PopupMenuItem(
              value: c,
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _hex(c),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: const Color(0xFFE0E4EA)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_highlightName(c),
                      style: const TextStyle(fontSize: 14)),
                ],
              ),
            )),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3B6FE0) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.border_color_outlined,
                size: 18,
                color: active ? Colors.white : const Color(0xFF2A3B52)),
            const SizedBox(width: 3),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _hex(_highlights.first),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: const Color(0xFFD6DCE8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _highlightName(String c) {
    switch (c) {
      case '#FFE58A':
        return '黄色';
      case '#B9F5C7':
        return '绿色';
      case '#BAD4FF':
        return '蓝色';
      case '#FFC7DA':
        return '粉色';
      case '#E2D1FF':
        return '紫色';
    }
    return '高亮';
  }

  static Color _hex(String c) {
    var h = c.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFFFE58A);
  }

  Widget _sizeBtn() {
    return PopupMenuButton<double>(
      tooltip: '字号',
      offset: const Offset(0, -220),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: _setSize,
      itemBuilder: (ctx) => [
        for (int i = 0; i < _sizes.length; i++)
          PopupMenuItem(
            value: _sizes[i],
            child: Row(
              children: [
                Container(
                  width: 26,
                  alignment: Alignment.center,
                  child: Text('A',
                      style: TextStyle(
                          fontSize: 11.0 + i * 3,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 10),
                Text(_sizeLabels[i], style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 16.0,
          child: Row(children: const [
            Icon(Icons.format_color_reset, size: 18),
            SizedBox(width: 8),
            Text('恢复默认', style: TextStyle(fontSize: 14)),
          ]),
        ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        child: Row(
          children: const [
            Text('A', style: TextStyle(fontSize: 12)),
            Text('A', style: TextStyle(fontSize: 17)),
            Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF9AA8BF)),
          ],
        ),
      ),
    );
  }
}
