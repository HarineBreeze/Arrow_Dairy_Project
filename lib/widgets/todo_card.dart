import 'package:flutter/material.dart';

import '../utils/haptics.dart';
import '../utils/rich_text.dart';
import '../utils/todo_text.dart';

/// 笔记浏览页里的「待办清单」卡片。
///
/// 正文中的 `[ ] xxx` / `[x] xxx` 会被解析成一条条可勾选的待办，
/// 进度条与「已勾选/总数」实时更新；勾选后通过 [onToggle] 把新的正文
/// 交回给调用方落盘，卡片自身立刻反映新状态（乐观更新）。
class TodoCard extends StatelessWidget {
  final String content;
  final Set<String> itemNames;

  /// 第 [lineIndex] 行（整篇正文从 0 计）的勾选被切换，参数为切换后的整篇正文。
  final ValueChanged<String>? onToggle;

  final TextStyle style;

  const TodoCard({
    Key? key,
    required this.content,
    this.itemNames = const {},
    this.onToggle,
    required this.style,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final lines = content.split('\n');
    final todos = <_TodoEntry>[];
    for (var i = 0; i < lines.length; i++) {
      final t = TodoText.parseLine(lines[i], 0);
      if (t != null) todos.add(_TodoEntry(lineIndex: i, todo: t));
    }
    if (todos.isEmpty) return const SizedBox.shrink();

    final done = todos.where((e) => e.todo.done).length;
    final total = todos.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F2A3B52),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rounded,
                  size: 16, color: Color(0xFF3B6FE0)),
              const SizedBox(width: 6),
              const Text('待办清单',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A3B52))),
              const Spacer(),
              Text('$done / $total',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF3B6FE0))),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 3,
              backgroundColor: const Color(0xFFEDF1F8),
              valueColor:
                  const AlwaysStoppedAnimation(Color(0xFF3B6FE0)),
            ),
          ),
          const SizedBox(height: 6),
          for (final e in todos)
            _TodoRow(
              todo: e.todo,
              itemNames: itemNames,
              style: style,
              onTap: onToggle == null
                  ? null
                  : () {
                      Haptics.light();
                      onToggle!(TodoText.toggleAt(content, e.lineIndex));
                    },
            ),
        ],
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  final TodoLine todo;
  final Set<String> itemNames;
  final TextStyle style;
  final VoidCallback? onTap;

  const _TodoRow({
    required this.todo,
    required this.itemNames,
    required this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final base = style.copyWith(fontSize: (style.fontSize ?? 16) * 0.94);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 勾选框本身给足点击面积（44 高），但视觉上是 20 的小圆角方框
            SizedBox(
              width: 26,
              height: 24,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  width: 19,
                  height: 19,
                  decoration: BoxDecoration(
                    color: todo.done
                        ? const Color(0xFF3B6FE0)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: todo.done
                          ? const Color(0xFF3B6FE0)
                          : const Color(0xFFC6D0E0),
                      width: 1.6,
                    ),
                  ),
                  child: todo.done
                      ? const Icon(Icons.check,
                          size: 13, color: Colors.white)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text.rich(
                  _buildSpan(todo.text, base),
                  style: base,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 待办文字同样支持 `@物品` 蓝色高亮与删除线（勾选后）。
  InlineSpan _buildSpan(String text, TextStyle base) {
    final segs = RichTextParser.parse(text, itemNames);
    final children = <TextSpan>[];
    for (final s in segs) {
      final isLink = s.type == 'mention' || s.type == 'topic';
      children.add(TextSpan(
        text: s.text,
        style: isLink
            ? base.copyWith(
                color: const Color(0xFF3B6FE0),
                decoration:
                    todo.done ? TextDecoration.lineThrough : null,
              )
            : base.copyWith(
                decoration:
                    todo.done ? TextDecoration.lineThrough : null,
                color: todo.done ? const Color(0xFF9AA8BF) : null,
              ),
      ));
    }
    return TextSpan(children: children);
  }
}

/// 一条待办 + 它在正文里的行号。
///
/// 不用 Record `(int, TodoLine)`：这个项目的最低 SDK 是 2.17，
/// Record 语法要 3.0 才支持。
class _TodoEntry {
  final int lineIndex;
  final TodoLine todo;
  const _TodoEntry({required this.lineIndex, required this.todo});
}
