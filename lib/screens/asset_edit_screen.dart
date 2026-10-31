import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/asset.dart';
import '../services/trash_storage.dart';
import '../widgets/unsaved_guard.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';
import '../widgets/save_done_button.dart';

/// 新增 / 编辑资产卡片。
class AssetEditScreen extends StatefulWidget {
  final Asset? asset; // null = 新增
  const AssetEditScreen({Key? key, this.asset}) : super(key: key);

  @override
  State<AssetEditScreen> createState() => _AssetEditScreenState();
}

class _AssetEditScreenState extends State<AssetEditScreen> {
  late final TextEditingController _noteCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _iconCtrl;
  late String _type;
  bool _saving = false;

  /// 完成动画的进度（0 = 常态，1 = 已收缩）。
  Animation<double> get _doneAnim =>
      _doneKey.currentState?.collapse ?? const AlwaysStoppedAnimation(1);

  final GlobalKey<SaveDoneButtonState> _doneKey =
      GlobalKey<SaveDoneButtonState>();

  /// 保存后待返回的资产对象（动画播完才 pop）
  Asset? _pending;
  bool _typeOpen = false; // 资产类型下拉是否展开

  /// 进入页面时的内容快照，用于判断是否有未保存的修改
  String _initial = '';

  /// 当前编辑内容（用于 dirty 比较）
  String _snapshot() => [
        _noteCtrl.text,
        _amountCtrl.text,
        _iconCtrl.text,
        _type,
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
    _initial = _snapshot();
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
              child: const Text('删除', style: TextStyle(color: Colors.red)),
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
  String? _validate() {
    if (double.tryParse(_amountCtrl.text.trim()) == null) return '请输入正确的金额';
    return null;
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    setState(() => _saving = true);
    Haptics.light();
    final a = widget.asset ??
        Asset(id: DateTime.now().microsecondsSinceEpoch.toString());
    a.icon = _iconCtrl.text.trim().isEmpty
        ? Asset.defaultIconFor(_type)
        : _iconCtrl.text.trim().characters.first;
    a.note = _noteCtrl.text.trim();
    a.type = _type;
    // 负债类型强制为负数展示语义：存正数，由类型决定正负
    a.amount = amount.abs() * (_isLiability ? -1 : 1);
    // 返回交给完成动画播完后执行（见 onDone），这里只暂存结果
    _pending = a;
    if (!mounted) return;
    _doneKey.currentState?.finish();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleLeave,
      child: Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xCC3B6FE0),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(widget.asset == null ? '新增资产' : '编辑资产'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
        // 右上角：删除当前资产卡片（仅编辑已有卡片时）
        actions: [
          if (widget.asset != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 资产图标：一排 7 个快捷图标 + 「...」更多
            _sectionLabel('资产图标'),
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

            // 资产类型：自定义下拉（固定从选框下方展开，选中项带底纹强调）
            _sectionLabel('资产类型'),
            GestureDetector(
              onTap: () {
                Haptics.light();
                setState(() => _typeOpen = !_typeOpen);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: _box(),
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_type,
                          style: const TextStyle(
                              fontSize: 15, color: Color(0xFF2A3B52))),
                    ),
                    AnimatedRotation(
                      turns: _typeOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down,
                          color: Color(0xFF5A6B82)),
                    ),
                  ],
                ),
              ),
            ),
            // 选项列表：始终固定在选框正下方展开，与选中项位置无关
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _typeOpen
                  ? Container(
                      margin: const EdgeInsets.only(top: 6),
                      decoration: _box(),
                      child: Column(
                        children: [
                          for (final t in Asset.types)
                            InkWell(
                              onTap: () {
                                Haptics.light();
                                setState(() {
                                  _type = t;
                                  _typeOpen = false;
                                  // 未手动改过图标时跟随类型换默认图标
                                  if (Asset.defaultIconFor(t) !=
                                          _iconCtrl.text.trim() &&
                                      Asset.types.any((x) =>
                                          Asset.defaultIconFor(x) ==
                                          _iconCtrl.text.trim())) {
                                    _iconCtrl.text = Asset.defaultIconFor(t);
                                  }
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 13),
                                decoration: BoxDecoration(
                                  // 选中项底纹强调
                                  color: t == _type
                                      ? const Color(0xFFDCE7FF)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
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
                                                  ? const Color(0xFF3B6FE0)
                                                  : const Color(0xFF2A3B52))),
                                    ),
                                    if (t == _type)
                                      const Icon(Icons.check,
                                          size: 16,
                                          color: Color(0xFF3B6FE0)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 16),

            // 资产备注
            _sectionLabel('资产备注'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: _box(),
              child: TextField(
                controller: _noteCtrl,
                maxLength: 15,
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: '如：工资卡、应急金、基金账户',
                  hintStyle: TextStyle(fontSize: 13, color: Color(0xFF9AA8BF)),
                  counterText: '',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 资产金额
            _sectionLabel('资产金额'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: _box(),
              child: Row(
                children: [
                  const Text('¥',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2A3B52))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: _isLiability ? '输入欠款金额' : '输入资产金额',
                        hintStyle: const TextStyle(
                            fontSize: 14, color: Color(0xFF9AA8BF)),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_isLiability)
              const Padding(
                padding: EdgeInsets.only(left: 4, top: 6),
                child: Text('该类型会计入负资产，金额请填正数',
                    style: TextStyle(fontSize: 12, color: Color(0xFFE06A6A))),
              ),
            const SizedBox(height: 28),

            // 保存：点击后收缩成圆形 + 打勾 + 粒子，播完再返回
            SaveDoneButton(
              key: _doneKey,
              color: const Color(0xFF3B6FE0),
              onTap: _save,
              onDone: () {
                if (mounted) Navigator.pop(context, _pending);
              },
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF9AA8BF),
              fontWeight: FontWeight.w600)),
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

  /// 「...」→ 全部图标 + 自定义 emoji
  Future<void> _showMoreIcons() async {
    final tmpCtrl = TextEditingController(text: _iconCtrl.text.trim());
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
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
                            fontSize: 16, fontWeight: FontWeight.w600)),
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
                            child: Text(e,
                                style: const TextStyle(fontSize: 24)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: tmpCtrl,
                      maxLength: 4,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                        labelText: '自定义 emoji',
                        hintText: '如 🐷、🚀',
                        hintStyle:
                            TextStyle(fontSize: 13, color: Color(0xFF9AA8BF)),
                        counterText: '',
                        isDense: true,
                        border: OutlineInputBorder(),
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
                            primary: const Color(0xFF3B6FE0),
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

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE8EDF5)),
    );
  }
}
