import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../models/diary_entry.dart';
import '../services/diary_storage.dart';
import '../services/item_storage.dart';
import '../widgets/highlight_controller.dart';
import '../widgets/format_toolbar.dart';
import '../utils/text_format.dart';
import '../utils/writing_prompts.dart';

class EditScreen extends StatefulWidget {
  final DiaryEntry? entry;
  final DateTime? defaultDate;
  const EditScreen({Key? key, this.entry, this.defaultDate}) : super(key: key);

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> with WidgetsBindingObserver {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final HighlightEditingController _contentCtrl;
  Set<String> _itemNames = {};
  late String _mood;
  late String _weather;
  late String _location;
  late DateTime _publishDate;
  bool _encrypted = false;
  bool _pinned = false;
  String _password = '';
  String _passwordHint = '';
  String _passwordAnswer = '';
  bool _saving = false;
  List<TextFormat> _formats = [];
  bool _showToolbar = false;
  late final FocusNode _contentFocus;
  bool _hadSelection = false;
  bool _tapStartedWithSelection = false;
  bool _selecting = false; // 框选模式：正文只读，不弹键盘
  int _savedStart = 0; // 切换只读前保存的选区，供工具栏使用
  int _savedEnd = 0;
  // 选区变更时重建工具栏，避免它沿用过一次的区间锁定/展开面板
  Key _toolbarKey = UniqueKey();
  String _lastContent = '';

  static const List<String> _moods = ['😊', '😌', '😢', '😡', '😴', '🥰'];
  static const List<String> _weathers = ['🌞', '⛅', '🌧️', '❄️', '🌙', '🌈'];
  static const List<String> _moreMoods = [
    '🤩', '😭', '😤', '🤯', '🥳', '🤔', '😷', '🥺', '😎', '🤗', '😇', '🤪'
  ];
  static const List<String> _moreWeathers = [
    '🌤️', '🌦️', '🌨️', '⛈️', '🌪️', '🌫️', '⚡', '💨', '🌈', '🌊', '☁️', '🌡️'
  ];

  bool get _isNew => widget.entry == null;

  /// 标题为空时展示的随机话题（内置 50 条）。仅新建笔记抽取，
  /// 编辑已有笔记若标题为空同样给一个，避免空白。
  late String _prompt = WritingPrompts.random();

  /// 换一个话题（点提示语右侧的小图标）。
  void _shufflePrompt() {
    setState(() => _prompt = WritingPrompts.random(exclude: _prompt));
    HapticFeedback.selectionClick();
  }

  // ---------- 撤销 / 重做 ----------
  // 栈中保存的是「某个历史状态」：文本 + 格式。
  // _lastContent / _formats 始终代表当前状态。
  final List<_Snap> _undoStack = [];
  final List<_Snap> _redoStack = [];
  Timer? _undoPending;

  /// 正在由 undo/redo 程序化改写文本，此时忽略 onChanged 的记录。
  bool _restoring = false;

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  /// 把「当前状态之前的旧状态」压入撤销栈。
  /// 必须在文本/格式发生改变之后调用，参数是改变前的值。
  void _pushUndo(String oldText, List<TextFormat> oldFormats) {
    _undoStack.add(_Snap(oldText, List<TextFormat>.from(oldFormats)));
    _redoStack.clear();
    if (_undoStack.length > 100) _undoStack.removeAt(0);
  }

  void _undo() {
    _undoPending?.cancel();
    if (_undoStack.isEmpty) return;
    _undoPending = null;
    // 当前状态存入重做栈
    _redoStack.add(_Snap(_contentCtrl.text, List<TextFormat>.from(_formats)));
    final s = _undoStack.removeLast();
    _applySnap(s);
  }

  void _redo() {
    _undoPending?.cancel();
    if (_redoStack.isEmpty) return;
    _undoStack.add(_Snap(_contentCtrl.text, List<TextFormat>.from(_formats)));
    final s = _redoStack.removeLast();
    _applySnap(s);
  }

  void _applySnap(_Snap s) {
    _restoring = true;
    final pos = s.text.length;
    _contentCtrl.value = TextEditingValue(
      text: s.text,
      selection: TextSelection.collapsed(offset: pos),
    );
    _contentCtrl.setFormats(s.formats);
    _formats = List<TextFormat>.from(s.formats);
    _lastContent = s.text;
    HapticFeedback.selectionClick();
    setState(() {
      _savedStart = 0;
      _savedEnd = 0;
      _hadSelection = false;
      _selecting = false;
      _toolbarKey = UniqueKey();
    });
    // 等 onChanged 链路走完再解除保护
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoring = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry?.title ?? '');
    _subtitleCtrl = TextEditingController(text: widget.entry?.subtitle ?? '');
    _formats = FormatStore.decode(widget.entry?.formats);
    _contentCtrl = HighlightEditingController(
      itemNames: _itemNames,
      text: widget.entry?.content ?? '',
      formats: _formats,
    );
    _lastContent = _contentCtrl.text;
    _contentFocus = FocusNode();
    _contentFocus.addListener(_onFocusChange);
    _contentCtrl.addListener(_onSelectionChanged);
    WidgetsBinding.instance.addObserver(this); // 监听键盘真实弹出/收起（viewInsets）
    _mood = widget.entry?.mood ?? _moods.first;
    _weather = widget.entry?.weather ?? _weathers.first;
    _location = widget.entry?.location ?? '';
    _publishDate =
        widget.entry?.publishDate ?? widget.defaultDate ?? DateTime.now();
    _encrypted = widget.entry?.encrypted ?? false;
    _pinned = widget.entry?.pinned ?? false;
    _password = widget.entry?.password ?? '';
    _passwordHint = widget.entry?.passwordHint ?? '';
    _passwordAnswer = widget.entry?.passwordAnswer ?? '';
    _loadItems();
  }

  /// 键盘真实可见性（window 度量的实时值）。
  /// 不能用 hasFocus 判断：Android 按返回键收起键盘时焦点仍保留；
  /// 也不能用 MediaQuery.of(context)：didChangeMetrics 时它还是上一帧的旧值。
  bool _isKbVisible() =>
      WidgetsBinding.instance.window.viewInsets.bottom > 0;

  /// 键盘真正收起（含返回键收起、焦点仍保留的情况）：选框回退为光标。
  void _onKeyboardHidden() {
    if (!mounted || _selecting) return;
    final sel = _contentCtrl.selection;
    if (sel.isValid && !sel.isCollapsed) {
      _contentCtrl.selection =
          TextSelection.collapsed(offset: sel.start < 0 ? 0 : sel.start);
    }
    _hadSelection = false;
    _savedStart = 0;
    _savedEnd = 0;
    if (_showToolbar) setState(() => _showToolbar = false);
    // 放弃残余焦点，断开输入连接，确保下次长按走框选分支
    if (_contentFocus.hasFocus) _contentFocus.unfocus();
  }

  Timer? _kbConfirmTimer; // 确认「真正收起」的延迟检查
  double _prevInset = 0; // 上一次上报的键盘高度，用于判断收起趋势

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final b = WidgetsBinding.instance.window.viewInsets.bottom;
    if (b > 0 && !_kbVisible && !_selecting) {
      // 键盘正在弹出：视觉立即响应（跟手）
      _kbConfirmTimer?.cancel();
      setState(() {
        _kbVisible = true;
        // 弹出文字输入键盘时，默认收起排版栏（用户可再次点击正文手动展开）
        _showToolbar = false;
      });
    } else if (_kbVisible && b < _prevInset) {
      // 键盘高度开始下降 = 收起动画开始：视觉立即还原（不再等动画结束）
      setState(() => _kbVisible = false);
      _scheduleConfirmedHide();
    } else if (b == 0 && !_kbVisible) {
      // 已还原但尚未确认：继续走确认流程
      _scheduleConfirmedHide();
    }
    _prevInset = b;
  }

  /// 延迟确认「键盘真的收起了」再执行破坏性操作（清选框/放弃焦点）。
  /// 误判（动画抖动瞬间报 0）只影响视觉，不会把键盘摁回去。
  void _scheduleConfirmedHide() {
    final hadFocus = _contentFocus.hasFocus; // 收起开始时是否持有焦点
    _kbConfirmTimer?.cancel();
    _kbConfirmTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      if (WidgetsBinding.instance.window.viewInsets.bottom == 0 &&
          !_selecting &&
          hadFocus == _contentFocus.hasFocus) {
        _onKeyboardHidden();
      }
    });
  }

  void _onFocusChange() {
    if (!mounted) return;
    // 键盘弹出（非框选模式的聚焦）→ 平滑收起头部信息区，给正文腾出空间
    final kb = _contentFocus.hasFocus && !_selecting;
    if (kb != _kbVisible) setState(() => _kbVisible = kb);
    if (_contentFocus.hasFocus) {
      if (_selecting) {
        // 框选模式下聚焦：持续压住键盘
        _suppressKeyboard();
      } else {
        // 聚焦后强制确保键盘弹出（readOnly 随焦点联动，框架可能延迟开连接）
        if (_showToolbar) setState(() => _showToolbar = false);
        Future.delayed(const Duration(milliseconds: 60), () {
          if (mounted &&
              _contentFocus.hasFocus &&
              !_selecting &&
              !_isKbVisible()) {
            SystemChannels.textInput.invokeMethod('TextInput.show');
          }
        });
      }
    } else if (!_selecting) {
      // 键盘收起（编辑态）：选框回退为光标，清掉排版锁定
      _onKeyboardHidden();
    }
  }

  /// 选区变化：出现框选 → 进入「框选模式」，正文变只读，系统键盘自动收起。
  void _onSelectionChanged() {
    if (!mounted) return;
    final sel = _contentCtrl.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    if (hasSelection && !_hadSelection) {
      // 键盘弹出状态下的长按 = 系统编辑手势（复制/粘贴/全选），不进框选模式
      if (!_selecting && _kbAtDown) {
        _hadSelection = true;
        return;
      }
      _hadSelection = true;
      // 关键：切只读会把 selection 重置为 offset 0，必须在切换前存下区间
      _savedStart = sel.start;
      _savedEnd = sel.end;
      _enterSelectMode();
    } else if (hasSelection) {
      // 已有选区又换了新区间（重新框选/拖动）：必须 setState，
      // 否则工具栏仍持有上一次的 rangeStart/rangeEnd，会先作用到旧选区。
      if (_savedStart != sel.start || _savedEnd != sel.end) {
        setState(() {
          _savedStart = sel.start;
          _savedEnd = sel.end;
          _toolbarKey = UniqueKey(); // 重建工具栏，清掉旧区间锁定与展开面板
        });
      }
    } else if (!hasSelection && _hadSelection) {
      _hadSelection = false;
      // 选区消失（用户点别处或收起）：退出框选模式
      if (_selecting) {
        setState(() => _selecting = false);
      }
    }
  }

  /// 进入框选模式：正文设只读 + 持续压住键盘 + 显示排版栏。
  void _enterSelectMode() {
    if (!_selecting) {
      setState(() {
        _selecting = true; // 切只读：系统层面就不需要键盘了
        _showToolbar = true;
      });
    } else if (!_showToolbar) {
      setState(() => _showToolbar = true);
    }
    _suppressKeyboard();
    // 手势开始时键盘本来就收着：长按可能让输入框抢焦点，放弃之，
    // 从源头杜绝键盘弹出（readOnly 已随失焦变为 true）。
    if (!_kbAtDown && _contentFocus.hasFocus) {
      _contentFocus.unfocus();
    }
  }

  /// 连续多次收起键盘，覆盖系统「切只读瞬间又弹一次」的行为。
  void _suppressKeyboard([int round = 0]) {
    if (!mounted || !_selecting) return;
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (round >= 4) return;
    Future.delayed(Duration(milliseconds: 60 + round * 80), () {
      _suppressKeyboard(round + 1);
    });
  }

  bool _kbAtDown = false; // 手指按下瞬间键盘是否真实弹出（viewInsets 判断）
  bool _kbVisible = false; // 键盘当前是否弹出（用于联动收起/展开头部信息区）

  // 记录按下时是否已有选区、键盘是否弹出
  void _onPointerDown(PointerDownEvent e) {
    final sel = _contentCtrl.selection;
    _tapStartedWithSelection = sel.isValid && !sel.isCollapsed;
    // 用真实键盘高度判断，而非焦点（返回键收起键盘后焦点仍在）
    _kbAtDown = _isKbVisible();
  }

  /// 单点正文 = 想编辑文字 → 弹键盘；长按拖选 = 想排版 → 不弹键盘。
  void _onContentTap() {
    // 点下时若有选区：取消选区、退出框选模式，进入编辑（键盘随后弹出）
    if (_tapStartedWithSelection || _selecting) {
      _hadSelection = false;
      _tapStartedWithSelection = false;
      setState(() {
        _selecting = false;
        _showToolbar = false; // 键盘即将弹出，默认收起排版栏
      });
      _savedStart = 0;
      _savedEnd = 0;
      // 光标位置交给 TextField 自身的点击处理（定位到点击处），不再强制回旧选区末尾；
      // 立即请求焦点（无延迟）：readOnly 将随重建变为 false，didUpdateWidget 会自动接通键盘
      if (!_contentFocus.hasFocus) _contentFocus.requestFocus();
      return;
    }
    if (_isKbVisible()) {
      // 键盘已弹出：再点正文 = 手动展开排版栏
      if (!_showToolbar) setState(() => _showToolbar = true);
    } else if (_showToolbar) {
      // 键盘即将弹出：默认收起排版栏
      setState(() => _showToolbar = false);
    }
  }

  void _closeToolbar() {
    setState(() {
      _showToolbar = false;
      _selecting = false;
    });
    _hadSelection = false;
    // 清除选区变回光标，下次点正文才弹键盘
    final pos = _contentCtrl.selection.isValid
        ? _contentCtrl.selection.end
        : _contentCtrl.text.length;
    _contentCtrl.selection = TextSelection.collapsed(offset: pos);
    _contentFocus.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  /// 点击 # / @：在框选文字前插入符号，使其成为话题或物品引用。
  /// - # 任意文字都可成为话题
  /// - @ 仅当框选文字在物资清单中存在时才插入，否则提示
  void _insertTag(bool isTopic) {
    final s = _savedStart;
    final e = _savedEnd;
    if (e <= s) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先框选一段文字')),
      );
      return;
    }
    final text = _contentCtrl.text;
    final word = text.substring(s, e).trim();
    if (word.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先框选一段文字')),
      );
      return;
    }

    if (!isTopic) {
      // 物品：必须精确存在于物资清单
      final matched = _itemNames.firstWhere(
        (n) => n == word,
        orElse: () => '',
      );
      if (matched.isEmpty) {
        // 尝试忽略空白的宽松匹配（选区可能带上首尾空格）
        final loose = _itemNames.where((n) => n.trim() == word).toList();
        if (loose.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('物资清单里没有「$word」，无法 @ 该物品'),
              duration: const Duration(milliseconds: 1800),
            ),
          );
          return;
        }
      }
    }

    final symbol = isTopic ? '#' : '@';
    // 若前面已经是同一符号，避免重复插入
    if (s > 0 && text.substring(s - 1, s) == symbol) return;

    final newText = text.substring(0, s) + symbol + text.substring(s);
    _pushUndo(text, _formats);
    // 格式区间：插入点之后的整体右移 1
    _formats = FormatStore.adjustRange(_formats, s, 0, 1);
    _contentCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: s + 1 + word.length,
        extentOffset: s + 1 + word.length,
      ),
    );
    _contentCtrl.setFormats(_formats);
    _lastContent = newText;

    HapticFeedback.selectionClick();
    setState(() {
      _savedStart = 0;
      _savedEnd = 0;
      _hadSelection = false;
      _selecting = false;
      _showToolbar = true;
      _toolbarKey = UniqueKey();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isTopic ? '已生成为话题 #$word' : '已引用物品 @$word'),
        duration: const Duration(milliseconds: 1300),
      ),
    );
  }

  Future<void> _loadItems() async {
    final items = await ItemStorage.load();
    if (!mounted) return;
    setState(() {
      _itemNames =
          items.map((e) => e.name).where((n) => n.isNotEmpty).toSet();
      _contentCtrl.itemNames = _itemNames;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _kbConfirmTimer?.cancel();
    _undoPending?.cancel();
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _contentCtrl.dispose();
    _contentFocus.removeListener(_onFocusChange);
    _contentCtrl.removeListener(_onSelectionChanged);
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    final subtitle = _encrypted ? _subtitleCtrl.text.trim() : '';
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写点什么再保存吧～')),
      );
      return;
    }
    if (_encrypted && subtitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写副标题～')),
      );
      return;
    }

    setState(() => _saving = true);

    final list = await DiaryStorage.load();
    if (_isNew) {
      final now = DateTime.now();
      list.add(DiaryEntry(
        id: now.microsecondsSinceEpoch.toString(),
        title: title,
        subtitle: subtitle,
        content: content,
        formats: content.isEmpty ? '' : FormatStore.encode(_formats),
        mood: _mood,
        weather: _weather,
        location: _location,
        encrypted: _encrypted,
        password: _password,
        passwordHint: _passwordHint,
        passwordAnswer: _passwordAnswer,
        pinned: _pinned,
        createdAt: now,
        updatedAt: now,
        publishDate: _publishDate,
      ));
    } else {
      final idx = list.indexWhere((e) => e.id == widget.entry!.id);
      if (idx >= 0) {
        list[idx].title = title;
        list[idx].subtitle = subtitle;
        list[idx].content = content;
        list[idx].formats =
            content.isEmpty ? '' : FormatStore.encode(_formats);
        list[idx].mood = _mood;
        list[idx].weather = _weather;
        list[idx].location = _location;
        list[idx].encrypted = _encrypted;
        list[idx].password = _password;
        list[idx].passwordHint = _passwordHint;
        list[idx].passwordAnswer = _passwordAnswer;
        list[idx].pinned = _pinned;
        list[idx].publishDate = _publishDate;
        list[idx].updatedAt = DateTime.now();
      }
    }
    await DiaryStorage.save(list);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _cancel() {
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认要删除这篇日记吗?'),
        content: const Text('注意！删除后无法恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final list = await DiaryStorage.load();
      list.removeWhere((e) => e.id == widget.entry!.id);
      await DiaryStorage.save(list);
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  Future<void> _pickVisibility() async {
    String choice = _encrypted ? 'encrypted' : 'public';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('可见度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('公开'),
                value: 'public',
                groupValue: choice,
                onChanged: (v) => setState(() => choice = v!),
              ),
              RadioListTile<String>(
                title: const Text('加密'),
                value: 'encrypted',
                groupValue: choice,
                onChanged: (v) => setState(() => choice = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, choice),
                child: const Text('确定')),
          ],
        ),
      ),
    );
    if (result == 'encrypted') {
      await _setPassword();
    } else if (result == 'public') {
      setState(() {
        _encrypted = false;
        _password = '';
        _passwordHint = '';
        _passwordAnswer = '';
      });
    }
  }

  Future<void> _setPassword() async {
    final ctrl = TextEditingController(text: _password);
    final hintCtrl = TextEditingController(text: _passwordHint);
    final ansCtrl = TextEditingController(text: _passwordAnswer);
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置密码'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(hintText: '请输入密码'),
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('密保问题（选填）',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9AA8BF))),
              ),
              TextField(
                controller: hintCtrl,
                maxLength: 20,
                decoration: const InputDecoration(
                  hintText: '如：我的生日是几号？',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('密保问题答案',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9AA8BF))),
              ),
              TextField(
                controller: ansCtrl,
                maxLength: 20,
                decoration: const InputDecoration(
                  hintText: '答案（忘记密码时用于找回）',
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, {
                    'pwd': ctrl.text,
                    'hint': hintCtrl.text.trim(),
                    'answer': ansCtrl.text.trim(),
                  }),
              child: const Text('确定')),
        ],
      ),
    );
    if (result != null && (result['pwd'] ?? '').isNotEmpty) {
      setState(() {
        _encrypted = true;
        _password = result['pwd']!;
        _passwordHint = result['hint'] ?? '';
        _passwordAnswer = result['answer'] ?? '';
      });
    }
    ctrl.dispose();
    hintCtrl.dispose();
    ansCtrl.dispose();
  }

  Widget _buildVisibilityRow() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _pickVisibility,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDCE7FF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: 16, color: Color(0xFF3B6FE0)),
                  const SizedBox(width: 6),
                  const Text(
                    '可见度',
                    style: TextStyle(fontSize: 13, color: Color(0xFF2A3B52)),
                  ),
                  const Spacer(),
                  Text(
                    _encrypted ? '加密' : '公开',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF3B6FE0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFF9AA8BF)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _buildMoreButton()),
      ],
    );
  }

  // 「更多」按钮：目前提供置顶开关，未来在此扩展其它选项
  Widget _buildMoreButton() {
    final active = _pinned;
    return InkWell(
      onTap: _showMoreSheet,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFDCE7FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color:
                  active ? const Color(0xFF3B6FE0) : const Color(0xFFDCE7FF)),
        ),
        child: Row(
          children: [
            Icon(Icons.more_horiz,
                size: 16,
                color: active ? const Color(0xFF3B6FE0) : Color(0xFF2A3B52)),
            const SizedBox(width: 6),
            Text(
              '更多',
              style: TextStyle(
                fontSize: 13,
                color: active ? const Color(0xFF3B6FE0) : Color(0xFF2A3B52),
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMoreSheet() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E4EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.push_pin_outlined,
                    size: 20, color: Color(0xFF3B6FE0)),
                title: const Text('置顶',
                    style:
                        TextStyle(fontSize: 14, color: Color(0xFF2A3B52))),
                value: _pinned,
                activeColor: const Color(0xFF3B6FE0),
                onChanged: (v) {
                  setState(() => _pinned = v);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _publishDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _publishDate = picked);
    }
  }

  Future<void> _pickLocation() async {
    final ctrl = TextEditingController(text: _location);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加地点'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 10,
          decoration: const InputDecoration(
            hintText: '输入地点（最多10字）',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _location = result);
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xCC3B6FE0),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: '撤销',
            color: Colors.white,
            disabledColor: Colors.white.withOpacity(0.35),
            onPressed: _canUndo ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: '重做',
            color: Colors.white,
            disabledColor: Colors.white.withOpacity(0.35),
            onPressed: _canRedo ? _redo : null,
          ),
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 键盘弹出时平滑收起心情/天气/日期/可见度，给正文腾出可视区域
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _kbVisible
                ? const SizedBox(width: double.infinity)
                : Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildChipRow('今天心情', _moods, _mood,
                    (v) => setState(() => _mood = v), _moreMoods),
                const SizedBox(height: 10),
                _buildChipRow('天气', _weathers, _weather,
                    (v) => setState(() => _weather = v), _moreWeathers),
                const SizedBox(height: 16),
                _buildDateLocationRow(),
                const SizedBox(height: 12),
                _buildVisibilityRow(),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleCtrl,
                        maxLength: 15,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          // 标题为空时随机展示一条写作话题作为引导
                          hintText: _titleCtrl.text.isEmpty ? _prompt : '标题',
                          hintStyle: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFFB4C0D2),
                          ),
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    // 标题为空时提供「换一个」入口
                    if (_titleCtrl.text.isEmpty)
                      InkWell(
                        onTap: _shufflePrompt,
                        borderRadius: BorderRadius.circular(20),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 6, vertical: 4),
                          child: Icon(Icons.refresh,
                              size: 18, color: Color(0xFF9AA8BF)),
                        ),
                      ),
                    Text(
                      '${_titleCtrl.text.length}/15',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9AA8BF)),
                    ),
                  ],
                ),
                const Divider(height: 1),
                if (_encrypted) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _subtitleCtrl,
                          maxLength: 20,
                          style: const TextStyle(
                              fontSize: 15, color: Color(0xFF2A3B52)),
                          decoration: const InputDecoration(
                            hintText: '此处标题会公开显示哦～',
                            hintStyle: TextStyle(
                                fontSize: 14, color: Color(0xFF9AA8BF)),
                            border: InputBorder.none,
                            counterText: '',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      Text(
                        '${_subtitleCtrl.text.length}/20',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9AA8BF)),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                ],
              ],
            ),
          ),
                ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      child: Listener(
                        onPointerDown: _onPointerDown,
                        child: TextField(
                        controller: _contentCtrl,
                        focusNode: _contentFocus,
                        readOnly: _selecting || !_contentFocus.hasFocus,
                        autofocus: _isNew && !_showToolbar,
                        maxLength: 2000,
                        maxLines: null,
                        minLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(fontSize: 16, height: 1.7),
                        decoration: const InputDecoration(
                          hintText: '今天发生了什么…',
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        onTap: _onContentTap,
                        onChanged: (v) {
                          if (_restoring) {
                            // undo/redo 程序化改写：不记录，只同步区间
                            _formats = FormatStore.adjustToText(_formats, _lastContent, v);
                            _contentCtrl.formats = _formats;
                            _lastContent = v;
                            setState(() {});
                            return;
                          }
                          if (v != _lastContent) {
                            // 先把「改变前」的状态压栈，再更新为当前
                            _pushUndo(_lastContent, _formats);
                            _undoPending?.cancel();
                            _undoPending = Timer(const Duration(milliseconds: 800), () {
                              // 输入停止后刷新按钮可用态
                              if (mounted) setState(() {});
                            });
                          }
                          if (v != _lastContent) {
                            // 基于新旧文本 diff 精确平移/收缩格式区间（支持任意位置编辑）
                            _formats = FormatStore.adjustToText(_formats, _lastContent, v);
                            _contentCtrl.formats = _formats;
                            _lastContent = v;
                          }
                          setState(() {});
                        },
                      ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 8,
                      child: Text(
                        '${_contentCtrl.text.length}/2000',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9AA8BF)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_showToolbar)
            FormatToolbar(
              key: _toolbarKey,
              controller: _contentCtrl,
              formats: _formats,
              rangeStart: _savedStart,
              rangeEnd: _savedEnd,
              onInsertTag: _insertTag,
              onChanged: (v) {
                // 记录改变前的状态，再应用新格式
                _pushUndo(_lastContent, _formats);
                setState(() => _formats = v);
                _contentCtrl.setFormats(v);
              },
              onClose: () {
                setState(() => _showToolbar = false);
                _contentFocus.unfocus();
              },
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF3B6FE0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('取消', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('完成', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateLocationRow() {
    final d = _publishDate;
    return Row(
      children: [
        Expanded(
          child: _buildInfoCell(
            icon: Icons.event,
            label: '${d.year}年${d.month}月${d.day}日',
            onTap: _pickDate,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildInfoCell(
            icon: Icons.location_on,
            label: _location.isEmpty ? '地点' : _location,
            onTap: _pickLocation,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCell({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE7FF)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF3B6FE0)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF2A3B52),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipRow(
    String label,
    List<String> options,
    String selected,
    ValueChanged<String> onSelect,
    List<String> moreOptions,
  ) {
    Widget chip(String o, {VoidCallback? onTap, bool isMore = false}) {
      final isSel = o == selected;
      return GestureDetector(
        onTap: onTap ?? () => onSelect(o),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (isSel && !isMore)
                ? const Color(0xFF3B6FE0)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (isSel && !isMore)
                  ? const Color(0xFF3B6FE0)
                  : const Color(0xFFDCE7FF),
            ),
          ),
          child: Text(o, style: const TextStyle(fontSize: 15)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9A8A7E))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...options.map((o) => chip(o)),
            chip('...',
                isMore: true,
                onTap: () => _showMoreEmoji(label, moreOptions, onSelect)),
          ],
        ),
      ],
    );
  }

  Future<void> _showMoreEmoji(
      String label, List<String> options, ValueChanged<String> onSelect) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('更多$label',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A3B52))),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: options.map((o) {
                  return GestureDetector(
                    onTap: () {
                      onSelect(o);
                      Navigator.pop(ctx);
                    },
                    child: Text(o, style: const TextStyle(fontSize: 30)),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 撤销栈快照：正文纯文本 + 排版格式
class _Snap {
  final String text;
  final List<TextFormat> formats;
  _Snap(this.text, this.formats);
}
