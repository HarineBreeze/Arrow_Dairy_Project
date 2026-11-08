import 'dart:async';
import 'dart:io';
import '../widgets/app_icons.dart';
import '../widgets/entry_image.dart';
import 'package:flutter/material.dart';

import '../utils/app_motion.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import '../utils/app_toast.dart';
import '../utils/diary_group_defaults.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';
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
import 'trash_screen.dart';
import '../services/trash_storage.dart';
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

const Color kPrimaryBlue = Color(0xFF3E8E6D);
const Color kLightBlue = Color(0xFFE4F2EB);
const Color kTextDark = Color(0xFF24382F);
const Color kTextMid = Color(0xFF647A70);
const Color kTextLight = Color(0xFF8FA09A);

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  List<DiaryEntry> _entries = [];
  bool _loading = true;

  /// 列表滚动控制器：用于「回顶」按钮的显隐与跳转。
  /// 两种视图（全部 / 分组）同一时刻只挂一个，共用同一个 controller。
  final ScrollController _listCtrl = ScrollController();
  bool _showBackTop = false;
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
  String _currentTab = 'diary'; // diary | items | assets | countdown | search | trash
  final GlobalKey<AssetScreenState> _assetListKey = GlobalKey();
  final GlobalKey<ItemListScreenState> _itemListKey =
      GlobalKey<ItemListScreenState>();
  final GlobalKey<CountdownScreenState> _countdownKey =
      GlobalKey<CountdownScreenState>();
  final GlobalKey<TrashScreenState> _trashKey = GlobalKey<TrashScreenState>();
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
    _listCtrl.addListener(_onListScroll);
    _load();
    _loadProfile();
    _initCountdown();
  }

  /// 事件：同步系统提醒 + 当天到期则弹出一次 App 内横幅
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
    _precacheCovers(list);
  }

  /// 首屏封面图预解码：放到下一帧之后做，不占用首帧时间。
  /// 只预热前 5 张（约一屏），其余仍按需解码 —— 全部预热反而会
  /// 在进入页面时抢解码线程，让第一张图的显示变慢。
  void _precacheCovers(List<DiaryEntry> list) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final e in list.take(5)) {
        if (e.imagePath.isEmpty) continue;
        if (!File(e.imagePath).existsSync()) continue;
        precacheImage(
          EntryImage.provider(context, e.imagePath, 124),
          context,
        ).catchError((Object _) {}); // 单张失败不影响其它
      }
    });
  }

  Future<void> _loadProfile() async {
    final p = await UserStorage.load();
    if (!mounted) return;
    setState(() => _profile = p);
  }

  Route<T> _slideRoute<T>(Widget page) => AppMotion.slide<T>(page);

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
        Haptics.mediumNow(); // 长按菜单：同步触发，避免异步等待导致振动被丢弃
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            ListTile(
              leading: AppIcon(
                entry.pinned ? AppIcons.pin : AppIcons.pinOn,
                // 与下方「编辑」按钮同款绿色，不再用红色
                color: const Color(0xFF3E8E6D),
              ),
              title: Text(entry.pinned ? '取消置顶' : '置顶',
                  style: const TextStyle(fontSize: 15)),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            // 加密笔记出于安全考虑，长按菜单仅支持置顶
            if (!entry.encrypted) ...[
              ListTile(
                leading:
                    const AppIcon(AppIcons.edit, color: Color(0xFF3E8E6D)),
                title: const Text('编辑', style: TextStyle(fontSize: 15)),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: const AppIcon(AppIcons.delete, color: Color(0xFFCB5C50)),
                title: const Text('删除',
                    style: TextStyle(fontSize: 15, color: Color(0xFFCB5C50))),
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
      AppToast.show(
          context,
          list.firstWhere((e) => e.id == entry.id).pinned
              ? '已置顶该笔记'
              : '已取消置顶');
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
                    style: const TextStyle(color: Color(0xFFCB5C50), fontSize: 13),
                  ),
                ],
              ],
            ),
            actions: [
              // 注意：不要在 actions（OverflowBar）里用 Spacer，会导致无限膨胀灰块
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
                  onPressed: () {
                    if (ctrl.text == entry.password) {
                      Navigator.pop(ctx, true);
                    } else {
                      setState(() => error = '密码错误，再试试吧～');
                    }
                  },
                  child: const Text('确认'),
                ),
              ),
              Pressable(
                enabled: true,
                child: TextButton(
                  onPressed: () => _showAnswerDialog(entry),
                  child: const Text(
                    '忘记密码',
                    style: TextStyle(fontSize: 13, color: Color(0xFF8FA09A)),
                  ),
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
                    style: TextStyle(fontSize: 13, color: Color(0xFF647A70)),
                  )
                else ...[
                  Text(
                    'Q：${entry.passwordHint}',
                    style: const TextStyle(
                        fontSize: 13, height: 1.5, color: Color(0xFF24382F)),
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
                      style: const TextStyle(color: Color(0xFFCB5C50), fontSize: 13),
                    ),
                  ],
                  if (revealedPwd != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4F2EB),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '密码：$revealedPwd',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3E8E6D),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
            actions: [
              if (revealedPwd == null && entry.passwordHint.isNotEmpty) ...[
                Pressable(
                  enabled: true,
                  child: TextButton(
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
                ),
              ],
              Pressable(
                enabled: true,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
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

  /// 默认展开的分组：按日视图下为「最近 7 天」，月/年为当前月/年，
  /// 全部视图不分组（无需展开项）
  ///
  /// 「最近 7 天」按自然日往前数（含今天），中间没写的日子本来就不会
  /// 生成分组，所以多算几天也不会有空分组，只是保证不会漏掉刚好
  /// 落在第 7 天写的那篇。规则细节见 [DiaryGroupDefaults]。
  List<String> _defaultExpandedKeys() {
    if (_viewMode == 'day') return DiaryGroupDefaults.expandedKeys();
    if (_viewMode == 'all') return const [];
    return [_defaultGroupKey()];
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
    if (_currentTab == 'trash') {
      // 回收站：筛选状态下返回先回到「全部」
      final trash = _trashKey.currentState;
      if (trash != null && trash.handleBack()) return false;
    }
    if (_currentTab == 'items') {
      final itemsState = _itemListKey.currentState;
      if (itemsState != null && itemsState.isSearching) {
        itemsState.closeSearch();
        return false;
      }
    }
    if (_currentTab == 'countdown') {
      // 事件子页：日历展开/搜索激活时，返回先收起日历/退出搜索
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
      // 连按返回键时只提示一次（去重窗口 2s 内不再重复）
      AppToast.show(context, '再返回一次退出应用',
          duration: const Duration(seconds: 2));
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
        content: const Text('删除后可在「回收站」保留 7 天，期间可还原。'),
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
      setState(() => _entries.removeWhere((e) => e.id == entry.id));
      await DiaryStorage.save(_entries);
      // 先入回收站：7 天内可从侧栏「回收站」还原
      await TrashStorage.addDiary(entry);
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 日期分组 key，统一走 [DiaryGroupDefaults.dateKey]，
  /// 避免默认展开的 key 与实际分组的 key 格式不一致而导致展不开
  String _dateKey(DateTime d) => DiaryGroupDefaults.dateKey(d);

  Set<String> get _markedDates =>
      _entries.map((e) => _dateKey(e.publishDate)).toSet();

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
    _listCtrl.removeListener(_onListScroll);
    _listCtrl.dispose();
    _menuController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 滚动超过一屏（600px）才显示「回顶」，避免短列表时按钮常驻遮挡卡片
  void _onListScroll() {
    if (!_listCtrl.hasClients) return;
    final show = _listCtrl.offset > AppMotion.backToTopThreshold;
    if (show != _showBackTop) setState(() => _showBackTop = show);
  }

  void _scrollToTop() {
    if (!_listCtrl.hasClients) return;
    Haptics.light();
    _listCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
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
            backgroundColor: const Color(0xFFF5FAF7),
            // Stack 覆盖整个 body（含状态栏区域）：这样菜单能从屏幕最顶端
            // 贯通到低端（顶部白色与状态栏区连成一体），遮罩也能盖住状态栏
            // 区域跟随变暗。主页内容自行用 SafeArea 避开状态栏。
            body: Container(
              color: const Color(0xB33E8E6D),
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
                            color: const Color(0xFFF5FAF7),
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
                                    // 全局搜索现为普通主页选项卡：
                                    // 高亮底纹滑至该项并切换内容，菜单收起
                                    _switchTab('search');
                                  },
                                  onOpenTrash: () {
                                    _switchTab('trash');
                                    // 切进来时重新读一次：期间可能刚删了东西
                                    _trashKey.currentState?.reload();
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
                              : _currentTab == 'search'
                                  ? KeyedSubtree(
                                      key: const ValueKey('search'),
                                      child: GlobalSearchScreen(
                                        onOpenMenu: _openMenu,
                                      ),
                                    )
                                  : _currentTab == 'trash'
                                      ? KeyedSubtree(
                                          key: const ValueKey('trash'),
                                          child: TrashScreen(
                                            key: _trashKey,
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
            floatingActionButton: _menuOpen ||
                    _currentTab == 'search' ||
                    _currentTab == 'trash'
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
                    child: const AppIcon(AppIcons.plus),
                  ),
          ),
        ),
      ),
    );
  }

  /// 横幅点击 → 切到事件主页并打开对应事件编辑页
  Future<void> _openCountdownById(String id) async {
    if (_currentTab != 'countdown') _switchTab('countdown');
    await Future.delayed(const Duration(milliseconds: 320));
    _countdownKey.currentState?.openEventById(id);
  }

  /// 首屏骨架占位：统一走全局 [ListSkeleton]（与其它主页一致）
  Widget _buildSkeleton() => const ListSkeleton();

  Widget _buildBody() {
    // 「全部」：不分组、无日期收纳栏，除置顶外的笔记按时间平铺；
    // 「按日/按月/按年」：保留可折叠的收纳栏
    final isFlat = _viewMode == 'all';
    final groups = isFlat ? <_NoteGroup>[] : _buildGroups();
    // 置顶笔记：顶部横滑卡带（不参与时间分组）
    final pinned = _filtered.where((e) => e.pinned).toList();
    final flatList =
        isFlat ? _filtered.where((e) => !e.pinned).toList() : <DiaryEntry>[];
    final isEmpty =
        isFlat ? (flatList.isEmpty && pinned.isEmpty) : groups.isEmpty;
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
          child: Stack(
            children: [
              Positioned.fill(
                child: isEmpty
                    ? _EmptyState(
                        hasQuery: _query.isNotEmpty,
                        hasDate: _selectedDate != null,
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: const Color(0xFF3E8E6D),
                        child: isFlat
                            ? _buildFlatList(pinned, flatList)
                            : _buildGroupedList(pinned, groups),
                      ),
              ),
              // 长列表快速回顶：只在滚过一屏后出现，避免遮挡内容。
              // 位置必须避开右下角的新建 FAB（占据底部 16~72），否则会被它盖住。
              if (_showBackTop)
                Positioned(
                  right: 16,
                  bottom: 92,
                  child: GestureDetector(
                    onTap: _scrollToTop,
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0x1F24382F),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const AppIcon(AppIcons.arrowUp,
                          size: 18, color: Color(0xFF3E8E6D)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 「全部」：置顶卡带（第 0 项）+ 平铺卡片，懒加载构建。
  /// 之前用 ListView(children:) 会一次性构建全部卡片，几百篇时首帧明显偏慢。
  Widget _buildFlatList(List<DiaryEntry> pinned, List<DiaryEntry> list) {
    final hasRail = pinned.isNotEmpty;
    return ListView.builder(
      // PageStorageKey：切换视图 / 从浏览页返回后仍停在原位置
      key: const PageStorageKey('note_list_all'),
      controller: _listCtrl,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: list.length + (hasRail ? 1 : 0),
      itemBuilder: (context, i) {
        if (hasRail && i == 0) return _buildPinnedRail(pinned);
        return _cardRow(list[hasRail ? i - 1 : i]);
      },
    );
  }

  /// 「按日/按月/按年」：把「分组头 / 卡片」摊平成一维行后交给 builder，
  /// 折叠起来的分组不产生卡片行，展开也只是多出可见范围内的构建。
  Widget _buildGroupedList(List<DiaryEntry> pinned, List<_NoteGroup> groups) {
    final rows = <_NoteRow>[];
    for (final g in groups) {
      rows.add(_NoteRow.header(g));
      if (_isGroupExpanded(g.key)) {
        for (final e in g.entries) {
          rows.add(_NoteRow.entry(e));
        }
      }
    }
    final hasRail = pinned.isNotEmpty;
    return ListView.builder(
      key: const PageStorageKey('note_list_grouped'),
      controller: _listCtrl,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: rows.length + (hasRail ? 1 : 0) + 1,
      itemBuilder: (context, i) {
        var index = i;
        if (hasRail) {
          if (i == 0) return _buildPinnedRail(pinned);
          index = i - 1;
        }
        // 末尾留白（与旧版 Column 末尾的 SizedBox 一致）
        if (index == rows.length) return const SizedBox(height: 12);
        final row = rows[index];
        if (row.group != null) {
          return _buildGroupHeader(
              row.group!, _isGroupExpanded(row.group!.key));
        }
        return _cardRow(row.entry!);
      },
    );
  }

  /// 单张卡片 + 长按手势（按住 500ms 不动，弹出操作菜单）。
  /// 外层 RepaintBoundary：滚动时卡片内容不参与主列表重绘。
  Widget _cardRow(DiaryEntry e) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Listener(
          onPointerDown: (ev) => _onCardPointerDown(e, ev.position),
          onPointerMove: (ev) => _onCardPointerMove(ev.position),
          onPointerUp: (_) => _cancelPressTracking(),
          onPointerCancel: (_) => _cancelPressTracking(),
          child: _DiaryCard(
            entry: e,
            isPinned: e.pinned,
            onTap: () => _openNote(e),
          ),
        ),
      ),
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
    final keys = ['all', 'day', 'month', 'year'];
    final labels = ['全部', '按日', '按月', '按年'];
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
                      onTap: () {
                        // 视图切换与其他页签类交互一致：轻触震动
                        if (selected) return;
                        Haptics.light();
                        _switchView(keys[i]);
                      },
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected
                                ? const Color(0xFF3E8E6D)
                                : const Color(0xFF647A70),
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
                    color: const Color(0xFF3E8E6D),
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
          // 用与长按菜单一致的置顶图标，不再用 📌 emoji：
          // emoji 在不同系统里字形差异大，且颜色不受主题控制
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(AppIcons.pinOn, size: 12, color: Color(0xFF3E8E6D)),
              const SizedBox(width: 3),
              Text(
                '置顶 ${pinned.length} 篇',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF3E8E6D)),
              ),
            ],
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
    final isDayView = _viewMode == 'day';
    final accent = isToday && isDayView;
    // 日视图：「10月27日」＋ 星期；月/年视图：整段作为日期
    final dateText =
        isDayView ? '${group.date.month}月${group.date.day}日' : group.label;
    return InkWell(
      onTap: () => _toggleGroup(group.key),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 7),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0 : -0.25,
              duration: const Duration(milliseconds: 180),
              child: const AppIcon(AppIcons.chevD,
                  size: 13, color: Color(0xFFB2C4BA)),
            ),
            const SizedBox(width: 3),
            Text(
              dateText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent ? kPrimaryBlue : kTextDark,
              ),
            ),
            if (isDayView) ...[
              const SizedBox(width: 5),
              Text(
                _weekdayLabel(group.date),
                style: const TextStyle(fontSize: 11, color: kTextLight),
              ),
            ],
            const SizedBox(width: 6),
            Text(
              '${group.entries.length} 篇',
              style: const TextStyle(fontSize: 11, color: kTextLight),
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
      color: const Color(0xB33E8E6D),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 15, color: Color(0xFF24382F)),
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                hintText: '搜索标题关键词…',
                hintStyle: const TextStyle(color: Color(0xFF8FA09A)),
                prefixIcon: const AppIcon(AppIcons.search,
                    size: 18, color: Color(0xFF8FA09A)),
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
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _closeSearch,
              child: const Text(
                '全部',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
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
      color: const Color(0xB33E8E6D),
      child: Stack(
        children: [
          Row(
            children: [
              IconButton(
                icon: const AppIcon(AppIcons.menu, color: Colors.white),
                onPressed: _openMenu,
              ),
              // 三条杠旁标出当前页名，与资产/事件页保持同一套「图标 + 页名」语言
              const Text(
                '日记',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const Spacer(),
              IconButton(
                icon: AppIcon(AppIcons.filter,
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
                  AppIcon(
                    _calendarExpanded ? AppIcons.chevU : AppIcons.chevD,
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                        color: Color(0xFF24382F),
                      ),
                    ),
                    const Spacer(),
                    Pressable(
                      enabled: true,
                      child: TextButton(
                        onPressed: () {
                          setState(() => _activeTopic = null);
                          Navigator.pop(ctx);
                        },
                        child: const Text(
                          '取消',
                          style: TextStyle(color: Color(0xFF8FA09A)),
                        ),
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
                            TextStyle(fontSize: 13, color: Color(0xFF8FA09A)),
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
                                active ? const Color(0xFF3E8E6D) : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: active
                                  ? const Color(0xFF3E8E6D)
                                  : const Color(0xFFE4F2EB),
                            ),
                          ),
                          child: Text(
                            '#$t',
                            style: TextStyle(
                              fontSize: 13,
                              color: active
                                  ? Colors.white
                                  : const Color(0xFF647A70),
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
      color: const Color(0xFFE4F2EB),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const AppIcon(AppIcons.tag, size: 14, color: Color(0xFF3E8E6D)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '正在筛选话题：#${_activeTopic}',
              style: const TextStyle(fontSize: 13, color: Color(0xFF3E8E6D)),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _activeTopic = null),
            child: const AppIcon(AppIcons.close, size: 16, color: Color(0xFF3E8E6D)),
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
          icon: const AppIcon(AppIcons.dblChevL,
              size: 20, color: kTextMid),
          tooltip: '上一年',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => setState(() => _visibleMonth =
              DateTime(_visibleMonth.year - 1, _visibleMonth.month, 1)),
        ),
        IconButton(
          icon: const AppIcon(AppIcons.chevL, color: kTextMid),
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
          icon: const AppIcon(AppIcons.chevR, color: kTextMid),
          onPressed: () => setState(() => _visibleMonth =
              DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1)),
        ),
        // ▶▶ 按年翻页
        IconButton(
          icon: const AppIcon(AppIcons.dblChevR,
              size: 20, color: kTextMid),
          tooltip: '下一年',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => setState(() => _visibleMonth =
              DateTime(_visibleMonth.year + 1, _visibleMonth.month, 1)),
        ),
        const Spacer(),
        Pressable(
          enabled: true,
          child: TextButton(
            onPressed: _showAll,
            child: const Text(
              '全部',
              style: TextStyle(
                color: kPrimaryBlue,
                fontWeight: FontWeight.w600,
              ),
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
                    style: const TextStyle(fontSize: 13, color: kTextLight),
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

/// 分组视图摊平后的一行：要么是分组头，要么是一张卡片。
/// 用 builder 列表时只保留「数据行」，widget 按需构建。
class _NoteRow {
  final _NoteGroup? group;
  final DiaryEntry? entry;
  _NoteRow.header(this.group) : entry = null;
  _NoteRow.entry(this.entry) : group = null;
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
    final t = entry.createdAt;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final encrypted = entry.encrypted;
    // 置顶卡两种形态，均为两行：
    // ① 加密笔记：第 1 行副标题，第 2 行「完整日期时间 + 锁」
    // ② 公开笔记：第 1 行标题，   第 2 行「完整日期时间」
    final title = encrypted
        ? (entry.subtitle.isNotEmpty ? entry.subtitle : '加密笔记')
        : (entry.title.isNotEmpty ? entry.title : '（无标题）');
    return Pressable(
      child:   Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              // 卡带里的卡本身就是置顶的，统一用主色描边
              border: Border.all(color: const Color(0xFF3E8E6D), width: 1.3),
            ),
            // 加密笔记：卡面铺斜纹纹理（与未置顶封条卡同一语言）
            // 注意：底色必须透明，否则会盖住下面的 painter
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: kTextDark,
                        ),
                      ),
                      const SizedBox(height: 5),
                      // 第 2 行：完整日期时间（加密笔记额外带锁标）
                      Row(
                        children: [
                          Text(
                            '${d.year}/${d.month}/${d.day} $hh:$mm',
                            style:
                                const TextStyle(fontSize: 9.5, color: kTextLight),
                          ),
                          if (encrypted) ...[
                            const SizedBox(width: 3),
                            const AppIcon(AppIcons.lock,
                                size: 10, color: kTextLight),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      )
    );;
  }
}

/// 加密卡斜向栅格纹理：与未置顶封条卡同一套 45° 斜纹（16px 周期、4px 线宽），
/// 铺满整张卡并以白色渐变压暗，保证副标题可读。
class _GridTexturePainter extends CustomPainter {
  const _GridTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 同 _SealStripePainter：裁掉 4px 线宽向带子边界外的溢出
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFEEF4F0));
    final paint = Paint()
      ..color = const Color(0xFFE4EDE8)
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
            fontWeight:
                (hasEntry || isSelected) ? FontWeight.w700 : FontWeight.w400,
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
  final bool isPinned;

  const _DiaryCard({
    Key? key,
    required this.entry,
    required this.onTap,
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
    // 有图走「左图右文」（图片 4:3）；无图沿用原撕页日历排版。
    // 图片文件可能已被系统清理：以实际存在为准，缺失自动回退无图版。
    final hasImage =
        entry.imagePath.isNotEmpty && File(entry.imagePath).existsSync();
    return Pressable(
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          // 置顶笔记：主色描边（不再用红色，避免和「涨/警示红」混淆）
          side: isPinned
              ? const BorderSide(color: Color(0xFF3E8E6D), width: 1.5)
              : BorderSide.none,
        ),
        color: Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: hasImage ? _buildImageCard() : _buildTextCard(),
        ),
      ),
    );
  }

  /// 有图版（方案 D）：左 4:3 图 + 右侧标题/摘要/元信息，单卡最矮
  Widget _buildImageCard() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          // 封面图与浏览页共享元素：点开笔记时图片从卡片位置飞到正文位置
          Hero(
            tag: 'note_cover_${entry.id}',
            // 飞行中统一用原文件渲染：两端解码宽度不同（124 vs 全宽），
            // 交给 Hero 默认处理会中途闪一次占位块
            flightShuttleBuilder: (_, __, ___, ____, _____) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(entry.imagePath), fit: BoxFit.cover),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 124,
                height: 93, // 4:3
                // 按 124 逻辑宽降采样解码，避免原图整幅驻留内存
                child: EntryImage(path: entry.imagePath, displayWidth: 124),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title.isNotEmpty ? entry.title : '（无标题）',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                    height: 1.35,
                  ),
                ),
                if (entry.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: kTextMid, height: 1.45),
                  ),
                ],
                const SizedBox(height: 6),
                _buildMetaRow(withDate: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 无图版：现有撕页日历排版（日期徽章 + 标题/摘要/时间地点）
  Widget _buildTextCard() {
    return Padding(
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
                        color: Color(0xFF3E8E6D),
                        height: 1.1)),
                const SizedBox(height: 2),
                // 年月：不换行，超宽时整体缩小适配两位月份
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                      '${entry.publishDate.year}.${entry.publishDate.month.toString().padLeft(2, '0')}',
                      maxLines: 1,
                      softWrap: false,
                      style: const TextStyle(fontSize: 11, color: kTextLight)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 右侧：标题 / 摘要 / 时间地点
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title.isNotEmpty ? entry.title : '（无标题）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: kTextDark,
                  ),
                ),
                if (entry.content.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    entry.content,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: kTextMid),
                  ),
                ],
                const SizedBox(height: 5),
                _buildMetaRow(withDate: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 元信息行：日期（仅图卡需要）/ 时间 / 地点
  /// 地点用 Flexible 吃满剩余宽度直到卡片右内边距（结尾不放 Spacer，
  /// 否则 Spacer 会与 Flexible 平分剩余空间，地点文字被提前截断）
  Widget _buildMetaRow({required bool withDate}) {
    final d = entry.publishDate;
    return Row(
      children: [
        if (withDate) ...[
          Text('${d.year}/${d.month}/${d.day}',
              style: const TextStyle(fontSize: 11, color: kTextLight)),
          const SizedBox(width: 5),
        ],
        Text(_timeLabel(entry.createdAt),
            style: const TextStyle(fontSize: 11, color: kTextLight)),
        if (entry.location.isNotEmpty) ...[
          const SizedBox(width: 6),
          const AppIcon(AppIcons.mapPin, size: 13, color: kTextLight),
          const SizedBox(width: 1),
          Flexible(
            child: Text(
              entry.location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: kTextLight),
            ),
          ),
        ],
      ],
    );
  }

  /// 加密笔记卡片（封条风）：
  /// 顶部斜纹密封带（🔒 已加密 · 月日）+ 下方副标题与时间，虚线边框。
  /// 只外显副标题、日期、时间，不涉及任何笔记内容。
  Widget _buildEncryptedCard() {
    // 置顶的加密笔记：粉底斜纹 + 红虚线边，置顶状态一望即知
    if (isPinned) {
      return Pressable(
        child:   Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ColoredBox(
              color: const Color(0xFFFBE3E8),
              child: CustomPaint(
                foregroundPainter: const _DashedRRectPainter(
                    color: Color(0xFFCB5C50), radius: 14),
                child: CustomPaint(
                  painter: const _PinnedStripePainter(),
                  child: Material(
                    color: const Color(0xE6FFFFFF),
                    child: InkWell(
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.subtitle.isNotEmpty
                                    ? entry.subtitle
                                    : '加密笔记',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: entry.subtitle.isNotEmpty
                                      ? const Color(0xFF647A70)
                                      : const Color(0xFF8FA09A),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(_timeLabel(entry.createdAt),
                                style: const TextStyle(
                                    fontSize: 11, color: kTextLight)),
                            const SizedBox(width: 4),
                            const AppIcon(AppIcons.lock,
                                size: 12, color: kTextLight),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        )
      );;
    }
    // 非置顶：封条带在上（🔒已加密 / 发布日期，斜纹底），白色主体在下
    //（副标题 + 记录时间），整卡无描边 —— 与封条档案袋观感一致。
    final d = entry.publishDate;
    return Pressable(
      child:   Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.white,
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 密封带：斜纹底 + 🔒已加密 / 月.日
                  CustomPaint(
                    painter: const _SealStripePainter(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                      child: Row(
                        children: [
                          const AppIcon(AppIcons.lock,
                              size: 11, color: kTextLight),
                          const SizedBox(width: 4),
                          const Text('已加密',
                              style: TextStyle(
                                  fontSize: 11, color: kTextLight)),
                          const Spacer(),
                          Text('${d.month}月${d.day}日',
                              style: const TextStyle(
                                  fontSize: 11, color: kTextLight)),
                        ],
                      ),
                    ),
                  ),
                  // 主体：副标题 + 时间
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.subtitle.isNotEmpty
                                ? entry.subtitle
                                : '加密笔记',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: entry.subtitle.isNotEmpty
                                  ? const Color(0xFF24382F)
                                  : const Color(0xFF8FA09A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(_timeLabel(entry.createdAt),
                            style: const TextStyle(
                                fontSize: 11, color: kTextLight)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      )
    );;
  }

  /// 置顶加密卡底纹：与封条卡同款 45° 斜纹，叠一层极淡的置顶粉
  /// （卡片真实渲染代码，不能只停留在设计稿）
}

/// 非置顶加密卡顶部「封条带」：淡灰底 + 45° 斜纹（16px 周期、4px 线宽），
/// 与置顶卡 / 置顶迷你卡的斜纹同一语言，仅不做中央提亮（带内无正文）。
class _SealStripePainter extends CustomPainter {
  const _SealStripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 斜线两端顶到带子边界，4px 线宽会向外溢出约 2px：
    // 底部溢出的锯齿会压到没有自绘背景的正文区（白色来自更早绘制的
    // Material），必须在 painter 内部自行裁剪到带子矩形内。
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFEEF4F0));
    final paint = Paint()
      ..color = const Color(0xFFE4EDE8)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    for (double x = -size.height; x < size.width + size.height; x += 16) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SealStripePainter oldDelegate) => false;
}

/// 虚线圆角边框（加密卡片的「档案袋」外框）
/// 置顶加密卡底纹：45° 斜纹（16px 周期、4px 线宽）+ 淡粉底，
/// 与未置顶封条卡的斜纹同一语言，仅色调改为置顶红系。
class _PinnedStripePainter extends CustomPainter {
  const _PinnedStripePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 同 _SealStripePainter：裁掉 4px 线宽向带子边界外的溢出
    canvas.clipRect(Offset.zero & size);
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
    // 同 _SealStripePainter：裁掉 4px 线宽向带子边界外的溢出
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFEEF4F0));
    final paint = Paint()
      ..color = const Color(0xFFE4EDE8)
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
