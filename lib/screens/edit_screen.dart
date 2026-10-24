import 'package:flutter/material.dart';
import '../models/diary_entry.dart';
import '../services/diary_storage.dart';
import '../services/item_storage.dart';
import '../widgets/highlight_controller.dart';

class EditScreen extends StatefulWidget {
  final DiaryEntry? entry;
  final DateTime? defaultDate;
  const EditScreen({Key? key, this.entry, this.defaultDate}) : super(key: key);

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final HighlightEditingController _contentCtrl;
  Set<String> _itemNames = {};
  late String _mood;
  late String _weather;
  late String _location;
  late DateTime _publishDate;
  bool _encrypted = false;
  String _password = '';
  bool _saving = false;

  static const List<String> _moods = ['😊', '😌', '😢', '😡', '😴', '🥰'];
  static const List<String> _weathers = ['🌞', '⛅', '🌧️', '❄️', '🌙', '🌈'];
  static const List<String> _moreMoods = [
    '🤩', '😭', '😤', '🤯', '🥳', '🤔', '😷', '🥺', '😎', '🤗', '😇', '🤪'
  ];
  static const List<String> _moreWeathers = [
    '🌤️', '🌦️', '🌨️', '⛈️', '🌪️', '🌫️', '⚡', '💨', '🌈', '🌊', '☁️', '🌡️'
  ];

  bool get _isNew => widget.entry == null;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry?.title ?? '');
    _subtitleCtrl = TextEditingController(text: widget.entry?.subtitle ?? '');
    _contentCtrl = HighlightEditingController(
      itemNames: _itemNames,
      text: widget.entry?.content ?? '',
    );
    _mood = widget.entry?.mood ?? _moods.first;
    _weather = widget.entry?.weather ?? _weathers.first;
    _location = widget.entry?.location ?? '';
    _publishDate =
        widget.entry?.publishDate ?? widget.defaultDate ?? DateTime.now();
    _encrypted = widget.entry?.encrypted ?? false;
    _password = widget.entry?.password ?? '';
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await ItemStorage.load();
    if (!mounted) return;
    setState(() {
      _itemNames =
          items.map((e) => e.name).where((n) => n.isNotEmpty).toSet();
      _contentCtrl.itemNames = _itemNames;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    final subtitle = _encrypted ? _subtitleCtrl.text.trim() : '';
    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写点什么再保存吧～')),
      );
      return;
    }
    if (_encrypted && subtitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写副标题～')),
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
        subtitle: subtitle,
        content: content,
        mood: _mood,
        weather: _weather,
        location: _location,
        encrypted: _encrypted,
        password: _password,
        createdAt: now,
        updatedAt: now,
        publishDate: _publishDate,
      ));
    } else {
      final idx = list.indexWhere((e) => e.id == widget.entry!.id);
      if (idx >= 0) {
        list[idx].title = title;
        list[idx].subtitle = subtitle;
        list[idx].content = content;
        list[idx].mood = _mood;
        list[idx].weather = _weather;
        list[idx].location = _location;
        list[idx].encrypted = _encrypted;
        list[idx].password = _password;
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
      list.removeWhere((e) => e.id == widget.entry!.id);
      await DiaryStorage.save(list);
      if (!mounted) return;
      Navigator.pop(context, true);
    }
  }

  Future<void> _pickVisibility() async {
    String choice = _encrypted ? 'encrypted' : 'public';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('可见度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('公开'),
                value: 'public',
                groupValue: choice,
                onChanged: (v) => setState(() => choice = v!),
              ),
              RadioListTile<String>(
                title: const Text('加密'),
                value: 'encrypted',
                groupValue: choice,
                onChanged: (v) => setState(() => choice = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, choice),
                child: const Text('确定')),
          ],
        ),
      ),
    );
    if (result == 'encrypted') {
      await _setPassword();
    } else if (result == 'public') {
      setState(() {
        _encrypted = false;
        _password = '';
      });
    }
  }

  Future<void> _setPassword() async {
    final ctrl = TextEditingController(text: _password);
    final pwd = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置密码'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(hintText: '请输入密码'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('确定')),
        ],
      ),
    );
    if (pwd != null && pwd.isNotEmpty) {
      setState(() {
        _encrypted = true;
        _password = pwd;
      });
    }
    ctrl.dispose();
  }

  Widget _buildVisibilityRow() {
    return InkWell(
      onTap: _pickVisibility,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFDCE7FF)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline,
                size: 16, color: Color(0xFF3B6FE0)),
            const SizedBox(width: 6),
            const Text(
              '可见度',
              style: TextStyle(fontSize: 13, color: Color(0xFF2A3B52)),
            ),
            const Spacer(),
            Text(
              _encrypted ? '加密' : '公开',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF3B6FE0),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: Color(0xFF9AA8BF)),
          ],
        ),
      ),
    );
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
          maxLength: 10,
          decoration: const InputDecoration(
            hintText: '输入地点（最多10字）',
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
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildChipRow('今天心情', _moods, _mood,
                    (v) => setState(() => _mood = v), _moreMoods),
                const SizedBox(height: 10),
                _buildChipRow('天气', _weathers, _weather,
                    (v) => setState(() => _weather = v), _moreWeathers),
                const SizedBox(height: 16),
                _buildDateLocationRow(),
                const SizedBox(height: 12),
                _buildVisibilityRow(),
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
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9AA8BF)),
                    ),
                  ],
                ),
                const Divider(height: 1),
                if (_encrypted) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _subtitleCtrl,
                          maxLength: 20,
                          style: const TextStyle(
                              fontSize: 15, color: Color(0xFF2A3B52)),
                          decoration: const InputDecoration(
                            hintText: '此处标题会公开显示哦～',
                            hintStyle: TextStyle(
                                fontSize: 14, color: Color(0xFF9AA8BF)),
                            border: InputBorder.none,
                            counterText: '',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      Text(
                        '${_subtitleCtrl.text.length}/20',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9AA8BF)),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                ],
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      child: TextField(
                        controller: _contentCtrl,
                        autofocus: _isNew,
                        maxLength: 2000,
                        maxLines: null,
                        minLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        style: const TextStyle(fontSize: 16, height: 1.7),
                        decoration: const InputDecoration(
                          hintText: '今天发生了什么…',
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 8,
                      child: Text(
                        '${_contentCtrl.text.length}/2000',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9AA8BF)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
                      : const Text('完成', style: TextStyle(fontSize: 16)),
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
    List<String> moreOptions,
  ) {
    Widget chip(String o, {VoidCallback? onTap, bool isMore = false}) {
      final isSel = o == selected;
      return GestureDetector(
        onTap: onTap ?? () => onSelect(o),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: (isSel && !isMore)
                ? const Color(0xFF3B6FE0)
                : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: (isSel && !isMore)
                  ? const Color(0xFF3B6FE0)
                  : const Color(0xFFDCE7FF),
            ),
          ),
          child: Text(o, style: const TextStyle(fontSize: 15)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9A8A7E))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...options.map((o) => chip(o)),
            chip('...',
                isMore: true,
                onTap: () => _showMoreEmoji(label, moreOptions, onSelect)),
          ],
        ),
      ],
    );
  }

  Future<void> _showMoreEmoji(
      String label, List<String> options, ValueChanged<String> onSelect) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('更多$label',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2A3B52))),
              const SizedBox(height: 16),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: options.map((o) {
                  return GestureDetector(
                    onTap: () {
                      onSelect(o);
                      Navigator.pop(ctx);
                    },
                    child: Text(o, style: const TextStyle(fontSize: 30)),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
