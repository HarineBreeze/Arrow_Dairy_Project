import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart'
    show SystemUiOverlayStyle, HapticFeedback;
import '../models/diary_entry.dart';
import '../models/user_profile.dart';
import '../services/diary_storage.dart';
import '../services/user_storage.dart';
import '../utils/rich_text.dart';
import 'edit_screen.dart';
import 'side_menu.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';
import 'global_search_screen.dart';
import 'note_view_screen.dart';
import 'item_list_screen.dart';
import 'asset_screen.dart';
import 'countdown_screen.dart';
import '../models/countdown_event.dart';
import '../services/countdown_storage.dart';
import '../services/countdown_reminder.dart';
import '../services/countdown_banner_log.dart';
import '../widgets/countdown_banner.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/empty_state.dart';
import '../utils/menu_gesture_gate.dart';

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

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
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
  final Set<String> _expandedKeys = {};
  String _viewMode = 'all'; // all | month | year
  String? _activeTopic; // 当前筛选的话题（null = 未筛选）
  String _currentTab = 'diary'; // diary | items | assets | countdown
  final GlobalKey<AssetScreenState> _assetListKey = GlobalKey();
  final GlobalKey<ItemListScreenState> _itemListKey =
      GlobalKey<ItemListScreenState>();
  final GlobalKey<CountdownScreenState> _countdownKey =
      GlobalKey<CountdownScreenState>();
  final GlobalKey<CountdownBannerHostState> _bannerKey =
      GlobalKey<CountdownBannerHostState>();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _menuController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    _menuAnim =
        CurvedAnimation(parent: _menuController, curve: Curves.easeOutCubic);
    _expandedKeys.addAll(_defaultExpandedKeys());
    _load();
    _loadProfile();
    _initCountdown();
  }

  /// 倒数日：同步系统提醒 + 当天到期则弹出一次 App 内横幅
  /// 同一事件同一天只弹一次（打开多少次 App 都不重复），记录见 CountdownBannerLog
  Future<void> _initCountdown() async {
    final list = await CountdownStorage.load();
    if (!mounted) return;
    await CountdownReminder.syncAll(list);
    if (!mounted) return;
    final due = list.where((e) => e.isDueToday).toList();
    if (due.isEmpty) return;
    // 过滤掉今天已经弹过横幅的事件
    final shown = await CountdownBannerLog.shownToday();
    if (!mounted) return;
    final fresh = due.where((e) => !shown.contains(e.id)).toList();
    if (fresh.isEmpty) return;
    final target = fresh.first;
    // 先落记录再弹，避免 App 在这期间被反复唤醒导致重复弹出
    await CountdownBannerLog.markShown(target.id);
    if (!mounted) return;
    // 等首帧布局完成、页面动画稳定后再滑出横幅（避免被首屏渲染盖住）
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _bannerKey.currentState?.showFor(target);
    });
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

  Route<T> _slideRoute<T>(Widget page) {
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  Timer? _stillTimer; // 40ms 静止观察
  Offset? _pressPos;
  double _pressMoved = 0;
  DiaryEntry? _pressEntry;

  /// 手指按下后 1 秒内屏幕保持不移动，即弹出操作菜单（置顶/编辑/删除）；
  /// 期间移动或抬起则取消，避免上下滑动屏幕时误触。
  void _onCardPointerDown(DiaryEntry e, Offset pos) {
    _cancelPressTracking();
    _pressEntry = e;
    _pressPos = pos;
    _pressMoved = 0;
    _stillTimer = Timer(const Duration(milliseconds: 500), () {
      _stillTimer = null;
      if (_pressEntry == e && _pressMoved < 6) {
        final entry = e;
        _cancelPressTracking();
        HapticFeedback.mediumImpact(); // 长按菜单震动反馈（与资产全景小眼睛一致的手感类型）
        _showNoteActions(entry);
      }
    });
  }

  void _onCardPointerMove(Offset pos) {
    if (_pressEntry == null || _pressPos == null) return;
    _pressMoved += (_pressPos! - pos).distance;
    _pressPos = pos;
    if (_pressMoved > 6) _cancelPressTracking();
  }

  void _cancelPressTracking() {
    _stillTimer?.cancel();
    _stillTimer = null;
    _pressEntry = null;
  }

  Future<void> _showNoteActions(DiaryEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            ListTile(
              leading: Icon(
                entry.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: const Color(0xFFE58BA0),
              ),
              title: Text(entry.pinned ? '取消置顶' : '置顶',
                  style: const TextStyle(fontSize: 15)),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            // 加密笔记出于安全考虑，长按菜单仅支持置顶
            if (!entry.encrypted) ...[
              ListTile(
                leading:
                    const Icon(Icons.edit_outlined, color: Color(0xFF3B6FE0)),
                title: const Text('编辑', style: TextStyle(fontSize: 15)),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('删除',
                    style: TextStyle(fontSize: 15, color: Colors.red)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'pin') {
      final list = await DiaryStorage.load();
      final idx = list.indexWhere((e) => e.id == entry.id);
      if (idx >= 0) {
        list[idx].pinned = !list[idx].pinned;
        await DiaryStorage.save(list);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(list.firstWhere((e) => e.id == entry.id).pinned
                ? '已置顶该笔记 📌'
                : '已取消置顶')),
      );
      _load();
    } else if (action == 'edit') {
      _openEditor(entry);
    } else if (action == 'delete') {
      _delete(entry);
    }
  }

  Future<void> _openEditor([DiaryEntry? entry]) async {
    final result = await Navigator.push<bool>(
      context,
      _slideRoute(EditScreen(entry: entry, defaultDate: _selectedDate)),
    );
    if (result == true) _load();
  }

  Future<void> _openNote(DiaryEntry entry) async {
    if (entry.encrypted) {
      final ok = await _verifyPassword(entry);
      if (!ok) return;
    }
    await Navigator.push<bool>(
      context,
      _slideRoute(NoteViewScreen(entry: entry)),
    );
    _load();
  }

  Future<bool> _verifyPassword(DiaryEntry entry) async {
    final ctrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String error = '';
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('请输入密码'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: '密码'),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
            actions: [
              // 注意：不要在 actions（OverflowBar）里用 Spacer，会导致无限膨胀灰块
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  if (ctrl.text == entry.password) {
                    Navigator.pop(ctx, true);
                  } else {
                    setState(() => error = '密码错误，再试试吧～');
                  }
                },
                child: const Text('确认'),
              ),
              TextButton(
                onPressed: () => _showAnswerDialog(entry),
                child: const Text(
                  '忘记密码',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9AA8BF)),
                ),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
    return result == true;
  }

  /// 忘记密码：回答密保问题，答对后展示该笔记密码
  Future<void> _showAnswerDialog(DiaryEntry entry) async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        String error = '';
        String? revealedPwd;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('密保问题'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.passwordHint.isEmpty)
                  const Text(
                    '这条笔记没有设置密保问题哦～',
                    style: TextStyle(fontSize: 14, color: Color(0xFF5A6B82)),
                  )
                else ...[
                  Text(
                    'Q：${entry.passwordHint}',
                    style: const TextStyle(
                        fontSize: 14, height: 1.5, color: Color(0xFF2A3B52)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    enabled: revealedPwd == null,
                    decoration: const InputDecoration(hintText: '请输入答案'),
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      error,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  if (revealedPwd != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCE7FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '密码：$revealedPwd',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B6FE0),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
            actions: [
              if (revealedPwd == null && entry.passwordHint.isNotEmpty) ...[
                TextButton(
                  onPressed: () {
                    if (ctrl.text.trim() == entry.passwordAnswer.trim() &&
                        entry.passwordAnswer.trim().isNotEmpty) {
                      setState(() => revealedPwd = entry.password);
                    } else {
                      setState(() => error = '答案不正确，再想想～');
                    }
                  },
                  child: const Text('确认'),
                ),
              ],
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      },
    );
    ctrl.dispose();
  }

  Future<void> _openProfileEditor() async {
    final result = await Navigator.push<bool>(
      context,
      _slideRoute(ProfileEditScreen(profile: _profile)),
    );
    if (result == true) _loadProfile();
  }

  Future<void> _openSettings() async {
    _closeMenu();
    final result = await Navigator.push<bool>(
      context,
      _slideRoute(const SettingsScreen()),
    );
    if (result == true) {
      _load();
      _loadProfile();
      _itemListKey.currentState?.reload();
    }
  }

  void _switchTab(String tab) {
    setState(() => _currentTab = tab);
    _closeMenu();
  }

  void _openMenu() {
    setState(() => _menuOpen = true);
    _menuController.forward();
  }

  void _closeMenu() {
    setState(() => _menuOpen = false);
    _menuController.reverse();
  }

  /// 侧边栏跟手拖拽（所有主页通用）。手势层用 pan 识别器（kPanSlop = 36px）
  /// 进入 Flutter 手势竞技场：页面内的横向/纵向拖拽识别器（日历翻页、攒钱
  /// 滑动、置顶卡带、列表滚动，均为 18px 声明阈值）都比 pan **更早声明获胜**
  /// 而优先执行，此时菜单完全不参与本次手势——二者绝不同时触发；
  /// 只有在没有页面手势争抢的区域，pan 才获胜并拉出/收回侧边栏。
  /// pan 胜出后按累计位移的主轴方向决定是否跟手：横向占优才拖动菜单，
  /// 纵向为主的滑动忽略（空白区上下轻扫不应拉出菜单）。
  /// 手势层设置 dragStartBehavior: DragStartBehavior.down，使 pan 胜出后
  /// 首次 onPanUpdate 携带「36px 声明阈值前的累计位移」，跟手不再丢失这段
  /// 距离——避免空白区第一次滑动只把侧边卡带出一点点、需第二次才正常。
  double? _menuDragBase;
  double _menuDragDx = 0;
  double _menuDragDy = 0;
  bool _menuDragActive = false;

  void _onMenuDragStart(DragStartDetails d) {
    _menuController.stop();
    _menuDragBase = _menuAnim.value;
    _menuDragDx = 0;
    _menuDragDy = 0;
    _menuDragActive = false;
  }

  void _onMenuDragUpdate(DragUpdateDetails d) {
    final base = _menuDragBase;
    if (base == null) return;
    _menuDragDx += d.delta.dx;
    _menuDragDy += d.delta.dy;
    if (!_menuDragActive) {
      if (_menuDragDx.abs() > _menuDragDy.abs()) {
        _menuDragActive = true; // 横向占优 → 开始跟手
      } else {
        return; // 纵向为主 → 忽略
      }
    }
    final w = MediaQuery.of(context).size.width * 3 / 4;
    _menuController.value = (base + _menuDragDx / w).clamp(0.0, 1.0);
  }

  void _onMenuDragEnd(DragEndDetails d) {
    final base = _menuDragBase;
    _menuDragBase = null;
    if (base == null || !_menuDragActive) return;
    final screenW = MediaQuery.of(context).size.width;
    // 已拉出的距离（像素），菜单宽度为屏幕的 3/4
    final dragged = _menuController.value * screenW * 3 / 4;
    final vx = d.velocity.pixelsPerSecond.dx;
    // 快速甩动优先：向左快甩直接收回，向右快甩直接展开
    if (vx < -900) {
      _closeMenu();
    } else if (vx > 900 || dragged > screenW / 3) {
      _openMenu();
    } else {
      _closeMenu();
    }
  }

  void _onMenuDragCancel() {
    final active = _menuDragActive;
    _menuDragBase = null;
    if (!active) return;
    if (_menuController.value > 0.5) {
      _openMenu();
    } else {
      _closeMenu();
    }
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

  void _showAll() {
    setState(() {
      _selectedDate = null;
      _activeTopic = null;
      _expandedKeys.addAll(_defaultExpandedKeys());
    });
  }

  bool _isGroupExpanded(String key) => _expandedKeys.contains(key);

  void _toggleGroup(String key) {
    setState(() {
      if (_expandedKeys.contains(key)) {
        _expandedKeys.remove(key);
      } else {
        _expandedKeys.add(key);
      }
    });
  }

  void _switchView(String mode) {
    setState(() {
      _viewMode = mode;
      _expandedKeys.clear();
      _expandedKeys.addAll(_defaultExpandedKeys());
    });
  }

  /// 默认展开的分组：日视图下为「今天 + 昨天」，其余视图为当前月/年
  List<String> _defaultExpandedKeys() {
    if (_viewMode != 'all') return [_defaultGroupKey()];
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    return [_dateKey(now), _dateKey(yesterday)];
  }

  String _defaultGroupKey() {
    final now = DateTime.now();
    switch (_viewMode) {
      case 'month':
        return '${now.year}-${now.month.toString().padLeft(2, '0')}';
      case 'year':
        return '${now.year}';
      default:
        return _dateKey(now);
    }
  }

  String _groupKeyOf(DateTime d) {
    switch (_viewMode) {
      case 'month':
        return '${d.year}-${d.month.toString().padLeft(2, '0')}';
      case 'year':
        return '${d.year}';
      default:
        return _dateKey(d);
    }
  }

  String _groupLabelOf(DateTime d) {
    switch (_viewMode) {
      case 'month':
        return '${d.year}年${d.month}月';
      case 'year':
        return '${d.year}年';
      default:
        return '${d.month}月${d.day}日 ${_weekdayLabel(d)}';
    }
  }

  String _weekdayLabel(DateTime d) {
    const weeks = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weeks[d.weekday - 1];
  }

  Future<bool> _handleBack() async {
    if (_menuOpen) {
      _closeMenu();
      return false;
    }
    if (_currentTab == 'items') {
      final itemsState = _itemListKey.currentState;
      if (itemsState != null && itemsState.isSearching) {
        itemsState.closeSearch();
        return false;
      }
    }
    if (_currentTab == 'countdown') {
      // 倒数日子页：日历展开/搜索激活时，返回先收起日历/退出搜索
      final cd = _countdownKey.currentState;
      if (cd != null && cd.handleBack()) return false;
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

  /// 当天第一篇（按创建时间最早）笔记的心情，用于日历小图标
  String? _moodOfDay(DateTime d) {
    DiaryEntry? first;
    for (final e in _entries) {
      if (!_sameDay(e.publishDate, d)) continue;
      if (first == null || e.createdAt.isBefore(first.createdAt)) {
        first = e;
      }
    }
    return first?.mood;
  }

  List<DiaryEntry> get _filtered {
    var list = _entries;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((e) => e.title.toLowerCase().contains(q)).toList();
    }
    if (_activeTopic != null) {
      final t = _activeTopic!;
      list = list
          .where((e) =>
              !e.encrypted &&
              RichTextParser.extractTopics(e.content).contains(t))
          .toList();
    }
    if (_selectedDate != null) {
      final d = _selectedDate!;
      list = list.where((e) => _sameDay(e.publishDate, d)).toList();
    }
    return list;
  }

  List<String> get _allTopics {
    final seen = <String>{};
    final result = <String>[];
    for (final e in _entries) {
      if (e.encrypted) continue;
      for (final t in RichTextParser.extractTopics(e.content)) {
        if (seen.add(t)) result.add(t);
      }
    }
    return result;
  }

  @override
  void dispose() {
    _stillTimer?.cancel();
    _menuController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 状态栏图标亮度随菜单开合切换：主页蓝底用浅色图标，
    // 菜单打开后顶部大部分为白色菜单区，改用深色图标。
    return AnimatedBuilder(
      animation: _menuAnim,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              _menuAnim.value > 0.5 ? Brightness.dark : Brightness.light,
        ),
        child: child!,
      ),
      child: CountdownBannerHost(
        key: _bannerKey,
        onOpenEvent: _openCountdownById,
        child: WillPopScope(
          onWillPop: _handleBack,
          child: Scaffold(
            backgroundColor: const Color(0xFFF3F6FB),
            // Stack 覆盖整个 body（含状态栏区域）：这样菜单能从屏幕最顶端
            // 贯通到低端（顶部白色与状态栏区连成一体），遮罩也能盖住状态栏
            // 区域跟随变暗。主页内容自行用 SafeArea 避开状态栏。
            body: Container(
              color: const Color(0xB33B6FE0),
              child: AnimatedBuilder(
                animation: _menuAnim,
                builder: (context, child) {
                  final menuWidth = MediaQuery.of(context).size.width * 3 / 4;
                  final offset = menuWidth * _menuAnim.value;
                  return Stack(
                    children: [
                      Transform.translate(
                        offset: Offset(offset, 0),
                        child: SafeArea(
                          child: Container(
                            color: const Color(0xFFF3F6FB),
                            child: child!,
                          ),
                        ),
                      ),
                      // 遮罩层：始终保留在树中。若按 `_menuAnim.value > 0`
                      // 条件增删，首次拖拽跨越 0 时会改变 Stack 子节点结构，
                      // 导致手势层识别器被打断（首次滑动卡住、无 end/cancel）。
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: _menuAnim.value <= 0,
                          child: GestureDetector(
                            onTap: _closeMenu,
                            child: Opacity(
                              opacity: _menuAnim.value * 0.45,
                              child: Container(color: Colors.black),
                            ),
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
                              // 菜单从屏幕最顶端贯通（背景白覆盖状态栏区域），
                              // 内容用 SafeArea 避开状态栏。
                              child: SafeArea(
                                bottom: false,
                                child: SideMenu(
                                  profile: _profile,
                                  currentTab: _currentTab,
                                  onClose: _closeMenu,
                                  onOpenProfile: _openProfileEditor,
                                  onOpenDiary: () => _switchTab('diary'),
                                  onOpenItems: () => _switchTab('items'),
                                  onOpenAssets: () => _switchTab('assets'),
                                  onOpenCountdown: () =>
                                      _switchTab('countdown'),
                                  onOpenSettings: _openSettings,
                                  onOpenGlobalSearch: () {
                                    _closeMenu();
                                    Navigator.of(context)
                                        .push(_slideRoute(
                                            const GlobalSearchScreen()))
                                        .then((r) {
                                      // 搜索页内三横杠/左右滑 → 返回并拉出菜单侧边栏
                                      if (r == 'open-menu' && mounted) {
                                        _openMenu();
                                      }
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 手势层（左半屏）：右滑拉出菜单。pan 识别器（36px 声明
                      // 阈值）进手势竞技场——页面内横向/纵向手势（18px 声明）
                      // 均优先获胜且菜单不参与，二者绝不同时触发；仅在无页面
                      // 手势争抢的区域菜单才响应。
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: MediaQuery.of(context).size.width / 2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          dragStartBehavior: DragStartBehavior.down,
                          onPanStart: _onMenuDragStart,
                          onPanUpdate: _onMenuDragUpdate,
                          onPanEnd: _onMenuDragEnd,
                          onPanCancel: _onMenuDragCancel,
                        ),
                      ),
                      // 右 2/3 手势层：菜单打开时左滑跟手收回。与左半屏共用
                      // 同一套回调；菜单关闭时拖动值被钳制在 0，无副作用。
                      Positioned(
                        left: MediaQuery.of(context).size.width / 3,
                        top: 0,
                        bottom: 0,
                        width: MediaQuery.of(context).size.width * 2 / 3,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          dragStartBehavior: DragStartBehavior.down,
                          onPanStart: _onMenuDragStart,
                          onPanUpdate: _onMenuDragUpdate,
                          onPanEnd: _onMenuDragEnd,
                          onPanCancel: _onMenuDragCancel,
                        ),
                      ),
                    ],
                  );
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
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
                  child: _currentTab == 'items'
                      ? KeyedSubtree(
                          key: const ValueKey('items'),
                          child: ItemListScreen(
                            key: _itemListKey,
                            onOpenMenu: _openMenu,
                          ),
                        )
                      : _currentTab == 'assets'
                          ? KeyedSubtree(
                              key: const ValueKey('assets'),
                              child: AssetScreen(
                                key: _assetListKey,
                                onOpenMenu: _openMenu,
                                onCancel: () => _switchTab('diary'),
                              ),
                            )
                          : _currentTab == 'countdown'
                              ? KeyedSubtree(
                                  key: const ValueKey('countdown'),
                                  child: CountdownScreen(
                                    key: _countdownKey,
                                    onOpenMenu: _openMenu,
                                  ),
                                )
                              : _loading
                                  ? KeyedSubtree(
                                      key: const ValueKey('loading'),
                                      child: _buildSkeleton(),
                                    )
                                  : KeyedSubtree(
                                      key: const ValueKey('diary'),
                                      child: _buildBody(),
                                    ),
                ),
              ),
            ),
            floatingActionButton: _menuOpen
                ? null
                : FloatingActionButton(
                    onPressed: () {
                      if (_currentTab == 'items') {
                        _itemListKey.currentState?.openNewItem();
                      } else if (_currentTab == 'assets') {
                        _assetListKey.currentState?.openNewAsset();
                      } else if (_currentTab == 'countdown') {
                        _countdownKey.currentState?.openNewEvent();
                      } else {
                        _openEditor();
                      }
                    },
                    child: const Icon(Icons.add),
                  ),
          ),
        ),
      ),
    );
  }

  /// 横幅点击 → 切到倒数日主页并打开对应事件编辑页
  Future<void> _openCountdownById(String id) async {
    if (_currentTab != 'countdown') _switchTab('countdown');
    await Future.delayed(const Duration(milliseconds: 320));
    _countdownKey.currentState?.openEventById(id);
  }

  /// 首屏骨架占位：统一走全局 [ListSkeleton]（与其它主页一致）
  Widget _buildSkeleton() => const ListSkeleton();

  Widget _buildBody() {
    final groups = _buildGroups();
    // 置顶笔记：顶部横滑卡带（不参与时间分组）
    final pinned = _filtered.where((e) => e.pinned).toList();
    // 标签筛选 + 全部视图：不按时间分组，所有匹配笔记平铺展示
    final flatTopicList = _activeTopic != null && _viewMode == 'all';
    return Column(
      children: [
        _buildTopBar(),
        _buildViewBar(),
        if (_activeTopic != null) _buildTopicBar(),
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
          child: (groups.isEmpty && !flatTopicList) ||
                  (flatTopicList && _filtered.isEmpty)
              ? _EmptyState(
                  hasQuery: _query.isNotEmpty,
                  hasDate: _selectedDate != null,
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: const Color(0xFF3B6FE0),
                  child: flatTopicList
                      ? ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) {
                            final e = _filtered[i];
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Listener(
                                onPointerDown: (ev) =>
                                    _onCardPointerDown(e, ev.position),
                                onPointerMove: (ev) =>
                                    _onCardPointerMove(ev.position),
                                onPointerUp: (_) => _cancelPressTracking(),
                                onPointerCancel: (_) => _cancelPressTracking(),
                                child: _DiaryCard(
                                  entry: e,
                                  isPinned: e.pinned,
                                  onTap: () => _openNote(e),
                                  onDelete: () => _delete(e),
                                ),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: groups.length + (pinned.isEmpty ? 0 : 1),
                          itemBuilder: (context, i) {
                            // 首项：置顶横滑卡带（P3）
                            if (pinned.isNotEmpty) {
                              if (i == 0) return _buildPinnedRail(pinned);
                              i -= 1;
                            }
                            final group = groups[i];
                            final expanded = _isGroupExpanded(group.key);
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildGroupHeader(group, expanded),
                                if (expanded)
                                  ...group.entries.map((e) => Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Listener(
                                          // 按住卡片 500ms 不动，弹出操作菜单
                                          onPointerDown: (ev) =>
                                              _onCardPointerDown(
                                                  e, ev.position),
                                          onPointerMove: (ev) =>
                                              _onCardPointerMove(ev.position),
                                          onPointerUp: (_) =>
                                              _cancelPressTracking(),
                                          onPointerCancel: (_) =>
                                              _cancelPressTracking(),
                                          child: _DiaryCard(
                                            entry: e,
                                            isPinned: e.pinned,
                                            onTap: () => _openNote(e),
                                            onDelete: () => _delete(e),
                                          ),
                                        ),
                                      )),
                                if (i == groups.length - 1)
                                  const SizedBox(height: 12),
                              ],
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }

  List<_NoteGroup> _buildGroups() {
    final groups = <_NoteGroup>[];
    // 置顶笔记改为顶部横滑卡带，不再进入时间分组
    _NoteGroup? current;
    for (final e in _filtered) {
      if (e.pinned) continue; // 置顶的移出普通日期分栏
      final key = _groupKeyOf(e.publishDate);
      final label = _groupLabelOf(e.publishDate);
      if (current == null || current.key != key) {
        current = _NoteGroup(
            key: key, label: label, date: e.publishDate, entries: []);
        groups.add(current);
      }
      current.entries.add(e);
    }
    return groups;
  }

  Widget _buildViewBar() {
    final keys = ['month', 'year', 'all'];
    final labels = ['按月', '按年', '全部'];
    final index = keys.indexOf(_viewMode);
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = constraints.maxWidth / keys.length;
        final left = index * cellW + (cellW - 40) / 2;
        return Container(
          height: 48,
          color: Colors.white,
          child: Stack(
            children: [
              Row(
                children: List.generate(keys.length, (i) {
                  final selected = keys[i] == _viewMode;
                  return Expanded(
                    child: InkWell(
                      onTap: () => _switchView(keys[i]),
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected
                                ? const Color(0xFF3B6FE0)
                                : const Color(0xFF5A6B82),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: left,
                bottom: 0,
                child: Container(
                  width: 40,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B6FE0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 按无障碍状态决定是否给卡带加手势闸门：
  /// TalkBack 触摸浏览会自己吞掉手势（部分机型还会缓存 semantics），
  /// 一旦闸门卡住会让整块区域再也拉不出菜单，所以这种场景直接不加。
  Widget _gatePinnedRail(Widget child) {
    if (WidgetsBinding.instance.platformDispatcher.semanticsEnabled) {
      return child;
    }
    return PageGestureGate(swipeAxis: Axis.horizontal, child: child);
  }

  /// 置顶横滑卡带（P3）：一行小标题 + 可左右滑动的迷你卡
  Widget _buildPinnedRail(List<DiaryEntry> pinned) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, left: 2, bottom: 7),
          child: Text(
            '📌 置顶 ${pinned.length} 篇',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFFC4697C)),
          ),
        ),
        // 页面横向手势优先：横滑卡带期间不让主页把菜单拖出来；
        // 无障碍（TalkBack 触摸浏览）时不区分，避免菜单被永久让位
        _gatePinnedRail(
          SizedBox(
            height: 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(right: 4),
              itemCount: pinned.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final e = pinned[i];
                return Listener(
                  onPointerDown: (ev) => _onCardPointerDown(e, ev.position),
                  onPointerMove: (ev) => _onCardPointerMove(ev.position),
                  onPointerUp: (_) => _cancelPressTracking(),
                  onPointerCancel: (_) => _cancelPressTracking(),
                  child: SizedBox(
                    width: 132,
                    child: _PinnedMiniCard(
                      entry: e,
                      onTap: () => _openNote(e),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// 时间分组头（T1）：无底块的浅灰小字行；今天用蓝色高亮日期
  Widget _buildGroupHeader(_NoteGroup group, bool expanded) {
    final isToday = _sameDay(group.date, DateTime.now());
    final isWeekView = _viewMode == 'all';
    final accent = isToday && isWeekView;
    // 日视图：「10月27日」＋ 星期；月/年视图：整段作为日期
    final dateText =
        isWeekView ? '${group.date.month}月${group.date.day}日' : group.label;
    return InkWell(
      onTap: () => _toggleGroup(group.key),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 7),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0 : -0.25,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.expand_more,
                  size: 13, color: Color(0xFFB4BFD0)),
            ),
            const SizedBox(width: 3),
            Text(
              dateText,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: accent ? kPrimaryBlue : kTextDark,
              ),
            ),
            if (isWeekView) ...[
              const SizedBox(width: 5),
              Text(
                _weekdayLabel(group.date),
                style: const TextStyle(fontSize: 10.5, color: kTextLight),
              ),
            ],
            const SizedBox(width: 6),
            Text(
              '${group.entries.length} 篇',
              style: const TextStyle(fontSize: 10.5, color: kTextLight),
            ),
            const Spacer(),
          ],
        ),
      ),
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
      color: const Color(0xB33B6FE0),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 15, color: Color(0xFF2A3B52)),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: '搜索标题关键词…',
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
            child: const Text(
              '全部',
              style: TextStyle(
                color: Colors.white,
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
    String label = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (_selectedDate != null) {
      final d = _selectedDate!;
      label = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    }
    return Container(
      key: const ValueKey('normal_bar'),
      height: 48,
      color: const Color(0xB33B6FE0),
      child: Stack(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: _openMenu,
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.filter_list,
                    color: _activeTopic == null
                        ? Colors.white
                        : const Color(0xFFFFD666)),
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
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
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

  void _showFilterSheet() {
    final topics = _allTopics;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '按话题筛选',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2A3B52),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() => _activeTopic = null);
                        Navigator.pop(ctx);
                      },
                      child: const Text(
                        '取消',
                        style: TextStyle(color: Color(0xFF9AA8BF)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (topics.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        '还没有话题\n在日记正文输入 #话题词 即可创建',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 13, color: Color(0xFF9AA8BF)),
                      ),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: topics.map((t) {
                      final active = t == _activeTopic;
                      return GestureDetector(
                        onTap: () {
                          if (active) {
                            setState(() => _activeTopic = null);
                          } else {
                            setState(() {
                              _activeTopic = t;
                              _viewMode = 'all';
                              _expandedKeys.clear();
                              _expandedKeys.addAll(_defaultExpandedKeys());
                            });
                          }
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color:
                                active ? const Color(0xFF3B6FE0) : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: active
                                  ? const Color(0xFF3B6FE0)
                                  : const Color(0xFFDCE7FF),
                            ),
                          ),
                          child: Text(
                            '#$t',
                            style: TextStyle(
                              fontSize: 13,
                              color: active
                                  ? Colors.white
                                  : const Color(0xFF5A6B82),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopicBar() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFDCE7FF),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.tag, size: 14, color: Color(0xFF3B6FE0)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '正在筛选话题：#${_activeTopic}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF3B6FE0)),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _activeTopic = null),
            child: const Icon(Icons.close, size: 16, color: Color(0xFF3B6FE0)),
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
        // ◀◀ 按年翻页
        IconButton(
          icon: const Icon(Icons.keyboard_double_arrow_left,
              size: 20, color: kTextMid),
          tooltip: '上一年',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => setState(() => _visibleMonth =
              DateTime(_visibleMonth.year - 1, _visibleMonth.month, 1)),
        ),
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
        // ▶▶ 按年翻页
        IconButton(
          icon: const Icon(Icons.keyboard_double_arrow_right,
              size: 20, color: kTextMid),
          tooltip: '下一年',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => setState(() => _visibleMonth =
              DateTime(_visibleMonth.year + 1, _visibleMonth.month, 1)),
        ),
        const Spacer(),
        TextButton(
          onPressed: _showAll,
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
      final isSelected =
          _selectedDate != null && _sameDay(_selectedDate!, date);
      final isToday = _sameDay(today, date);
      cells.add(_DayCell(
        day: day,
        hasEntry: hasEntry,
        isSelected: isSelected,
        isToday: isToday,
        mood: hasEntry ? _moodOfDay(date) : null,
        onTap: () {
          setState(() {
            if (_selectedDate != null && _sameDay(date, _selectedDate!)) {
              _selectedDate = null; // 再次点击选中的日期 → 回到当日
            } else {
              _selectedDate = date;
            }
          });
        },
      ));
    }
    // 页面手势闸门：日历滑动翻月优先，期间不触发菜单侧边栏拖拽
    return PageGestureGate(
      child: GestureDetector(
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
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

class _NoteGroup {
  final String key;
  final String label;
  final DateTime date;
  final List<DiaryEntry> entries;
  _NoteGroup({
    required this.key,
    required this.label,
    required this.date,
    required this.entries,
  });
}

/// 置顶横滑卡带里的迷你卡（P3）：红描边 + 标题 + 日期/心情，加密笔记只露副标题
class _PinnedMiniCard extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onTap;

  const _PinnedMiniCard({Key? key, required this.entry, required this.onTap})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final d = entry.publishDate;
    final encrypted = entry.encrypted;
    // 置顶卡两种形态，均为两行：
    // ① 加密笔记：第 1 行副标题，第 2 行「月.日 + 锁」
    // ② 公开笔记：第 1 行标题，   第 2 行「月.日 + 心情」
    final title = encrypted
        ? (entry.subtitle.isNotEmpty ? entry.subtitle : '加密笔记')
        : (entry.title.isNotEmpty ? entry.title : '（无标题）');
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFFE0576A), width: 1.3),
          ),
          // 加密笔记：卡面铺斜纹纹理（与未置顶封条卡同一语言）
          // 注意：底色必须透明，否则会盖住下面的 painter
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CustomPaint(
              painter: encrypted ? const _GridTexturePainter() : null,
              child: Container(
                color: encrypted ? Colors.transparent : Colors.white,
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 第 1 行：标题 / 副标题
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: kTextDark,
                      ),
                    ),
                    const SizedBox(height: 5),
                    // 第 2 行：月.日 + （加密：锁 / 公开：心情）
                    Row(
                      children: [
                        Text(
                          '${d.month}.${d.day}',
                          style:
                              const TextStyle(fontSize: 9.5, color: kTextLight),
                        ),
                        const SizedBox(width: 3),
                        if (encrypted)
                          const Icon(Icons.lock, size: 10, color: kTextLight)
                        else
                          Text(
                            entry.mood,
                            maxLines: 1,
                            style: const TextStyle(fontSize: 9.5),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 加密卡斜向栅格纹理：与未置顶封条卡同一套 45° 斜纹（16px 周期、4px 线宽），
/// 铺满整张卡并以白色渐变压暗，保证副标题可读。
class _GridTexturePainter extends CustomPainter {
  const _GridTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFEFF2F7));
    final paint = Paint()
      ..color = const Color(0xFFE7EBF1)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    for (double x = -size.height; x < size.width + size.height; x += 16) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
    // 中央留白：让 🔒 + 副标题落在干净底色上
    final fade = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xCCFFFFFF),
          Color(0xB3FFFFFF),
          Color(0x99FFFFFF),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, fade);
  }

  @override
  bool shouldRepaint(covariant _GridTexturePainter oldDelegate) => false;
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool hasEntry;
  final bool isSelected;
  final bool isToday;
  final String? mood; // 当天第一篇笔记的心情
  final VoidCallback onTap;

  const _DayCell({
    Key? key,
    required this.day,
    required this.hasEntry,
    required this.isSelected,
    required this.isToday,
    this.mood,
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight: (hasEntry || isSelected)
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: fg,
              ),
            ),
            // 日历小心情：有日记的当日在日期下显示第一篇笔记的心情
            if (mood != null && mood!.isNotEmpty)
              Text(mood!, style: const TextStyle(fontSize: 8, height: 1.0)),
          ],
        ),
      ),
    );
  }
}

class _DiaryCard extends StatelessWidget {
  final DiaryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool isPinned;

  const _DiaryCard({
    Key? key,
    required this.entry,
    required this.onTap,
    required this.onDelete,
    this.isPinned = false,
  }) : super(key: key);

  String _timeLabel(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isEncrypted = entry.encrypted;
    // 加密笔记：封条风卡片（斜纹密封带 + 虚线边框），只外显副标题与日期时间
    if (isEncrypted) return _buildEncryptedCard();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        // 置顶笔记：红色描边（收纳栏不变）
        side: isPinned
            ? const BorderSide(color: Color(0xFFE0576A), width: 1.5)
            : BorderSide.none,
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 左侧日期徽章：大号「日」+ 年月小字，像撕页日历
              Container(
                width: 52,
                padding: const EdgeInsets.only(right: 10),
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Color(0xFFE8EDF5)),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('${entry.publishDate.day}',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3B6FE0),
                            height: 1.1)),
                    const SizedBox(height: 2),
                    // 年月：不换行，超宽时整体缩小适配两位月份
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                          '${entry.publishDate.year}.${entry.publishDate.month.toString().padLeft(2, '0')}',
                          maxLines: 1,
                          softWrap: false,
                          style:
                              const TextStyle(fontSize: 10, color: kTextLight)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 右侧：标题 / 摘要 / 心情天气地点脚注
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title.isNotEmpty ? entry.title : '（无标题）',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              color: kTextDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (entry.content.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        entry.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: kTextMid),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(entry.mood, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Text(entry.weather,
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 6),
                        Text(_timeLabel(entry.createdAt),
                            style: const TextStyle(
                                fontSize: 11, color: kTextLight)),
                        if (entry.location.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.location_on,
                              size: 13, color: kTextLight),
                          const SizedBox(width: 1),
                          Flexible(
                            child: Text(
                              entry.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11, color: kTextLight),
                            ),
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
            ],
          ),
        ),
      ),
    );
  }

  /// 加密笔记卡片（封条风）：
  /// 顶部斜纹密封带（🔒 已加密 · 月日）+ 下方副标题与时间，虚线边框。
  /// 只外显副标题、日期、时间，不涉及任何笔记内容。
  Widget _buildEncryptedCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      // 置顶的加密笔记：与未置顶封条卡保持同款，但底纹换成斜纹 + 红虚线边
      // （虚线颜色 = 置顶红，未置顶为灰），让置顶状态一望即知。
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(
          color: isPinned ? const Color(0xFFFBE3E8) : Colors.transparent,
          child: CustomPaint(
            foregroundPainter: _DashedRRectPainter(
                color: isPinned
                    ? const Color(0xFFE0576A)
                    : const Color(0xFFC9CFD9),
                radius: 14),
            child: CustomPaint(
              painter: isPinned ? const _PinnedStripePainter() : null,
              child: Material(
                // 置顶加密卡：沿用封条式排版（顶部密封带 + 副标题时间行），
                // 仅把锁图标从标题前移到时间右侧。
                color: isPinned ? const Color(0xE6FFFFFF) : Colors.white,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.subtitle.isNotEmpty ? entry.subtitle : '加密笔记',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: entry.subtitle.isNotEmpty
                                  ? const Color(0xFF5A6B82)
                                  : const Color(0xFF9AA8BF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_timeLabel(entry.createdAt),
                            style: const TextStyle(
                                fontSize: 11, color: kTextLight)),
                        const SizedBox(width: 4),
                        const Icon(Icons.lock, size: 12, color: kTextLight),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 置顶加密卡底纹：与封条卡同款 45° 斜纹，叠一层极淡的置顶粉
  /// （卡片真实渲染代码，不能只停留在设计稿）
}

/// 虚线圆角边框（加密卡片的「档案袋」外框）
/// 置顶加密卡底纹：45° 斜纹（16px 周期、4px 线宽）+ 淡粉底，
/// 与未置顶封条卡的斜纹同一语言，仅色调改为置顶红系。
class _PinnedStripePainter extends CustomPainter {
  const _PinnedStripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFFBE3E8));
    final paint = Paint()
      ..color = const Color(0xFFF0CBD4)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    for (double x = -size.height; x < size.width + size.height; x += 16) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
    // 中间提亮：封条与正文所在区域不被斜纹压花
    final fade = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xCCFFFFFF), Color(0xB3FFFFFF)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, fade);
  }

  @override
  bool shouldRepaint(covariant _PinnedStripePainter oldDelegate) => false;
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dashWidth;
  final double dashGap;
  final double strokeWidth;

  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    this.dashWidth = 5,
    this.dashGap = 4,
    this.strokeWidth = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = (dist + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, next.toDouble()), paint);
        dist = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

/// 斜纹保密封带：浅灰底 + 45° 斜线纹理
class _StripeBandPainter extends CustomPainter {
  const _StripeBandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFEFF2F7));
    final paint = Paint()
      ..color = const Color(0xFFE7EBF1)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    // 以 16px 为周期画 45° 斜线，覆盖整个矩形
    for (double x = -size.height; x < size.width + size.height; x += 16) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
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
    // 统一走全局空状态组件，视觉与其它主页保持一致
    return Center(
      child: EmptyState(
        topGap: 0,
        icon: '📖',
        title: message,
        subtitle: sub,
      ),
    );
  }
}
