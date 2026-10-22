import 'package:flutter/material.dart';
import '../models/diary_entry.dart';
import '../services/diary_storage.dart';

class EditScreen extends StatefulWidget {
  final DiaryEntry? entry;
  const EditScreen({Key? key, this.entry}) : super(key: key);

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late String _mood;
  late String _weather;
  bool _saving = false;

  static const List<String> _moods = ['😊', '😌', '😢', '😡', '😴', '🥰'];
  static const List<String> _weathers = ['☀️', '⛅', '🌧️', '❄️', '🌙', '🌈'];

  bool get _isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry?.title ?? '');
    _contentCtrl = TextEditingController(text: widget.entry?.content ?? '');
    _mood = widget.entry?.mood ?? '😊';
    _weather = widget.entry?.weather ?? '☀️';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写点什么再保存吧～')),
      );
      return;
    }

    setState(() => _saving = true);

    final list = await DiaryStorage.load();
    if (_isNew) {
      final now = DateTime.now();
      list.add(DiaryEntry(
        id: now.microsecondsSinceEpoch.toString(),
        title: title,
        content: content,
        mood: _mood,
        weather: _weather,
        createdAt: now,
        updatedAt: now,
      ));
    } else {
      final idx = list.indexWhere((e) => e.id == widget.entry!.id);
      if (idx >= 0) {
        list[idx].title = title;
        list[idx].content = content;
        list[idx].mood = _mood;
        list[idx].weather = _weather;
        list[idx].updatedAt = DateTime.now();
      }
    }
    await DiaryStorage.save(list);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '写日记' : '编辑日记'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildChipRow('今天心情', _moods, _mood, (v) => setState(() => _mood = v)),
            const SizedBox(height: 12),
            _buildChipRow('天气', _weathers, _weather, (v) => setState(() => _weather = v)),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: '标题（可选）',
                border: InputBorder.none,
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 16),
            TextField(
              controller: _contentCtrl,
              autofocus: _isNew,
              maxLines: null,
              minLines: 8,
              style: const TextStyle(fontSize: 16, height: 1.7),
              decoration: const InputDecoration(
                hintText: '今天发生了什么…',
                border: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipRow(
    String label,
    List<String> options,
    String selected,
    ValueChanged<String> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF9A8A7E))),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: options.map((o) {
            final isSel = o == selected;
            return GestureDetector(
              onTap: () => onSelect(o),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isSel ? const Color(0xFFD98E63) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSel ? const Color(0xFFD98E63) : const Color(0xFFE5D8CF),
                  ),
                ),
                child: Text(o, style: const TextStyle(fontSize: 20)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
