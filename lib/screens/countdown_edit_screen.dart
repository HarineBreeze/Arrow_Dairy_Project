import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/countdown_event.dart';
import '../widgets/unsaved_guard.dart';

/// 新增 / 编辑倒数日。
class CountdownEditScreen extends StatefulWidget {
  final CountdownEvent? event; // null = 新增
  const CountdownEditScreen({Key? key, this.event}) : super(key: key);

  @override
  State<CountdownEditScreen> createState() => _CountdownEditScreenState();
}

class _CountdownEditScreenState extends State<CountdownEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _iconCtrl;
  DateTime? _target;
  late String _type;
  late RepeatRule _repeat;
  late int _remindBeforeDays;
  bool _saving = false;

  /// 进入页面时的内容快照，用于判断是否有未保存的修改
  String _initial = '';

  /// 当前编辑内容（用于 dirty 比较）
  String _snapshot() => [
        _nameCtrl.text,
        _noteCtrl.text,
        _iconCtrl.text,
        _type,
        _repeat.keyName,
        '$_remindBeforeDays',
        _target?.toIso8601String() ?? '',
      ].join('\u0001');

  bool get _dirty => _snapshot() != _initial;

  /// 主动返回（AppBar 返回键 / 系统返回键）：有改动时弹框，确定即放弃保存返回
  Future<bool> _handleLeave() => confirmLeaveIfDirty(context, dirty: _dirty);

  /// 退出前自动保存（不弹保存成功提示，用户是「返回」而非「保存」）
  Future<bool> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写事件名称')),
      );
      return false;
    }
    if (_target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择事件日')),
      );
      return false;
    }
    if (!mounted) return false;
    setState(() => _saving = true);
    HapticFeedback.selectionClick();
    final e = widget.event ??
        CountdownEvent(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          icon: _iconCtrl.text.trim(),
          name: name,
          target: _target!,
          type: _type,
        );
    e
      ..icon = _iconCtrl.text.trim().isEmpty
          ? CountdownEvent.defaultIconFor(_type)
          : _iconCtrl.text.trim()
      ..name = name
      ..note = _noteCtrl.text.trim()
      ..target = _target!
      ..type = _type
      ..repeat = _repeat
      ..remindBeforeDays = _remindBeforeDays;
    Navigator.pop(context, e);
    return true;
  }

  static const List<String> _quickIcons = CountdownEvent.quickIcons;

  /// 重复规则的说明文案
  String get _repeatHint {
    switch (_repeat) {
      case RepeatRule.none:
        return '到期后停止计数，不再重复';
      case RepeatRule.yearly:
        return '到期后自动进入下一年的同月同日倒计时';
      case RepeatRule.monthly:
        return '到期后自动进入下一个月的同日倒计时（小月自动取当月最后一天）';
      case RepeatRule.weekly:
        return '到期后自动进入下一周的同一天倒计时';
    }
  }

  /// 进入页面时保存的图标原文（可能为空 → 表示用类型默认）
  String _initIcon = '';

  /// 用户本次是否手动点过图标
  bool _iconTouched = false;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _noteCtrl = TextEditingController(text: e?.note ?? '');
    _target = e?.target == null ? null : CountdownEvent.dateOnly(e!.target);
    _type = e?.type ?? '纪念日';
    _repeat = e?.repeat ?? RepeatRule.none;
    _remindBeforeDays = e?.remindBeforeDays ?? 0;
    // 记住进入时的图标（可能为空），用于判断用户是否手动改过图标
    _initIcon = (e?.icon ?? '').trim();
    _iconCtrl = TextEditingController(
        text: _initIcon.isEmpty
            ? CountdownEvent.defaultIconFor(_type)
            : _initIcon);
    _iconTouched = false;
    _initial = _snapshot();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除这个倒数日?'),
        content: const Text('删除后无法恢复'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.pop(context, 'deleted');
  }

  /// 日历选日：支持左右滑动翻页
  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    final picked = await Navigator.push<DateTime>(
      context,
      MaterialPageRoute(
        builder: (_) => _DatePickerPage(initial: _target ?? DateTime.now()),
      ),
    );
    if (picked != null && mounted) setState(() => _target = picked);
  }

  String get _dateTimeLabel {
    if (_target == null) return '';
    final t = _target!;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.year}年${t.month}月${t.day}日  $hh:$mm';
  }

  /// 事件日在未来 → 倒数；在过去 → 正数
  bool get _isCountdown =>
      _target != null && _target!.isAfter(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleLeave,
      child: Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3B6FE0),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(widget.event == null ? '新增倒数日' : '编辑倒数日'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          if (widget.event != null)
            IconButton(
                icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图标：一排 7 个 + 「...」
            _sectionLabel('倒数日图标'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _box(),
              child: Row(
                children: [
                  ..._quickIcons.take(7).map((e) => _iconCell(e)),
                  _iconCell(null, isMore: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 事件名称
            _sectionLabel('事件名称'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: _box(),
              child: TextField(
                controller: _nameCtrl,
                maxLength: 20,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: '纪念日/生日/表白日/节日...',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9AA8BF)),
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 事件备注
            _sectionLabel('事件备注'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: _box(),
              child: TextField(
                controller: _noteCtrl,
                maxLength: 15,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: '写点什么…（选填）',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9AA8BF)),
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 事件日：左侧日期输入框 + 右侧「正数/倒数」标记框（同一行、各自独立）
            _sectionLabel('事件日'),
            // IntrinsicHeight：让两框等高，又不受滚动视图无界高度影响
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                        decoration: _box(),
                        child: Row(
                          children: [
                            Icon(Icons.event_outlined,
                                size: 18,
                                color: _target == null
                                    ? const Color(0xFF9AA8BF)
                                    : const Color(0xFF3B6FE0)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _target == null
                                    ? '选择未来日倒数，过去日正数'
                                    : _dateTimeLabel,
                                style: TextStyle(
                                  fontSize: _target == null ? 13 : 15,
                                  color: _target == null
                                      ? const Color(0xFF9AA8BF)
                                      : const Color(0xFF2A3B52),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 独立的「正数 / 倒数」标记框（两字宽）
                  Container(
                    width: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _target == null
                          ? const Color(0xFFF5F7FB)
                          : (_isCountdown
                              ? const Color(0xFFDCE7FF)
                              : const Color(0xFFFDEEF3)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _target == null ? '--' : (_isCountdown ? '倒数' : '正数'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _target == null
                            ? const Color(0xFFB4C0D2)
                            : (_isCountdown
                                ? const Color(0xFF3B6FE0)
                                : const Color(0xFFD9738F)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 事件类型（单选）
            _sectionLabel('事件类型'),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: _box(),
              child: Row(
                children: CountdownEvent.types
                    .map((t) => _radioTile(
                          label: t,
                          selected: _type == t,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            // 顺序很关键：必须在改 _type 之前判断，
                            // 否则比较的是「新类型的默认图标」，导致永远命中
                            // 或永远不命中。
                            final prevType = _type;
                            final cur = _iconCtrl.text.trim();
                            final oldDefault =
                                CountdownEvent.defaultIconFor(prevType);
                            final newDefault = CountdownEvent.defaultIconFor(t);
                            final followType = !_iconTouched ||
                                cur.isEmpty ||
                                cur == oldDefault ||
                                // 旧数据可能已经是另一类型的默认值
                                cur == newDefault;
                            setState(() {
                              _type = t;
                              if (followType) _iconCtrl.text = newDefault;
                            });
                          },
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),

            // 重复规则（单排胶囊：不重复 / 每年 / 每月 / 每周）
            _sectionLabel('重复规则'),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: _box(),
              child: Row(
                children: [
                  for (final r in RepeatRule.values) ...[
                    _radioTile(
                      label: r.label,
                      selected: _repeat == r,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _repeat = r);
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                _repeatHint,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BF)),
              ),
            ),
            const SizedBox(height: 16),

            // 提前提醒（0 = 当天）
            _sectionLabel('提前提醒'),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: _box(),
              child: Row(
                children: [
                  for (final d in const [0, 1, 3, 7]) ...[
                    _radioTile(
                      label: d == 0 ? '当天' : '提前 $d 天',
                      selected: _remindBeforeDays == d,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _remindBeforeDays = d);
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                _remindBeforeDays == 0
                    ? '在事件日当天的设定时间提醒'
                    : '在事件日前 $_remindBeforeDays 天的设定时间提醒',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BF)),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF3B6FE0)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('完成', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _radioTile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFDCE7FF) : const Color(0xFFF5F7FB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFF3B6FE0) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 16,
                color:
                    selected ? const Color(0xFF3B6FE0) : const Color(0xFF9AA8BF),
              ),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected
                          ? const Color(0xFF3B6FE0)
                          : const Color(0xFF2A3B52))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF9AA8BF),
                fontWeight: FontWeight.w600)),
      );

  BoxDecoration _box() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      );

  Widget _iconCell(String? icon, {bool isMore = false}) {
    final cur = _iconCtrl.text.trim().isEmpty
        ? CountdownEvent.defaultIconFor(_type)
        : _iconCtrl.text.trim().characters.first;
    final sel = !isMore && cur == icon;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          if (isMore) {
            _showMoreIcons();
          } else {
            _iconCtrl.text = icon!;
            _iconTouched = true;
            setState(() {});
          }
        },
        child: Container(
          height: 40,
          margin: const EdgeInsets.only(right: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel
                ? const Color(0xFFDCE7FF)
                : (isMore ? const Color(0xFFF0F4FB) : const Color(0xFFF5F7FB)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? const Color(0xFF3B6FE0) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: isMore
              ? const Icon(Icons.more_horiz,
                  size: 22, color: Color(0xFF5A6B82))
              : Text(icon!, style: const TextStyle(fontSize: 22)),
        ),
      ),
    );
  }

  Future<void> _showMoreIcons() async {
    final tmpCtrl = TextEditingController(text: _iconCtrl.text.trim());
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择图标',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _quickIcons.map((e) {
                    final sel = tmpCtrl.text.trim() == e;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setSheet(() => tmpCtrl.text = e);
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFFDCE7FF)
                              : const Color(0xFFF5F7FB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: sel
                                ? const Color(0xFF3B6FE0)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 24)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tmpCtrl,
                  maxLength: 4,
                  decoration: const InputDecoration(
                    labelText: '自定义 emoji',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setSheet(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('取消')),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _iconCtrl.text = tmpCtrl.text.trim();
                          _iconTouched = true;
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 日历选日页（支持左右滑动翻页） ====================

class _DatePickerPage extends StatefulWidget {
  final DateTime initial;
  const _DatePickerPage({required this.initial});

  @override
  State<_DatePickerPage> createState() => _DatePickerPageState();
}

class _DatePickerPageState extends State<_DatePickerPage> {
  late DateTime _month; // 每月 1 日
  late DateTime _selected; // 仅日期
  late TimeOfDay _time;

  @override
  void initState() {
    super.initState();
    _selected = CountdownEvent.dateOnly(widget.initial);
    _month = DateTime(_selected.year, _selected.month, 1);
    _time = TimeOfDay(
        hour: widget.initial.hour, minute: widget.initial.minute);
  }

  /// 合并日期与时分
  DateTime get _result => DateTime(_selected.year, _selected.month,
      _selected.day, _time.hour, _time.minute);

  Future<void> _pickTime() async {
    HapticFeedback.selectionClick();
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null && mounted) setState(() => _time = t);
  }

  void _shift(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta, 1));
  }

  /// 按年翻页（保持当前月份）
  void _shiftYear(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _month = DateTime(
        _month.year + delta, _month.month, 1));
  }

  @override
  Widget build(BuildContext context) {
    final year = _month.year;
    final month = _month.month;
    final firstWeekday = DateTime(year, month, 1).weekday;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final today = DateTime.now();

    final cells = <Widget>[];
    for (int i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final isSel = date.year == _selected.year &&
          date.month == _selected.month &&
          date.day == _selected.day;
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      cells.add(GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selected = date);
        },
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSel
                  ? const Color(0xFF3B6FE0)
                  : (isToday ? const Color(0xFFDCE7FF) : Colors.transparent),
              shape: BoxShape.circle,
            ),
            child: Text('$day',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSel || isToday
                        ? FontWeight.w700
                        : FontWeight.normal,
                    color: isSel ? Colors.white : const Color(0xFF2A3B52))),
          ),
        ),
      ));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF3B6FE0),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('选择事件日'),
      ),
      body: Column(
        children: [
          // 月份切换（◀◀ / ▶▶ 按年翻页，◀ / ▶ 按月翻页）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_double_arrow_left,
                      size: 18, color: Color(0xFF8A99B3)),
                  tooltip: '上一年',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 36),
                  onPressed: () => _shiftYear(-1),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Color(0xFF5A6B82)),
                  tooltip: '上一月',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 36),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Center(
                    child: Text('${_month.year}年${_month.month}月',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2A3B52))),
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.chevron_right, color: Color(0xFF5A6B82)),
                  tooltip: '下一月',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 36),
                  onPressed: () => _shift(1),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_double_arrow_right,
                      size: 18, color: Color(0xFF8A99B3)),
                  tooltip: '下一年',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 36),
                  onPressed: () => _shiftYear(1),
                ),
              ],
            ),
          ),
          // 时间选择（小时:分钟）
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.access_time,
                    size: 18, color: Color(0xFF9AA8BF)),
                const SizedBox(width: 8),
                const Text('时间',
                    style: TextStyle(fontSize: 14, color: Color(0xFF5A6B82))),
                const Spacer(),
                GestureDetector(
                  onTap: _pickTime,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4FB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B6FE0)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: const ['一', '二', '三', '四', '五', '六', '日']
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w,
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF9AA8BF))),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          // 左右滑动翻页
          GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -200) _shift(1);
              if (v > 200) _shift(-1);
            },
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              crossAxisCount: 7,
              childAspectRatio: 1.1,
              children: cells,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _result),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                    '确定 ${_selected.year}-${_selected.month.toString().padLeft(2, '0')}-${_selected.day.toString().padLeft(2, '0')} '
                    '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
