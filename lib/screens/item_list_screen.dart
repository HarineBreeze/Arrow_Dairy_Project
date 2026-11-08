import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_toast.dart';
import '../models/item.dart';
import '../services/item_storage.dart';
import '../services/trash_storage.dart';
import '../utils/menu_gesture_gate.dart';
import '../widgets/app_icons.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_skeleton.dart';
import 'item_edit_screen.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';
import '../widgets/entry_icon.dart';

enum _ItemFilter { all, owning, lost, wishlist }

enum _ItemSortField { usage, days, price, avgCost, acquired }

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

  _ItemFilter _filter = _ItemFilter.all;
  _ItemSortField _sortField = _ItemSortField.acquired;
  bool _sortAscending = false;
  bool _costByUse = false; // false=平均成本(日均), true=次均成本

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

  /// 供外部（如导入备份后）强制刷新
  void reload() {
    setState(() => _loading = true);
    _load();
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

  /// 长按物品卡片：编辑 / 删除
  Future<void> _showItemMenu(Item item) async {
    Haptics.mediumNow(); // 长按菜单：同步触发，避免异步等待导致振动被丢弃
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading:
                  const AppIcon(AppIcons.edit, color: Color(0xFF3E8E6D)),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const AppIcon(AppIcons.delete, color: Color(0xFFCB5C50)),
              title: const Text('删除', style: TextStyle(color: Color(0xFFCB5C50))),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      _openEditor(item);
      return;
    }
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('删除「${item.name}」?'),
          content: const Text('删除后可在「回收站」保留 7 天，期间可还原'),
          actions: [
            Pressable(
              enabled: true,
              child: TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('取消')),
            ),
            Pressable(
              enabled: true,
              child: TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('删除', style: TextStyle(color: Color(0xFFCB5C50)))),
            ),
          ],
        ),
      );
      if (ok == true && mounted) {
        final list = await ItemStorage.load();
        list.removeWhere((e) => e.id == item.id);
        await ItemStorage.save(list);
        await TrashStorage.addItem(item);
        _load();
      }
    }
  }

  Route<T> _slideRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
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

  /// 愿望单：按每次攒钱金额 调整已攒金额
  Future<void> _adjustSaved(Item item, int direction) async {
    final step = item.savePerTime > 0 ? item.savePerTime : 1;
    final list = await ItemStorage.load();
    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx < 0) return;
    final it = list[idx];
    var saved = it.savedAmount + step * direction;
    if (saved < 0) saved = 0;

    if (it.price > 0 && saved >= it.price) {
      // 攒钱完成 → 自动转为已拥有
      it.savedAmount = 0;
      it.wishlist = false;
      it.calcMethod = 0;
      it.lostDate = null;
      it.acquiredDate = DateTime.now();
      await ItemStorage.save(list);
      if (!mounted) return;
      AppToast.show(context, '攒钱完成，「${it.name}」已加入拥有中！');
      _load();
      return;
    }
    it.savedAmount = saved;
    await ItemStorage.save(list);
    _load();
  }

  List<Item> get _filtered {
    var list = List<Item>.of(_items);
    if (_filter == _ItemFilter.owning) {
      list = list.where((e) => !e.wishlist && e.lostDate == null).toList();
    } else if (_filter == _ItemFilter.lost) {
      list = list.where((e) => !e.wishlist && e.lostDate != null).toList();
    } else if (_filter == _ItemFilter.wishlist) {
      list = list.where((e) => e.wishlist).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q)).toList();
    }
    list.sort(_compareItems);
    return list;
  }

  /// 排序键：愿望单物品按需求参与排序
  /// - 使用次数/使用天数/平均成本：愿望单一律排在已拥有物品之前（值最小），
  ///   多件愿望单之间，新添加的排更前（值更小）
  /// - 购买价格：按物品价格正常排序
  /// - 购买时间：愿望单一律视为最新，新添加的更新
  /// （id 为创建时的微秒时间戳，可用来比较“新添加”的先后）
  double _sortKey(Item e) {
    final ts = double.tryParse(e.id) ??
        e.acquiredDate.millisecondsSinceEpoch.toDouble();
    switch (_sortField) {
      case _ItemSortField.usage:
        return e.wishlist ? -ts : e.usageCount.toDouble();
      case _ItemSortField.days:
        return e.wishlist ? -ts : e.acquiredDays.toDouble();
      case _ItemSortField.price:
        return e.actualPrice;
      case _ItemSortField.avgCost:
        return e.wishlist ? -ts : e.unitPrice;
      case _ItemSortField.acquired:
        return e.wishlist
            ? ts
            : e.acquiredDate.millisecondsSinceEpoch.toDouble();
    }
  }

  int _compareItems(Item a, Item b) {
    final cmp = _sortKey(a).compareTo(_sortKey(b));
    return _sortAscending ? cmp : -cmp;
  }

  // 统计数据不包含愿望单物品（攒满转已拥有后参与计算）
  List<Item> get _ownedItems => _items.where((e) => !e.wishlist).toList();

  double get _totalValue =>
      _ownedItems.fold(0.0, (sum, e) => sum + e.actualPrice);

  double get _dailyCost => _ownedItems
          .where((e) => e.calcMethod == 0 && e.lostDate == null)
          .fold(0.0, (sum, e) {
        final days = e.acquiredDays;
        return days > 0 ? sum + e.actualPrice / days : sum;
      });

  double get _perUseCost => _ownedItems
          .where((e) => e.calcMethod == 1 && e.lostDate == null)
          .fold(0.0, (sum, e) {
        final n = e.usageCount < 1 ? 1 : e.usageCount;
        return sum + e.actualPrice / n;
      });

  String _sortFieldLabel(_ItemSortField f) {
    switch (f) {
      case _ItemSortField.usage:
        return '使用次数';
      case _ItemSortField.days:
        return '使用天数';
      case _ItemSortField.price:
        return '购买价格';
      case _ItemSortField.avgCost:
        return '平均成本';
      case _ItemSortField.acquired:
        return '购买时间';
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchCtrl.clear();
      }
    });
  }

  bool get isSearching => _searching;

  void closeSearch() {
    if (_searching) _toggleSearch();
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                    const Text('排序方式',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF24382F))),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _ItemSortField.values.map((f) {
                        final sel = f == _sortField;
                        return GestureDetector(
                          onTap: () => setSheetState(() => _sortField = f),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color:
                                  sel ? const Color(0xFF3E8E6D) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: sel
                                    ? const Color(0xFF3E8E6D)
                                    : const Color(0xFFE4F2EB),
                              ),
                            ),
                            child: Text(
                              _sortFieldLabel(f),
                              style: TextStyle(
                                fontSize: 13,
                                color: sel
                                    ? Colors.white
                                    : const Color(0xFF647A70),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: Pressable(
                        enabled: true,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() {});
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('完成', style: TextStyle(fontSize: 15)),
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
          const Expanded(child: ListSkeleton(count: 4, withAvatar: false))
        else ...[
          _buildFilterBar(),
          const Divider(height: 1, color: Color(0xFFE8EDF5)),
          _buildDataView(),
          const Divider(height: 1, color: Color(0xFFE8EDF5)),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF3E8E6D),
              onRefresh: _load,
              child: _filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        EmptyState(
                          icon: '🎒',
                          title: _searching ? '没有匹配的物品' : '还没有物品',
                          subtitle: _searching ? '换个关键词试试' : '点右下角 + 添加第一件',
                        ),
                      ],
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
                          key: ValueKey(it.id),
                          item: it,
                          onTap: () => _openEditor(it),
                          onLongPress: () => _showItemMenu(it),
                          onUse: !it.wishlist && it.calcMethod == 1
                              ? () => _incrementUsage(it)
                              : null,
                          onAdjustSaved:
                              it.wishlist ? (d) => _adjustSaved(it, d) : null,
                        );
                      },
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 48,
      color: const Color(0xB33E8E6D),
      child: Row(
        children: [
          IconButton(
            icon: const AppIcon(AppIcons.menu, color: Colors.white),
            onPressed: widget.onOpenMenu,
          ),
          // 页面标题：与资产全景主页顶栏一致（菜单键右侧、白色 17 号加粗）
          if (!_searching)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('物品',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
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
                      autofocus: false,
                      style: const TextStyle(
                          fontSize: 15, color: Color(0xFF24382F)),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: const InputDecoration(
                        hintText: '搜索物品…',
                        hintStyle: TextStyle(color: Color(0xFF8FA09A)),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  )
                : const SizedBox(),
          ),
          // 升/降序切换（排序方式按钮左侧）
          IconButton(
            tooltip: _sortAscending ? '正序' : '倒序',
            icon: AppIcon(
              _sortAscending ? AppIcons.arrowUp : AppIcons.arrowDn,
              size: 20,
              color: Colors.white,
            ),
            onPressed: () {
              Haptics.light();
              setState(() => _sortAscending = !_sortAscending);
            },
          ),
          // 排序方式（底部弹出选择排序字段），位于顶栏最右侧
          // 图标与其他主页的筛选按钮统一（filter_list 三条渐变横线）
          IconButton(
            tooltip: '排序方式',
            icon: const AppIcon(AppIcons.filter, size: 24, color: Colors.white),
            onPressed: _showSortSheet,
          ),
          const SizedBox(width: 4),
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
          _buildDataItem('物品数', '${_ownedItems.length}'),
          _buildDivider(),
          _buildDataItem('总价值', '¥${_totalValue.toStringAsFixed(0)}'),
          _buildDivider(),
          _buildCostItem(),
        ],
      ),
    );
  }

  Widget _buildCostItem() {
    final label = _costByUse ? '次均成本' : '日均成本';
    final value = _costByUse
        ? '¥${_perUseCost.toStringAsFixed(2)}'
        : '¥${_dailyCost.toStringAsFixed(2)}';
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _costByUse = !_costByUse),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3E8E6D),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF8FA09A)),
                ),
                const SizedBox(width: 2),
                const AppIcon(AppIcons.swapV, size: 14, color: Color(0xFF8FA09A)),
              ],
            ),
          ],
        ),
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
              color: Color(0xFF3E8E6D),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF8FA09A)),
          ),
        ],
      ),
    );
  }

  /// 分类切换条：与日记主页「按月 / 按年 / 全部」同款样式与动画 ——
  /// 等宽文字标签 + 底部 40×3 绿色滑块（AnimatedPositioned 250ms）。
  Widget _buildFilterBar() {
    const labels = <_ItemFilter, String>{
      _ItemFilter.all: '全部',
      _ItemFilter.owning: '拥有中',
      _ItemFilter.lost: '已失去',
      _ItemFilter.wishlist: '愿望单',
    };
    final keys = labels.keys.toList();
    final index = keys.indexOf(_filter);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = constraints.maxWidth / keys.length;
        final left = index * cellW + (cellW - 40) / 2;
        return Container(
          height: 48,
          color: Colors.white,
          child: Stack(
            children: [
              Row(
                children: List.generate(keys.length, (i) {
                  final selected = keys[i] == _filter;
                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        if (selected) return;
                        Haptics.light();
                        setState(() => _filter = keys[i]);
                      },
                      child: Center(
                        child: Text(
                          labels[keys[i]]!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? const Color(0xFF3E8E6D)
                                : const Color(0xFF647A70),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: left,
                bottom: 0,
                child: Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3E8E6D),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDivider() =>
      Container(width: 1, height: 30, color: const Color(0xFFE8EDF5));
}

class _ItemCard extends StatefulWidget {
  final Item item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress; // 长按：编辑 / 删除
  final VoidCallback? onUse;
  final ValueChanged<int>? onAdjustSaved; // 愿望单 +1/-1 攒钱

  const _ItemCard(
      {Key? key,
      required this.item,
      required this.onTap,
      this.onLongPress,
      this.onUse,
      this.onAdjustSaved})
      : super(key: key);

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  Item get item => widget.item;

  double _dx = 0; // 滑动位移
  static const double _maxDx = 90;
  static const double _triggerDx = 55;

  @override
  Widget build(BuildContext context) {
    final wishlist = item.wishlist;
    final child = wishlist
        ? _buildWishlistBody()
        : _buildOwnedBody(item.lostDate != null);
    if (!wishlist) {
      return _buildAnimatedCard(child);
    }
    // 愿望单：左右滑动攒钱（页面手势闸门：滑动期间菜单让位）
    return PageGestureGate(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) =>
            setState(() => _dx = (_dx + d.delta.dx).clamp(-_maxDx, _maxDx)),
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (_dx < -_triggerDx || v < -600) {
            widget.onAdjustSaved?.call(-1);
          } else if (_dx > _triggerDx || v > 600) {
            widget.onAdjustSaved?.call(1);
          }
          setState(() => _dx = 0);
        },
        onHorizontalDragCancel: () => setState(() => _dx = 0),
        child: _buildAnimatedCard(child),
      ),
    );
  }

  Widget _buildAnimatedCard(Widget child) {
    return Pressable(
      child:   AnimatedContainer(
        duration: _dx == 0
            ? const Duration(milliseconds: 300)
            : Duration.zero, // 松手后自然回弹
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(_dx, 0, 0),
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: item.wishlist
              ? const Color(0xFFFBE9EC) // 低饱和度淡粉色
              : (item.lostDate != null ? const Color(0xFFE1ECE6) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          // 愿望单物品：红色描边
          border: item.wishlist
              ? Border.all(color: const Color(0xFFCB5C50), width: 1.5)
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: animation, child: child),
            ),
            // key 随状态变化触发自然过渡
            child: item.wishlist
                ? _buildWishlistBody()
                : _buildOwnedBody(item.lostDate != null),
          ),
        ),
      )
    );;
  }

  // ---------- 愿望单卡片 ----------
  Widget _buildWishlistBody() {
    return Stack(
      fit: StackFit.expand,
      key: const ValueKey('wishlist'),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EntryIcon(item.icon, size: 40),
              const SizedBox(height: 6),
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF24382F),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '已攒 ¥${_fmt(item.savedAmount)}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF3E8E6D)),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: _buildProgressbar(),
              ),
            ],
          ),
        ),
        // 左上角 ❤️（Lucide 细线心形，主题红）
        Positioned(
          top: 8,
          left: 10,
          child: EntryIcon('❤️', size: 13, color: Color(0xFFCB5C50)),
        ),
        // 右上角物品总价
        Positioned(
          top: 8,
          right: 10,
          child: Text(
            '¥${_fmt(item.price)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFFB58793)),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressbar() {
    final pct = (item.progress * 100).round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 9,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Container(color: const Color(0xFFDFEAE5)),
            // 绿色完成块从左侧往右侧增加（与编辑页进度条一致）
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: item.progress,
              child: Container(color: const Color(0xFF3E8E6D)),
            ),
            Center(
              child: Text(
                '$pct%',
                style: const TextStyle(
                  fontSize: 7,
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
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  // ---------- 已拥有 / 已失去卡片 ----------
  Widget _buildOwnedBody(bool lost) {
    final unitLabel = item.calcMethod == 1 ? '次' : '天';
    final usageLabel = item.calcMethod == 1
        ? '使用 ${item.usageCount} 次'
        : '已用 ${item.acquiredDays} 天';
    return Stack(
      fit: StackFit.expand,
      key: const ValueKey('owned'),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Opacity(
                opacity: lost ? 0.5 : 1,
                child: EntryIcon(item.icon, size: 40),
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
                      lost ? const Color(0xFF8FA09A) : const Color(0xFF24382F),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '¥${item.unitPrice.toStringAsFixed(2)}/$unitLabel',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      lost ? const Color(0xFFAFBFB8) : const Color(0xFF3E8E6D),
                ),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: widget.onUse,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  usageLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: lost
                        ? const Color(0xFFAFBFB8)
                        : const Color(0xFF8FA09A),
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 8,
          right: 10,
          child: Text(
            '¥${item.actualPrice.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 11,
              color: lost ? const Color(0xFFAFBFB8) : const Color(0xFF8FA09A),
            ),
          ),
        ),
      ],
    );
  }
}
