import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/item_storage.dart';

const List<String> kCategories = ['数码设备', '衣物', '配饰', '家具'];
const Map<String, List<String>> kCategoryIcons = {
  '数码设备': ['📱', '💻', '📷', '🎧', '⌚', '🖥️', '🎮'],
  '衣物': ['👕', '👖', '👗', '🧥', '👟', '🧢', '👔'],
  '配饰': ['💍', '👜', '🕶️', '🧣', '🎒', '🕐', '👓'],
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
  late String _category;
  late String _icon;
  late DateTime _acquiredDate;
  DateTime? _lostDate;
  late int _calcMethod;
  late bool _wishlist;
  late double _savePerTime;
  late double _savedAmount;
  bool _saving = false;

  bool get _isNew => widget.item == null;

  /// 主题强调色：愿望单=粉色，已拥有=蓝色
  Color get _accent =>
      _wishlist ? const Color(0xFFE58BA0) : const Color(0xFF3B6FE0);

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
    _acquiredDate = it?.acquiredDate ?? DateTime.now();
    _lostDate = it?.lostDate;
    _calcMethod = it?.calcMethod ?? 0;
    _wishlist = it?.wishlist ?? false;
    _savePerTime = it?.savePerTime ?? 0;
    _savedAmount = it?.savedAmount ?? 0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _extraCtrl.dispose();
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
          .showSnackBar(const SnackBar(content: Text('请填写物品价格')));
      return;
    }

    // 愿望单转已拥有（攒钱完成）：默认价格/天数，拥有日为当天
    final wasWishlist = widget.item?.wishlist ?? false;
    DateTime acquired = _acquiredDate;
    if (wasWishlist && !_wishlist) {
      acquired = DateTime.now();
      _calcMethod = 0;
      _lostDate = null;
    }

    setState(() => _saving = true);

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
        backgroundColor: _wishlist
            ? const Color(0xFFE58BA0)
            : const Color(0xCC3B6FE0),
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
            _buildStatusRow(),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _buildNameField(),
            const Divider(height: 1),
            const SizedBox(height: 16),
            _buildPriceField(),
            const Divider(height: 1),
            const SizedBox(height: 16),
            if (!_wishlist) ...[
              _buildExtraPriceField(),
              const Divider(height: 1),
              const SizedBox(height: 16),
            ],
            _buildCategoryRow(),
            const SizedBox(height: 16),
            _buildIconRow(),
            if (!_wishlist) ...[
              const SizedBox(height: 16),
              _buildDateRow(),
              const SizedBox(height: 12),
              _buildCalcMethodRow(),
              if (_calcMethod == 1) ...[
                const SizedBox(height: 12),
                _buildUsageField(),
              ],
            ] else ...[
              const SizedBox(height: 16),
              _buildSavePerTimeRow(),
              const SizedBox(height: 12),
              _buildSavedAmountRow(),
              const SizedBox(height: 16),
              _buildProgressBarRow(),
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
                    primary: _accent,
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

  Widget _buildStatusRow() {
    return Row(
      children: [
        const Text('物品状态',
            style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52))),
        const Spacer(),
        _buildStatusChip('已拥有', false),
        const SizedBox(width: 8),
        _buildStatusChip('愿望单', true),
      ],
    );
  }

  Widget _buildStatusChip(String label, bool wishlistValue) {
    final sel = _wishlist == wishlistValue;
    final accent = wishlistValue
        ? const Color(0xFFE58BA0)
        : const Color(0xFF3B6FE0);
    return GestureDetector(
      onTap: () => setState(() => _wishlist = wishlistValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? accent : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: sel ? accent : const Color(0xFFDCE7FF),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: sel ? Colors.white : const Color(0xFF5A6B82),
          ),
        ),
      ),
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
          decoration: const InputDecoration(
            hintText: '0.00',
            prefixText: '¥ ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, double.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('确定'),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Text('每次攒钱',
                style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52))),
            const Spacer(),
            Text(
              _savePerTime > 0 ? '¥${_fmtAmount(_savePerTime)}' : '点击设置',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _savePerTime > 0
                    ? const Color(0xFF34A853)
                    : const Color(0xFF9AA8BF),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: Color(0xFFC4CEDD)),
          ],
        ),
      ),
    );
  }

  double get _saveStep => _savePerTime > 0 ? _savePerTime : 1;

  Widget _buildSavedAmountRow() {
    return Row(
      children: [
        const Text('已攒金额',
            style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52))),
        const Spacer(),
        // 加减号并排放置在已攒金额左侧
        _buildStepButton(Icons.remove, () {
          setState(() {
            _savedAmount = (_savedAmount - _saveStep) < 0
                ? 0
                : _savedAmount - _saveStep;
          });
        }),
        const SizedBox(width: 8),
        _buildStepButton(Icons.add, () {
          setState(() => _savedAmount += _saveStep);
        }),
        const SizedBox(width: 14),
        // 金额右侧显示，与「每次攒钱」金额对齐
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
              color: Color(0xFF34A853),
            ),
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC4CEDD)),
      ],
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
        // 与「已攒金额、每次攒钱」同行样式一致（15号、深灰、左对齐）
        const Text('攒钱进度',
            style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52))),
        const SizedBox(height: 10),
        // 长度进一步缩短
        Padding(
          padding: const EdgeInsets.only(right: 56),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Stack(
                children: [
                  Container(color: const Color(0xFFE0E4EA)),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(color: const Color(0xFF34A853)),
                  ),
                  Center(
                    child: Text(
                      '$pct%',
                      style: const TextStyle(
                        fontSize: 10,
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
                color: sel ? _accent : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? _accent : const Color(0xFFDCE7FF),
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
          color: sel ? _accent.withOpacity(0.15) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel ? _accent : const Color(0xFFE8EDF5),
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
        const Text('物品价格',
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

  /// 附加价格：选填，可为负数；实际价格 = 物品价格 + 附加价格
  Widget _buildExtraPriceField() {
    final extra = double.tryParse(_extraCtrl.text.trim()) ?? 0;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('附加价格',
            style: TextStyle(fontSize: 15, color: Color(0xFF2A3B52))),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: _extraCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true, signed: true),
            style: const TextStyle(fontSize: 16),
            decoration: const InputDecoration(
              hintText: '选填，可为负数',
              prefixText: '¥ ',
              border: InputBorder.none,
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
              color: Color(0xFF3B6FE0),
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
                  color: sel ? _accent : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: sel ? _accent : const Color(0xFFDCE7FF),
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
        child: Icon(icon, size: 18, color: _accent),
      ),
    );
  }
}
