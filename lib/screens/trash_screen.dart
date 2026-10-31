import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/trash_storage.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';

/// 回收站主页。
/// 交互与其它主页一致：顶部蓝色三横杠 + 标题、左右滑由 HomeScreen 统一处理。
/// 保存用户删除的笔记 / 物品 / 事件 / 资产，最长 7 天，可还原或二次删除。
class TrashScreen extends StatefulWidget {
  final VoidCallback onOpenMenu;

  const TrashScreen({Key? key, required this.onOpenMenu}) : super(key: key);

  @override
  State<TrashScreen> createState() => TrashScreenState();
}

class TrashScreenState extends State<TrashScreen> {
  List<TrashEntry> _entries = [];
  bool _loading = true;

  /// 收纳栏分类；null = 全部
  TrashKind? _category;

  /// 当前排序：删除时间倒序（新删的在上）
  bool _newestFirst = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await TrashStorage.load();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  /// 外部（主页切到本页时）主动刷新
  void reload() => _load();

  /// 供主页返回键调用：清空筛选
  bool handleBack() {
    if (_category != null) {
      setState(() => _category = null);
      return true;
    }
    return false;
  }

  List<TrashEntry> get _filtered {
    final list = _category == null
        ? List<TrashEntry>.from(_entries)
        : _entries.where((e) => e.kind == _category).toList();
    list.sort((a, b) => _newestFirst
        ? b.deletedAt.compareTo(a.deletedAt)
        : a.deletedAt.compareTo(b.deletedAt));
    return list;
  }

  int _countOf(TrashKind k) => _entries.where((e) => e.kind == k).length;

  // ---------- 操作 ----------

  Future<void> _restore(TrashEntry e) async {
    Haptics.light();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('还原「${e.title}」?'),
        content: Text('将还原到${e.kind.label}页，回收站记录同时移除。'),
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
                child: const Text('还原')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TrashStorage.restore(e);
    await _load();
    if (!mounted) return;
    _toast('已还原');
  }

  /// 二次删除：彻底删除，不可恢复
  Future<void> _purge(TrashEntry e) async {
    Haptics.light();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('彻底删除?'),
        content: Text('「${e.title}」将被永久删除，无法恢复。'),
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
                child:
                    const Text('彻底删除', style: TextStyle(color: Colors.red))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TrashStorage.remove(e.id);
    await _load();
    if (!mounted) return;
    _toast('已彻底删除');
  }

  Future<void> _clearAll() async {
    if (_entries.isEmpty) return;
    final scope = _category;
    final n = scope == null ? _entries.length : _countOf(scope);
    if (n == 0) return;
    Haptics.light();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('清空${scope == null ? '回收站' : scope.label}?'),
        content: Text('共 $n 项将被永久删除，无法恢复。'),
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
                child: const Text('清空', style: TextStyle(color: Colors.red))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await TrashStorage.clear(scope);
    await _load();
    if (!mounted) return;
    _toast('已清空');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating),
    );
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: _loading
              ? const SizedBox()
              : _entries.isEmpty
                  ? _buildEmpty()
                  : _buildBody(),
        ),
      ],
    );
  }

  /// 顶栏：与其它主页同款（高 48、0xB3 蓝、三横杠）
  Widget _buildTopBar() {
    final subtitle = _entries.isEmpty
        ? ''
        : '${_entries.length} 项 · 最长保留 7 天';
    return Container(
      height: 48,
      color: const Color(0xB33B6FE0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: widget.onOpenMenu,
          ),
          const SizedBox(width: 4),
          const Text(
            '回收站',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white),
          ),
          const SizedBox(width: 8),
          if (subtitle.isNotEmpty)
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.white.withOpacity(0.85)),
              ),
            )
          else
            const Spacer(),
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_sweep_outlined,
                  color: Colors.white, size: 22),
              onPressed: _clearAll,
            ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_outline,
                size: 54,
                color: const Color(0xFF9AA8BF).withOpacity(0.55)),
            const SizedBox(height: 14),
            const Text(
              '回收站是空的',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A6B82)),
            ),
            const SizedBox(height: 8),
            Text(
              '删除的笔记、物品、事件、资产会先放到这里\n7 天内可随时还原',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.7,
                  color: const Color(0xFF9AA8BF).withOpacity(0.95)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final list = _filtered;
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    '${_category?.label ?? ''}没有内容',
                    style: const TextStyle(
                        fontSize: 13.5, color: Color(0xFF9AA8BF)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  children: [
                    for (final e in list) ...[
                      _buildCard(e),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        '超过 7 天的内容会自动彻底删除',
                        style: TextStyle(
                            fontSize: 11.5,
                            color:
                                const Color(0xFF9AA8BF).withOpacity(0.9)),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// 收纳栏：全部 / 笔记 / 物品 / 事件 / 资产（与全局搜索同款横滑胶囊）
  Widget _buildFilterBar() {
    final cats = <_Cat>[
      _Cat('全部', _entries.length, Icons.all_inbox_outlined, null),
      for (final k in TrashKind.values)
        _Cat(k.label, _countOf(k), _iconOf(k), k),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = cats[i];
          final selected = _category == c.kind;
          final disabled = c.kind != null && c.count == 0;
          return GestureDetector(
            onTap: disabled
                ? null
                : () {
                    Haptics.light();
                    setState(() => _category = c.kind);
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? const Color(0xB33B6FE0) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: selected
                        ? const Color(0xB33B6FE0)
                        : const Color(0xFFE8EDF5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.icon,
                      size: 14,
                      color: selected
                          ? Colors.white
                          : (disabled
                              ? const Color(0xFFC4CEDD)
                              : const Color(0xFF3B6FE0))),
                  const SizedBox(width: 5),
                  Text('${c.name} ${c.count}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : (disabled
                                  ? const Color(0xFFC4CEDD)
                                  : const Color(0xFF2A3B52)))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconOf(TrashKind k) {
    switch (k) {
      case TrashKind.diary:
        return Icons.book_outlined;
      case TrashKind.item:
        return Icons.inventory_2_outlined;
      case TrashKind.event:
        return Icons.event_available_outlined;
      case TrashKind.asset:
        return Icons.account_balance_outlined;
    }
  }

  Widget _buildCard(TrashEntry e) {
    final left = e.daysLeft;
    // 剩余 ≤2 天：橙色警示
    final urgent = left <= 2;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _bgOf(e.kind),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_iconOf(e.kind),
                      size: 18, color: _fgOf(e.kind)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              e.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2A3B52)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // 类型小铭牌
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: _bgOf(e.kind),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(e.kind.label,
                                style: TextStyle(
                                    fontSize: 9.5,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                    color: _fgOf(e.kind))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        e.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF9AA8BF)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 剩余天数
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: urgent
                        ? const Color(0xFFFBEEE9)
                        : const Color(0xFFF3F6FB),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    left <= 1 ? '今天到期' : '$left 天后消失',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: urgent
                            ? const Color(0xFFF08C3A)
                            : const Color(0xFF8A99B3)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F3F8)),
          // 操作区：还原 / 彻底删除
          Row(
            children: [
              Expanded(
                child: _buildAction(
                  icon: Icons.restore,
                  label: '还原',
                  color: const Color(0xFF3B6FE0),
                  onTap: () => _restore(e),
                ),
              ),
              Container(width: 1, height: 20, color: const Color(0xFFF0F3F8)),
              Expanded(
                child: _buildAction(
                  icon: Icons.delete_forever_outlined,
                  label: '彻底删除',
                  color: const Color(0xFFE0576A),
                  onTap: () => _purge(e),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Color _bgOf(TrashKind k) {
    switch (k) {
      case TrashKind.diary:
        return const Color(0xFFE8F0FE);
      case TrashKind.item:
        return const Color(0xFFE7F3EA);
      case TrashKind.event:
        return const Color(0xFFFBEEE9);
      case TrashKind.asset:
        return const Color(0xFFEDF0F6);
    }
  }

  Color _fgOf(TrashKind k) {
    switch (k) {
      case TrashKind.diary:
        return const Color(0xFF3B6FE0);
      case TrashKind.item:
        return const Color(0xFF34A853);
      case TrashKind.event:
        return const Color(0xFFF08C3A);
      case TrashKind.asset:
        return const Color(0xFF5A6B82);
    }
  }
}

class _Cat {
  final String name;
  final int count;
  final IconData icon;
  final TrashKind? kind;
  const _Cat(this.name, this.count, this.icon, this.kind);
}
