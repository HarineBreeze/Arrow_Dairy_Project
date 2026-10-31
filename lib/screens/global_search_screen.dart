import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_toast.dart';
import '../models/asset.dart';
import '../models/countdown_event.dart';
import '../models/diary_entry.dart';
import '../models/item.dart';
import '../services/asset_storage.dart';
import '../services/countdown_storage.dart';
import '../services/diary_storage.dart';
import '../services/item_storage.dart';
import 'asset_edit_screen.dart';
import 'countdown_edit_screen.dart';
import 'item_edit_screen.dart';
import 'note_view_screen.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';

/// 全局搜索主页：一个搜索框同时检索 笔记标题 / 物品名称 / 事件名称 / 资产备注。
/// 顶部搜索框持久保持；结果用「收纳栏」（笔记/物品/事件/资产 + 数量）+ 分区列表呈现。
///
/// 本页以「主页选项卡」形式嵌入 [HomeScreen] 的 Stack，与其它主页（写日记 /
/// 物品清单 / 重要事件 / 资产全景）一致：状态栏贯通、左右滑跟手拉出/收回
/// 菜单侧边栏，均由主页统一提供，这里只负责页内内容。
class GlobalSearchScreen extends StatefulWidget {
  final VoidCallback onOpenMenu;

  const GlobalSearchScreen({Key? key, required this.onOpenMenu})
      : super(key: key);

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  List<DiaryEntry> _diaries = [];
  List<Item> _items = [];
  List<CountdownEvent> _events = [];
  List<Asset> _assets = [];
  bool _loading = true;

  /// 资产全景已设置密码（加密访问）：资产不参与检索
  bool _assetLocked = false;

  /// 资产结果卡金额默认打码（关闭小眼睛）
  bool _hideAssetAmount = true;

  /// 当前选中的收纳栏分类；null = 全部
  String? _category;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final diaries = await DiaryStorage.load();
    final items = await ItemStorage.load();
    final events = await CountdownStorage.load();
    final assets = await AssetStorage.load();
    // 资产全景设置了密码 → 资产不参与全局检索
    final assetLocked = await AssetStorage.hasPin();
    if (!mounted) return;
    setState(() {
      _diaries = diaries;
      _items = items;
      _events = events;
      _assets = assetLocked ? const [] : assets;
      _assetLocked = assetLocked;
      _loading = false;
    });
  }

  // ---------- 检索 ----------

  List<DiaryEntry> get _hitDiaries {
    final q = _ctrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _diaries.where((e) => e.title.toLowerCase().contains(q)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  List<Item> get _hitItems {
    final q = _ctrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _items.where((e) => e.name.toLowerCase().contains(q)).toList()
      ..sort((a, b) => a.acquiredDate.compareTo(b.acquiredDate));
  }

  List<CountdownEvent> get _hitEvents {
    final q = _ctrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _events.where((e) => e.name.toLowerCase().contains(q)).toList()
      ..sort((a, b) => a.target.compareTo(b.target));
  }

  List<Asset> get _hitAssets {
    final q = _ctrl.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _assets.where((e) => e.note.toLowerCase().contains(q)).toList();
  }

  // ---------- 路由 ----------

  Route<T> _slideRoute<T>(Widget page) => PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, animation, __, child) {
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

  Future<T?> _push<T>(Widget page) => Navigator.of(context).push<T>(
        _slideRoute(page),
      );

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    final diaries = _hitDiaries;
    final items = _hitItems;
    final events = _hitEvents;
    final assets = _hitAssets;
    final query = _ctrl.text.trim();

    // 主页选项卡形态：不自带 Scaffold / 状态栏处理。状态栏贯通与
    // 左右滑跟手菜单均由 HomeScreen 统一提供，这里只输出页内内容。
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: _loading
              ? const SizedBox()
              : query.isEmpty
                  ? _buildEmptyHint()
                  : _buildResults(diaries, items, events, assets),
        ),
      ],
    );
  }

  /// 顶部持久搜索框（不默认吊起输入法，点击后才聚焦）。
  /// 作为主页选项卡：蓝色顶栏在 SafeArea 内容区内（状态栏区域由主页统一
  /// 铺蓝贯通），这里只铺一层 0xB3 蓝即可，与其它主页顶栏一致。
  Widget _buildSearchBar() {
    return Container(
      height: 56,
      color: const Color(0xB33B6FE0),
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            tooltip: '菜单',
            onPressed: widget.onOpenMenu,
          ),
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: Color(0xFF9AA8BF)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autofocus: false, // 进入页面不默认弹出输入法
                      style: const TextStyle(
                          fontSize: 15, color: Color(0xFF2A3B52)),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: const InputDecoration(
                        hintText: '搜索笔记 / 物品 / 事件 / 资产…',
                        hintStyle: TextStyle(color: Color(0xFF9AA8BF)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_ctrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _ctrl.clear();
                        setState(() {});
                      },
                      child: const Icon(Icons.close,
                          size: 16, color: Color(0xFF9AA8BF)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 未搜索时的空白提示
  Widget _buildEmptyHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_search,
                size: 56, color: const Color(0xFF9AA8BF).withOpacity(0.6)),
            const SizedBox(height: 14),
            const Text(
              '输入关键词，即可检索对应内容',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A6B82)),
            ),
            const SizedBox(height: 8),
            Text(
              '支持检索：笔记标题、物品名称、事件名称、资产备注',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: const Color(0xFF9AA8BF).withOpacity(0.9)),
            ),
          ],
        ),
      ),
    );
  }

  /// 结果区：收纳栏 + 分区列表
  Widget _buildResults(
    List<DiaryEntry> diaries,
    List<Item> items,
    List<CountdownEvent> events,
    List<Asset> assets,
  ) {
    final total = diaries.length + items.length + events.length + assets.length;
    if (total == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.search_off, size: 48, color: Color(0xFFC4CEDD)),
            SizedBox(height: 10),
            Text('没有匹配的内容',
                style: TextStyle(fontSize: 13.5, color: Color(0xFF9AA8BF))),
          ],
        ),
      );
    }

    // 收纳栏：从左到右固定顺序 笔记/物品/事件/资产
    final cats = <_SearchCategory>[
      _SearchCategory(
          '笔记', '${diaries.length} 篇', Icons.book_outlined, diaries.isNotEmpty),
      _SearchCategory('物品', '${items.length} 件', Icons.inventory_2_outlined,
          items.isNotEmpty),
      _SearchCategory('事件', '${events.length} 个',
          Icons.event_available_outlined, events.isNotEmpty),
      _SearchCategory('资产', _assetLocked ? '已加密' : '${assets.length} 项',
          Icons.account_balance_outlined, assets.isNotEmpty),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        // 收纳栏：类似笔记页置顶收纳栏的横滑样式
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: cats.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final c = cats[i];
              final selected = _category == c.name;
              return GestureDetector(
                onTap: () {
                  Haptics.light();
                  setState(() => _category = selected ? null : c.name);
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
                              : (c.hasHit
                                  ? const Color(0xFF3B6FE0)
                                  : const Color(0xFFC4CEDD))),
                      const SizedBox(width: 5),
                      Text('${c.name} ${c.count}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : (c.hasHit
                                      ? const Color(0xFF2A3B52)
                                      : const Color(0xFFC4CEDD)))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // 分区结果（按收纳栏选中状态过滤）
        if (_category == null || _category == '笔记')
          if (diaries.isNotEmpty)
            _buildSection(
              '笔记',
              Icons.book_outlined,
              diaries
                  .map((e) => _ResultRow(
                        icon: e.encrypted
                            ? Icons.lock_outline
                            : Icons.book_outlined,
                        iconBg: const Color(0xFFE8F0FE),
                        iconColor: const Color(0xFF3B6FE0),
                        title: e.encrypted
                            ? (e.subtitle.isNotEmpty ? e.subtitle : '加密笔记')
                            : (e.title.isNotEmpty ? e.title : '（无标题）'),
                        subtitle:
                            '${e.publishDate.year}.${e.publishDate.month.toString().padLeft(2, '0')}.${e.publishDate.day.toString().padLeft(2, '0')} · ${e.encrypted ? '已加密' : e.mood}',
                        onTap: () => _openNote(e),
                      ))
                  .toList(),
            ),
        if (_category == null || _category == '物品')
          if (items.isNotEmpty)
            _buildSection(
              '物品',
              Icons.inventory_2_outlined,
              items
                  .map((e) => _ResultRow(
                        icon: Icons.inventory_2_outlined,
                        iconBg: const Color(0xFFE7F3EA),
                        iconColor: const Color(0xFF34A853),
                        title: e.name,
                        subtitle:
                            '${e.category} · ¥${e.price.toStringAsFixed(e.price.truncateToDouble() == e.price ? 0 : 2)}',
                        onTap: () async {
                          await _push(ItemEditScreen(item: e));
                          _loadAll();
                        },
                      ))
                  .toList(),
            ),
        if (_category == null || _category == '事件')
          if (events.isNotEmpty)
            _buildSection(
              '事件',
              Icons.event_available_outlined,
              events
                  .map((e) => _ResultRow(
                        icon: Icons.event_available_outlined,
                        iconBg: const Color(0xFFFBEEE9),
                        iconColor: const Color(0xFFF08C3A),
                        title: e.name,
                        subtitle:
                            '${e.target.year}.${e.target.month.toString().padLeft(2, '0')}.${e.target.day.toString().padLeft(2, '0')} · ${e.type}',
                        onTap: () async {
                          await _push(CountdownEditScreen(event: e.clone()));
                          _loadAll();
                        },
                      ))
                  .toList(),
            ),
        if (_category == null || _category == '资产')
          if (assets.isNotEmpty)
            _buildSection(
              '资产',
              Icons.account_balance_outlined,
              assets
                  .map((e) => _ResultRow(
                        icon: Icons.account_balance_outlined,
                        iconBg: const Color(0xFFEDF0F6),
                        iconColor: const Color(0xFF5A6B82),
                        title: e.note.isNotEmpty ? e.note : e.type,
                        subtitle: '${e.type} · ${_assetAmountLabel(e)}',
                        // 资产结果卡默认「关闭小眼睛」：金额打码；
                        // 点小眼睛可就地查看，点卡片进编辑页看全部
                        trailing: _buildAssetEye(),
                        onTap: () async {
                          await _push(AssetEditScreen(asset: e));
                          _loadAll();
                        },
                      ))
                  .toList(),
            ),
      ],
    );
  }

  /// 资产金额文案：默认打码（关闭小眼睛），点击小眼睛后显示真实金额
  String _assetAmountLabel(Asset e) {
    if (_hideAssetAmount) return '¥ ****';
    return '¥${e.amount.toStringAsFixed(e.amount.truncateToDouble() == e.amount ? 0 : 2)}';
  }

  /// 资产结果卡的小眼睛开关（默认关闭态）
  Widget _buildAssetEye() {
    return GestureDetector(
      onTap: () {
        Haptics.light();
        setState(() => _hideAssetAmount = !_hideAssetAmount);
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          _hideAssetAmount
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 16,
          color: const Color(0xFF9AA8BF),
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, List<_ResultRow> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 7),
            child: Row(
              children: [
                Icon(icon, size: 13, color: const Color(0xFF9AA8BF)),
                const SizedBox(width: 5),
                Text(title,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF8A99B3))),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EDF5)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  rows[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 打开笔记：加密笔记引导回主页打开（搜索结果不展示内容，避免绕过验证）
  void _openNote(DiaryEntry e) {
    if (e.encrypted) {
      // 连点加密笔记时不应反复弹同一句
      AppToast.show(context, '加密笔记请在笔记主页中打开，以验证密码');
      return;
    }
    _push(NoteViewScreen(entry: e));
  }
}

class _SearchCategory {
  final String name;
  final String count;
  final IconData icon;
  final bool hasHit;
  const _SearchCategory(this.name, this.count, this.icon, this.hasHit);
}

class _ResultRow extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing; // 行尾附加控件（如资产卡小眼睛）

  const _ResultRow({
    Key? key,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child:   InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2A3B52))),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF9AA8BF))),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFFC4CEDD)),
            ],
          ),
        ),
      )
    );;
  }
}
