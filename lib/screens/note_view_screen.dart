import 'package:flutter/material.dart';
import '../models/diary_entry.dart';
import '../models/item.dart';
import '../services/diary_storage.dart';
import '../services/item_storage.dart';
import '../widgets/rich_note_text.dart';
import '../utils/text_format.dart';
import 'edit_screen.dart';
import 'item_edit_screen.dart';

class NoteViewScreen extends StatefulWidget {
  final DiaryEntry entry;
  const NoteViewScreen({Key? key, required this.entry}) : super(key: key);

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
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ItemEditScreen(item: item),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
              parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    await _loadItems();
  }

  Future<void> _openEditor() async {
    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            EditScreen(entry: _entry),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
              parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
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

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认要删除这篇日记吗?'),
        content: const Text('注意！删除后无法恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final list = await DiaryStorage.load();
      list.removeWhere((e) => e.id == _entry.id);
      await DiaryStorage.save(list);
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  String _timeLabel() {
    final d = _entry.publishDate;
    final t = _entry.createdAt;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${d.year}-${d.month}-${d.day} $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xCC3B6FE0),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _openEditor,
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
                  Row(
                    children: [
                      Text(_entry.mood, style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 10),
                      Text(_entry.weather, style: const TextStyle(fontSize: 24)),
                    ],
                  ),
                  if (_entry.title.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _entry.title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2A3B52),
                        ),
                      ),
                    ),
                  ],
                  if (_entry.content.isNotEmpty) ...[
                    const SizedBox(height: 12),
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
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.8,
                          color: Color(0xFF2A3B52),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                if (_entry.location.isNotEmpty) ...[
                  const Icon(Icons.location_on,
                      size: 14, color: Color(0xFF9AA8BF)),
                  const SizedBox(width: 4),
                  Text(
                    _entry.location,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF9AA8BF)),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  _timeLabel(),
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF9AA8BF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
