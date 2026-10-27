import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/asset.dart';

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

  static const List<String> _quickIcons = [
    '🏦', '💸', '📈', '🪙', '📊', '💳', '🧾', '💰',
    '🇨🇳', '🏠', '🚗', '📱', '💼', '🎁', '🐷', '🌙',
  ];

  bool get _isLiability =>
      _type == '信用卡' || _type == '欠款';

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
        content: const Text('删除后无法恢复'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context, 'deleted');
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入正确的金额')),
      );
      return;
    }
    setState(() => _saving = true);
    HapticFeedback.selectionClick();
    final a = widget.asset ?? Asset(id: DateTime.now().microsecondsSinceEpoch.toString());
    a.icon = _iconCtrl.text.trim().isEmpty
        ? Asset.defaultIconFor(_type)
        : _iconCtrl.text.trim().characters.first;
    a.note = _noteCtrl.text.trim();
    a.type = _type;
    // 负债类型强制为负数展示语义：存正数，由类型决定正负
    a.amount = amount.abs() * (_isLiability ? -1 : 1);
    Navigator.pop(context, a);
  }

  @override
  Widget build(BuildContext context) {
    final iconPreview = _iconCtrl.text.trim().isEmpty
        ? Asset.defaultIconFor(_type)
        : _iconCtrl.text.trim().characters.first;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: const Color(0xCC3B6FE0),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(widget.asset == null ? '新增资产' : '编辑资产'),
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
            // 资产图标
            _sectionLabel('资产图标'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: _box(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4FB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE8EDF5)),
                        ),
                        child: Text(iconPreview,
                            style: const TextStyle(fontSize: 30)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _iconCtrl,
                          maxLength: 4,
                          style: const TextStyle(fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: '自定义 emoji，如 🐷',
                            hintStyle:
                                TextStyle(fontSize: 13, color: Color(0xFF9AA8BF)),
                            counterText: '',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickIcons.map((e) {
                      final sel = iconPreview == e;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _iconCtrl.text = e;
                          setState(() {});
                        },
                        child: Container(
                          width: 40,
                          height: 40,
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
                          child: Text(e, style: const TextStyle(fontSize: 22)),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 资产类型
            _sectionLabel('资产类型'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: _box(),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Asset.types.map((t) {
                  final sel = _type == t;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _type = t;
                        // 未手动改过图标时跟随类型换默认图标
                        if (Asset.defaultIconFor(t) != _iconCtrl.text.trim() &&
                            Asset.types
                                .any((x) => Asset.defaultIconFor(x) == _iconCtrl.text.trim())) {
                          _iconCtrl.text = Asset.defaultIconFor(t);
                        }
                      });
                    },
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF3B6FE0) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: sel ? const Color(0xFF3B6FE0) : const Color(0xFFD6DCE8),
                        ),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 13,
                          color: sel ? Colors.white : const Color(0xFF5A6B82),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
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

            // 保存
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  primary: const Color(0xFF3B6FE0),
                  onPrimary: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(widget.asset == null ? '添加' : '保存',
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
          ],
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

  BoxDecoration _box() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE8EDF5)),
    );
  }
}
