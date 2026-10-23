import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/item_storage.dart';
import 'item_edit_screen.dart';

class ItemListScreen extends StatefulWidget {
  final VoidCallback onOpenMenu;

  const ItemListScreen({Key? key, required this.onOpenMenu}) : super(key: key);

  @override
  State<ItemListScreen> createState() => ItemListScreenState();
}

class ItemListScreenState extends State<ItemListScreen> {
  List<Item> _items = [];
  bool _loading = true;
  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ItemStorage.load();
    list.sort((a, b) => b.acquiredDate.compareTo(a.acquiredDate));
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> openNewItem() async {
    await _openEditor();
  }

  Future<void> _openEditor([Item? item]) async {
    final result = await Navigator.push<bool>(
      context,
      _slideRoute(ItemEditScreen(item: item)),
    );
    if (result == true) _load();
  }

  Route<T> _slideRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder:
          (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
            parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  Future<void> _incrementUsage(Item item) async {
    final list = await ItemStorage.load();
    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx >= 0) {
      list[idx].usageCount += 1;
      await ItemStorage.save(list);
      _load();
    }
  }

  List<Item> get _filtered {
    if (_query.isEmpty) return _items;
    final q = _query.toLowerCase();
    return _items.where((e) => e.name.toLowerCase().contains(q)).toList();
  }

  double get _totalValue =>
      _items.fold(0.0, (sum, e) => sum + e.price);

  double get _dailyCost => _items.fold(0.0, (sum, e) {
        final days = e.acquiredDays;
        return days > 0 ? sum + e.price / days : sum;
      });

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchCtrl.clear();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(),
        if (_loading)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _buildDataView(),
          const Divider(height: 1, color: Color(0xFFE8EDF5)),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      _searching ? '没有匹配的物品' : '还没有物品',
                      style: const TextStyle(
                          fontSize: 15, color: Color(0xFF9AA8BF)),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final it = _filtered[i];
                      return _ItemCard(
                        item: it,
                        onTap: () => _openEditor(it),
                        onUse: it.calcMethod == 1
                            ? () => _incrementUsage(it)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 48,
      color: const Color(0xB33B6FE0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: widget.onOpenMenu,
          ),
          Expanded(
            child: _searching
                ? Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      style: const TextStyle(
                          fontSize: 15, color: Color(0xFF2A3B52)),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: const InputDecoration(
                        hintText: '搜索物品…',
                        hintStyle: TextStyle(color: Color(0xFF9AA8BF)),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  )
                : const SizedBox(),
          ),
          IconButton(
            icon: Icon(
              _searching ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: _toggleSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildDataView() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          _buildDataItem('物品数', '${_items.length}'),
          _buildDivider(),
          _buildDataItem('总价值', '¥${_totalValue.toStringAsFixed(0)}'),
          _buildDivider(),
          _buildDataItem('日均成本', '¥${_dailyCost.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Widget _buildDataItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3B6FE0),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BF)),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() =>
      Container(width: 1, height: 30, color: const Color(0xFFE8EDF5));
}

class _ItemCard extends StatelessWidget {
  final Item item;
  final VoidCallback onTap;
  final VoidCallback? onUse;

  const _ItemCard(
      {Key? key, required this.item, required this.onTap, this.onUse})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final lost = item.lostDate != null;
    final unitLabel = item.calcMethod == 1 ? '次' : '天';
    final usageLabel = item.calcMethod == 1
        ? '使用 ${item.usageCount} 次'
        : '已用 ${item.acquiredDays} 天';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: lost ? const Color(0xFFE4E7EC) : Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: lost ? 0.5 : 1,
                child: Text(item.icon, style: const TextStyle(fontSize: 40)),
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color:
                      lost ? const Color(0xFF9AA8BF) : const Color(0xFF2A3B52),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '¥${item.unitPrice.toStringAsFixed(2)}/$unitLabel',
                style: TextStyle(
                  fontSize: 13,
                  color: lost ? const Color(0xFFB0B8C4) : const Color(0xFF3B6FE0),
                ),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: onUse,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  usageLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: lost
                        ? const Color(0xFFB0B8C4)
                        : const Color(0xFF9AA8BF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
