import 'dart:async';

import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';

import '../utils/app_toast.dart';
import '../services/trash_storage.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
import '../utils/app_sheet.dart';
/// 回收站主页。
/// 交互与其它主页一致：顶部蓝色三横杠 + 标题、左右滑由 HomeScreen 统一处理。
/// 保存用户删除的笔记 / 物品 / 事件 / 资产，最长 7 天。
///
/// 还原与删除都不再挂在每张卡片上：
/// - 顶栏「还原」弹出菜单：选择还原（选择模式，单选 / 多选）/ 全部还原；
/// - 顶栏「删除」弹出菜单：选择删除（选择模式）/ 清空回收站。
class TrashScreen extends StatefulWidget {
  final VoidCallback onOpenMenu;

  const TrashScreen({Key? key, required this.onOpenMenu}) : super(key: key);

  @override
  State<TrashScreen> createState() => TrashScreenState();
}

/// 选择模式用途
enum _SelectMode { restore, purge }

class TrashScreenState extends State<TrashScreen> {
  List<TrashEntry> _entries = [];
  bool _loading = true;

  /// 收纳栏分类；null = 全部
  TrashKind? _category;

  /// 当前排序：删除时间倒序（新删的在上）
  bool _newestFirst = true;

  /// 选择模式；null = 普通浏览态
  _SelectMode? _mode;

  /// 已选中的回收站记录 id
  final Set<String> _selected = <String>{};

  /// 每分钟刷新一次：剩余天数跨天实时递减。
  /// 原来直接 `_load()`，页面开着就每分钟读一次文件 + 全量解析；
  /// 现在只做内存内的重建（daysLeft 由当前时间实时算出），
  /// 仅当真的有条目过期时才回读存储，顺带清理过期登记。
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final alive = _entries.where((e) => e.daysLeft > 0).toList();
    final hadExpired = alive.length != _entries.length;
    setState(() => _entries = alive);
    if (hadExpired) _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await TrashStorage.load();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
      // 选中的条目可能已被还原 / 删除，剔除失效 id
      final aliveIds = list.map((e) => e.id).toSet();
      _selected.removeWhere((id) => !aliveIds.contains(id));
      if (_entries.isEmpty) {
        _mode = null;
        _selected.clear();
      }
    });
  }

  /// 外部（主页切到本页时）主动刷新
  void reload() => _load();

  /// 供主页返回键调用：选择态优先退出，其次清空筛选
  bool handleBack() {
    if (_mode != null) {
      setState(() {
        _mode = null;
        _selected.clear();
      });
      return true;
    }
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

  // ---------- 选择模式 ----------

  void _enterSelect(_SelectMode mode) {
    Haptics.light();
    setState(() {
      _mode = mode;
      _selected.clear();
    });
  }

  void _exitSelect() {
    setState(() {
      _mode = null;
      _selected.clear();
    });
  }

  void _toggle(TrashEntry e) {
    Haptics.light();
    setState(() {
      if (!_selected.remove(e.id)) _selected.add(e.id);
    });
  }

  bool get _allSelected {
    final ids = _filtered.map((e) => e.id).toList();
    return ids.isNotEmpty && ids.every(_selected.contains);
  }

  void _toggleSelectAll() {
    Haptics.light();
    final ids = _filtered.map((e) => e.id).toList();
    setState(() {
      if (_allSelected) {
        _selected.removeAll(ids);
      } else {
        _selected.addAll(ids);
      }
    });
  }

  Future<void> _confirm() async {
    final picked = _filtered.where((e) => _selected.contains(e.id)).toList();
    if (picked.isEmpty) {
      _toast('请先选择内容');
      return;
    }
    if (_mode == _SelectMode.restore) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppPalette.c(0xFFFFFFFF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('确认要还原吗?', style: TextStyle(fontSize: 17)),
          content: Text('将还原所选的 ${picked.length} 项内容。',
              style: const TextStyle(fontSize: 13, height: 1.6)),
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
                  child: Text('还原',
                      style: TextStyle(color: AppPalette.c(0xFF3E8E6D)))),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final n = await TrashStorage.restoreMany(picked);
      if (!mounted) return;
      setState(() {
        _mode = null;
        _selected.clear();
      });
      await _load();
      if (!mounted) return;
      _toast('已还原 $n 项');
      return;
    }

    Haptics.light();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.c(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('彻底删除 ${picked.length} 项?', style: const TextStyle(fontSize: 17)),
        content: const Text('所选内容将被永久删除，无法恢复。',
            style: TextStyle(fontSize: 13, height: 1.6)),
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
                child: const Text('彻底删除',
                    style: TextStyle(color: Color(0xFFCB5C50)))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await TrashStorage.removeMany(picked.map((e) => e.id));
    if (!mounted) return;
    setState(() {
      _mode = null;
      _selected.clear();
    });
    await _load();
    if (!mounted) return;
    _toast('已彻底删除 ${picked.length} 项');
  }

  /// 卡片长按菜单（与主页卡片长按同一套样式）：还原 / 彻底删除 单条。
  /// 普通浏览态才可用；选择态下长按不弹菜单，避免与勾选冲突。
  Future<void> _showCardActions(TrashEntry entry) async {
    Haptics.mediumNow();
    final action = await AppSheet.show<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            ListTile(
              key: const ValueKey('trash_card_action_restore'),
              leading:
                  AppIcon(AppIcons.restore, color: AppPalette.c(0xFF3E8E6D)),
              title: const Text('还原', style: TextStyle(fontSize: 15)),
              onTap: () => Navigator.pop(ctx, 'restore'),
            ),
            ListTile(
              key: const ValueKey('trash_card_action_delete'),
              leading:
                  const AppIcon(AppIcons.delete, color: Color(0xFFCB5C50)),
              title: const Text('彻底删除',
                  style: TextStyle(fontSize: 15, color: Color(0xFFCB5C50))),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'restore') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppPalette.c(0xFFFFFFFF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('确认要还原吗?', style: TextStyle(fontSize: 17)),
          content: const Text('将还原这条内容。',
              style: TextStyle(fontSize: 13, height: 1.6)),
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
                  child: Text('还原',
                      style: TextStyle(color: AppPalette.c(0xFF3E8E6D)))),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await TrashStorage.restore(entry);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      _toast('已还原 1 项');
      return;
    }
    // 彻底删除不可逆，与其他删除操作一样走二次确认
    Haptics.light();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.c(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('彻底删除?', style: TextStyle(fontSize: 17)),
        content: const Text('该内容将被永久删除，无法恢复。',
            style: TextStyle(fontSize: 13, height: 1.6)),
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
                child: const Text('彻底删除',
                    style: TextStyle(color: Color(0xFFCB5C50)))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await TrashStorage.remove(entry.id);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    _toast('已彻底删除 1 项');
  }

  // ---------- 清空回收站 ----------

  Future<void> _clearAll() async {
    if (_entries.isEmpty) return;
    final scope = _category;
    final n = scope == null ? _entries.length : _countOf(scope);
    if (n == 0) return;
    Haptics.light();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.c(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('清空${scope == null ? '回收站' : scope.label}?',
            style: const TextStyle(fontSize: 17)),
        content: Text('共 $n 项将被永久删除，无法恢复。',
            style: const TextStyle(fontSize: 13, height: 1.6)),
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
                    const Text('清空', style: TextStyle(color: Color(0xFFCB5C50)))),
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

  /// 还原按钮的二级菜单：选择还原 / 全部还原
  Future<void> _showRestoreMenu() async {
    Haptics.light();
    final action = await AppSheet.show<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            _menuRow(
              key: const ValueKey('trash-menu-restore-selective'),
              icon: AppIcons.check,
              label: '选择还原',
              hint: '勾选要还原的内容',
              color: AppPalette.c(0xFF24382F),
              onTap: () => Navigator.pop(ctx, 'selective'),
            ),
            Divider(height: 1, indent: 56, color: AppPalette.c(0xFFEFF5F1)),
            _menuRow(
              key: const ValueKey('trash-menu-restore-all'),
              icon: AppIcons.restore,
              label: '全部还原',
              hint: _category == null
                  ? '恢复回收站中的全部内容'
                  : '恢复「${_category!.label}」分类下的内容',
              color: AppPalette.c(0xFF24382F),
              onTap: () => Navigator.pop(ctx, 'all'),
            ),
            // 抽屉不再放「取消」按钮：点遮罩 / 下滑即可关闭，
            // 与其它主页的长按菜单保持一致
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'selective') {
      _enterSelect(_SelectMode.restore);
    } else {
      await _restoreAll();
    }
  }

  /// 全部还原：按当前分类范围一次性恢复，二次确认后批量还原
  Future<void> _restoreAll() async {
    final picked = _filtered;
    if (picked.isEmpty) return;
    Haptics.light();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.c(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('全部还原?', style: TextStyle(fontSize: 17)),
        content: Text('共 ${picked.length} 项将恢复到原位置。',
            style: const TextStyle(fontSize: 13, height: 1.6)),
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
                child: Text('还原',
                    style: TextStyle(color: AppPalette.c(0xFF3E8E6D)))),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = await TrashStorage.restoreMany(picked);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    _toast('已还原 $n 项');
  }

  /// 删除按钮的二级菜单：选择删除 / 清空回收站
  Future<void> _showDeleteMenu() async {
    Haptics.light();
    final action = await AppSheet.show<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            _menuRow(
              key: const ValueKey('trash-menu-selective'),
              icon: AppIcons.check,
              label: '选择删除',
              hint: '勾选要彻底删除的内容',
              color: AppPalette.c(0xFF24382F),
              onTap: () => Navigator.pop(ctx, 'selective'),
            ),
            Divider(height: 1, indent: 56, color: AppPalette.c(0xFFEFF5F1)),
            _menuRow(
              key: const ValueKey('trash-menu-clear'),
              icon: AppIcons.trash,
              label: '清空回收站',
              hint: _category == null
                  ? '永久删除全部内容'
                  : '永久删除「${_category!.label}」分类下的内容',
              color: AppPalette.c(0xFF24382F),
              onTap: () => Navigator.pop(ctx, 'clear'),
            ),
            // 抽屉不再放「取消」按钮：点遮罩 / 下滑即可关闭
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'selective') {
      _enterSelect(_SelectMode.purge);
    } else {
      await _clearAll();
    }
  }

  Widget _menuRow({
    required Key key,
    required String icon,
    required String label,
    required String hint,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Row(
          children: [
            AppIcon(icon, size: 19, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: color)),
                  const SizedBox(height: 2),
                  Text(hint,
                      style: TextStyle(
                          fontSize: 12, color: AppPalette.c(0xFF8FA09A))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 回收站操作反馈：走全局去重提示（连点不会刷一屏）
  void _toast(String msg) => AppToast.show(context, msg);

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
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

  /// v4.9.48：底部提示语取消吸附页面底部，改为随内容滚动、置于内容最底部
  /// （与笔记浏览页时间/地点信息行同款处理，需滑到底才可见）。
  Widget _buildTipText() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Text(
          '超过时间的内容将彻底删除',
          style: TextStyle(
              fontSize: 11, color: AppPalette.c(0xFF8FA09A).withOpacity(0.9)),
        ),
      ),
    );
  }

  /// 顶栏：普通态（三横杠 / 还原 / 删除）与选择态（关闭 / 已选 / 全选 / 确认）
  Widget _buildTopBar() {
    final selecting = _mode != null;
    return Container(
      height: 48,
      color: AppPalette.c(0xB33E8E6D),
      child: Row(
        children: [
          if (selecting)
            IconButton(
              key: const ValueKey('trash-cancel'),
              tooltip: '取消',
              icon: const AppIcon(AppIcons.close, color: Colors.white, size: 20),
              onPressed: _exitSelect,
            )
          else
            IconButton(
              icon: const AppIcon(AppIcons.menu, color: Colors.white),
              onPressed: widget.onOpenMenu,
            ),
          const SizedBox(width: 4),
          Text(
            selecting ? '已选 ${_selected.length} 项' : '回收站',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const Spacer(),
          if (selecting) ...[
            TextButton(
              key: const ValueKey('trash-select-all'),
              onPressed: _filtered.isEmpty ? null : _toggleSelectAll,
              child: Text(
                _allSelected ? '取消全选' : '全选',
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
            IconButton(
              key: const ValueKey('trash-confirm'),
              tooltip: '确认',
              icon: Opacity(
                opacity: _selected.isEmpty ? 0.4 : 1,
                child: const AppIcon(AppIcons.check,
                    color: Colors.white, size: 22),
              ),
              onPressed: _selected.isEmpty ? null : _confirm,
            ),
          ] else if (_entries.isNotEmpty) ...[
            IconButton(
              key: const ValueKey('trash-restore'),
              tooltip: '还原',
              icon: const AppIcon(AppIcons.restore,
                  color: Colors.white, size: 21),
              onPressed: _showRestoreMenu,
            ),
            IconButton(
              key: const ValueKey('trash-delete'),
              tooltip: '删除',
              // 删除类图标全站统一为普通垃圾桶轮廓（与笔记卡片右下角一致）
              icon: const AppIcon(AppIcons.delete,
                  color: Colors.white, size: 22),
              onPressed: _showDeleteMenu,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(AppIcons.delete,
                      size: 54,
                      color: AppPalette.c(0xFF8FA09A).withOpacity(0.55)),
                  const SizedBox(height: 14),
                  Text(
                    '回收站是空的',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.c(0xFF647A70)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '删除的内容支持7日内恢复哦～',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.7,
                        color: AppPalette.c(0xFF8FA09A).withOpacity(0.95)),
                  ),
                ],
              ),
            ),
          ),
        ),
        // v4.9.48：提示语置于空态最底部，与有内容态同款（页面最底部）
        _buildTipText(),
      ],
    );
  }

  Widget _buildBody() {
    final list = _filtered;
    return Column(
      children: [
        // 选择模式不再显示说明条：顶栏已有「已选 x 项 / 全选 / 确认」，
        // 分类筛选栏在选择态一并隐藏，避免切换分类把已选内容弄乱。
        if (_mode == null) _buildFilterBar(),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    '${_category?.label ?? ''}没有内容',
                    style: TextStyle(
                        fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(
                      16, _mode == null ? 6 : 14, 16, 12),
                  children: [
                    for (final e in list) ...[
                      _buildCard(e),
                      const SizedBox(height: 8),
                    ],
                    // v4.9.48：提示语置于列表末尾，随内容滚动，滑到底才可见
                    _buildTipText(),
                  ],
                ),
        ),
      ],
    );
  }

  /// 收纳栏：全部 / 笔记 / 物品 / 事件 / 资产（与全局搜索同款横滑胶囊）
  Widget _buildFilterBar() {
    final cats = <_Cat>[
      _Cat('全部', _entries.length, null),
      for (final k in TrashKind.values) _Cat(k.label, _countOf(k), k),
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
                    setState(() {
                      _category = c.kind;
                      _selected.clear();
                    });
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? AppPalette.c(0xB33E8E6D) : AppPalette.c(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected
                        ? AppPalette.c(0xB33E8E6D)
                        : AppPalette.c(0xFFE8EDF5)),
              ),
              child: Center(
                child: Text('${c.name} ${c.count}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : (disabled
                                ? AppPalette.c(0xFFC6D6CD)
                                : AppPalette.c(0xFF24382F)))),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCard(TrashEntry e) {
    final left = e.daysLeft;
    // 剩余 ≤2 天：橙色警示
    final urgent = left <= 2;
    final selecting = _mode != null;
    final picked = _selected.contains(e.id);

    final card = Container(
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: picked ? AppPalette.c(0xFF3E8E6D) : Colors.transparent,
          width: 1.4,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        child: Row(
          // v4.9.25：圆圈选择器与右侧文字块、剩余天数垂直居中对齐
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (selecting) ...[
              Container(
                width: 20,
                height: 20,
                // Container 不给 alignment 时 child 会被 20×20 的紧约束撑开，
                // 13px 的对勾被拉到左上角而不是落在圆圈中心。
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: picked ? AppPalette.c(0xFF3E8E6D) : AppPalette.c(0xFFFFFFFF),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: picked
                        ? AppPalette.c(0xFF3E8E6D)
                        : AppPalette.c(0xFFC6D6CD),
                  ),
                ),
                child: picked
                    ? const AppIcon(AppIcons.check,
                        size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.c(0xFF24382F)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    e.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: AppPalette.c(0xFF8FA09A)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 剩余天数：居中对齐，字号收小
            Text(
                left <= 1 ? '今天到期' : '$left 天后消失',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: urgent
                        ? const Color(0xFFF08C3A)
                        : AppPalette.c(0xFF7C8F86)),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      key: ValueKey('trash-entry-${e.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: selecting ? () => _toggle(e) : null,
      // 长按弹单条操作菜单；选择态下交给 onTap 勾选，不弹菜单
      onLongPress: selecting ? null : () => _showCardActions(e),
      child: selecting ? card : Pressable(child: card),
    );
  }
}

class _Cat {
  final String name;
  final int count;
  final TrashKind? kind;
  const _Cat(this.name, this.count, this.kind);
}
