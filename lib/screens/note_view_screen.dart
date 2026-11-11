import '../widgets/app_icons.dart';
import '../widgets/entry_image.dart';
import 'dart:io';
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/app_motion.dart';
import '../utils/app_toast.dart';
import '../utils/share_image.dart';
import '../models/diary_entry.dart';
import '../models/item.dart';
import '../services/app_settings.dart';
import '../services/diary_storage.dart';
import '../services/item_storage.dart';
import '../services/trash_storage.dart';
import 'package:flutter/services.dart';
import '../widgets/rich_note_text.dart';
import '../widgets/todo_card.dart';
import '../utils/text_format.dart';
import 'edit_screen.dart';
import 'item_edit_screen.dart';
import '../utils/haptics.dart';
import '../utils/todo_text.dart';
import '../widgets/pressable.dart';

/// 分享图生成器签名（测试可注入替身，避免 real async 截图流程）
typedef ShareCapture = Future<File?> Function(
    BuildContext context, DiaryEntry entry, List<Item> items);

class NoteViewScreen extends StatefulWidget {
  final DiaryEntry entry;

  /// 仅测试使用：替换真实的「截图 + 落盘」实现
  @visibleForTesting
  final ShareCapture? shareCapture;

  const NoteViewScreen({Key? key, required this.entry, this.shareCapture})
      : super(key: key);

  @override
  State<NoteViewScreen> createState() => _NoteViewScreenState();
}

class _NoteViewScreenState extends State<NoteViewScreen> {
  late DiaryEntry _entry;
  List<Item> _items = [];

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    _loadItems();
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
        content: const Text('删除后可在「回收站」保留 7 天，期间可还原'),
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
  ///
  /// 生成期间挡一个不可关闭的进度弹窗；生成失败给可重试的提示。
  Future<void> _share() async {
    Haptics.light();
    unawaited(showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ShareProgressDialog(),
    ));
    File? file;
    try {
      final capture = widget.shareCapture ?? captureShareCard;
      file = await capture(context, _entry, _items);
    } catch (_) {
      file = null;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // 关闭进度弹窗
    if (file == null) {
      AppToast.show(context, '分享图生成失败，请重试');
      return;
    }
    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: _entry.title.isNotEmpty
            ? '「阿尤日记」· ${_entry.title}'
            : '来自「阿尤日记」',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 10, 10),
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '分享失败，请重试');
    }
  }

  String _timeLabel() {
    final d = _entry.publishDate;
    final t = _entry.createdAt;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${d.year}/${d.month}/${d.day} $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    // 字体选择（设置页切换后返回本页即生效）
    final String? fontFamily = AppSettings.fontFamily;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xCC3E8E6D),
        foregroundColor: Colors.white,
        elevation: 0,
        // 顺序固定为：编辑、删除、分享（分享在最右）
        actions: [
          IconButton(
            key: const ValueKey('note_action_edit'),
            tooltip: '编辑',
            // 编辑笔路径重心比垃圾桶高约 1.8px，绘制下移补齐基线
            icon: Transform.translate(
              offset: const Offset(0, 1.8),
              child: const AppIcon(AppIcons.edit),
            ),
            onPressed: _openEditor,
          ),
          IconButton(
            key: const ValueKey('note_action_delete'),
            tooltip: '删除',
            icon: const AppIcon(AppIcons.delete),
            onPressed: _delete,
          ),
          IconButton(
            key: const ValueKey('note_action_share'),
            tooltip: '分享',
            icon: const AppIcon(AppIcons.share),
            onPressed: _share,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 排版顺序：封面图 → 标题 → 正文；无图时标题直接从顶部开始
                  if (_hasImage) ...[
                    // 封面图只随页面滑入，不做跨页共享元素飞行
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        // 页宽 - 左右各 16 边距；降采样解码后滚动更顺
                        child: EntryImage(
                          path: _entry.imagePath,
                          displayWidth: MediaQuery.of(context).size.width - 32,
                          iconSize: 24,
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _entry.title,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF24382F),
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
                        color: Colors.white,
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
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.8,
                          color: const Color(0xFF24382F),
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
                        color: const Color(0xFF24382F),
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
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF8FA09A)),
                ),
                if (_entry.location.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  const AppIcon(AppIcons.mapPin,
                      size: 14, color: Color(0xFF8FA09A)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      _entry.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF8FA09A)),
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

/// 分享图生成期间的进度弹窗：不可点掉，生成完由调用方关闭。
class _ShareProgressDialog extends StatelessWidget {
  const _ShareProgressDialog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            SizedBox(height: 14),
            Text(
              '正在生成分享图…',
              style: TextStyle(fontSize: 14, color: Color(0xFF24382F)),
            ),
          ],
        ),
      ),
    );
  }
}
