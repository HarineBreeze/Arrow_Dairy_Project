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
import 'image_viewer_screen.dart';
import 'item_edit_screen.dart';
import '../utils/haptics.dart';
import '../utils/todo_text.dart';
import '../widgets/pressable.dart';

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
  /// 打开全屏查看：Hero 共享元素 + 缩放/下拉/单击退出
  void _openImage() {
    if (!_hasImage) return;
    Navigator.of(context).push(ImageViewerScreen.route(
      path: _entry.imagePath,
      heroTag: 'note_cover_${_entry.id}',
    ));
  }

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

  /// 顶栏命中条：「N 处匹配」+ 上/下一条，数字跟随当前命中。
  Widget _buildMatchBar() {
    final n = _hitCount;
    if (n <= 0) {
      return const Text('无匹配',
          style: TextStyle(fontSize: 15, color: Colors.white));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${_hitIndex + 1}/$n 处匹配',
            style: const TextStyle(fontSize: 14, color: Colors.white)),
        const SizedBox(width: 2),
        IconButton(
          key: const ValueKey('match_prev'),
          tooltip: '上一个匹配',
          icon: const Icon(Icons.keyboard_arrow_up, size: 22, color: Colors.white),
          onPressed: () => _gotoHit(-1),
        ),
        IconButton(
          key: const ValueKey('match_next'),
          tooltip: '下一个匹配',
          icon: const Icon(Icons.keyboard_arrow_down, size: 22, color: Colors.white),
          onPressed: () => _gotoHit(1),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    // 字体选择（设置页切换后返回本页即生效）
    final String? fontFamily = AppSettings.fontFamily;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppPalette.c(0xCC3E8E6D),
        foregroundColor: Colors.white,
        elevation: 0,
        // v4.9.27：搜索进入时顶栏显示「N 处匹配」+ 上/下一条定位
        title: widget.searchQuery.trim().isEmpty
            ? null
            : _buildMatchBar(),
        actions: [
          // v4.9.27：编辑/删除/分享收进「更多」，点击从按钮处弹下拉选框
          // v4.9.28：竖三点改为横三点；热区与左侧返回箭头一致（48×48）
          Builder(
            builder: (btnCtx) => IconButton(
              key: const ValueKey('note_action_more'),
              tooltip: '更多',
              padding: EdgeInsets.zero,
              // AppBar 的返回键热区是 56×56（leadingWidth 默认值），
              // 这里取同尺寸，避免右侧图标感觉「更难点」
              constraints:
                  const BoxConstraints.tightFor(width: 56, height: 56),
              iconSize: 24,
              icon: const AppIcon(AppIcons.moreH),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 排版顺序：封面图 → 标题 → 正文；无图时标题直接从顶部开始
                  if (_hasImage) ...[
                    // 封面图只随页面滑入，不做跨页共享元素飞行
                    // v4.9.28：点击进入全屏查看（双指缩放 / 下拉关闭 / 单击退出）
                    GestureDetector(
                      onTap: _openImage,
                      child: Hero(
                        tag: 'note_cover_${_entry.id}',
                        child: ClipRRect(
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
                      ),
                    ),
                  ],
                  if (_entry.title.isNotEmpty) ...[
                    if (_hasImage) const SizedBox(height: 16),
                    // 标题回到白色卡片底纹上：与下方正文卡片同一视觉层级
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppPalette.c(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _entry.title,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.c(0xFF24382F),
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
                        color: AppPalette.c(0xFFFFFFFF),
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
                          color: AppPalette.c(0xFF24382F),
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
                        color: AppPalette.c(0xFF24382F),
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
          ),
          // 底部信息行：时间在最左，与正文文字左缘对齐
          // （正文卡片有 16px 内边距，页面 padding 16，合计 32px）
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 16, 16),
            child: Row(
              children: [
                Text(
                  _timeLabel(),
                  style: TextStyle(
                      fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
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
                      style: TextStyle(
                          fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
