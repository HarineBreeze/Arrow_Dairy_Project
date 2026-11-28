import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/asset.dart';
import '../models/user_profile.dart';
import '../services/trash_storage.dart';
import '../services/user_storage.dart';
import '../services/reward_service.dart';
import '../widgets/identity_badge.dart';
import '../widgets/unsaved_guard.dart';
import '../utils/haptics.dart';
import '../utils/app_toast.dart';
import '../widgets/pressable.dart';
import '../widgets/save_done_button.dart';
import '../widgets/save_bar.dart';
import '../widgets/entry_icon.dart';
import '../widgets/wheel_picker.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
import '../utils/app_sheet.dart';
/// 新增 / 编辑资产卡片。
class AssetEditScreen extends StatefulWidget {
  final Asset? asset; // null = 新增

  /// 测试注入：档案加载（默认 UserStorage.load）
  static Future<UserProfile> Function()? loadProfileOverride;

  const AssetEditScreen({Key? key, this.asset}) : super(key: key);

  @override
  State<AssetEditScreen> createState() => _AssetEditScreenState();
}

class _AssetEditScreenState extends State<AssetEditScreen> {
  late final TextEditingController _noteCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _iconCtrl;
  late String _type;
  late String _owner;
  DateTime? _repayDate;
  bool _isVip = false; // 还款时间为权益功能（v5.0.21）

  final GlobalKey<SaveDoneButtonState> _doneKey =
      GlobalKey<SaveDoneButtonState>();

  /// 保存后待返回的资产对象（动画播完才 pop）
  Asset? _pending;

  /// 进入页面时的内容快照，用于判断是否有未保存的修改
  String _initial = '';

  /// 当前编辑内容（用于 dirty 比较）
  String _snapshot() => [
        _noteCtrl.text,
        _amountCtrl.text,
        _iconCtrl.text,
        _type,
        _owner,
        _repayDate?.millisecondsSinceEpoch.toString() ?? '',
      ].join('\u0001');

  bool get _dirty => _snapshot() != _initial;

  /// 主动返回（AppBar 返回键 / 系统返回键）：有改动时弹框，确定即放弃保存返回
  Future<bool> _handleLeave() => confirmLeaveIfDirty(context, dirty: _dirty);

  static const List<String> _quickIcons = [
    '🏦', '💸', '📈', '🪙', '📊', '💳', '💰',
    '🇨🇳', '🏠', '🚗', '📱', '💼', '🎁', '🐷', '🌙', '🧾',
  ];

  bool get _isLiability =>
      _type == '信用卡' || _type == '欠款' || _type == '账单';

  @override
  void initState() {
    super.initState();
    final a = widget.asset;
    _noteCtrl = TextEditingController(text: a?.note ?? '');
    _amountCtrl = TextEditingController(
      text: a == null ? '' : a.amount.toStringAsFixed(a.amount.truncateToDouble() == a.amount ? 0 : 2),
    );
    _iconCtrl = TextEditingController(text: a?.icon ?? Asset.defaultIconFor(a?.type ?? '银行储蓄'));
    _type = a?.type ?? '银行储蓄';
    _owner = a?.owner ?? '本人';
    _repayDate = a?.repayDate;
    _initial = _snapshot();
    _loadVip();
  }

  /// 还款时间属权益功能，读取档案判断 VIP 身份（失败按未解锁处理）。
  Future<void> _loadVip() async {
    try {
      final profile = await (AssetEditScreen.loadProfileOverride ?? UserStorage.load)();
      final vip = RewardService.hasVipPrivilege(profile);
      if (mounted && vip != _isVip) setState(() => _isVip = vip);
    } catch (_) {}
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _amountCtrl.dispose();
    _iconCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除这张资产卡片?'),
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
              child: const Text('删除', style: TextStyle(color: Color(0xFFCB5C50))),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Haptics.medium();
      // 编辑页删除同样入回收站（与列表长按删除保持一致）
      await TrashStorage.addAsset(widget.asset!);
      if (!mounted) return;
      Navigator.pop(context, 'deleted');
    }
  }

  /// 同步校验：返回 null 表示可以保存，返回文案则提示并中止。
  ///
  /// 金额是**必填项**：空着点完成不再静默存成 0，而是明确提示去填。
  /// 空值与填了乱码分成两句提示，「没填」和「填错了」用户的下一步动作不同，
  /// 混成一句「请输入正确的金额」会让没填的人以为自己填错了。
  String? _validate() {
    final raw = _amountCtrl.text.trim();
    if (raw.isEmpty) return _isLiability ? '请输入欠款金额' : '请输入资产金额';
    final v = double.tryParse(raw);
    if (v == null) return '请输入正确的金额';
    if (v == 0) return '金额不能为 0';
    return null;
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    Haptics.light();
    final a = widget.asset ??
        Asset(id: DateTime.now().microsecondsSinceEpoch.toString());
    a.icon = _iconCtrl.text.trim().isEmpty
        ? Asset.defaultIconFor(_type)
        : _iconCtrl.text.trim().characters.first;
    a.note = _noteCtrl.text.trim();
    a.type = _type;
    a.owner = _owner;
    // 负资产 + 有 VIP 才保留还款时间；正资产/未解锁一律清空，避免脏数据
    a.repayDate = (_isLiability && _isVip) ? _repayDate : null;
    // 负债类型强制为负数展示语义：存正数，由类型决定正负
    a.amount = amount.abs() * (_isLiability ? -1 : 1);
    // 返回交给完成动画播完后执行（见 onDone），这里只暂存结果
    _pending = a;
    if (!mounted) return;
    _doneKey.currentState?.finish();
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return WillPopScope(
      onWillPop: _handleLeave,
      child: Scaffold(
      backgroundColor: AppPalette.c(0xFFF5FAF7),
      appBar: AppBar(
        toolbarHeight: 48, // v4.9.31：与资产主页顶栏同高
        backgroundColor: AppPalette.c(0xB33E8E6D), // v4.9.31：与资产主页顶栏同色
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(widget.asset == null ? '新增资产' : '编辑资产'),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
        // 右上角：删除当前资产卡片（仅编辑已有卡片时）
        actions: [
          if (widget.asset != null)
            IconButton(
              icon: const AppIcon(AppIcons.delete),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 资产图标：一排 7 个快捷图标 + 「...」更多（v4.9.43：标题移除）
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

            // 资产类型：右箭头打开抽屉，在抽屉内选择（v4.9.43）
            // v5.0.19：移除「资产类型」节标题，行内值已能自解释
            Pressable(
              enabled: true,
              child: GestureDetector(
                onTap: _pickTypeSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: _box(),
                  height: 48,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(_type,
                            style: TextStyle(
                                fontSize: 15, color: AppPalette.c(0xFF24382F))),
                      ),
                      AppIcon(AppIcons.chevR,
                          size: 18, color: AppPalette.c(0xFF647A70)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // v5.0.23：资产备注 / 资产金额改为档案页昵称行同款
            // ——白卡内左侧 76px 标签 + 右侧无边框输入，与档案 _buildFieldLabel 对齐
            _buildLabeledField(
              label: '资产备注',
              field: TextField(
                controller: _noteCtrl,
                maxLength: 15,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: '工资卡、应急金、养老金...',
                  hintStyle:
                      TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 资产金额（必填）
            // v5.0.23：改为档案昵称行同款，提示语统一为「输入金额」
            // 金额输入移除 ¥ 金钱符号、取消加粗，字号与正文统一 15。
            _buildLabeledField(
              label: '资产金额',
              field: TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: '输入金额',
                  hintStyle:
                      TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 资产归属（v5.0.22 由「资产所有人」更名；选项型，默认「本人」）
            Pressable(
              enabled: true,
              child: GestureDetector(
                onTap: _pickOwnerSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: _box(),
                  height: 48,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 76,
                        child: Text('资产归属',
                            style: TextStyle(
                                fontSize: 15,
                                color: AppPalette.c(0xFF24382F))),
                      ),
                      Expanded(
                        child: Text(_owner,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 14, color: AppPalette.c(0xFF647A70))),
                      ),
                      const SizedBox(width: 6),
                      AppIcon(AppIcons.chevR,
                          size: 18, color: AppPalette.c(0xFF647A70)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 还款时间（v5.0.21，权益功能 + 仅负资产生效）
            // v5.0.22：标题不换行、VIP 标识缩小、移除「选择还款日期」占位
            Pressable(
              enabled: true,
              child: GestureDetector(
                onTap: _onRepayTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: _box(),
                  height: 48,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 112,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('还款时间',
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                    fontSize: 15,
                                    color: _repayEnabled
                                        ? AppPalette.c(0xFF24382F)
                                        : AppPalette.c(0xFFC2D4C9))),
                            // v5.0.23：VIP 牌与其它点位一致大小（0.85），
                            // 且无论是否拥有权益都常驻显示，不再随 _isVip 消失
                            const SizedBox(width: 4),
                            const IdentityBadge(
                                badge: UserProfile.badgeVip, scale: 0.85),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          _repayEnabled && _repayDate != null
                              ? '${_repayDate!.year}/${_repayDate!.month}/${_repayDate!.day}'
                              : '',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              color: _repayEnabled
                                  ? AppPalette.c(0xFF647A70)
                                  : AppPalette.c(0xFFC2D4C9)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      AppIcon(AppIcons.chevR,
                          size: 18,
                          color: _repayEnabled
                              ? AppPalette.c(0xFF647A70)
                              : AppPalette.c(0xFFC2D4C9)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],
        ),
      ),
      // v4.9.39：保存栏改「取消 + 完成」吸底双按钮，与事件/物品页一致
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: _buildSaveBar(),
        ),
      ),
    ),
    );
  }

  /// 保存栏：点完成后取消淡出、完成收缩打勾 + 粒子，播完再保存返回。
  Widget _buildSaveBar() {
    return SaveBar(
      saveKey: _doneKey,
      color: AppPalette.c(0xFF3E8E6D),
      onCancel: () => Navigator.pop(context),
      validate: _validate,
      onSave: _save,
      onDone: () {
        if (mounted) Navigator.pop(context, _pending);
      },
    );
  }

  /// 快捷图标格（含「...」更多入口）。选中时高亮底纹 + 蓝色描边。
  Widget _iconCell(String? icon, {bool isMore = false}) {
    final iconPreview = _iconCtrl.text.trim().isEmpty
        ? Asset.defaultIconFor(_type)
        : _iconCtrl.text.trim().characters.first;
    final sel = !isMore && iconPreview == icon;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Haptics.light();
          if (isMore) {
            _showMoreIcons();
          } else {
            _iconCtrl.text = icon!;
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
          ),
          child: isMore
              ? AppIcon(AppIcons.moreH,
                  size: 22, color: AppPalette.c(0xFF647A70))
              : EntryIcon(icon!, size: 22),
        ),
      ),
    );
  }

  /// 还款时间是否可用：需同时满足「负资产」+「VIP 权益」
  bool get _repayEnabled => _isLiability && _isVip;

  /// 还款时间点击：正资产提示换类型、未解锁提示 VIP、否则开滚轮
  Future<void> _onRepayTap() async {
    Haptics.light();
    if (!_isLiability) {
      AppToast.show(context, '选择负资产时可用');
      return;
    }
    if (!_isVip) {
      // 规范 5 统一口径：x是VIP专属权益，请充值后再尝试～
      AppToast.show(context, '还款时间是VIP专属权益，请充值后再尝试～');
      return;
    }
    final picked = await showWheelDatePicker(
      context,
      initial: _repayDate ?? DateTime.now(),
      minimum: DateTime.now(),
      maximum: DateTime.now().add(const Duration(days: 365 * 30)),
      title: '还款时间',
    );
    if (picked != null && mounted) {
      setState(() => _repayDate = picked);
      // v5.0.23：设置成功提示（与提醒链路的「年/月/日」文案一致）
      AppToast.show(
        context,
        '设置成功，阿尤会在${picked.year}年${picked.month}月${picked.day}日提醒哦～',
      );
    }
  }

  /// 资产所有人：选项型抽屉（无标题 + 打勾 + 箭头左侧显示当前值）
  Future<void> _pickOwnerSheet() async {
    Haptics.light();
    await AppSheet.show(
      context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.c(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final o in Asset.owners)
                  InkWell(
                    onTap: () {
                      Haptics.light();
                      setState(() => _owner = o);
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(o,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: o == _owner
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: o == _owner
                                        ? AppPalette.c(0xFF3E8E6D)
                                        : AppPalette.c(0xFF24382F))),
                          ),
                          if (o == _owner)
                            AppIcon(AppIcons.check,
                                size: 16, color: AppPalette.c(0xFF3E8E6D)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// v4.9.43：资产类型 → 右箭头打开的抽屉选择（沿用 _pickOptionSheet 同款样式）
  Future<void> _pickTypeSheet() async {
    Haptics.light();
    await AppSheet.show(
      context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppPalette.c(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (final t in Asset.types)
                      InkWell(
                        onTap: () {
                          Haptics.light();
                          setState(() {
                            _type = t;
                            // v5.0.21：切到正资产时清空还款时间（负资产专属）
                            final nowLiability = t == '信用卡' ||
                                t == '欠款' ||
                                t == '账单';
                            if (!nowLiability) _repayDate = null;
                            // 未手动改过图标时跟随类型换默认图标
                            if (Asset.defaultIconFor(t) !=
                                    _iconCtrl.text.trim() &&
                                Asset.types.any((x) =>
                                    Asset.defaultIconFor(x) ==
                                    _iconCtrl.text.trim())) {
                              _iconCtrl.text = Asset.defaultIconFor(t);
                            }
                          });
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          // v5.0.20：移除选中项底纹，与其它选项型抽屉一致——
                          // 选中态只用加粗/主色文字 + 右侧勾选图标表达，不再铺底色
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(t,
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: t == _type
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: t == _type
                                            ? AppPalette.c(0xFF3E8E6D)
                                            : AppPalette.c(0xFF24382F))),
                              ),
                              if (t == _type)
                                AppIcon(AppIcons.check,
                                    size: 16, color: AppPalette.c(0xFF3E8E6D)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 「...」→ 全部图标 + 自定义 emoji
  Future<void> _showMoreIcons() async {
    final tmpCtrl = TextEditingController(text: _iconCtrl.text.trim());
    await AppSheet.show(
      context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('选择图标',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _quickIcons.map((e) {
                        final sel = tmpCtrl.text.trim() == e;
                        return GestureDetector(
                          onTap: () {
                            Haptics.light();
                            setSheetState(() => tmpCtrl.text = e);
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
                            ),
                            child: EntryIcon(e, size: 24),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: tmpCtrl,
                      maxLength: 4,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        labelText: '自定义 emoji',
                        hintText: '如 🐷、🚀',
                        hintStyle:
                            TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
                        counterText: '',
                        isDense: true,
                        // 与页面其它输入框统一：浅底填充替代描边
                        filled: true,
                        fillColor: AppPalette.c(0xFFF5FAF7),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: Pressable(
                        enabled: true,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            primary: AppPalette.c(0xFF3E8E6D),
                            onPrimary: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            final v = tmpCtrl.text.trim();
                            Navigator.pop(ctx);
                            setState(() {
                              _iconCtrl.text = v.characters.isEmpty
                                  ? Asset.defaultIconFor(_type)
                                  : v.characters.first;
                            });
                          },
                          child: const Text('确定', style: TextStyle(fontSize: 15)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// v5.0.23：档案页昵称行同款——白卡内左侧固定宽 76 的标签 + 右侧无边框输入。
  /// 与档案 `_buildFieldLabel`、物品编辑 `_buildLabeledField` 对齐。
  Widget _buildLabeledField({
    required String label,
    required TextField field,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _box(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: 15, color: AppPalette.c(0xFF24382F)),
            ),
          ),
          Expanded(child: field),
        ],
      ),
    );
  }

  BoxDecoration _box() {
    return BoxDecoration(
      color: AppPalette.c(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(12),
    );
  }
}
