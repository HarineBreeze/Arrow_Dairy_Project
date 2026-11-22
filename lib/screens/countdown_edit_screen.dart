import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';
import '../models/countdown_event.dart';
import '../models/user_profile.dart';
import '../services/user_storage.dart';
import '../services/reward_service.dart';
import '../services/trash_storage.dart';
import '../utils/app_toast.dart';
import '../widgets/identity_badge.dart';
import '../widgets/unsaved_guard.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';
import '../widgets/save_done_button.dart';
import '../widgets/save_bar.dart';
import '../widgets/wheel_picker.dart';
import '../widgets/entry_icon.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
import '../utils/app_sheet.dart';
/// 新增 / 编辑事件。
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

  /// v4.9.27：智能回车——单行输入回车跳下一栏，末栏收起键盘。
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _noteFocus = FocusNode();
  DateTime? _target;
  late String _type;
  late RepeatRule _repeat;
  late int _remindBeforeDays;
  bool _saving = false;

  /// 「提醒时间」VIP 门槛：是否有内测版/VIP/终身VIP 身份。
  /// null = 尚未从磁盘读出（先按无权限渲染，读出后再刷新）。
  bool? _hasVip;
  /// 本次进入时已有的提醒值（>0 表示曾设置过；VIP 失去后用于区分「不提示」）
  late int _initialRemindDays;


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
    // 保留已有的时分：日期与时间现在是两个独立模块，
    // 若这里只用 dateOnly 会把已设的提醒时间清零（时间行永远显示 00:00）
    _target = e?.target;
    _type = e?.type ?? '纪念日';
    _repeat = e?.repeat ?? RepeatRule.none;
    _remindBeforeDays = e?.remindBeforeDays ?? 0;
    _initialRemindDays = _remindBeforeDays;
    // 异步读取档案判断提醒时间的 VIP 权限
    UserStorage.load().then((p) {
      if (!mounted) return;
      setState(() {
        _hasVip = RewardService.hasVipPrivilege(p);
        _ownedVipBadge = _pickVipBadge(p);
      });
    }).catchError((_) {
      if (mounted) setState(() => _hasVip = false);
    });
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
    _nameFocus.dispose();
    _noteFocus.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除这个事件?'),
        content: const Text('删除后可在「回收站」保留 7 天'),
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
                child: const Text('删除', style: TextStyle(color: Color(0xFFCB5C50)))),
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

  /// 选日期：只弹「年 / 月 / 日」滚轮
  Future<void> _pickDate() async {
    Haptics.light();
    final base = _target ?? DateTime.now();
    final picked = await showWheelDatePicker(
      context,
      initial: base,
      title: '选择日期',
    );
    if (picked == null || !mounted) return;
    // 只改年月日，时分沿用已选值（没选过就补当前时间）
    setState(() => _target = DateTime(picked.year, picked.month, picked.day,
        base.hour, base.minute));
  }

  /// 选具体时间：只弹「时 / 分」滚轮
  Future<void> _pickTime() async {
    Haptics.light();
    final base = _target ?? DateTime.now();
    final picked = await showWheelTimePicker(
      context,
      initial: TimeOfDay(hour: base.hour, minute: base.minute),
      title: '选择时间',
    );
    if (picked == null || !mounted) return;
    setState(() => _target = DateTime(
        base.year, base.month, base.day, picked.hour, picked.minute));
  }

  /// 日期部分的展示文案（不含时分）
  String get _dateLabel {
    if (_target == null) return '';
    final t = _target!;
    return '${t.year}年${t.month}月${t.day}日';
  }

  /// 时间部分的展示文案（24 小时制补零）
  String get _timeLabel {
    if (_target == null) return '';
    final t = _target!;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// 事件日在未来 → 倒数；在过去 → 正数
  bool get _isCountdown =>
      _target != null && _target!.isAfter(DateTime.now());

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return WillPopScope(
      onWillPop: _handleLeave,
      child: Scaffold(
      backgroundColor: AppPalette.c(0xFFF5FAF7),
      appBar: AppBar(
        // v4.9.31：与事件主页顶栏同色同高
        backgroundColor: AppPalette.c(0xB33E8E6D),
        toolbarHeight: 48,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(widget.event == null ? '新增事件' : '编辑事件'),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          if (widget.event != null)
            IconButton(
                icon: const AppIcon(AppIcons.delete), onPressed: _delete),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图标：一排 7 个 + 「...」（v4.9.43：标题移除，图标直接置顶）
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
                focusNode: _nameFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _noteFocus.requestFocus(),
                maxLength: 20,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: '纪念日/生日/表白日/节日...',
                  hintStyle: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
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
                focusNode: _noteFocus,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                maxLength: 15,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: '写点什么…（选填）',
                  hintStyle: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // —— 事件日：一行三块 ——
            // 事件日期 : 具体时间 : 正数/倒数 = 2 : 2 : 1（= 五分之二 / 五分之二 / 五分之一）。
            // 三块各自独立：前两块分别点开「日期滚轮」「时间滚轮」，
            // 第三块只是状态提示（未来=倒数、过去=正数），不可点。
            _sectionLabel('事件日期'),
            Row(
              children: [
                // 第 1 块：日期
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _pickDate,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _box(),
                      child: Row(
                        children: [
                          AppIcon(AppIcons.event,
                              size: 17,
                              color: _target == null
                                  ? AppPalette.c(0xFF8FA09A)
                                  : AppPalette.c(0xFF3E8E6D)),
                          const SizedBox(width: 6),
                          Expanded(
                            // 列宽只有五分之二，日期文字必须压缩显示，
                            // 否则「2030年5月1日」在窄屏会把图标挤出去
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _target == null ? '选择日期' : _dateLabel,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: _target == null ? 13 : 14,
                                  color: _target == null
                                      ? AppPalette.c(0xFF8FA09A)
                                      : AppPalette.c(0xFF24382F),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 第 2 块：具体时间
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _pickTime,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: _box(),
                      child: Row(
                        children: [
                          AppIcon(AppIcons.clock,
                              size: 17,
                              color: _target == null
                                  ? AppPalette.c(0xFF8FA09A)
                                  : AppPalette.c(0xFF3E8E6D)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _target == null ? '选择时间' : _timeLabel,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: _target == null ? 13 : 14,
                                  fontWeight: _target == null
                                      ? FontWeight.normal
                                      : FontWeight.w600,
                                  color: _target == null
                                      ? AppPalette.c(0xFF8FA09A)
                                      : AppPalette.c(0xFF24382F),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 第 3 块：正数 / 倒数（状态提示，不可点）
                Expanded(
                  flex: 1,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      // v4.9.25：「正数 / 倒数」不再用绿/粉特殊底纹标示，统一普通底
                      color: AppPalette.c(0xFFF5FAF7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _target == null
                            ? '--'
                            : (_isCountdown ? '倒数' : '正数'),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _target == null
                              ? AppPalette.c(0xFFB2C4BA)
                              : AppPalette.c(0xFF24382F),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // v4.9.26：三组单选收进「当前值 + 右箭头」行，点整行弹底部选择层。
            // 事件类型
            _selectRow(
              label: '事件类型',
              value: _type,
              onTap: () => _pickOptionSheet(
                options: CountdownEvent.types,
                current: _type,
                onSelected: _applyType,
              ),
            ),
            const SizedBox(height: 16),

            // 重复规则（不重复 / 每年 / 每月 / 每周）
            _selectRow(
              label: '重复规则',
              value: _repeat.label,
              onTap: () => _pickOptionSheet(
                options: RepeatRule.values.map((r) => r.label).toList(),
                current: _repeat.label,
                onSelected: (label) => setState(() => _repeat = RepeatRule.values
                    .firstWhere((r) => r.label == label)),
              ),
            ),
            const SizedBox(height: 16),

            // 提醒时间（0 = 当天）：VIP 专属，右上角身份牌角标
            _buildRemindRow(),
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


  /// v4.9.26：档案页同款「标签 — 当前值 ›」行，点整行弹底部选择层。
  /// [labelTrailing] 可在标题文字后紧跟一个小部件（如 VIP 身份牌角标）。
  Widget _selectRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool dimmed = false,
    Widget? labelTrailing,
  }) {
    final labelColor = dimmed
        ? AppPalette.c(0xFFB2C2BA)
        : AppPalette.c(0xFF24382F);
    final valueColor = dimmed
        ? AppPalette.c(0xFFB2C2BA)
        : AppPalette.c(0xFF647A70);
    return Container(
      decoration: _box(),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Haptics.light();
          onTap();
        },
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                SizedBox(
                  width: labelTrailing != null ? 112 : 76,
                  child: Row(
                    children: [
                      Text(label,
                          style: TextStyle(fontSize: 15, color: labelColor)),
                      if (labelTrailing != null) ...[
                        const SizedBox(width: 4),
                        Flexible(child: labelTrailing),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: valueColor),
                  ),
                ),
                const SizedBox(width: 6),
                AppIcon(AppIcons.chevR,
                    size: 16, color: AppPalette.c(0xFFC6D6CD)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 到期提醒行：VIP 身份门槛 + 标题后紧跟身份牌角标。
  Widget _buildRemindRow() {
    final canEdit = _hasVip == true;
    final wasSet = _initialRemindDays > 0; // VIP 失去前已设过提醒
    final value = _remindBeforeDays == 0
        ? '当天'
        : '提前 $_remindBeforeDays 天';

    // 角标：有权限显示用户自己的 VIP 类牌，无权限显示 VIP 牌作「专属」提示
    final badgeId = canEdit ? _vipBadgeId : UserProfile.badgeVip;

    return _selectRow(
      label: '到期提醒',
      labelTrailing: Transform.scale(
        scale: 0.85,
        child: IdentityBadge(badge: badgeId),
      ),
      value: canEdit
          ? value
          : (wasSet ? value : '未解锁'),
      dimmed: !canEdit,
      onTap: () {
        if (canEdit) {
          _pickOptionSheet(
            options: const [0, 1, 3, 7]
                .map((d) => d == 0 ? '当天' : '提前 $d 天')
                .toList(),
            current: _remindBeforeDays == 0
                ? '当天'
                : '提前 $_remindBeforeDays 天',
            onSelected: (label) => setState(() => _remindBeforeDays =
                label == '当天'
                    ? 0
                    : int.parse(label.replaceAll(RegExp(r'[^0-9]'), ''))),
          );
        } else {
          // v5.0.0：非 VIP 点击统一提示需 VIP，含「VIP 期间已设过提醒时间」
          // 的情况——此前 wasSet 分支直接 return 导致提示语丢失。
          // 已设的提醒时间仍保持不变、不可修改，仅补回提示。
          AppToast.show(
              context, '到期提醒是VIP专属权益，请充值后再尝试～');
        }
      },
    );
  }

  /// 当前拥有的 VIP 类身份牌 id（用于角标展示）
  String get _vipBadgeId {
    // 依次取终身VIP > VIP > 内测版，与权益强度一致
    return _ownedVipBadge ?? UserProfile.badgeVip;
  }

  String? _ownedVipBadge;

  /// 取用户拥有的 VIP 类身份牌 id（终身VIP > VIP > 内测版），用于角标展示
  static String? _pickVipBadge(UserProfile p) {
    if (p.ownedBadges.contains(UserProfile.badgeVipForever) ||
        p.badge == UserProfile.badgeVipForever) {
      return UserProfile.badgeVipForever;
    }
    if (p.ownedBadges.contains(UserProfile.badgeVip) ||
        p.badge == UserProfile.badgeVip ||
        p.vipCardActive) {
      return UserProfile.badgeVip;
    }
    if (p.ownedBadges.contains(UserProfile.badgeBeta) ||
        p.badge == UserProfile.badgeBeta) {
      return UserProfile.badgeBeta;
    }
    return null;
  }

  /// 通用底部选择层：标题 + 选项列表 + 当前项打勾（档案页性别弹层同款）。
  Future<void> _pickOptionSheet({
    required List<String> options,
    required String current,
    required ValueChanged<String> onSelected,
  }) async {
    final picked = await AppSheet.show<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // v4.9.46：移除抽屉标题「选择$title」，只保留选项列表
            for (final opt in options)
              InkWell(
                onTap: () => Navigator.pop(ctx, opt),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Text(opt,
                          style: TextStyle(
                              fontSize: 14, color: AppPalette.c(0xFF647A70))),
                      const Spacer(),
                      if (opt == current)
                        AppIcon(AppIcons.check,
                            size: 20, color: AppPalette.c(0xFF3E8E6D)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    onSelected(picked);
  }

  /// 应用事件类型：保留原「切换类型时图标跟随」判定逻辑。
  void _applyType(String t) {
    // 顺序很关键：必须在改 _type 之前判断，否则比较的是新类型的默认图标。
    final prevType = _type;
    final cur = _iconCtrl.text.trim();
    final oldDefault = CountdownEvent.defaultIconFor(prevType);
    final newDefault = CountdownEvent.defaultIconFor(t);
    final followType = !_iconTouched ||
        cur.isEmpty ||
        cur == oldDefault ||
        cur == newDefault;
    setState(() {
      _type = t;
      if (followType) _iconCtrl.text = newDefault;
    });
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                color: AppPalette.c(0xFF8FA09A),
                fontWeight: FontWeight.w600)),
      );

  BoxDecoration _box() => BoxDecoration(
        color: AppPalette.c(0xFFFFFFFF),
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
            // 图标底纹移除：未选中透明，选中保留浅绿强调
            color: sel ? AppPalette.c(0xFFE4F2EB) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: sel ? AppPalette.c(0xFF3E8E6D) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: isMore
              ? AppIcon(AppIcons.moreH,
                  size: 22, color: AppPalette.c(0xFF647A70))
              : EntryIcon(icon!, size: 22),
        ),
      ),
    );
  }

  Future<void> _showMoreIcons() async {
    final tmpCtrl = TextEditingController(text: _iconCtrl.text.trim());
    await AppSheet.show(
      context,
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
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
                          // 图标底纹移除：未选中透明，选中保留浅绿强调
                          color: sel
                              ? AppPalette.c(0xFFE4F2EB)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: sel
                                ? AppPalette.c(0xFF3E8E6D)
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: EntryIcon(e, size: 24),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: tmpCtrl,
                  textInputAction: TextInputAction.done,
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
