import '../widgets/app_icons.dart';
import '../widgets/entry_image.dart';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_motion.dart';
import '../utils/share_note.dart';
import '../models/diary_entry.dart';
import '../models/item.dart';
import '../services/app_settings.dart';
import '../services/diary_storage.dart';
import '../services/item_storage.dart';
import '../services/trash_storage.dart';
import '../widgets/rich_note_text.dart';
import '../widgets/todo_card.dart';
import '../utils/text_format.dart';
import 'edit_screen.dart';
import 'item_edit_screen.dart';
import '../utils/haptics.dart';
import '../utils/todo_text.dart';
import '../widgets/pressable.dart';
import '../utils/stationery.dart';
import '../widgets/stationery_paper.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
class NoteViewScreen extends StatefulWidget {
  final DiaryEntry entry;

  /// v4.9.27：从全局搜索带入的关键词，正文命中高亮 + 顶栏逐条定位。
  /// 空字符串（默认）表示普通浏览，不显示匹配条。
  final String searchQuery;

  /// 仅测试使用：替换真实的「截图 + 落盘」实现
  @visibleForTesting
  final ShareCapture? shareCapture;

  const NoteViewScreen({
    Key? key,
    required this.entry,
    this.searchQuery = '',
    this.shareCapture,
  }) : super(key: key);

  @override
  State<NoteViewScreen> createState() => _NoteViewScreenState();
}

class _NoteViewScreenState extends State<NoteViewScreen> {
  late DiaryEntry _entry;
  List<Item> _items = [];

  /// v4.9.27：正文滚动控制 + 搜索命中逐条定位
  final ScrollController _bodyCtrl = ScrollController();
  final GlobalKey _bodyKey = GlobalKey();
  int _hitIndex = 0;

  int get _hitCount =>
      RichNoteText.countHits(_entry.content, widget.searchQuery);

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _loadItems();
    if (_hitCount > 1) _hitIndex = 0;
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  /// 在上/下箭头点击时切换当前命中，并把正文滚动到该命中所在行附近。
  void _gotoHit(int delta) {
    final n = _hitCount;
    if (n <= 0) return;
    setState(() => _hitIndex = (_hitIndex + delta + n) % n);
    _scrollToCurrentHit();
  }

  void _scrollToCurrentHit() {
    final q = widget.searchQuery.trim().toLowerCase();
    if (q.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_bodyCtrl.hasClients) return;
      final ctx = _bodyKey.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      // 估算命中所在行的 Y：按命中字符在正文中的位置比例推算。
      // 仅作"大致滚到附近"，精确高亮由 RichNoteText 的 currentHit 负责。
      final lower = _entry.content.toLowerCase();
      var from = 0;
      var hitStart = 0;
      for (var k = 0; k <= _hitIndex; k++) {
        final i = lower.indexOf(q, from);
        if (i < 0) break;
        hitStart = i;
        from = i + q.length;
      }
      final ratio = _entry.content.isEmpty
          ? 0.0
          : (hitStart / _entry.content.length).clamp(0.0, 1.0);
      final target = (box.size.height * ratio - 120).clamp(
        0.0,
        _bodyCtrl.position.maxScrollExtent,
      );
      _bodyCtrl.animateTo(
        target.toDouble(),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  /// 顶栏「更多」：从按钮位置弹出下拉选框（编辑 / 删除 / 分享）。
  Future<void> _showMoreMenu(BuildContext btnCtx) async {
    final box = btnCtx.findRenderObject() as RenderBox;
    final overlay =
        Overlay.of(context)!.context.findRenderObject() as RenderBox;
    final pos = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final menuTextStyle =
        TextStyle(fontSize: 14, color: AppPalette.c(0xFF24382F));
    final choice = await showMenu<String>(
      context: context,
      position: pos,
      color: AppPalette.c(0xFFFFFFFF),
      items: [
        PopupMenuItem<String>(
            value: 'edit', child: Text('编辑', style: menuTextStyle)),
        PopupMenuItem<String>(
            value: 'delete', child: Text('删除', style: menuTextStyle)),
        PopupMenuItem<String>(
            value: 'share', child: Text('分享', style: menuTextStyle)),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'edit':
        _openEditor();
        break;
      case 'delete':
        _delete();
        break;
      case 'share':
        _share();
        break;
    }
  }

  Future<void> _loadItems() async {
    final list = await ItemStorage.load();
    if (!mounted) return;
    setState(() => _items = list);
  }

  Future<void> _openItem(String name) async {
    final idx = _items.indexWhere((e) => e.name == name);
    if (idx < 0) return;
    final item = _items[idx];
    await Navigator.push<bool>(
      context,
      AppMotion.slide(
        ItemEditScreen(item: item),
      ),
    );
    await _loadItems();
  }

  Future<void> _openEditor() async {
    final result = await Navigator.push<bool>(
      context,
      AppMotion.slide(
        EditScreen(entry: _entry),
      ),
    );
    if (result == true) {
      final list = await DiaryStorage.load();
      final idx = list.indexWhere((e) => e.id == _entry.id);
      if (idx >= 0 && mounted) {
        setState(() => _entry = list[idx]);
      } else if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  bool get _hasTodos => TodoText.parseAll(_entry.content).isNotEmpty;

  /// 封面图是否可用（文件被系统清理时自动回退为无图）
  bool get _hasImage =>
      _entry.imagePath.isNotEmpty && File(_entry.imagePath).existsSync();

  /// 勾选/取消一条待办：只改正文里的 `[ ]` ↔ `[x]`，其余内容与排版不动。
  ///
  /// 先更新界面再落盘（乐观更新）：勾选是高频小操作，等 IO 回包再刷新
  /// 会有明显的延迟感；写盘失败的概率极低，且下一步编辑会覆盖回正确值。
  Future<void> _applyToggledContent(String newContent) async {
    if (newContent == _entry.content) return;
    setState(() {
      _entry.content = newContent;
      _entry.updatedAt = DateTime.now();
    });
    final list = await DiaryStorage.load();
    final idx = list.indexWhere((e) => e.id == _entry.id);
    if (idx < 0) return;
    final saved = list[idx];
    saved.content = newContent;
    saved.updatedAt = _entry.updatedAt;
    await DiaryStorage.save(list);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认要删除这篇日记吗?'),
        content: const Text('删除后可在「回收站」保留 7 天'),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除', style: TextStyle(color: Color(0xFFCB5C50))),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      Haptics.medium();
      final list = await DiaryStorage.load();
      list.removeWhere((e) => e.id == _entry.id);
      await DiaryStorage.save(list);
      // 阅读页删除同样入回收站
      await TrashStorage.addDiary(_entry);
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  /// 分享：把当前笔记渲染成带品牌落款的长图，调起系统分享面板。
  /// 具体链路（进度弹窗 / 失败提示）与主页长按菜单共用 [shareEntryImage]。
  Future<void> _share() => shareEntryImage(
        context,
        _entry,
        items: _items,
        capture: widget.shareCapture,
      );

  String _timeLabel() {
    final d = _entry.publishDate;
    final t = _entry.createdAt;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${d.year}/${d.month}/${d.day} $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    // 字体选择（设置页切换后返回本页即生效）
    final String? fontFamily = AppSettings.fontFamily;
    // v4.9.40：信纸样式——空 id = 普通（保持原白卡），非空则正文落在信纸上
    final String paperId = _entry.stationery;
    final bool hasPaper = paperId.isNotEmpty;
    final Color paperTextColor =
        hasPaper ? StationeryPaper.textColor(paperId) : AppPalette.c(0xFF24382F);
    final Color cardColor =
        hasPaper ? const Color(0x00000000) : AppPalette.c(0xFFFFFFFF);
    final Color metaColor = hasPaper && paperId == 'night'
        ? const Color(0xFFB9CCC1)
        : AppPalette.c(0xFF8FA09A);
    // 星夜来信：笔记与图片之外的区域同步压暗，避免白底与深色信纸割裂
    final Color? pageBg = paperId == 'night' ? const Color(0xFF1A201C) : null;
    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        toolbarHeight: 48, // v4.9.31：与笔记主页顶栏同高
        leadingWidth: 48, // v4.9.31：返回键与右侧图标同为 48×48 热区
        backgroundColor: AppPalette.c(0xB33E8E6D), // v4.9.31：与笔记主页顶栏同色
        foregroundColor: Colors.white,
        elevation: 0,
        // v4.9.38：从搜索页进入时也移除顶栏「N 处匹配 / 上一条下一条」，
        // 仅保留正文高亮；顶栏标题留空。
        title: null,
        actions: [
          // v4.9.27：编辑/删除/分享收进「更多」，点击从按钮处弹下拉选框
          // v4.9.28：竖三点改为横三点；热区与左侧返回箭头一致（48×48）
          Builder(
            builder: (btnCtx) => IconButton(
              key: const ValueKey('note_action_more'),
              tooltip: '更多',
              padding: EdgeInsets.zero,
              // v4.9.31：顶栏统一为 48 高（与各主页一致），
              // 图标热区同步为 48×48，与返回键一致
              constraints:
                  const BoxConstraints.tightFor(width: 48, height: 48),
              // v4.9.38：横三点偏右且偏小——放大到 28 并小幅左移 3px
              iconSize: 28,
              icon: Transform.translate(
                offset: const Offset(-3, 0),
                child: const AppIcon(AppIcons.moreH, size: 28),
              ),
              onPressed: () => _showMoreMenu(btnCtx),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: _bodyKey,
              controller: _bodyCtrl,
              padding: hasPaper
                  ? const EdgeInsets.all(14)
                  : const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                // 封面图独立板块：在信纸之外，与正文信纸分成两块
                if (_hasImage) ...[
                  // v4.9.30：移除点击封面进入全屏预览的入口，
                  // 封面图仅作展示，不响应点击
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      // 页宽 - 左右各 16 边距；降采样解码后滚动更顺
                      child: EntryImage(
                        path: _entry.imagePath,
                        displayWidth:
                            MediaQuery.of(context).size.width - 32,
                        iconSize: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                StationeryPaper(
                  styleId: paperId,
                  padding: hasPaper
                      ? const EdgeInsets.fromLTRB(16, 22, 16, 22)
                      : EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (_entry.title.isNotEmpty) ...[
                    // 标题回到白色卡片底纹上：与下方正文卡片同一视觉层级
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _entry.title,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: paperTextColor,
                          fontFamily: fontFamily,
                        ),
                      ),
                    ),
                  ],
                  if (_entry.content.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: RichNoteText(
                        text: _entry.content,
                        formats: FormatStore.decode(_entry.formats),
                        itemNames: _items
                            .map((e) => e.name)
                            .where((n) => n.isNotEmpty)
                            .toSet(),
                        onTapMention: _openItem,
                        searchQuery: widget.searchQuery,
                        currentHit: widget.searchQuery.trim().isEmpty
                            ? -1
                            : _hitIndex,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.8,
                          color: paperTextColor,
                          fontFamily: fontFamily,
                        ),
                      ),
                    ),
                  ],
                  // 正文里的 [ ] / [x] 行 → 可勾选的待办清单
                  if (_hasTodos) ...[
                    const SizedBox(height: 12),
                    TodoCard(
                      content: _entry.content,
                      itemNames:
                          _items.map((e) => e.name).where((n) => n.isNotEmpty).toSet(),
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.5,
                        color: paperTextColor,
                        fontFamily: fontFamily,
                      ),
                      // 传回的是切换后的整篇正文，行号在卡片内部已算好，
                      // 这里用「新旧文本对齐」反推是哪一行被切换
                      onToggle: _applyToggledContent,
                    ),
                    ],
                  ],
                ),
              ),
              // v4.9.48：时间/地点信息行取消吸底，随正文滚动、置于内容最底部
              // （需滑到最底部才可见），与回收站底部提示语同一处理。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 0, 4),
                child: Row(
                  children: [
                    Text(
                      _timeLabel(),
                      style: TextStyle(fontSize: 13, color: metaColor),
                    ),
                    if (_entry.location.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      AppIcon(AppIcons.mapPin,
                          size: 14, color: AppPalette.c(0xFF8FA09A)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _entry.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: metaColor),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
