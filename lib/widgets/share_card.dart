import 'dart:io';

import 'package:flutter/material.dart';

import '../models/diary_entry.dart';
import '../models/item.dart';
import '../services/app_settings.dart';
import '../utils/text_format.dart';
import '../utils/todo_text.dart';
import 'app_icons.dart';
import 'entry_image.dart';
import 'rich_note_text.dart';
import 'todo_card.dart';

/// 分享卡片：把当前笔记渲染成一张可分享的长图。
///
/// 结构（自上而下）：
/// - 内容区（浅绿底）：封面图 → 标题白卡 → 正文白卡 → 待办卡
/// - 底部白色信息条（自然高度，紧贴内容区）：显示 APP Logo、
///   APP 名称、写作日期时间与地点（品牌露出位）。
///   左侧内边距 20 与内容区正文对齐，下方不留多余白区。
class ShareCard extends StatelessWidget {
  final DiaryEntry entry;
  final List<Item> items;

  /// 信息条 key（测试与校验用）
  final Key? footerKey;

  const ShareCard({
    Key? key,
    required this.entry,
    required this.items,
    this.footerKey,
  }) : super(key: key);

  /// 写作时间文案：与浏览页底部信息行同一格式
  String get _timeLabel {
    final d = entry.publishDate;
    final t = entry.createdAt;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${d.year}/${d.month}/${d.day} $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final String? fontFamily = AppSettings.fontFamily;
    final bool hasImage =
        entry.imagePath.isNotEmpty && File(entry.imagePath).existsSync();
    final bool hasTodos = TodoText.parseAll(entry.content).isNotEmpty;

    final content = Container(
      width: 375,
      color: const Color(0xFFF5FAF7),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: EntryImage(
                  path: entry.imagePath,
                  displayWidth: 335,
                  iconSize: 24,
                ),
              ),
            ),
          ],
          if (entry.title.isNotEmpty) ...[
            if (hasImage) const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                entry.title,
                style: TextStyle(
                  fontSize: 20,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF24382F),
                  fontFamily: fontFamily,
                ),
              ),
            ),
          ],
          if (entry.content.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: RichNoteText(
                text: entry.content,
                formats: FormatStore.decode(entry.formats),
                itemNames:
                    items.map((e) => e.name).where((n) => n.isNotEmpty).toSet(),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.8,
                  color: const Color(0xFF24382F),
                  fontFamily: fontFamily,
                ),
              ),
            ),
          ],
          if (hasTodos) ...[
            const SizedBox(height: 12),
            TodoCard(
              content: entry.content,
              itemNames:
                  items.map((e) => e.name).where((n) => n.isNotEmpty).toSet(),
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: const Color(0xFF24382F),
                fontFamily: fontFamily,
              ),
            ),
          ],
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        content,
        // 底部白色信息条：自然高度，紧贴内容区，Logo + 名称 + 写作时间地点。
        // 左内边距 20 与内容区正文的 20px 内边距对齐。
        Container(
          key: footerKey,
          width: 375,
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '阿尤日记',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF24382F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _timeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF8FA09A)),
                          ),
                        ),
                        if (entry.location.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const AppIcon(AppIcons.mapPin,
                              size: 12, color: Color(0xFF8FA09A)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              entry.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF8FA09A)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
