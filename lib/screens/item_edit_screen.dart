import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/item_storage.dart';

const List<String> kCategories = ['数码设备', '衣物', '配饰', '家具'];
const Map<String, List<String>> kCategoryIcons = {
  '数码设备': ['📱', '💻', '📷', '🎧', '⌚', '🖥️', '🎮', '⌨️'],
  '衣物': ['👕', '👖', '👗', '🧥', '👟', '🧢', '👔', '👘'],
  '配饰': ['💍', '👜', '🕶️', '🧣', '🎒', '🕐', '👓', '🧤'],
  '家具': ['🛋️', '🛏️', '💡', '🪑', '🚪', '📺', '🪴', '🛁'],
};
const List<String> kFallbackIcons = ['📱', '💻', '📷', '🎧', '⌚', '🖥️', '🎮', '⌨️'];

class ItemEditScreen extends StatefulWidget {
  final Item? item;
  const ItemEditScreen({Key? key, this.item}) : super(key: key);

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _usageCtrl;
  late String _category;
  late String _icon;
  late DateTime _acquiredDate;
  DateTime? _lostDate;
  late int _calcMethod;
  bool _saving = false;

  bool get _isNew => widget.item == null;

  @override
  void initState() {
    super.initState();
    final it = widget.item;
    _nameCtrl = TextEditingController(text: it?.name ?? '');
    _priceCtrl = TextEditingController(
        text: it != null && it.price > 0 ? it.price.toString() : '');
    _usageCtrl = TextEditingController(
        text: it != null && it.usageCount > 0 ? it.usageCount.toString() : '');
    _category = it?.category ?? '数码设备';
    _icon = it?.icon ?? '📱';
    _acquiredDate = it?.acquiredDate ?? DateTime.now();
    _lostDate = it?.lostDate;
    _calcMethod = it?.calcMethod ?? 0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _usageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写物品名')));
      return;
    }
    if (price <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写购买价格')));
      return;
    }

    setState(() => _saving = true);

    final list = await ItemStorage.load();
    final usage = int.tryParse(_usageCtrl.text.trim()) ?? 0;
    if (_isNew) {
      list.add(Item(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        category: _category,
        icon: _icon,
        price: price,
        acquiredDate: _acquiredDate,
        lostDate: _lostDate,
        calcMethod: _calcMethod,
        usageCount: usage,
      ));
    } else {
      final idx = list.indexWhere((e) => e.id == widget.item!.id);
      if (idx >= 0) {
        list[idx].name = name;
        list[idx].category = _category;
        list[idx].icon = _icon;
        list[idx].price = price;
        list[idx].acquiredDate = _acquiredDate;
        list[idx].lostDate = _lostDate;
        list[idx].calcMethod = _calcMethod;
        list[idx].usageCount = usage;
      }
    }
    await ItemStorage.save(list);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除这件物品吗?'),
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
    if (confirmed != true) return;

    final list = await ItemStorage.load();
    list.removeWhere((e) => e.id == widget.item!.id);
    await ItemStorage.save(list);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _pickAcquired() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _acquiredDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _acquiredDate = picked);
  }

  Future<void> _pickLost() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _lostDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
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
          maxLength: 8,
          decoration: const InputDecoration(hintText: '输入类型名（最多8字）'),
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
          decoration: const InputDecoration(hintText: '输入一个emoji，如 🎸'),
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
    ctrl.dispose();
    if (result != null && result.isNotEmpty) {
      setState(() => _icon = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xCC3B6FE0),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_isNew ? '添加物品' : '编辑物品'),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNameField(),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _buildPriceField(),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _buildCategoryRow(),
            const SizedBox(height: 16),
            _buildIconRow(),
            const SizedBox(height: 16),
            _buildDateRow(),
            const SizedBox(height: 12),
            _buildCalcMethodRow(),
            if (_calcMethod == 1) ...[
              const SizedBox(height: 12),
              _buildUsageField(),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context),
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
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('完成', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, color: Color(0xFF9A8A7E)),
      );

  Widget _buildNameField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('物品名',
            style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52))),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: _nameCtrl,
            maxLength: 20,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: '请输入物品名',
              border: InputBorder.none,
              counterText: '',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryRow() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...kCategories.map((c) {
          final sel = c == _category;
          return GestureDetector(
            onTap: () => setState(() {
              _category = c;
              _icon = kCategoryIcons[c]!.first;
            }),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFF3B6FE0) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel
                      ? const Color(0xFF3B6FE0)
                      : const Color(0xFFDCE7FF),
                ),
              ),
              child: Text(
                c,
                style: TextStyle(
                  fontSize: 13,
                  color: sel ? Colors.white : const Color(0xFF5A6B82),
                ),
              ),
            ),
          );
        }),
        GestureDetector(
          onTap: _addCustomCategory,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCE7FF)),
            ),
            child: const Text(
              '自定义',
              style: TextStyle(fontSize: 13, color: Color(0xFF5A6B82)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconRow() {
    final icons = kCategoryIcons[_category] ?? kFallbackIcons;
    return Wrap(
      spacing: 4,
      runSpacing: 6,
      children: [
        ...icons.map((ic) => _buildIconCell(ic)),
        _buildIconCell('…', isCustom: true),
      ],
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
          color: sel ? const Color(0xFFDCE7FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? const Color(0xFF3B6FE0) : const Color(0xFFE8EDF5),
          ),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontSize: isCustom ? 18 : 18,
            color: isCustom ? const Color(0xFF9AA8BF) : null,
          ),
        ),
      ),
    );
  }

  Widget _buildPriceField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('购买价格',
            style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52))),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: '0.00',
              prefixText: '¥ ',
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateRow() {
    return Row(
      children: [
        Expanded(
          child: _buildDateCell(
            label: '获得日',
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE7FF)),
        ),
        child: Row(
          children: [
            const Icon(Icons.event, size: 16, color: Color(0xFF3B6FE0)),
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
                      ? const Color(0xFF9AA8BF)
                      : const Color(0xFF2A3B52),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close,
                    size: 16, color: Color(0xFF9AA8BF)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalcMethodRow() {
    final methods = [0, 1];
    final labels = ['价格/天数', '价格/使用次数'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel('均价计算方式'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: List.generate(methods.length, (i) {
            final sel = _calcMethod == methods[i];
            return GestureDetector(
              onTap: () => setState(() => _calcMethod = methods[i]),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? const Color(0xFF3B6FE0) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: sel
                        ? const Color(0xFF3B6FE0)
                        : const Color(0xFFDCE7FF),
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 14,
                    color: sel ? Colors.white : const Color(0xFF5A6B82),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildUsageField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('使用次数',
            style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52))),
        const Spacer(),
        _buildStepButton(Icons.remove, () => _changeUsage(-1)),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: TextField(
            controller: _usageCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: '0',
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 8),
        _buildStepButton(Icons.add, () => _changeUsage(1)),
        const SizedBox(width: 6),
        const Text('次',
            style: TextStyle(fontSize: 14, color: Color(0xFF9AA8BF))),
      ],
    );
  }

  void _changeUsage(int delta) {
    final cur = int.tryParse(_usageCtrl.text.trim()) ?? 0;
    final next = (cur + delta) < 0 ? 0 : (cur + delta);
    _usageCtrl.text = '$next';
    setState(() {});
  }

  Widget _buildStepButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFDCE7FF)),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF3B6FE0)),
      ),
    );
  }
}
