import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/item_storage.dart';
import '../services/reward_service.dart';
import '../services/trash_storage.dart';
import '../utils/app_toast.dart';
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
const List<String> kCategories = ['数码设备', '衣物', '配饰', '家具'];
const Map<String, List<String>> kCategoryIcons = {
  '数码设备': ['📱', '💻', '📷', '🎧', '⌚', '🖥️', '🎮'],
  '衣物': ['👕', '👟', '🎒', '👓', '⌚', '👜', '💍'],
  '配饰': ['💍', '👜', '🕶️', '🕐', '👓', '⌚', '🎒'],
  '家具': ['🛋️', '🛏️', '💡', '🪑', '🚪', '📺', '🪴'],
};
const List<String> kFallbackIcons = ['📱', '💻', '📷', '🎧', '⌚', '🖥️', '🎮'];

class ItemEditScreen extends StatefulWidget {
  final Item? item;
  const ItemEditScreen({Key? key, this.item}) : super(key: key);

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _extraCtrl;
  late final TextEditingController _usageCtrl;

  /// v4.9.27：智能回车——名称→价格→附加价→用量逐栏跳转，末栏收起键盘。
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();
  final FocusNode _extraFocus = FocusNode();
  final FocusNode _usageFocus = FocusNode();

  late String _category;
  late String _icon;
  DateTime? _acquiredDate; // 拥有日：需手动选择后才能创建已拥有物品
  DateTime? _lostDate;
  late int _calcMethod;
  late bool _wishlist;
  late double _savePerTime;
  late double _savedAmount;
  bool _saving = false;


  final GlobalKey<SaveDoneButtonState> _doneKey =
      GlobalKey<SaveDoneButtonState>();


  bool get _isNew => widget.item == null;

  /// 主题强调色：愿望单=粉色，已拥有=蓝色
  Color get _accent =>
      _wishlist ? const Color(0xFFE58BA0) : const Color(0xFF3E8E6D);

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _nameCtrl = TextEditingController(text: it?.name ?? '');
    _priceCtrl = TextEditingController(
        text: it != null && it.price > 0 ? it.price.toString() : '');
    _extraCtrl = TextEditingController(
        text: it != null && it.extraPrice != 0 ? it.extraPrice.toString() : '');
    _usageCtrl = TextEditingController(
        text: it != null && it.usageCount > 0 ? it.usageCount.toString() : '');
    _category = it?.category ?? '数码设备';
    _icon = it?.icon ?? '📱';
    _acquiredDate = it?.acquiredDate;
    _lostDate = it?.lostDate;
    _calcMethod = it?.calcMethod ?? 0;
    _wishlist = it?.wishlist ?? false;
    _savePerTime = it?.savePerTime ?? 0;
    _savedAmount = it?.savedAmount ?? 0;
    _initial = _snapshot();
  }

  /// 进入页面时的内容快照，用于判断是否有未保存的修改
  String _initial = '';

  /// 当前编辑内容（用于 dirty 比较）
  String _snapshot() => [
        _nameCtrl.text,
        _priceCtrl.text,
        _extraCtrl.text,
        _usageCtrl.text,
        _category,
        _icon,
        _acquiredDate?.toIso8601String() ?? '',
        _lostDate?.toIso8601String() ?? '',
        _calcMethod.toString(),
        _wishlist ? '1' : '0',
        _savePerTime.toString(),
        _savedAmount.toString(),
      ].join('\u0001');

  bool get _dirty => _snapshot() != _initial;

  /// 主动返回（AppBar 返回键 / 系统返回键）：有改动时弹框，确定即放弃保存返回
  Future<bool> _handleLeave() => confirmLeaveIfDirty(context, dirty: _dirty);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _extraCtrl.dispose();
    _usageCtrl.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    _extraFocus.dispose();
    _usageFocus.dispose();
    super.dispose();
  }

  // 校验阶段算出的值，_save 落盘时复用
  String? _vName;
  double? _vPrice;
  DateTime? _vAcquired;

  /// 同步校验：返回 null 表示可以保存，返回文案则提示并中止。
  /// 抽出来是为了让「点击 → 收缩动画」立刻开始，不必等异步落盘。
  String? _validate() {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    if (name.isEmpty) return '请填写物品名';
    if (price <= 0) return '请填写物品价格';

    // 已拥有物品必须选择拥有日
    final wasWishlist = widget.item?.wishlist ?? false;
    DateTime acquired;
    if (_wishlist) {
      acquired = widget.item?.acquiredDate ?? DateTime.now();
    } else if (wasWishlist && !_wishlist) {
      // 愿望单转已拥有（攒钱完成/手动切换）：拥有日为当天
      acquired = DateTime.now();
      _calcMethod = 0;
      _lostDate = null;
    } else {
      if (_acquiredDate == null) return '请选择拥有日';
      acquired = _acquiredDate!;
    }
    _vName = name;
    _vPrice = price;
    _vAcquired = acquired;
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final name = _vName ?? '';
    final price = _vPrice ?? 0;
    final acquired = _vAcquired ?? DateTime.now();
    final extra = double.tryParse(_extraCtrl.text.trim()) ?? 0;
    final list = await ItemStorage.load();
    final usage = int.tryParse(_usageCtrl.text.trim()) ?? 0;
    if (_isNew) {
      list.add(Item(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        category: _category,
        icon: _icon,
        price: price,
        acquiredDate: acquired,
        lostDate: _lostDate,
        calcMethod: _calcMethod,
        usageCount: usage,
        wishlist: _wishlist,
        savePerTime: _savePerTime,
        savedAmount: _savedAmount,
        extraPrice: _wishlist ? 0 : extra,
      ));
    } else {
      final idx = list.indexWhere((e) => e.id == widget.item!.id);
      if (idx >= 0) {
        list[idx].name = name;
        list[idx].category = _category;
        list[idx].icon = _icon;
        list[idx].price = price;
        list[idx].acquiredDate = acquired;
        list[idx].lostDate = _lostDate;
        list[idx].calcMethod = _calcMethod;
        list[idx].usageCount = usage;
        list[idx].wishlist = _wishlist;
        list[idx].savePerTime = _savePerTime;
        list[idx].savedAmount = _wishlist ? _savedAmount : 0;
        list[idx].extraPrice = _wishlist ? 0 : extra;
      }
    }
    await ItemStorage.save(list);

    // 首次新增物品奖励灵感（仅新增、每类 1 次，异步不阻塞动画）
    if (_isNew) {
      RewardService.awardFirstAdd(FirstAddKind.item).then((n) {
        if (n > 0 && mounted) {
          AppToast.show(context, '首次新增物品，+$n 点灵感');
        }
      });
    }

    if (!mounted) return;
    // 落盘完成：续播对勾 + 粒子，播完由 onDone 返回
    _doneKey.currentState?.finish();
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除这件物品吗?'),
        content: const Text('删除后可在「回收站」保留 7 天'),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
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
    if (confirmed != true) return;
    Haptics.medium();

    final list = await ItemStorage.load();
    list.removeWhere((e) => e.id == widget.item!.id);
    await ItemStorage.save(list);
    // 编辑页删除同样入回收站
    await TrashStorage.addItem(widget.item!);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _pickAcquired() async {
    final picked = await showWheelDatePicker(
        context, initial: _acquiredDate ?? DateTime.now());
    if (picked != null) setState(() => _acquiredDate = picked);
  }

  Future<void> _pickLost() async {
    final picked = await showWheelDatePicker(
        context, initial: _lostDate ?? DateTime.now());
    if (picked != null) setState(() => _lostDate = picked);
  }

  Future<void> _addCustomCategory() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义类型'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          maxLength: 8,
          decoration: const InputDecoration(hintText: '输入类型名（最多8字）'),
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('确定'),
            ),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      setState(() {
        _category = result;
        _icon = kFallbackIcons.first;
      });
    }
  }

  Future<void> _addCustomIcon() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义图标'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '输入一个emoji，如 🎸'),
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('确定'),
            ),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      setState(() => _icon = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return WillPopScope(
      onWillPop: _handleLeave,
      child: Scaffold(
      appBar: AppBar(
        toolbarHeight: 48, // v4.9.31：与物品主页顶栏同高
        backgroundColor: _wishlist
            ? const Color(0xFFE58BA0)
            : AppPalette.c(0xB33E8E6D), // v4.9.31：与物品主页顶栏同色
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_isNew ? '添加物品' : '编辑物品'),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const AppIcon(AppIcons.delete),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        // 版式与事件编辑页统一：灰色小节标题在上、内容块在下，
        // 节与节之间 16px 空隙，不再用分割线
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _selectRow(
              label: '物品状态',
              value: _wishlist ? '愿望单' : '已拥有',
              onTap: () => _pickOptionSheet(
                title: '物品状态',
                options: const ['已拥有', '愿望单'],
                current: _wishlist ? '愿望单' : '已拥有',
                onSelected: (v) => setState(() => _wishlist = v == '愿望单'),
              ),
            ),
            const SizedBox(height: 16),
            _sectionLabel('物品名称'),
            _buildNameField(),
            const SizedBox(height: 16),
            _sectionLabel('物品价格'),
            _buildPriceField(),
            if (!_wishlist) ...[
              const SizedBox(height: 16),
              _sectionLabel('附加价格'),
              _buildExtraPriceField(),
            ],
            const SizedBox(height: 16),
            _selectRow(
              label: '物品类型',
              value: _category,
              onTap: () => _pickCategorySheet(),
            ),
            const SizedBox(height: 16),
            _sectionLabel('物品图标'),
            _buildIconRow(),
            if (!_wishlist) ...[
              const SizedBox(height: 16),
              _sectionLabel('日期'),
              _buildDateRow(),
              const SizedBox(height: 16),
              _sectionLabel('计算方式'),
              const SizedBox(height: 8),
              _selectRow(
                label: '方式',
                value: _calcMethod == 0 ? '价格/天数' : '价格/使用次数',
                onTap: () => _pickOptionSheet(
                  title: '计算方式',
                  options: const ['价格/天数', '价格/使用次数'],
                  current: _calcMethod == 0 ? '价格/天数' : '价格/使用次数',
                  onSelected: (v) =>
                      setState(() => _calcMethod = v == '价格/天数' ? 0 : 1),
                ),
              ),
              if (_calcMethod == 1) ...[
                const SizedBox(height: 16),
                _sectionLabel('使用次数'),
                _buildUsageField(),
              ],
            ] else ...[
              const SizedBox(height: 16),
              _sectionLabel('每次攒钱'),
              _buildSavePerTimeRow(),
              const SizedBox(height: 16),
              _sectionLabel('已攒金额'),
              _buildSavedAmountRow(),
              const SizedBox(height: 16),
              _sectionLabel('攒钱进度'),
              _buildProgressBarRow(),
            ],
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


  /// 保存栏：点完成后取消按钮淡出让出整行，完成按钮收缩成居中圆形，
  /// 打勾描边 + 粒子迸发，停留片刻再保存返回。
  Widget _buildSaveBar() {
    return SaveBar(
      saveKey: _doneKey,
      color: _accent,
      onCancel: _saving ? null : () => Navigator.pop(context),
      validate: _validate,
      onSave: _save,
      onDone: () {
        if (mounted) Navigator.pop(context, true);
      },
    );
  }


  Future<double?> _inputAmountDialog(String title, double initial) async {
    final ctrl = TextEditingController(
        text: initial > 0 ? _fmtAmount(initial) : '');
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: '0.00',
            prefixText: '¥ ',
          ),
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () =>
                  Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? 0),
              child: const Text('确定'),
            ),
          ),
        ],
      ),
    );
    return result;
  }

  String _fmtAmount(double v) {
    return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  }

  Widget _buildSavePerTimeRow() {
    return InkWell(
      onTap: () async {
        final v = await _inputAmountDialog('每次攒钱金额', _savePerTime);
        if (v != null && v >= 0) setState(() => _savePerTime = v);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: _box(),
        child: Row(
          children: [
            Text(
              _savePerTime > 0 ? '¥${_fmtAmount(_savePerTime)}' : '点击设置',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _savePerTime > 0
                    ? const Color(0xFF3E8E6D)
                    : AppPalette.c(0xFF8FA09A),
              ),
            ),
            const Spacer(),
            AppIcon(AppIcons.chevR,
                size: 18, color: AppPalette.c(0xFFC6D6CD)),
          ],
        ),
      ),
    );
  }

  double get _saveStep => _savePerTime > 0 ? _savePerTime : 1;

  Widget _buildSavedAmountRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _box(),
      child: Row(
        children: [
          // 加减号并排放置在已攒金额左侧
          _buildStepButton(AppIcons.minus, () {
            setState(() {
              _savedAmount = (_savedAmount - _saveStep) < 0
                  ? 0
                  : _savedAmount - _saveStep;
            });
          }),
          const SizedBox(width: 8),
          _buildStepButton(AppIcons.plus, () {
            setState(() => _savedAmount += _saveStep);
          }),
          const Spacer(),
          // 金额右侧显示，点按可直接输入
          GestureDetector(
            onTap: () async {
              final v = await _inputAmountDialog('已攒金额', _savedAmount);
              if (v != null && v >= 0) setState(() => _savedAmount = v);
            },
            behavior: HitTestBehavior.opaque,
            child: Text(
              '¥${_fmtAmount(_savedAmount)}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3E8E6D),
              ),
            ),
          ),
          const SizedBox(width: 4),
          AppIcon(AppIcons.chevR, size: 18, color: AppPalette.c(0xFFC6D6CD)),
        ],
      ),
    );
  }

  Widget _buildProgressBarRow() {
    final percent = price > 0 ? _savedAmount / price * 100 : 0.0;
    final ratio = price > 0
        ? (_savedAmount / price).clamp(0.0, 1.0)
        : 0.0;
    final pct = (percent.round()).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 长度进一步缩短
        Padding(
          padding: const EdgeInsets.only(right: 56),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Stack(
                children: [
                  Container(color: AppPalette.c(0xFFDFEAE5)),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(color: const Color(0xFF3E8E6D)),
                  ),
                  Center(
                    child: Text(
                      '$pct%',
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                              blurRadius: 3,
                              color: Colors.black38,
                              offset: Offset(0, 1))
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  double get price =>
      double.tryParse(_priceCtrl.text.trim()) ?? 0;

  /// v4.9.26：档案页同款「标签 — 当前值 ›」行，点整行弹底部选择层。
  Widget _selectRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
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
                  width: 76,
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 15, color: AppPalette.c(0xFF24382F))),
                ),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14, color: AppPalette.c(0xFF647A70)),
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

  /// 通用底部选择层：标题 + 选项列表 + 当前项打勾（档案页性别弹层同款）。
  Future<void> _pickOptionSheet({
    required String title,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('选择$title',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.c(0xFF24382F))),
            ),
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
                        const AppIcon(AppIcons.check,
                            size: 20, color: Color(0xFF3E8E6D)),
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

  /// 物品类型选择层：已有分类 + 当前自定义分类 + 「自定义」入口。
  Future<void> _pickCategorySheet() async {
    final options = List<String>.from(kCategories);
    if (!options.contains(_category)) options.add(_category);
    const custom = '自定义…';
    final picked = await AppSheet.show<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('选择物品类型',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.c(0xFF24382F))),
            ),
            for (final opt in [...options, custom])
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
                      if (opt != custom && opt == _category)
                        const AppIcon(AppIcons.check,
                            size: 20, color: Color(0xFF3E8E6D)),
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
    if (picked == custom) {
      await _addCustomCategory();
      return;
    }
    setState(() {
      _category = picked;
      _icon = kCategoryIcons[picked]?.first ?? kFallbackIcons.first;
    });
  }

  /// 小节标题：与事件编辑页同一套（灰色小字、加粗、左侧留 4px）
  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                color: AppPalette.c(0xFF8FA09A),
                fontWeight: FontWeight.w600)),
      );

  /// 白色圆角内容块：与事件编辑页同一套
  BoxDecoration _box() => BoxDecoration(
        color: AppPalette.c(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(12),
      );

  Widget _buildNameField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _box(),
      child: TextField(
        controller: _nameCtrl,
        focusNode: _nameFocus,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _priceFocus.requestFocus(),
        maxLength: 20,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          hintText: '请输入物品名',
          hintStyle: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
          border: InputBorder.none,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildIconRow() {
    final icons = kCategoryIcons[_category] ?? kFallbackIcons;
    final cells = [
      ...icons.map((ic) => _buildIconCell(ic)),
      _buildIconCell('…', isCustom: true),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: cells,
    );
  }

  Widget _buildIconCell(String value, {bool isCustom = false}) {
    final sel = !isCustom && value == _icon;
    return GestureDetector(
      onTap: () =>
          isCustom ? _addCustomIcon() : setState(() => _icon = value),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? _accent.withOpacity(0.15) : AppPalette.c(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: isCustom
            // 自定义入口（…）保持灰色文本；预设值走 Lucide 细线图标
            ? Text('…',
                style: TextStyle(fontSize: 17, color: AppPalette.c(0xFF8FA09A)))
            : EntryIcon(value, size: 18),
      ),
    );
  }

  Widget _buildPriceField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _box(),
      child: TextField(
        controller: _priceCtrl,
        focusNode: _priceFocus,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _extraFocus.requestFocus(),
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 15),
        decoration: const InputDecoration(
          hintText: '0.00',
          prefixText: '¥ ',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  /// 附加价格：选填，可为负数；实际价格 = 物品价格 + 附加价格
  Widget _buildExtraPriceField() {
    final extra = double.tryParse(_extraCtrl.text.trim()) ?? 0;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _box(),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _extraCtrl,
              focusNode: _extraFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _usageFocus.requestFocus(),
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(
                hintText: '可为负数（选填）',
                prefixText: '¥ ',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (extra != 0 || price > 0)
            Text(
              '实际 ¥${_fmtAmount(price + extra)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3E8E6D),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateRow() {
    return Row(
      children: [
        Expanded(
          child: _buildDateCell(
            label: '拥有日',
            value: _acquiredDate,
            onTap: _pickAcquired,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildDateCell(
            label: '失去日',
            value: _lostDate,
            onTap: _pickLost,
            optional: true,
            onClear: _lostDate != null ? () => setState(() => _lostDate = null) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDateCell({
    required String label,
    required DateTime? value,
    required VoidCallback onTap,
    bool optional = false,
    VoidCallback? onClear,
  }) {
    final d = value;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppPalette.c(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const AppIcon(AppIcons.event, size: 16, color: Color(0xFF3E8E6D)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                d == null
                    ? label
                    : '${d.year}/${d.month}/${d.day}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: d == null
                      ? AppPalette.c(0xFF8FA09A)
                      : AppPalette.c(0xFF24382F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: AppIcon(AppIcons.close,
                    size: 16, color: AppPalette.c(0xFF8FA09A)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _box(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStepButton(AppIcons.minus, () => _changeUsage(-1)),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: TextField(
              controller: _usageCtrl,
              focusNode: _usageFocus,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(
                hintText: '0',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          _buildStepButton(AppIcons.plus, () => _changeUsage(1)),
          const SizedBox(width: 6),
          Text('次',
              style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
        ],
      ),
    );
  }

  void _changeUsage(int delta) {
    final cur = int.tryParse(_usageCtrl.text.trim()) ?? 0;
    final next = (cur + delta) < 0 ? 0 : (cur + delta);
    _usageCtrl.text = '$next';
    setState(() {});
  }

  Widget _buildStepButton(String icon, VoidCallback onTap) {
    // 无底纹：裸图标 + 圆形点击区，视觉与该行文字居中对齐
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: AppIcon(icon, size: 18, color: _accent),
        ),
      ),
    );
  }
}
