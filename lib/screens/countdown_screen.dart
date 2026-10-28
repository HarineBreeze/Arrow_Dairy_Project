import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/countdown_event.dart';
import '../services/countdown_storage.dart';
import '../services/countdown_reminder.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_skeleton.dart';
import '../utils/menu_gesture_gate.dart';
import 'countdown_edit_screen.dart';

/// 倒数日主页：顶栏（年月 + 搜索 + 筛选）、日历视图、
/// 置顶组 / 纪念日 / 资产日 三个可折叠分组的长条卡片列表。
class CountdownScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  const CountdownScreen({Key? key, this.onOpenMenu}) : super(key: key);

  @override
  State<CountdownScreen> createState() => CountdownScreenState();
}

class CountdownScreenState extends State<CountdownScreen> {
  List<CountdownEvent> _events = [];
  bool _loading = true;

  // 搜索
  bool _searching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  // 日历
  bool _calendarExpanded = false;
  late DateTime _visibleMonth;

  // 筛选：null = 全部
  String? _typeFilter;

  // 分组展开状态
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await CountdownStorage.load();
    if (!mounted) return;
    setState(() {
      _events = list;
      _loading = false;
    });
  }

  /// 下拉刷新：重新读取本地数据并同步提醒（与其它主页行为一致）
  Future<void> _refresh() async {
    await _load();
    if (!mounted) return;
    // 提醒同步不阻塞刷新动画
    CountdownReminder.syncAll(_events);
    HapticFeedback.selectionClick();
  }

  /// 供外部（首页 FAB）调用的快捷入口
  Future<void> openNewEvent() async {
    final r = await Navigator.push<CountdownEvent>(
      context,
      _slideRoute(CountdownEditScreen()),
    );
    if (r != null) {
      if (!mounted) return;
      // 先刷新界面，落盘与闹钟同步异步进行（不阻塞返回动画后的首帧）
      setState(() => _events.add(r));
      CountdownStorage.save(_events);
      CountdownReminder.syncAll(_events);
    }
  }

  /// 供外部（横幅点击）调用：按 id 打开事件编辑页
  Future<void> openEventById(String id) async {
    final i = _events.indexWhere((e) => e.id == id);
    if (i < 0) return;
    await _openEditor(_events[i]);
  }

  PageRouteBuilder<T> _slideRoute<T>(Widget page) => PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, animation, __, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(curved),
            child: child,
          );
        },
      );

  // ---------- 过滤 ----------

  List<CountdownEvent> get _filtered {
    final q = _query.trim().toLowerCase();
    return _events.where((e) {
      if (_typeFilter != null && e.type != _typeFilter) return false;
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  bool get _hasFilter => _typeFilter != null;

  /// 分组：置顶 / 纪念日 / 资产日
  Map<String, List<CountdownEvent>> get _grouped {
    final pinned = <CountdownEvent>[];
    final memorial = <CountdownEvent>[];
    final asset = <CountdownEvent>[];
    for (final e in _filtered) {
      if (e.pinned) {
        pinned.add(e);
      } else if (e.type == '资产日') {
        asset.add(e);
      } else {
        memorial.add(e);
      }
    }
    // 组内按剩余天数升序（最近的在前）
    int byDays(CountdownEvent a, CountdownEvent b) =>
        a.daysLeft.compareTo(b.daysLeft);
    pinned.sort(byDays);
    memorial.sort(byDays);
    asset.sort(byDays);
    return {'置顶': pinned, '纪念日': memorial, '资产日': asset};
  }

  // ---------- 操作 ----------

  Future<void> _openEditor([CountdownEvent? e]) async {
    // 传入深拷贝：编辑页会直接改传入对象（保存时 `e..icon=...`），
    // 若传原对象，用户放弃修改也会污染列表里的实例。
    final r = await Navigator.push<dynamic>(
      context,
      _slideRoute(CountdownEditScreen(event: e == null ? null : e.clone())),
    );
    if (r == 'deleted') {
      if (!mounted) return;
      final id = e!.id;
      final next = _events.where((x) => x.id != id).toList();
      setState(() => _events = next);
      CountdownReminder.cancelOne(id);
      CountdownStorage.save(next);
      return;
    }
    if (r is CountdownEvent) {
      final i = _events.indexWhere((x) => x.id == r.id);
      if (!mounted) return;
      setState(() {
        if (i >= 0) {
          _events[i] = r;
        } else {
          _events.add(r);
        }
      });
      CountdownStorage.save(_events);
      CountdownReminder.syncAll(_events);
    }
  }

  /// 长按 500ms → 选框：置顶 / 编辑 / 删除
  void _showCardMenu(CountdownEvent e) {
    HapticFeedback.mediumImpact(); // 长按菜单震动反馈
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(
                e.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: const Color(0xFF3B6FE0),
              ),
              title: Text(e.pinned ? '取消置顶' : '置顶'),
              onTap: () async {
                Navigator.pop(ctx);
                e.pinned = !e.pinned;
                await CountdownStorage.save(_events);
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Color(0xFF3B6FE0)),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _openEditor(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    title: const Text('删除这个倒数日?'),
                    content: const Text('删除后无法恢复'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('取消')),
                      TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('删除',
                              style: TextStyle(color: Colors.red))),
                    ],
                  ),
                );
                if (ok == true) {
                  // 先算出要保存的新列表并立即刷新界面（删除反馈零延迟）；
                  // 落盘与闹钟取消异步进行，不阻塞 UI，也不出现「先顿一下再消失」。
                  final target = e;
                  final next =
                      _events.where((x) => x.id != target.id).toList();
                  setState(() => _events = next);
                  HapticFeedback.mediumImpact();
                  // 只取消这一条提醒（单次通道调用，远比整表重排快）
                  CountdownReminder.cancelOne(target.id);
                  CountdownStorage.save(next);
                }
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          Widget option(String label, String? value) {
            final on = _typeFilter == value;
            return Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setSheet(() {
                    // 再次点击已选项 → 恢复全部
                    _typeFilter = on ? null : value;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: on ? const Color(0xFF3B6FE0) : const Color(0xFFF5F7FB),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          color: on ? Colors.white : const Color(0xFF2A3B52),
                          fontWeight:
                              on ? FontWeight.w600 : FontWeight.normal)),
                ),
              ),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('按事件类型筛选',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2A3B52))),
                  const SizedBox(height: 14),
                  Wrap(children: [
                    option('全部', null),
                    ...CountdownEvent.types.map((t) => option(t, t)),
                  ]),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {});
                      },
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _openSearch() {
    setState(() {
      _searching = true;
      _calendarExpanded = false;
    });
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchCtrl.clear();
    });
  }

  /// 跳到某个日期（日历点击）：仅切换月份展示，不做数据筛选
  void _onDayTap(DateTime date) {
    setState(() {
      if (date.year != _visibleMonth.year ||
          date.month != _visibleMonth.month) {
        _visibleMonth = DateTime(date.year, date.month, 1);
      }
    });
  }

  // ---------- 构建 ----------

  /// 返回键/侧滑：日历展开 → 收起日历；搜索激活 → 退出搜索。
  /// 返回 true 表示本次返回已被本页消费（由主页的 WillPopScope 委托调用）。
  bool handleBack() {
    if (_calendarExpanded) {
      setState(() => _calendarExpanded = false);
      return true;
    }
    if (_searching) {
      _closeSearch();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: (_calendarExpanded && !_searching)
                ? _buildCalendar()
                : const SizedBox(width: double.infinity),
          ),
        ),
        Expanded(
          child: _loading
              ? const ListSkeleton()
              : RefreshIndicator(
                  color: const Color(0xFF3B6FE0),
                  onRefresh: _refresh,
                  child: _filtered.isEmpty
                      ? ListView(
                          // 空态也需要可滚动，否则下拉手势无法触发刷新
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            EmptyState(
                              icon: '⏳',
                              title: _searching ? '没有匹配的倒数日' : '还没有倒数日',
                              subtitle: _searching
                                  ? '换个关键词试试'
                                  : '点右下角 + 添加第一个',
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                          children: _buildGroups(),
                        ),
                ),
        ),
      ],
    );
  }

  List<Widget> _buildGroups() {
    final g = _grouped;
    final widgets = <Widget>[];
    for (final key in ['置顶', '纪念日', '资产日']) {
      final list = g[key] ?? const <CountdownEvent>[];
      if (list.isEmpty) continue;
      final expanded = !_collapsed.contains(key);
      widgets.add(_buildSectionHeader(key, list.length, expanded));
      if (expanded) {
        widgets.addAll(list.map(_buildCard));
      }
      widgets.add(const SizedBox(height: 8));
    }
    return widgets;
  }

  Widget _buildSectionHeader(String title, int count, bool expanded) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (expanded) {
            _collapsed.add(title);
          } else {
            _collapsed.remove(title);
          }
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
        child: Row(
          children: [
            // 置顶组分类小色块
            Container(
              width: 4,
              height: 14,
              decoration: BoxDecoration(
                color: title == '置顶'
                    ? const Color(0xFFF2A0C0)
                    : (title == '资产日'
                        ? const Color(0xFF9BC2F0)
                        : const Color(0xFFA9D8B8)),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2A3B52))),
            const SizedBox(width: 6),
            Text('$count',
                style: const TextStyle(fontSize: 12, color: Color(0xFF9AA8BF))),
            const Spacer(),
            Icon(expanded ? Icons.expand_less : Icons.expand_more,
                size: 20, color: const Color(0xFF9AA8BF)),
          ],
        ),
      ),
    );
  }

  /// 长条卡片：图标 | 名称+类型 | 剩余时间
  Widget _buildCard(CountdownEvent e) {
    final grey = e.expired;
    final loopRed = e.loopHighlight;
    Color bg = Colors.white;
    if (grey) bg = const Color(0xFFF0F1F3);

    return GestureDetector(
      onTap: () => _openEditor(e),
      onLongPress: () => _showCardMenu(e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          // 置顶 / 到期循环标记：红色描边（与其它主页置顶描边统一）
          border: (loopRed || e.pinned)
              ? Border.all(color: const Color(0xFFE0576A), width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              // 不再给图标加底纹色块，图标直接落在卡片底色上
              child: Text(
                  e.icon.trim().isEmpty
                      ? CountdownEvent.defaultIconFor(e.type)
                      : e.icon,
                  style: TextStyle(
                      fontSize: 24,
                      color: grey ? const Color(0xFF9AA8BF) : null)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: grey
                              ? const Color(0xFF9AA8BF)
                              : const Color(0xFF2A3B52))),
                  // 卡片上不展示事件类型，该位置显示事件备注；无备注则留空
                  if (e.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(e.note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: grey
                                ? const Color(0xFFB4BCC8)
                                : const Color(0xFF5A6B82))),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 已结束（主文案为空）时，副标题升为主文案，避免重复展示
                if (e.displayText.isNotEmpty)
                  Text(
                    e.displayText,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: grey
                          ? const Color(0xFFB4BCC8)
                          : (e.daysLeft == 0
                              ? const Color(0xFFE0576A)
                              : const Color(0xFF3B6FE0)),
                    ),
                  ),
                // 副标题：资产日「已拥有 x 天」/ 纪念日「已过去 x 天」
                if (e.subtitle != null && e.displayText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(e.subtitle!,
                      style: TextStyle(
                          fontSize: 11,
                          color: grey
                              ? const Color(0xFFB4BCC8)
                              : const Color(0xFF9AA8BF))),
                ],
                if (e.displayText.isEmpty && e.subtitle != null)
                  Text(e.subtitle!,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: grey
                            ? const Color(0xFFB4BCC8)
                            : const Color(0xFF3B6FE0),
                      )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 顶栏 ----------

  Widget _buildTopBar() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => SlideTransition(
        position:
            Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(animation),
        child: child,
      ),
      child: _searching ? _buildSearchBar() : _buildNormalBar(),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      key: const ValueKey('cd_search'),
      height: 48,
      color: const Color(0xB33B6FE0),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: false, // 不默认吊起键盘，由用户点输入框后再弹
              style: const TextStyle(fontSize: 15, color: Color(0xFF2A3B52)),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: '搜索倒数日名称…',
                hintStyle: const TextStyle(color: Color(0xFF9AA8BF)),
                prefixIcon: const Icon(Icons.search,
                    size: 18, color: Color(0xFF9AA8BF)),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                filled: true,
                fillColor: Colors.white,
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
            child: const Text('全部',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalBar() {
    final label =
        '${_visibleMonth.year}-${_visibleMonth.month.toString().padLeft(2, '0')}';
    return Container(
      key: const ValueKey('cd_normal'),
      height: 48,
      color: const Color(0xB33B6FE0),
      child: Stack(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: widget.onOpenMenu,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: _openSearch,
              ),
              IconButton(
                icon: Icon(Icons.filter_list,
                    color: _hasFilter ? const Color(0xFFFFD666) : Colors.white),
                tooltip: '筛选',
                onPressed: _showFilterSheet,
              ),
            ],
          ),
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  setState(() => _calendarExpanded = !_calendarExpanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(width: 4),
                  Icon(
                    _calendarExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 日历 ----------

  Widget _buildCalendar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              // 上一年
              IconButton(
                icon: const Icon(Icons.keyboard_double_arrow_left,
                    size: 18, color: Color(0xFF8A99B3)),
                tooltip: '上一年',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                onPressed: () => setState(() => _visibleMonth = DateTime(
                    _visibleMonth.year - 1, _visibleMonth.month, 1)),
              ),
              // 上一月
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Color(0xFF5A6B82)),
                tooltip: '上一月',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                onPressed: () => setState(() => _visibleMonth = DateTime(
                    _visibleMonth.year, _visibleMonth.month - 1, 1)),
              ),
              Expanded(
                child: Center(
                  child: Text('${_visibleMonth.year}年${_visibleMonth.month}月',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2A3B52))),
                ),
              ),
              // 下一月
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Color(0xFF5A6B82)),
                tooltip: '下一月',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                onPressed: () => setState(() => _visibleMonth = DateTime(
                    _visibleMonth.year, _visibleMonth.month + 1, 1)),
              ),
              // 下一年
              IconButton(
                icon: const Icon(Icons.keyboard_double_arrow_right,
                    size: 18, color: Color(0xFF8A99B3)),
                tooltip: '下一年',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                onPressed: () => setState(() => _visibleMonth = DateTime(
                    _visibleMonth.year + 1, _visibleMonth.month, 1)),
              ),
              TextButton(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _visibleMonth = DateTime(now.year, now.month, 1);
                    _calendarExpanded = false;
                  });
                },
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('今天',
                    style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF3B6FE0),
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Row(
            children: const ['一', '二', '三', '四', '五', '六', '日']
                .map((w) => Expanded(
                      child: Center(
                        child: Text(w,
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF9AA8BF))),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 4),
          _buildDayGrid(),
        ],
      ),
    );
  }

  Widget _buildDayGrid() {
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = firstDay.weekday;

    final cells = <Widget>[];
    for (int i = 1; i < startWeekday; i++) {
      cells.add(const SizedBox());
    }
    final today = DateTime.now();
    // 日期 → 该日第一个事件的图标（用于日历内展示）
    final dayIcon = <String, String>{};
    for (final e in _events) {
      final t = CountdownEvent.dateOnly(e.target);
      final key = '${t.year}-${t.month}-${t.day}';
      dayIcon.putIfAbsent(
          key,
          () => e.icon.trim().isEmpty
              ? CountdownEvent.defaultIconFor(e.type)
              : e.icon);
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(year, month, day);
      final key = '${date.year}-${date.month}-${date.day}';
      final icon = dayIcon[key];
      final hasEvent = icon != null;
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      cells.add(GestureDetector(
        onTap: () => _onDayTap(date),
        child: Center(
          child: Container(
            width: 34,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // 有记录的日期：浅蓝底纹；今天：浅蓝圆底
              color: hasEvent
                  ? const Color(0xFFEAF0FB)
                  : (isToday ? const Color(0xFFDCE7FF) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$day',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.1,
                        fontWeight: (isToday || hasEvent)
                            ? FontWeight.w700
                            : FontWeight.normal,
                        color: isToday
                            ? const Color(0xFF3B6FE0)
                            : const Color(0xFF2A3B52))),
                const SizedBox(height: 1),
                Text(
                  hasEvent ? icon : '',
                  style: const TextStyle(fontSize: 9, height: 1.0),
                ),
              ],
            ),
          ),
        ),
      ));
    }
    // 页面手势闸门：日历滑动翻月优先，期间不触发菜单侧边栏拖拽
    return PageGestureGate(
      child: GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) {
            setState(() => _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1));
          } else if (v > 200) {
            setState(() => _visibleMonth =
                DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1));
          }
        },
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 7,
          childAspectRatio: 1.15,
          children: cells,
        ),
      ),
    );
  }
}
