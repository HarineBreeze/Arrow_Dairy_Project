import 'dart:async';

import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_toast.dart';
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
                    const Text('彻底删除', style: TextStyle(color: Color(0xFFCB5C50)))),
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
                child: const Text('清空', style: TextStyle(color: Color(0xFFCB5C50)))),
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

  /// 回收站操作反馈：走全局去重提示（连点「清空 / 还原」不会刷一屏）
  void _toast(String msg) => AppToast.show(context, msg);

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
    return Container(
      height: 48,
      color: const Color(0xB33E8E6D),
      child: Row(
        children: [
          IconButton(
            icon: const AppIcon(AppIcons.menu, color: Colors.white),
            onPressed: widget.onOpenMenu,
          ),
          const SizedBox(width: 4),
          const Text(
            '回收站',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white),
          ),
          const Spacer(),
          if (_entries.isNotEmpty)
            IconButton(
              tooltip: '清空',
              // 删除类图标全站统一为普通垃圾桶轮廓（与笔记卡片右下角一致）
              icon: const AppIcon(AppIcons.delete,
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
            AppIcon(AppIcons.delete,
                size: 54,
                color: const Color(0xFF8FA09A).withOpacity(0.55)),
            const SizedBox(height: 14),
            const Text(
              '回收站是空的',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF647A70)),
            ),
            const SizedBox(height: 8),
            Text(
              '删除的内容支持7日内恢复哦～',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: const Color(0xFF8FA09A).withOpacity(0.95)),
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
                        fontSize: 13, color: Color(0xFF8FA09A)),
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
                        '超过7天的内容将彻底删除',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                const Color(0xFF8FA09A).withOpacity(0.9)),
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
                    setState(() => _category = c.kind);
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: selected ? const Color(0xB33E8E6D) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected
                        ? const Color(0xB33E8E6D)
                        : const Color(0xFFE8EDF5)),
              ),
              child: Center(
                child: Text('${c.name} ${c.count}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : (disabled
                                ? const Color(0xFFC6D6CD)
                                : const Color(0xFF24382F)))),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            // 右侧留 12，让右上角的天数标签贴角
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF24382F)),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        e.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF8FA09A)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 剩余天数：移到卡片右上角，字号收小
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    left <= 1 ? '今天到期' : '$left 天后消失',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: urgent
                            ? const Color(0xFFF08C3A)
                            : const Color(0xFF7C8F86)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEFF5F1)),
          // 操作区：还原 / 彻底删除（纯文字，不再带图标）
          Row(
            children: [
              Expanded(
                child: _buildAction(
                  label: '还原',
                  color: const Color(0xFF3E8E6D),
                  onTap: () => _restore(e),
                ),
              ),
              Container(width: 1, height: 20, color: const Color(0xFFEFF5F1)),
              Expanded(
                child: _buildAction(
                  label: '彻底删除',
                  color: const Color(0xFFCB5C50),
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
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ),
      ),
    );
  }
}

class _Cat {
  final String name;
  final int count;
  final TrashKind? kind;
  const _Cat(this.name, this.count, this.kind);
}
