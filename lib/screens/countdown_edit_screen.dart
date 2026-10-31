import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/countdown_event.dart';
import '../services/trash_storage.dart';
import '../widgets/unsaved_guard.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';
import '../widgets/save_done_button.dart';
import '../widgets/save_bar.dart';
import '../widgets/wheel_picker.dart';

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


  final GlobalKey<SaveDoneButtonState> _doneKey =
      GlobalKey<SaveDoneButtonState>();

  /// 保存后待返回的事件对象（动画播完才 pop）
  CountdownEvent? _pending;


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
  /// 同步校验：返回 null 表示可以保存，返回文案则提示并中止。
  /// 抽出来是为了让「点击 → 收缩动画」立刻开始，不必等异步落盘。
  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return '请填写事件名称';
    if (_target == null) return '请选择事件日';
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    Haptics.light();
    final name = _nameCtrl.text.trim();
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
    // 返回交给完成动画播完后执行（见 onDone）
    _pending = e;
    if (!mounted) return;
    _doneKey.currentState?.finish();
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
        content: const Text('删除后可在「回收站」保留 7 天，期间可还原'),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除', style: TextStyle(color: Colors.red))),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Haptics.medium();
      // 编辑页删除同样入回收站
      await TrashStorage.addEvent(widget.event!);
      if (!mounted) return;
      Navigator.pop(context, 'deleted');
    }
  }

  /// 日历选日：支持左右滑动翻页
  Future<void> _pickDate() async {
    Haptics.light();
    final picked = await showWheelDateTimePicker(
        context, initial: _target ?? DateTime.now());
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
                            Haptics.light();
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
                        Haptics.light();
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
                        Haptics.light();
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: _buildSaveBar(),
        ),
      ),
    ),
    );
  }

  /// 单选项：四等分排列。
  /// 选项文字长度不一（「每年」vs「提前 7 天」），若图标与文字并排，
  /// 窄屏下按钮宽度不足会把文字挤出边框。这里改为「图标在上、文字在下」，
  /// 并让文字按需缩放 + 省略，保证任何机型都不出框。

  /// 保存栏：点完成后取消按钮淡出让出整行，完成按钮收缩成居中圆形，
  /// 打勾描边 + 粒子迸发，停留片刻再保存返回。
  Widget _buildSaveBar() {
    return SaveBar(
      saveKey: _doneKey,
      color: Theme.of(context).colorScheme.primary,
      onCancel: _saving ? null : () => Navigator.pop(context),
      validate: _validate,
      onSave: _save,
      onDone: () {
        if (mounted) Navigator.pop(context, _pending);
      },
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
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFDCE7FF) : const Color(0xFFF5F7FB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0xFF3B6FE0) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 15,
                color: selected
                    ? const Color(0xFF3B6FE0)
                    : const Color(0xFF9AA8BF),
              ),
              const SizedBox(height: 3),
              // 文字宽度不超过胶囊内宽，超长时整体缩小（不会撑破边框）
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                      color: selected
                          ? const Color(0xFF3B6FE0)
                          : const Color(0xFF2A3B52),
                    ),
                  ),
                ),
              ),
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
          Haptics.light();
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
                        Haptics.light();
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
                    Pressable(
                      enabled: true,
                      child: TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消')),
                    ),
                    const SizedBox(width: 8),
                    Pressable(
                      enabled: true,
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _iconCtrl.text = tmpCtrl.text.trim();
                            _iconTouched = true;
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('确定'),
                      ),
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
