import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';

import '../utils/app_motion.dart';

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

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
/// 全局搜索主页：一个搜索框同时检索 笔记标题 / 物品名称 / 事件名称 / 资产备注。
/// 顶部搜索框持久保持；结果用「收纳栏」（笔记/物品/事件/资产 + 数量）+ 分区列表呈现。
///
/// 本页以「主页选项卡」形式嵌入 [HomeScreen] 的 Stack，与其它主页（写日记 /
/// 物品清单 / 重要事件 / 资产全景）一致：状态栏贯通、左右滑跟手拉出/收回
/// 菜单侧边栏，均由主页统一提供，这里只负责页内内容。
class GlobalSearchScreen extends StatefulWidget {
  final VoidCallback onOpenMenu;

  /// 仅测试/截图使用：进入时预填的搜索词。
  @visibleForTesting
  final String initialQuery;

  const GlobalSearchScreen({
    Key? key,
    required this.onOpenMenu,
    this.initialQuery = '',
  }) : super(key: key);

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
    if (widget.initialQuery.isNotEmpty) _ctrl.text = widget.initialQuery;
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

  Route<T> _slideRoute<T>(Widget page) => AppMotion.slide<T>(page);

  Future<T?> _push<T>(Widget page) => Navigator.of(context).push<T>(
        _slideRoute(page),
      );

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    final diaries = _hitDiaries;
    final items = _hitItems;
    final events = _hitEvents;
    final assets = _hitAssets;
    final query = _ctrl.text.trim();

    // 主页选项卡形态：不自带 Scaffold / 状态栏处理。状态栏贯通与
    // 左右滑跟手菜单均由 HomeScreen 统一提供，这里只输出页内内容。
    return LayoutBuilder(
      builder: (context, constraints) {
        // v5.0.20：筛选栏「全部」在 1/5 等宽 cell 内居中，
        // 文字左边缘 = cellW/2 - 文字宽/2（「全部」2 字、13px ≈ 26px）。
        // 结果区分区标题/卡片标题/副标题统一对齐到这条基线。
        final cellW = constraints.maxWidth / 5;
        final allLeft = (cellW - 26) / 2;
        return Column(
          children: [
            _buildSearchBar(),
            // v5.0.12：分类栏固定在搜索栏下方，不随是否有搜索结果而显隐。
            _buildFilterBar(),
            Expanded(
              child: _loading
                  ? const SizedBox()
                  : query.isEmpty
                      ? _buildEmptyHint()
                      : _buildResults(
                          diaries, items, events, assets, allLeft),
            ),
          ],
        );
      },
    );
  }

  /// 顶部持久搜索框（不默认吊起输入法，点击后才聚焦）。
  /// 作为主页选项卡：蓝色顶栏在 SafeArea 内容区内（状态栏区域由主页统一
  /// 铺蓝贯通），这里只铺一层 0xB3 蓝即可，与其它主页顶栏一致。
  Widget _buildSearchBar() {
    return Container(
      height: 56,
      color: AppPalette.c(0xB33E8E6D),
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            icon: const AppIcon(AppIcons.menu, color: Colors.white),
            tooltip: '菜单',
            onPressed: widget.onOpenMenu,
          ),
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppPalette.c(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  AppIcon(AppIcons.search, size: 18, color: AppPalette.c(0xFF8FA09A)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      autofocus: false, // 进入页面不默认弹出输入法
                      style: TextStyle(
                          fontSize: 15, color: AppPalette.c(0xFF24382F)),
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        hintText: '搜索笔记 / 物品 / 事件 / 资产…',
                        hintStyle: TextStyle(color: AppPalette.c(0xFF8FA09A)),
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
                      child: AppIcon(AppIcons.close,
                          size: 16, color: AppPalette.c(0xFF8FA09A)),
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
            AppIcon(AppIcons.search,
                size: 56, color: AppPalette.c(0xFF8FA09A).withOpacity(0.6)),
            const SizedBox(height: 14),
            Text(
              '输入关键词，即可检索对应内容',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.c(0xFF647A70)),
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
    double allLeft,
  ) {
    final total = diaries.length + items.length + events.length + assets.length;
    final queryText = _ctrl.text.trim();
    if (total == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(AppIcons.searchX, size: 48, color: AppPalette.c(0xFFC6D6CD)),
            const SizedBox(height: 10),
            Text('没有匹配的内容',
                style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
          ],
        ),
      );
    }

    return ListView(
      // v5.0.12：分类栏已提升到搜索栏下方固定显示，这里补回原先 12px 顶部间距。
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      children: [
        // 分区结果（按收纳栏选中状态过滤）
        if (_category == null || _category == '笔记')
          if (diaries.isNotEmpty)
            _buildSection(
              '笔记',
              allLeft,
              diaries
                  .map((e) => _ResultRow(
                        allLeft: allLeft,
                        query: queryText,
                        title: e.encrypted
                            ? (e.subtitle.isNotEmpty ? e.subtitle : '加密笔记')
                            : (e.title.isNotEmpty ? e.title : '（无标题）'),
                        subtitle: e.encrypted
                            ? '${e.publishDate.year}.${e.publishDate.month.toString().padLeft(2, '0')}.${e.publishDate.day.toString().padLeft(2, '0')} · 已加密'
                            : '${e.publishDate.year}.${e.publishDate.month.toString().padLeft(2, '0')}.${e.publishDate.day.toString().padLeft(2, '0')}',
                        onTap: () => _openNote(e),
                      ))
                  .toList(),
            ),
        if (_category == null || _category == '物品')
          if (items.isNotEmpty)
            _buildSection(
              '物品',
              allLeft,
              items
                  .map((e) => _ResultRow(
                        allLeft: allLeft,
                        query: queryText,
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
              allLeft,
              events
                  .map((e) => _ResultRow(
                        allLeft: allLeft,
                        query: queryText,
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
              allLeft,
              assets
                  .map((e) => _ResultRow(
                        allLeft: allLeft,
                        query: queryText,
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

  /// 分类栏（v5.0.11）：与日记页「全部/按日/按月/按年」同款 ——
  /// 等宽文字标签 + 底部 40×3 主题色滑块（AnimatedPositioned 250ms）。
  /// 保留类型筛选语义：null = 全部，其余为笔记/物品/事件/资产。
  Widget _buildFilterBar() {
    const cats = <String?>[null, '笔记', '物品', '事件', '资产'];
    const labels = ['全部', '笔记', '物品', '事件', '资产'];
    final index = cats.indexOf(_category);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = constraints.maxWidth / cats.length;
        final left = index * cellW + (cellW - 40) / 2;
        return Container(
          height: 48,
          color: AppPalette.c(0xFFFFFFFF),
          child: Stack(
            children: [
              Row(
                children: List.generate(cats.length, (i) {
                  final selected = i == index;
                  return Expanded(
                    child: InkWell(
                      onTap: () {
                        if (selected) return;
                        Haptics.light();
                        setState(() => _category = cats[i]);
                      },
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected
                                ? AppPalette.c(0xFF3E8E6D)
                                : AppPalette.c(0xFF647A70),
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
                    color: AppPalette.c(0xFF3E8E6D),
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
        child: AppIcon(
          _hideAssetAmount
              ? AppIcons.eyeOff
              : AppIcons.eyeOn,
          size: 16,
          color: AppPalette.c(0xFF8FA09A),
        ),
      ),
    );
  }

  Widget _buildSection(String title, double allLeft, List<_ResultRow> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // v5.0.20：分区标题左边缘与筛选栏「全部」文字左对齐（动态 allLeft），
          // 同时卡片标题/副标题在 _ResultRow 内也用同一 allLeft，三者齐平。
          Padding(
            padding: EdgeInsets.only(left: allLeft, bottom: 7),
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.c(0xFF7C8F86))),
          ),
          Container(
            // 预览卡去描边：白底圆角 + 内部分隔线
            decoration: BoxDecoration(
              color: AppPalette.c(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: allLeft),
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
    _push(NoteViewScreen(entry: e, searchQuery: _ctrl.text.trim()));
  }
}

/// 通用：把标题里命中 query 的片段加浅黄底 + 深墨字（深色模式同样可见）。
Widget buildHighlightedTitle(String title, String query) {
  if (query.trim().isEmpty) {
    return Text(title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppPalette.c(0xFF24382F)));
  }
  final spans = <TextSpan>[];
  final lower = title.toLowerCase();
  final needle = query.trim().toLowerCase();
  var from = 0;
  while (true) {
    final i = lower.indexOf(needle, from);
    if (i < 0) break;
    if (i > from) spans.add(TextSpan(text: title.substring(from, i)));
    spans.add(TextSpan(
      text: title.substring(i, i + needle.length),
      style: const TextStyle(
          backgroundColor: Color(0xFFFFF0B3), color: Color(0xFF24382F)),
    ));
    from = i + needle.length;
  }
  if (from < title.length) spans.add(TextSpan(text: title.substring(from)));
  return Text.rich(
    TextSpan(
      style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppPalette.c(0xFF24382F)),
      children: spans,
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

class _SearchCategory {
  final String name;
  final String count;
  final bool hasHit;
  const _SearchCategory(this.name, this.count, this.hasHit);
}

class _ResultRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing; // 行尾附加控件（如资产卡小眼睛）
  final String query; // 命中关键词高亮
  final double allLeft; // v5.0.20：标题/副标题左边缘，与筛选栏「全部」对齐

  const _ResultRow({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.query = '',
    this.allLeft = 14,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return Pressable(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          // v5.0.20：左内边距用 allLeft，与分区标题/筛选栏「全部」齐平
          padding: EdgeInsets.fromLTRB(allLeft, 11, 14, 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildHighlightedTitle(title, query),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: AppPalette.c(0xFF8FA09A))),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              AppIcon(AppIcons.chevR, size: 18, color: AppPalette.c(0xFFC6D6CD)),
            ],
          ),
        ),
      ),
    );
  }
}
