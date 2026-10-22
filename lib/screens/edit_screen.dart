import 'package:flutter/material.dart';
import '../models/diary_entry.dart';
import '../services/diary_storage.dart';

class EditScreen extends StatefulWidget {
  final DiaryEntry? entry;
  final DateTime? defaultDate;
  const EditScreen({Key? key, this.entry, this.defaultDate}) : super(key: key);

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late String _mood;
  late String _weather;
  late String _location;
  late DateTime _publishDate;
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
    _location = widget.entry?.location ?? '';
    _publishDate =
        widget.entry?.publishDate ?? widget.defaultDate ?? DateTime.now();
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
        location: _location,
        createdAt: now,
        updatedAt: now,
        publishDate: _publishDate,
      ));
    } else {
      final idx = list.indexWhere((e) => e.id == widget.entry!.id);
      if (idx >= 0) {
        list[idx].title = title;
        list[idx].content = content;
        list[idx].mood = _mood;
        list[idx].weather = _weather;
        list[idx].location = _location;
        list[idx].publishDate = _publishDate;
        list[idx].updatedAt = DateTime.now();
      }
    }
    await DiaryStorage.save(list);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _cancel() {
    Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _publishDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _publishDate = picked);
    }
  }

  Future<void> _pickLocation() async {
    final ctrl = TextEditingController(text: _location);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加地点'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 8,
          decoration: const InputDecoration(
            hintText: '输入地点（最多8字）',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null) {
      setState(() => _location = result);
    }
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xCC3B6FE0),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildChipRow(
                '今天心情', _moods, _mood, (v) => setState(() => _mood = v)),
            const SizedBox(height: 10),
            _buildChipRow(
                '天气', _weathers, _weather, (v) => setState(() => _weather = v)),
            const SizedBox(height: 16),
            _buildDateLocationRow(),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleCtrl,
                    maxLength: 15,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      hintText: '标题',
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Text(
                  '${_titleCtrl.text.length}/15',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BF)),
                ),
              ],
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            TextField(
              controller: _contentCtrl,
              autofocus: _isNew,
              maxLength: 2000,
              maxLines: null,
              minLines: 8,
              style: const TextStyle(fontSize: 16, height: 1.7),
              decoration: const InputDecoration(
                hintText: '今天发生了什么…',
                border: InputBorder.none,
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
            Row(
              children: [
                if (_location.isNotEmpty)
                  Text(
                    '📍 $_location',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF9AA8BF)),
                  ),
                const Spacer(),
                Text(
                  '${_contentCtrl.text.length}/2000',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BF)),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF3B6FE0)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('取消', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('确认', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateLocationRow() {
    final d = _publishDate;
    return Row(
      children: [
        Expanded(
          child: _buildInfoCell(
            icon: Icons.event,
            label: '${d.year}年${d.month}月${d.day}日',
            onTap: _pickDate,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildInfoCell(
            icon: Icons.location_on,
            label: _location.isEmpty ? '地点' : _location,
            onTap: _pickLocation,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCell({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE7FF)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF3B6FE0)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF2A3B52),
                  fontWeight: FontWeight.w600,
                ),
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
        Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9A8A7E))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((o) {
            final isSel = o == selected;
            return GestureDetector(
              onTap: () => onSelect(o),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSel ? const Color(0xFF3B6FE0) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSel
                        ? const Color(0xFF3B6FE0)
                        : const Color(0xFFDCE7FF),
                  ),
                ),
                child: Text(o, style: const TextStyle(fontSize: 15)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
