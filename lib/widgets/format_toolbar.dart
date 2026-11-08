import 'app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/text_format.dart';
import '../utils/haptics.dart';

/// 富文本格式工具栏：选中文字后点击即可应用样式。
/// 颜色 / 字号用「内嵌展开行」而非 PopupMenu，避免菜单抢焦点导致选区丢失。
class FormatToolbar extends StatefulWidget {
  final TextEditingController controller;
  final List<TextFormat> formats;
  final ValueChanged<List<TextFormat>> onChanged;
  final VoidCallback onClose;

  /// 外部（编辑页）持有的选区区间：只读模式下 controller.selection 会归零，
  /// 因此必须以这个为准。
  final int? rangeStart;
  final int? rangeEnd;

  /// 点击 # / @ 时回调，参数为 true 表示 #（话题），false 表示 @（物品）。
  final void Function(bool isTopic)? onInsertTag;

  /// 点击 ➕ 时回调：在当前光标/选区处插入待办清单。
  final VoidCallback? onInsertTodo;

  const FormatToolbar({
    Key? key,
    required this.controller,
    required this.formats,
    required this.onChanged,
    required this.onClose,
    this.rangeStart,
    this.rangeEnd,
    this.onInsertTag,
    this.onInsertTodo,
  }) : super(key: key);

  @override
  State<FormatToolbar> createState() => FormatToolbarState();
}

class FormatToolbarState extends State<FormatToolbar> {
  static const List<String> _highlights = [
    '#FFE58A',
    '#B9F5C7',
    '#BAD4FF',
    '#FFC7DA',
    '#E2D1FF',
  ];
  static const List<String> _hlNames = ['黄', '绿', '蓝', '粉', '紫'];
  static const List<double> _sizes = [14, 16, 19, 23, 28];
  static const List<String> _sizeLabels = ['小', '常', '中', '大', '特大'];

  /// 0=无展开，1=调色板，2=字号
  int _panel = 0;

  /// 展开面板时锁定的作用区间，防止焦点变化后选区丢失。
  int? _lockStart;
  int? _lockEnd;

  TextSelection get _sel => widget.controller.selection;

  bool get _hasSelection => _sel.isValid && !_sel.isCollapsed;

  /// 有效作用区间优先级：
  /// 1. 外部传入的选区（编辑页在切只读前保存的）
  /// 2. 面板展开时锁定的区间
  /// 3. controller 当前选区
  /// 4. 光标所在行
  List<int> get _range {
    if (widget.rangeStart != null &&
        widget.rangeEnd != null &&
        widget.rangeEnd! > widget.rangeStart!) {
      return [widget.rangeStart!, widget.rangeEnd!];
    }
    if (_lockStart != null && _lockEnd != null) {
      return [_lockStart!, _lockEnd!];
    }
    if (_hasSelection) return [_sel.start, _sel.end];
    final text = widget.controller.text;
    final pos = _sel.isValid ? _sel.baseOffset : text.length;
    final clamped = pos.clamp(0, text.length);
    int s = clamped == 0 ? -1 : text.lastIndexOf('\n', clamped - 1);
    if (s < 0) {
      s = 0;
    } else {
      s = s + 1;
    }
    int e = text.indexOf('\n', clamped);
    if (e < 0) e = text.length;
    if (e <= s) {
      s = clamped;
      e = (clamped + 1).clamp(0, text.length);
    }
    return [s, e];
  }

  void _lock() {
    final rg = _range;
    _lockStart = rg[0];
    _lockEnd = rg[1];
  }

  void _unlock() {
    _lockStart = null;
    _lockEnd = null;
  }

  bool _isOn(String key, dynamic value) {
    final rg = _range;
    final s = rg[0], e = rg[1];
    if (e <= s) return false;
    for (int i = s; i < e; i++) {
      if (!FormatStore.hasAt(widget.formats, i, key, value)) return false;
    }
    return true;
  }

  void _toggle(String key) {
    final rg = _range;
    final s = rg[0], e = rg[1];
    if (e <= s) return;
    final on = _isOn(key, true);
    // 只写这一项属性，其余字段留 null（不回带其它样式，避免扩散）
    final patch = TextFormat(
      start: s,
      end: e,
      bold: key == 'bold' ? !on : null,
      italic: key == 'italic' ? !on : null,
      underline: key == 'underline' ? !on : null,
      strike: key == 'strike' ? !on : null,
    );
    widget.onChanged(FormatStore.apply(widget.formats, s, e, patch));
    _restoreSelection(s, e);
  }

  void _setHighlight(String? color) {
    final rg = _range;
    final s = rg[0], e = rg[1];
    if (e <= s) return;
    final patch = TextFormat(start: s, end: e, highlight: color);
    widget.onChanged(FormatStore.apply(widget.formats, s, e, patch,
        clearHighlight: color == null));
    _restoreSelection(s, e);
  }

  void _setSize(double size) {
    final rg = _range;
    final s = rg[0], e = rg[1];
    if (e <= s) return;
    final patch = TextFormat(start: s, end: e, size: size);
    widget.onChanged(
        FormatStore.apply(widget.formats, s, e, patch, clearSize: false));
    _restoreSelection(s, e);
  }

  /// 应用格式后同步高亮区间（只读模式下 controller 不持有选区，跳过）。
  void _restoreSelection(int s, int e) {
    if (widget.rangeStart != null && widget.rangeEnd != null) return;
    if (s != e && e <= widget.controller.text.length) {
      widget.controller.selection =
          TextSelection(baseOffset: s, extentOffset: e);
    }
  }

  /// 外部改动了正文（如插入待办）：清掉区间锁与展开面板，
  /// 否则锁着的旧区间会被下一次点按用到新内容上。
  void resetRange() {
    _unlock();
    if (_panel != 0) {
      setState(() => _panel = 0);
    }
  }

  void _togglePanel(int which) {
    Haptics.light();
    if (_panel == which) {
      setState(() {
        _panel = 0;
        _unlock();
      });
    } else {
      _lock();
      setState(() => _panel = which);
    }
  }

  // ---------- 按钮 ----------

  Widget _textBtn({
    required String label,
    required bool active,
    required VoidCallback onTap,
    TextStyle? style,
  }) {
    return InkWell(
      onTap: () {
        Haptics.light();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 34),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3E8E6D) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: (style ?? const TextStyle(fontSize: 13)).copyWith(
            color: active ? Colors.white : const Color(0xFF24382F),
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

  static Color _hex(String c) {
    var h = c.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFFFFE58A);
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    final rg = _range;
    final s = rg[0], e = rg[1];
    final currentSize = FormatStore.stateAt(widget.formats, s, e).size ?? 16.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE8EDF5))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_panel == 1) _buildColorPanel(),
            if (_panel == 2) _buildSizePanel(currentSize),
            _buildMainRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainRow() {
    // 收拢一档按钮间距（38 → 34）：多出「待办」入口后，
    // 小屏横向滚动区不至于把高亮/字号挤出可点范围。
    final row = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _textBtn(
                    label: 'B',
                    active: _isOn('bold', true),
                    onTap: () => _toggle('bold'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  _textBtn(
                    label: 'I',
                    active: _isOn('italic', true),
                    onTap: () => _toggle('italic'),
                    style: const TextStyle(
                        fontSize: 17, fontStyle: FontStyle.italic),
                  ),
                  _textBtn(
                    label: 'U',
                    active: _isOn('underline', true),
                    onTap: () => _toggle('underline'),
                    style: const TextStyle(
                        fontSize: 15, decoration: TextDecoration.underline),
                  ),
                  _textBtn(
                    label: 'S',
                    active: _isOn('strike', true),
                    onTap: () => _toggle('strike'),
                    style: const TextStyle(
                        fontSize: 15, decoration: TextDecoration.lineThrough),
                  ),
                  _divider(),
                  // 话题 / 物品：把符号插到选区文字前面
                  _textBtn(
                    label: '#',
                    active: false,
                    onTap: () => widget.onInsertTag?.call(true),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  _textBtn(
                    label: '@',
                    active: false,
                    onTap: () => widget.onInsertTag?.call(false),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  _divider(),
                  // 待办清单：在该行插入「[ ] 」，浏览页可勾选
                  InkWell(
                    onTap: () {
                      Haptics.light();
                      _lock();
                      widget.onInsertTodo?.call();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 36,
                      constraints: const BoxConstraints(minWidth: 38),
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          AppIcon(AppIcons.plus,
                              size: 15, color: Color(0xFF24382F)),
                          SizedBox(width: 2),
                          AppIcon(AppIcons.todo,
                              size: 16, color: Color(0xFF24382F)),
                        ],
                      ),
                    ),
                  ),
                  _divider(),
                  // 高亮入口
                  InkWell(
                    onTap: () => _togglePanel(1),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _panel == 1
                            ? const Color(0xFFE4F2EB)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const AppIcon(AppIcons.edit,
                              size: 18, color: Color(0xFF24382F)),
                          const SizedBox(width: 3),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: _hex(_highlights.first),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFD5E2DB)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _divider(),
                  // 字号入口
                  InkWell(
                    onTap: () => _togglePanel(2),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _panel == 2
                            ? const Color(0xFFE4F2EB)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: const [
                          Text('A', style: TextStyle(fontSize: 13)),
                          Text('A', style: TextStyle(fontSize: 17)),
                          AppIcon(AppIcons.chevD,
                              size: 16, color: Color(0xFF8FA09A)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: row,
            ),
          ),
          InkWell(
            onTap: widget.onClose,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              child: const AppIcon(AppIcons.keyboardHide,
                  size: 20, color: Color(0xFF8FA09A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPanel() {
    final current = FormatStore.stateAt(
      widget.formats,
      _range[0],
      _range[1],
    ).highlight;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEFF5F1))),
      ),
      child: Row(
        children: [
          const Text('高亮',
              style: TextStyle(fontSize: 13, color: Color(0xFF8FA09A))),
          const SizedBox(width: 10),
          ...List.generate(_highlights.length, (i) {
            final c = _highlights[i];
            final active = current == c;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: GestureDetector(
                onTap: () {
                  Haptics.light();
                  _setHighlight(active ? null : c);
                },
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _hex(c),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: active
                          ? const Color(0xFF3E8E6D)
                          : const Color(0xFFDFEAE5),
                      width: active ? 2 : 1,
                    ),
                  ),
                  child: active
                      ? const AppIcon(AppIcons.check,
                          size: 16, color: Color(0xFF24382F))
                      : null,
                ),
              ),
            );
          }),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Haptics.light();
              _setHighlight(null);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDFEAE5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('清除',
                  style: TextStyle(fontSize: 13, color: Color(0xFF647A70))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSizePanel(double current) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEFF5F1))),
      ),
      child: Row(
        children: [
          const Text('字号',
              style: TextStyle(fontSize: 13, color: Color(0xFF8FA09A))),
          const SizedBox(width: 10),
          ...List.generate(_sizes.length, (i) {
            final sz = _sizes[i];
            final active = (current - sz).abs() < 0.5;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  Haptics.light();
                  _setSize(sz);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF3E8E6D)
                        : const Color(0xFFF5FAF7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _sizeLabels[i],
                    style: TextStyle(
                      fontSize: 13,
                      color: active ? Colors.white : const Color(0xFF24382F),
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
