import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import '../models/diary_entry.dart';
import '../models/user_profile.dart';
import '../services/diary_storage.dart';
import '../services/user_storage.dart';
import 'edit_screen.dart';
import 'side_menu.dart';
import 'profile_edit_screen.dart';
import 'note_view_screen.dart';

const Color kPrimaryBlue = Color(0xFF3B6FE0);
const Color kLightBlue = Color(0xFFDCE7FF);
const Color kTextDark = Color(0xFF2A3B52);
const Color kTextMid = Color(0xFF5A6B82);
const Color kTextLight = Color(0xFF9AA8BF);

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  List<DiaryEntry> _entries = [];
  bool _loading = true;
  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  DateTime? _selectedDate; // null = 全部
  bool _calendarExpanded = false;
  late DateTime _visibleMonth;

  bool _menuOpen = false;
  UserProfile _profile = UserProfile();
  late final AnimationController _menuController;
  late final Animation<double> _menuAnim;
  DateTime? _lastBackAt;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _menuController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _menuAnim = CurvedAnimation(
        parent: _menuController, curve: Curves.easeOutCubic);
    _load();
    _loadProfile();
  }

  Future<void> _load() async {
    final list = await DiaryStorage.load();
    list.sort((a, b) => b.publishDate.compareTo(a.publishDate));
    if (!mounted) return;
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  Future<void> _loadProfile() async {
    final p = await UserStorage.load();
    if (!mounted) return;
    setState(() => _profile = p);
  }

  Future<void> _openEditor([DiaryEntry? entry]) async {
    final result = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
          builder: (_) => EditScreen(entry: entry, defaultDate: _selectedDate)),
    );
    if (result == true) _load();
  }

  Future<void> _openNoteView(DiaryEntry entry) async {
    await Navigator.push<bool>(
      context,
      CupertinoPageRoute(builder: (_) => NoteViewScreen(entry: entry)),
    );
    _load();
  }

  Future<void> _openProfileEditor() async {
    final result = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(builder: (_) => ProfileEditScreen(profile: _profile)),
    );
    if (result == true) _loadProfile();
  }

  void _openMenu() {
    setState(() => _menuOpen = true);
    _menuController.forward();
  }

  void _closeMenu() {
    setState(() => _menuOpen = false);
    _menuController.reverse();
  }

  void _openSearch() {
    setState(() => _searching = true);
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchCtrl.clear();
    });
  }

  Future<bool> _handleBack() async {
    if (_menuOpen) {
      _closeMenu();
      return false;
    }
    if (_calendarExpanded) {
      setState(() => _calendarExpanded = false);
      return false;
    }
    if (_searching) {
      _closeSearch();
      return false;
    }
    final now = DateTime.now();
    if (_lastBackAt == null ||
        now.difference(_lastBackAt!) > const Duration(seconds: 2)) {
      _lastBackAt = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('再返回一次退出应用'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _delete(DiaryEntry entry) async {
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
      setState(() => _entries.removeWhere((e) => e.id == entry.id));
      await DiaryStorage.save(_entries);
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Set<String> get _markedDates =>
      _entries.map((e) => _dateKey(e.publishDate)).toSet();

  List<DiaryEntry> get _filtered {
    var list = _entries;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((e) => e.title.toLowerCase().contains(q)).toList();
    }
    if (_selectedDate != null) {
      final d = _selectedDate!;
      list = list.where((e) => _sameDay(e.publishDate, d)).toList();
    }
    return list;
  }

  @override
  void dispose() {
    _menuController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        body: AnimatedBuilder(
          animation: _menuAnim,
          builder: (context, child) {
            final menuWidth = MediaQuery.of(context).size.width * 3 / 4;
            final offset = menuWidth * _menuAnim.value;
            return Stack(
              children: [
                Transform.translate(
                  offset: Offset(offset, 0),
                  child: child!,
                ),
                if (_menuAnim.value > 0)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: _closeMenu,
                      child: Opacity(
                        opacity: _menuAnim.value * 0.45,
                        child: Container(color: Colors.black),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Transform.translate(
                    offset: Offset(-menuWidth * (1 - _menuAnim.value), 0),
                    child: Material(
                      color: Colors.white,
                      elevation: 8,
                      child: SizedBox(
                        width: menuWidth,
                        child: SideMenu(
                          profile: _profile,
                          onClose: _closeMenu,
                          onOpenProfile: _openProfileEditor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
          child: SafeArea(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(),
          ),
        ),
        floatingActionButton: _menuOpen
            ? null
            : FloatingActionButton(
                onPressed: () => _openEditor(),
                child: const Icon(Icons.add),
              ),
      ),
    );
  }

  Widget _buildBody() {
    final list = _filtered;
    return Column(
      children: [
        _buildTopBar(),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: (_calendarExpanded && !_searching)
                ? _buildCalendar()
                : const SizedBox(width: double.infinity),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE8EDF5)),
        Expanded(
          child: list.isEmpty
              ? _EmptyState(
                  hasQuery: _query.isNotEmpty,
                  hasDate: _selectedDate != null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final e = list[i];
                    return _DiaryCard(
                      entry: e,
                      onTap: () => _openNoteView(e),
                      onDelete: () => _delete(e),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      },
      child: _searching ? _buildSearchBar() : _buildNormalBar(),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      key: const ValueKey('search_bar'),
      height: 48,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: '搜索标题关键词…',
                hintStyle: const TextStyle(color: kTextLight),
                prefixIcon: const Icon(Icons.search, color: kTextLight),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: const Color(0xFFF3F6FB),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          TextButton(
            onPressed: _closeSearch,
            child: const Text(
              '全部',
              style: TextStyle(
                color: kPrimaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalBar() {
    final now = DateTime.now();
    String label = '${now.year} - ${now.month} - ${now.day}';
    if (_selectedDate != null) {
      final d = _selectedDate!;
      label = '${d.year} - ${d.month} - ${d.day}';
    }
    return Container(
      key: const ValueKey('normal_bar'),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: kTextDark),
            onPressed: _openMenu,
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  setState(() => _calendarExpanded = !_calendarExpanded),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: kTextDark,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _calendarExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18,
                    color: kTextLight,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search, color: kTextMid),
            onPressed: _openSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          _buildMonthHeader(),
          _buildWeekHeader(),
          const SizedBox(height: 4),
          _buildDayGrid(),
        ],
      ),
    );
  }

  Widget _buildMonthHeader() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: kTextMid),
          onPressed: () => setState(() => _visibleMonth =
              DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1)),
        ),
        Text(
          '${_visibleMonth.year}年${_visibleMonth.month}月',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: kTextDark,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: kTextMid),
          onPressed: () => setState(() => _visibleMonth =
              DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1)),
        ),
        const Spacer(),
        TextButton(
          onPressed: () => setState(() => _selectedDate = null),
          child: const Text(
            '全部',
            style: TextStyle(
              color: kPrimaryBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeekHeader() {
    const weeks = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: weeks
          .map((w) => Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: const TextStyle(fontSize: 12, color: kTextLight),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildDayGrid() {
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday; // 1=周一 ... 7=周日

    final cells = <Widget>[];
    for (int i = 1; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }
    final today = DateTime.now();
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final hasEntry = _markedDates.contains(_dateKey(date));
      final isSelected = _selectedDate != null && _sameDay(_selectedDate!, date);
      final isToday = _sameDay(today, date);
      cells.add(_DayCell(
        day: day,
        hasEntry: hasEntry,
        isSelected: isSelected,
        isToday: isToday,
        onTap: () => setState(() => _selectedDate = date),
      ));
    }
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      childAspectRatio: 1.15,
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool hasEntry;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  const _DayCell({
    Key? key,
    required this.day,
    required this.hasEntry,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color bg = Colors.transparent;
    Color fg = kTextDark;
    if (isSelected) {
      bg = kPrimaryBlue;
      fg = Colors.white;
    } else if (hasEntry) {
      bg = kLightBlue;
      fg = kPrimaryBlue;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: (isToday && !isSelected)
              ? Border.all(color: kPrimaryBlue, width: 1.2)
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 13,
            fontWeight: (hasEntry || isSelected)
                ? FontWeight.w700
                : FontWeight.w400,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _DiaryCard extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _DiaryCard({
    Key? key,
    required this.entry,
    required this.onTap,
    required this.onDelete,
  }) : super(key: key);

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    if (diff == 2) return '前天';
    return '${d.year}年${d.month}月${d.day}日';
  }

  String _timeLabel(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(entry.mood, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(entry.weather, style: const TextStyle(fontSize: 16)),
                  const Spacer(),
                  Text(
                    '${_dateLabel(entry.publishDate)} ${_timeLabel(entry.createdAt)}',
                    style: const TextStyle(fontSize: 11, color: kTextLight),
                  ),
                ],
              ),
              if (entry.title.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                ),
              ],
              if (entry.content.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  entry.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: kTextMid),
                ),
              ],
              const SizedBox(height: 2),
              Row(
                children: [
                  if (entry.location.isNotEmpty) ...[
                    const Icon(Icons.location_on,
                        size: 14, color: kTextLight),
                    const SizedBox(width: 2),
                    Text(
                      entry.location,
                      style: const TextStyle(fontSize: 12, color: kTextLight),
                    ),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: onDelete,
                    child: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: kTextLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasQuery;
  final bool hasDate;
  const _EmptyState({Key? key, required this.hasQuery, required this.hasDate})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    String message = '还没有日记';
    String sub = '点击右下角 + 写下第一篇吧';
    if (hasQuery) {
      message = '没有找到相关日记';
      sub = '换个关键词试试';
    } else if (hasDate) {
      message = '这一天还没有日记';
      sub = '点击右下角 + 记录这一天';
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📖', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(fontSize: 16, color: kTextMid),
          ),
          const SizedBox(height: 8),
          Text(
            sub,
            style: const TextStyle(fontSize: 13, color: kTextLight),
          ),
        ],
      ),
    );
  }
}
