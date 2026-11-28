import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_motion.dart';
import '../utils/app_toast.dart';
import '../services/reward_service.dart';
import '../models/asset.dart';
import '../models/user_profile.dart';
import '../services/app_settings.dart';
import '../services/asset_storage.dart';
import '../services/user_storage.dart';
import '../services/trash_storage.dart';
import '../utils/usable_days.dart';
import '../widgets/empty_state.dart';
import '../widgets/entry_icon.dart';
import '../widgets/loading_skeleton.dart';
import 'asset_edit_screen.dart';
import 'usable_days_settings_sheet.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';
import '../widgets/asset_pie_card.dart';
import '../widgets/asset_sankey_card.dart';
import '../widgets/app_icons.dart';
import '../widgets/pin_setup_wizard.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
import '../utils/app_sheet.dart';
/// 资产全景主页。默认无需密码即可查看；
/// 开启「加密访问」后，进入本页需先输入密码解锁。
/// 返回 true 表示确认完成（供外部回调刷新）。
class AssetScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  /// 用户在密码页点了「取消」时回调，由首页切回笔记主页（保留兼容，正常不再触发）
  final VoidCallback? onCancel;

  /// 仅供测试：注入用户档案加载（验证 VIP 权益锁态）。
  final Future<UserProfile> Function()? loadProfileOverride;

  const AssetScreen({
    Key? key,
    this.onOpenMenu,
    this.onCancel,
    this.loadProfileOverride,
  }) : super(key: key);

  @override
  State<AssetScreen> createState() => AssetScreenState();
}

class AssetScreenState extends State<AssetScreen> {

  List<Asset> _assets = [];
  bool _loading = true;
  bool _unlocked = true; // 未加密时默认已解锁
  bool _hasPin = false; // 是否启用了加密访问
  String _typeFilter = '全部'; // 全部 | 总资产 | 负资产 | 现金流
  String _signFilter = '全部'; // 全部 | 金额为正 | 金额为负
  bool _hideNumbers = false; // 看板数字是否隐藏（默认显示）
  bool _isVip = false; // 是否拥有 VIP 权益（桑基图等权益功能解锁）

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 不再强制要求进入前设置/输入密码：先加载数据，加密是可选开关
    final hasPin = await AssetStorage.hasPin();
    if (!mounted) return;
    setState(() {
      _hasPin = hasPin;
      _unlocked = !hasPin;
    });
    await _load();
    if (hasPin && mounted) {
      // 已启用加密访问：进入本页需解锁
      await _askUnlock();
      if (!mounted) return;
      await _load();
    }
  }

  Future<void> _load() async {
    final list = await AssetStorage.load();
    if (!mounted) return;
    setState(() {
      _assets = list;
      _loading = false;
    });
    // VIP 权益状态：决定桑基图是否上锁。失败按未解锁处理（保守）。
    _loadVip();
  }

  Future<void> _loadVip() async {
    try {
      final profile = await (widget.loadProfileOverride ?? UserStorage.load)();
      final vip = RewardService.hasVipPrivilege(profile);
      if (mounted && vip != _isVip) setState(() => _isVip = vip);
    } catch (_) {
      // 档案读取失败：保持未解锁，不影响资产主流程
    }
  }

  /// 供外部（首页 FAB）调用的快捷入口
  Future<void> openNewAsset() async {
    final r = await Navigator.push<dynamic>(
      context,
      _slideRoute(const AssetEditScreen()),
    );
    if (r is Asset) {
      _assets.add(r);
      await AssetStorage.save(_assets);
      if (mounted) setState(() {});
      // 首次新增资产奖励灵感
      RewardService.awardFirstAdd(FirstAddKind.asset).then((n) {
        if (n > 0 && mounted) {
          AppToast.show(context, '首次新增资产，+$n 点灵感');
        }
      });
    }
  }

  // ---------- 密码流程 ----------

  Route<dynamic> _slideRoute(Widget page) => AppMotion.slide<dynamic>(page);

  Future<void> _askUnlock() async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PinUnlockDialog(),
    );
    if (!mounted) return;
    setState(() => _unlocked = r == true);
  }

  /// 锁定时点击「解锁」按钮
  Future<void> _unlockManually() async {
    await _askUnlock();
    if (mounted && _unlocked) await _load();
  }

  // ---------- 设置 ----------

  /// 齿轮 → 设置选项卡（底部弹层）
  void _openSettings() {
    AppSheet.show(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // v5.0.3：移除「设置」标题，抽屉直接列出选项
            const SizedBox(height: 14),
            // 加密访问开关（在上方）
            ListTile(
              leading: AppIcon(
                  _hasPin ? AppIcons.lock : AppIcons.unlock,
                  color: AppPalette.c(0xFF3E8E6D)),
              title: const Text('设置加密访问'),
              subtitle: Text(
                  _hasPin
                      ? '已开启：进入资产全景需输入密码'
                      : '未开启：进入资产全景无需密码',
                  style: TextStyle(
                      fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
              trailing: Switch(
                value: _hasPin,
                activeColor: AppPalette.c(0xFF3E8E6D),
                onChanged: (v) {
                  Navigator.pop(ctx);
                  if (v) {
                    _openSetupPin();
                  } else {
                    _openDisablePin();
                  }
                },
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (_hasPin) {
                  _openDisablePin();
                } else {
                  _openSetupPin();
                }
              },
            ),
            // 修改密码：仅开启加密后可用
            ListTile(
              leading: AppIcon(AppIcons.lock,
                  color: _hasPin
                      ? AppPalette.c(0xFF3E8E6D)
                      : AppPalette.c(0xFFC2D4C9)),
              enabled: _hasPin,
              title: Text('修改资产密码',
                  style: TextStyle(
                      color: _hasPin
                          ? AppPalette.c(0xFF24382F)
                          : AppPalette.c(0xFFB2C4BA))),
              subtitle: Text(
                  _hasPin ? '可通过当前密码或密保问题验证' : '开启加密访问后可修改',
                  style: TextStyle(
                      fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
              onTap: _hasPin
                  ? () {
                      Navigator.pop(ctx);
                      _openChangePin();
                    }
                  : null,
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  /// 开启加密访问：3 步向导（设置密码 → 确认密码 → 密保）。
  Future<void> _openSetupPin() async {
    final result = await showPinSetupWizard3(context);
    if (result == null || !mounted) return;
    await AssetStorage.savePin(
      pin: result.pin,
      question: result.question,
      answer: result.answer,
    );
    if (!mounted) return;
    setState(() {
      _hasPin = true;
      _unlocked = true; // 刚设置完密码，本次访问无需再解锁
    });
    AppToast.show(context, '已开启加密访问');
  }

  /// 取消加密访问：需验证当前密码或密保答案
  Future<void> _openDisablePin() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _DisablePinDialog(),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _hasPin = false;
      _unlocked = true;
    });
    AppToast.show(context, '已取消加密访问');
  }

  Future<void> _openChangePin() async {
    // 第 1 步：验证当前密码 / 密保答案
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ChangePinDialog(),
    );
    if (ok != true || !mounted) return;

    // 第 2 步：复用「开启加密访问」同款 3 步向导收集新凭证
    // （设置密码 → 确认密码 → 设置密保），样式与流程完全一致。
    final result = await showPinSetupWizard3(context);
    if (result == null || !mounted) return;

    await AssetStorage.updatePin(
      newPin: result.pin,
      question: result.question,
      answer: result.answer,
    );
    if (mounted) AppToast.show(context, '资产密码已更新');
  }

  // ---------- 筛选 ----------

  bool get _hasFilter => _typeFilter != '全部' || _signFilter != '全部';

  List<Asset> get _filtered {
    return _assets.where((a) {
      bool typeOk = true;
      if (_typeFilter == '总资产') {
        typeOk = a.amount > 0;
      } else if (_typeFilter == '负资产') {
        typeOk = a.amount < 0;
      } else if (_typeFilter == '现金流') {
        typeOk = Asset.cashTypes.contains(a.type);
      } else if (_typeFilter == '理财金') {
        typeOk = _investTypes.contains(a.type);
      }
      bool signOk = true;
      if (_signFilter == '金额为正') signOk = a.amount > 0;
      if (_signFilter == '金额为负') signOk = a.amount < 0;
      return typeOk && signOk;
    }).toList();
  }

  /// 筛选器弹层（顶栏漏斗图标）
  void _openFilterSheet() {
    AppSheet.show(
      context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Widget group(String title, List<String> options,
                String current, ValueChanged<String> onPick) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          color: AppPalette.c(0xFF8FA09A),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.map((o) {
                      final sel = current == o;
                      return GestureDetector(
                        // 再次点击已选中的选项 → 恢复默认「全部」
                        onTap: () => setSheetState(
                            () => onPick(current == o ? '全部' : o)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppPalette.c(0xFF3E8E6D)
                                : AppPalette.c(0xFFF5FAF7),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(o,
                              style: TextStyle(
                                fontSize: 13,
                                color: sel
                                    ? Colors.white
                                    : AppPalette.c(0xFF647A70),
                              )),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('筛选',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    group('按资产类型', ['全部', '总资产', '负资产', '现金流', '理财金'],
                        _typeFilter, (v) => _typeFilter = v),
                    group('按资产性质', ['全部', '金额为正', '金额为负'],
                        _signFilter, (v) => _signFilter = v),
                    // v4.9.29：取消不再带底纹描边，双按钮统一收至右下角
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Pressable(
                          enabled: true,
                          child: TextButton(
                            onPressed: () {
                              // 取消 → 恢复默认筛选（全部）
                              _typeFilter = '全部';
                              _signFilter = '全部';
                              Navigator.pop(ctx);
                              setState(() {});
                            },
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // v4.9.30：确定按钮去底纹色块，与取消统一为主/次文字按钮
                        Pressable(
                          enabled: true,
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() {});
                            },
                            child: Text('确定',
                                style: TextStyle(
                                    color: AppPalette.c(0xFF3E8E6D),
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- 统计 ----------

  double get _totalAssets {
    double sum = 0;
    for (final a in _assets) {
      if (a.amount > 0) sum += a.amount;
    }
    return sum;
  }

  double get _totalDebt {
    double sum = 0;
    for (final a in _assets) {
      if (a.amount < 0) sum += a.amount; // 负数
    }
    return sum; // 负值
  }

  double get _netWorth => _totalAssets + _totalDebt;

  double get _cashFlow {
    double sum = 0;
    for (final a in _assets) {
      if (Asset.cashTypes.contains(a.type)) sum += a.amount;
    }
    return sum;
  }

  /// 理财资产 = 基金 + 黄金 + 股票金额之和
  double get _investTotal {
    double sum = 0;
    for (final a in _assets) {
      if (_investTypes.contains(a.type)) sum += a.amount;
    }
    return sum;
  }

  // ---------- 操作 ----------

  Future<void> _openEditor([Asset? asset]) async {
    // 点击会立刻 push 新页面，原页面的 PointerUp 多半收不到，
    // 卡片会永久停在按压缩放态。跳转前主动复位。
    _resetPressStates();
    final r = await Navigator.push<dynamic>(
      context,
      _slideRoute(AssetEditScreen(asset: asset)),
    );
    _resetPressStates();
    if (r == 'deleted') {
      // 编辑页右上角删除
      _assets.removeWhere((e) => e.id == asset!.id);
      await AssetStorage.save(_assets);
      if (mounted) setState(() {});
      return;
    }
    if (r is Asset) {
      // 编辑/新增保存
      await AssetStorage.save(_assets);
      if (mounted) setState(() {});
      // 仅新增（非编辑）发首次奖励
      if (asset == null) {
        RewardService.awardFirstAdd(FirstAddKind.asset).then((n) {
          if (n > 0 && mounted) {
            AppToast.show(context, '首次新增资产，+$n 点灵感');
          }
        });
      }
    }
  }

  // ---------- 拖拽排序 ----------

  /// 当前被手指压住、正等待「原地松手 / 拖走」判定的卡片
  String? _pendingId;

  /// 每张资产卡片各自的按压句柄（按资产 id 缓存，用于页面跳转时统一复位）。
  /// 必须在 build 之外创建并复用：若在 itemBuilder 里每次现建，
  /// 列表任何一次重建都会让正在跑动画的句柄失去引用。
  final Map<String, PressableHandle> _pressHandles = {};

  /// 长按按住的那一刻：先只做视觉提示，不立刻弹菜单。
  /// 之后的走向由松手时的位移决定（见 [_CardShell]）：
  /// · 原地松手 → 弹出编辑/删除菜单（等价于原来的长按菜单）；
  /// · 拖走 → 进入排序，不弹菜单。
  void _onCardHold(Asset a) {
    Haptics.mediumNow();
    setState(() => _pendingId = a.id);
  }

  void _onCardRelease(Asset a, {required bool moved}) {
    if (_pendingId != a.id) return;
    setState(() => _pendingId = null);
    if (!moved) _showCardMenu(a);
  }

  /// 让所有卡片立刻回到 100%（用于页面跳转、返回本页等场景）。
  ///
  /// 这些场景不会走 PointerUp，卡片会卡在按压缩放态；
  /// 更糟的是该实例的 `_down` 一直为 true，导致这一页后续的按压不再有动画。
  void _resetPressStates() {
    for (final h in _pressHandles.values) {
      h.reset();
    }
  }

  /// 拖拽时浮起的卡片：轻度放大 + 投影，避免和底下让位的卡片混在一起
  /// 拖拽时浮起的卡片：轻微放大 + 紧凑投影，避免和底下让位的卡片混在一起。
  ///
  /// 注意阴影不能用大面积的彩色软晕（elevation 大 + 高透明度彩色）：
  /// 浅色背景上会形成一个宽大的圆角「光晕框」，叠加正在位移的邻卡后，
  /// 视觉上像「一张卡片嵌套着另一张卡片」（bug 反馈截图的来源）。
  /// 这里改用范围克制的深色投影，让浮层明确读作「就是那张卡被拿起来了」。
  Widget _buildDragProxy(Widget child, int index, Animation<double> animation) {
    // 列表项 = Padding(间距) + 卡片本体。投影必须只包卡片本体：
    // 若连同透明间距一起投影，会透出一块灰色「背板」，
    // 叠在位移中的邻卡上就像「一张卡嵌着另一张卡」。
    // 注意：间距不能再重复包一层——proxy 的高度由框架按列表项实测给定，
    // 再加一层 Padding 会把卡片压矮（内部 Column 溢出、内容变形）。
    final inner = child is Padding ? child.child! : child;
    return Material(
      color: Colors.transparent,
      child: AnimatedBuilder(
        animation: animation,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // 不加描边：仅靠少量阴影给出「浮起」层次，
            // 避免深色边框在浅色背景上被读成「黑框」
            boxShadow: const [
              // 长按拖动时的阴影：大幅减淡，只保留一丝下阴影
              // （原来 0x1A + blur6 在拖动中像「深色背板」，喧宾夺主）
              BoxShadow(
                color: Color(0x0A24382F),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: inner,
        ),
        builder: (context, boxed) {
          // 拿起瞬间随过渡动画等比缩小到 96%：
          // 只有一个缩放源、中心对齐，卡片和图标一起等比变小，
          // 不再出现「下方往上收」的形变。
          final t =
              Curves.easeOut.transform(animation.value.clamp(0.0, 1.0));
          return Transform.scale(
            scale: 1.0 - 0.04 * t,
            alignment: Alignment.center,
            child: boxed,
          );
        },
      ),
    );
  }

  /// ReorderableListView 回调：下标以「含看板」的完整列表为准（看板固定在第 0 位）。
  /// 这里把列表下标换算成业务列表下标，再落到 _assets 的真实位置，
  /// 因此即使正处于筛选状态，拖拽也只会在可见卡片所在的真实位置之间移动。
  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex == 0) return; // 看板本身不参与排序
    // 看板固定在第 0 项，不能把卡片拖到看板之前（newIndex==0）。
    // newIndex==1 表示「放到第一张卡片的位置」，是合法的置顶操作，必须放行。
    if (newIndex < 1) return; // 只拦截拖到看板之前；<=1 会误杀置顶，已修复

    final list = _filtered;
    final from = oldIndex - 1;
    // Flutter 的约定：newIndex 是「移除前」的目标下标，向下移动时需要减 1
    var to = newIndex - 1;
    if (to > from) to -= 1;
    if (from < 0 || from >= list.length) return;
    to = to.clamp(0, list.length - 1);
    if (to == from) return;

    // 在可见列表里换位，再把结果按顺序回写到 _assets 中这些卡片原本占据的下标
    final moved = list.removeAt(from);
    list.insert(to, moved);

    final visibleIds = list.map((e) => e.id).toSet();
    final slots = <int>[];
    for (var i = 0; i < _assets.length; i++) {
      if (visibleIds.contains(_assets[i].id)) slots.add(i);
    }
    for (var i = 0; i < slots.length; i++) {
      _assets[slots[i]] = list[i];
    }

    Haptics.mediumNow(); // 落位震动：拖拽结束给出「已放好」的确认感
    setState(() {});
    // 落盘：把排序结果写回 assets.json（不 await，避免阻塞拖拽收尾）
    AssetStorage.saveOrder(List<Asset>.from(_assets));
  }

  /// 长按（500ms 系统默认）弹出编辑/删除选框
  void _showCardMenu(Asset a) {
    Haptics.mediumNow(); // 长按菜单：同步触发，避免异步等待导致振动被丢弃
    AppSheet.show(
      context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            ListTile(
              leading: AppIcon(AppIcons.edit, color: AppPalette.c(0xFF3E8E6D)),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _openEditor(a);
              },
            ),
            ListTile(
              leading: const AppIcon(AppIcons.delete, color: Color(0xFFCB5C50)),
              title: const Text('删除',
                  style: TextStyle(color: Color(0xFFCB5C50))),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    title: const Text('删除这张资产卡片?'),
                    content: const Text('删除后可在「回收站」保留 7 天'),
                    actions: [
                      Pressable(
                        enabled: true,
                        child: TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消')),
                      ),
                      Pressable(
                        enabled: true,
                        child: TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('删除',
                                style: TextStyle(color: Color(0xFFCB5C50)))),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  _assets.removeWhere((e) => e.id == a.id);
                  await AssetStorage.save(_assets);
                  await TrashStorage.addAsset(a);
                  if (mounted) setState(() {});
                }
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return Column(
      children: [
        // 顶栏：与物资清单同款
        Container(
          height: 48,
          color: AppPalette.c(0xB33E8E6D),
          child: Row(
            children: [
              IconButton(
                icon: const AppIcon(AppIcons.menu, color: Colors.white),
                onPressed: widget.onOpenMenu,
              ),
              // v4.9.50：四主页顶栏标题字号统一为 15，与日记/物品/事件页一致，
              // 视觉上与 24 号菜单图标对齐。
              const Expanded(
                child: Text('资产',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
              IconButton(
                icon: AppIcon(AppIcons.filter,
                    color: _hasFilter ? const Color(0xFFFFD666) : Colors.white),
                tooltip: '筛选',
                onPressed: _unlocked ? _openFilterSheet : null,
              ),
              IconButton(
                // 设置图标与侧边栏「设置」同款细线图标（AppIcons.settings）
                icon: const AppIcon(AppIcons.settings,
                    size: 22, color: Colors.white),
                tooltip: '设置',
                onPressed: _openSettings, // 锁定时也可进入，用于解锁后的设置调整
              ),
            ],
          ),
        ),
        Expanded(
          child: !_unlocked
              ? _buildLocked()
              : _loading
                  ? const ListSkeleton()
                  : RefreshIndicator(
                      color: AppPalette.c(0xFF3E8E6D),
                      onRefresh: _load,
                      child: _filtered.isEmpty
                          ? ListView(
                              // 空态也要可滚动，否则无法下拉刷新
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                              children: [
                                // v5.0.3：空状态也保留数据看板，数值显示 0
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: _buildOverview(),
                                ),
                                EmptyState(
                                  icon: '💰',
                                  title: _hasFilter
                                      ? '没有符合条件的资产卡片'
                                      : '还没有资产卡片',
                                  subtitle: _hasFilter
                                      ? '试试调整筛选条件'
                                      : '点右下角 + 添加第一笔',
                                ),
                              ],
                            )
                          : ReorderableListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                              // 去掉右侧默认拖拽把手：本页改用「长按卡片任意处」拖拽
                              buildDefaultDragHandles: false,
                              // 拖拽时卡片浮起 + 轻微放大，给出「拿起来了」的明确反馈
                              proxyDecorator: _buildDragProxy,
                              itemCount: _filtered.length + 1,
                              onReorder: _onReorder,
                              // 句柄只建一次并按 key 缓存：
                              // 若在 itemBuilder 里现建，任何一次重建（含滑动
                              // 看板引起的重排）都会让旧句柄丢失，按压动画卡死
                              itemBuilder: (context, i) {
                                if (i == 0) {
                                  // 第 0 项是数据看板。
                                  // 必须自带 key：看板内部（饼图卡）可能会改变自身高度，
                                  // 若让 ReorderableListView 自动包一层 KeyedSubtree，
                                  // 高度一变父级就重建、key 重算，会触发
                                  // 「Every item of ReorderableListView must have a key」。
                                  return Padding(
                                    key: const ValueKey('__overview__'),
                                    // 底部留出与资产卡片一致的间距（列表卡间距 10 + 额外呼吸感）：
                                    // 叠在下面的第二张卡还有 16~32px 的错位，
                                    // 间距太小会让「露边」和下方卡片挤在一起
                                    padding:
                                        const EdgeInsets.only(bottom: 18),
                                    child: _buildOverview(),
                                  );
                                }
                                final a = _filtered[i - 1];
                                // key 必须挂在 ListView 的直接子项上。
                                // 长按语义由 _CardShell 统一裁决：按住 → 松手判定菜单/排序
                                final handle = _pressHandles.putIfAbsent(
                                    a.id, () => PressableHandle());
                                // 卡片间距放在列表项外层（而非卡片内部 margin）：
                                // 拖拽浮层的投影要紧贴卡片本体，透明的 margin
                                // 区域会让阴影透出来形成一块灰色「背板」
                                return Padding(
                                  key: ValueKey('asset-${a.id}'),
                                  padding:
                                      const EdgeInsets.only(bottom: 10),
                                  child: _CardShell(
                                    index: i,
                                    pressHandle: handle,
                                    onHold: () => _onCardHold(a),
                                    onRelease: (moved) =>
                                        _onCardRelease(a, moved: moved),
                                    builder: (held, moved) => _buildCard(a,
                                        held: held,
                                        moved: moved,
                                        pressHandle: handle),
                                  ),
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }

  /// 已开启加密访问但尚未解锁
  Widget _buildLocked() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.lock, size: 44, color: AppPalette.c(0xFFC2D4C9)),
          const SizedBox(height: 12),
          Text('资产全景已加密',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.c(0xFF24382F))),
          const SizedBox(height: 6),
          Text('输入密码后查看',
              style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
          const SizedBox(height: 16),
          Pressable(
            enabled: true,
            child: ElevatedButton(
              onPressed: _unlockManually,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('解锁'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 总览卡片 ----------

  Widget _buildOverview() {
    final slices = buildSlices(_assets);
    final sankey = buildSankeyData(_assets);
    return OverviewStack(
      hasSecond: slices.isNotEmpty,
      // 净资产为负时桑基图不自洽（带宽无法守恒），此时不挂载第三张卡
      hasThird: sankey.isValid,
      card1: _buildNetWorthCard(),
      card2: AssetPieCard(
        slices: slices,
        hideNumbers: _hideNumbers,
        money: _money,
        onTapType: (type) {
          // 点图例 = 按该类型筛列表
          setState(() => _typeFilter = type);
        },
      ),
      card3: AssetSankeyCard(
        data: sankey,
        money: _money,
        unlocked: _isVip,
      ),
    );
  }

  Widget _buildNetWorthCard() {
    final net = _netWorth;
    return Container(
      // v5.0.13：数据排版不变，整体上下左右居中——上下 padding 相等、
      // 左右 padding 相等；内容块用 center 在拉伸后的卡片里垂直居中，
      // 多余高度平均分到上下两侧，不再堆顶。
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 21),
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F24382F),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // v5.0.13：整体上下居中，上下边距相等。卡片被拉伸到轮盘高度后，
        // 多出的高度平均分到上下两侧（不再是 spaceBetween 分到各段之间）。
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 左：净资产　右：可使用 x 天 —— 两栏同版式（同一行内左标题右数字）。
          //
          // 刻意不用 IntrinsicHeight：里面的数字行用了 baseline 对齐，
          // 而 IntrinsicHeight 要求能算出子树的固有高度，baseline 对齐的
          // Row 不支持固有高度计算，会直接抛断言。两栏高度由内容自然撑开，
          // 数字行统一 32px 字号 + 固定行高，天然等高，不需要额外约束。
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildNetWorthBlock(net)),
              const SizedBox(width: 12),
              Expanded(child: _buildUsableDaysBlock()),
            ],
          ),
          // 14 → 20：这一行整体下移，同时把它与结构条之间的 12 收到 8，
          // 让「下移」不是靠撑大底部空白实现的 —— 内容往下走，底部留白
          // 反而变小，视觉上上下才平衡。
          const SizedBox(height: 20),
          Row(
            children: [
              _statItem('总资产', _totalAssets, AppPalette.c(0xFF24382F)),
              // 负资产红：#CB5C50 主题深红（与预览卡片负金额红一致）
              _statItem('负资产', _totalDebt, const Color(0xFFCB5C50)),
              _statItem('现金流', _cashFlow, AppPalette.c(0xFF24382F)),
              _statItem('理财资产', _investTotal, AppPalette.c(0xFF24382F)),
            ],
          ),
          // 正/负资产结构条（绿=正资产，红=负资产），无文字标注
          const SizedBox(height: 8),
          _buildStructureBar(),
        ],
      ),
    );
  }

  /// 标题行统一高度（18px）。
  ///
  /// 13px 文字的实际行盒约 18px，之前锁 16px 会让文字溢出、压到下方数字上。
  /// 18px 既容得下行盒，又让左右两栏高度严格一致 —— 两栏标题后面挂的
  /// 图标高度不同（15px 眼睛 / 16px 圈叹号），不锁高会差 3px，数字就错行。
  static const double _kCardTitleRowHeight = 18;

  /// 让图标跟旁边的标题文字做基线参照对齐。
  ///
  /// baseline Row 的每个子节点都要在 alphabetic 基线上有位置，但图标
  /// 本身没有基线 —— 直接用会报错。这里包一层 `Baseline(alphabetic)`，
  /// 把「图标盒子顶部」钉在文字基线上方 [baseline] px 处。
  ///
  /// 为什么不用 center：中文字体的行盒比字形高得多（13px 字号的行盒
  /// 约 18px，字形只有 13px 左右），center 会把图标放到行盒中心，
  /// 而人眼看到的是字形中心偏下，结果就是图标位置不对。
  ///
  /// [baseline] 越大图标越靠下、越小越靠上（1:1 位移）。像素标定下
  /// 15px 的小眼睛取 18，圆心才与 13px 中文字形中心齐平。
  /// 注意：只有自身能提供 alphabetic 基线的 child 才响应这个定位；
  /// 右栏圈叹号外包了 SizedBox + OverflowBox，需改用 Transform 平移。
  Widget _baselineIcon(Widget icon, {double baseline = 13}) {
    return Baseline(
      baseline: baseline,
      baselineType: TextBaseline.alphabetic,
      child: icon,
    );
  }

  /// 左栏：净资产。
  ///
  /// 第一行「净资产」+ 眼睛，第二行金额 —— 两栏的标题在同一行、
  /// 数字在下一行，左右对齐。
  Widget _buildNetWorthBlock(double net) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题行高固定 18px 让两栏第二行数字齐平，但行内用 baseline 对齐：
        // 图标以「文字字形底」为基准，不随字体行的上下面留白浮动 ——
        // 中文字体的行盒比字形高不少，center 对齐在真机上图标会偏上。
        SizedBox(
          height: _kCardTitleRowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('净资产',
                  style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF647A70))),
              const SizedBox(width: 4),
              // 隐藏/显示看板数字（默认显示）
              GestureDetector(
                onTap: () {
                  // 小眼睛：同步触发中震动，切换金额可见性给予明确触感
                  Haptics.mediumNow();
                  setState(() => _hideNumbers = !_hideNumbers);
                },
                behavior: HitTestBehavior.opaque,
                child: _baselineIcon(
                  // 像素标定：15px 眼睛取 baseline 18 时，圆心与 13px
                  // 中文字形中心落在同一 y（Baseline 定位按 1:1 下移）。
                  AppIcon(
                    _hideNumbers
                        ? AppIcons.eyeOff
                        : AppIcons.eyeOn,
                    size: 15,
                    color: AppPalette.c(0xFF8FA09A),
                  ),
                  baseline: 18,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            _hideNumbers ? '****' : _money(net),
            maxLines: 1,
            style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppPalette.c(0xFF24382F),
                height: 1.15),
          ),
        ),
      ],
    );
  }

  /// 右栏：可使用 x 天。
  ///
  /// 第一行「可使用」+ 圈叹号，第二行「x 天」—— 与左栏同结构，
  /// 两栏标题齐平、数字齐平。
  /// 计算口径见 [UsableDays]；总资产未手填时自动取当前净资产。
  Widget _buildUsableDaysBlock() {
    final days = UsableDays.compute(
      total: AppSettings.resolveTotal(netWorthFallback: _netWorth),
      monthlyCost: AppSettings.usableMonthlyCost,
      daysPerMonth: AppSettings.usableDaysPerMonth,
      annualRate: AppSettings.annualRate,
      inflationRate: AppSettings.inflationRate,
    );
    final hasValue = days != null && days > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 与左栏一致：锁 18px 高 + baseline 对齐图标，两栏数字才能齐平
        SizedBox(
          height: _kCardTitleRowHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('可使用',
                  style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF647A70))),
              const SizedBox(width: 2),
              // 圈叹号：进入参数设置。始终显示，否则算不出数时用户
              // 找不到入口，只会看到一块空白。
              //
              // 点触区 36×36、视觉圆点 12px。外面套 18px 的 SizedBox +
              // OverflowBox，把大点触区溢出出去，不撑高标题行。
              // 圈叹号：像素标定下比标题字形中心低 2px，显式上移对齐。
              // 它外层是 SizedBox + OverflowBox，没有 alphabetic 基线，
              // Baseline 定位对这类 child 不生效，所以用视觉平移
              // （不改行高，点触区也跟着一起移）。
              Transform.translate(
                offset: const Offset(0, -2),
                child: _baselineIcon(
                SizedBox(
                  width: 18,
                  height: 18,
                  child: OverflowBox(
                    maxWidth: 36,
                    maxHeight: 36,
                    child: GestureDetector(
                      key: const ValueKey('usable-days-settings'),
                      onTap: () async {
                        Haptics.lightNow();
                        final changed = await UsableDaysSettingsSheet.show(
                          context,
                          netWorth: _netWorth,
                        );
                        if (changed == true && mounted) setState(() {});
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 36,
                        height: 36,
                        color: Colors.transparent,
                        alignment: Alignment.center,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppPalette.c(0xFF8FA09A), width: 1),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '!',
                            style: TextStyle(
                              fontSize: 8,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.c(0xFF8FA09A),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                  baseline: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: hasValue
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      _hideNumbers ? '****' : UsableDays.format(days),
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.c(0xFF24382F),
                          height: 1.15),
                    ),
                    if (!_hideNumbers)
                      Padding(
                        padding: EdgeInsets.only(left: 2),
                        child: Text(
                          '天',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.c(0xFF647A70),
                          ),
                        ),
                      ),
                  ],
                )
              // 算不出来时留一个占位，两栏数字行仍然齐平
              : Text(
                  '—',
                  style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.c(0xFFC2CFC8),
                      height: 1.15),
                ),
        ),
      ],
    );
  }

  /// 数据看板下方的资产性质结构条：绿=正资产、红=负资产，按金额占比分配宽度。
  /// 无论是否有数据都会绘制（无数据时显示一条半透明中性底），保证入口位置稳定。
  Widget _buildStructureBar() {
    final pos = _totalAssets.abs();
    final neg = _totalDebt.abs();
    final total = pos + neg;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        key: const ValueKey('asset-structure-bar'),
        height: 7,
        width: double.infinity,
        child: total <= 0
            ? const ColoredBox(color: Color(0x140F2E1F))
            : Row(
                children: [
                  if (pos > 0)
                    Expanded(
                      flex: (pos / total * 1000).round().clamp(1, 999),
                      child: ColoredBox(color: AppPalette.c(0xFF3E8E6D)),
                    ),
                  if (neg > 0)
                    Expanded(
                      flex: (neg / total * 1000).round().clamp(1, 999),
                      child: const ColoredBox(color: Color(0xFFCB5C50)),
                    ),
                ],
              ),
      ),
    );
  }

  /// 金额格式化（负数前导 -）
  String _money(double v) {
    if (_hideNumbers) return '****';
    if (v < 0) {
      final a = -v;
      return '-¥${a.toStringAsFixed(a.truncateToDouble() == a ? 0 : 2)}';
    }
    return '¥${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2)}';
  }

  Widget _statItem(String label, double value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: AppPalette.c(0xFF8FA09A)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            _money(value),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------- 资产卡片 ----------

  /// 理财类资产：理财 / 黄金 / 股票
  static const List<String> _investTypes = ['基金', '黄金', '股票'];

  /// 资产卡片本体。长按语义由外层 [_CardShell] 提供（按住 → 松手判定）。
  Widget _buildCard(Asset a,
      {bool held = false, bool moved = false, required PressableHandle pressHandle}) {
    final negative = a.amount < 0;
    final invest = _investTypes.contains(a.type);
    // 左侧色条代表资产性质：负资产红 / 理财蓝 / 其它绿
    final barColor = negative
        ? const Color(0xFFCB5C50)
        : (invest ? const Color(0xFF3E7BD6) : AppPalette.c(0xFF3E8E6D));
    return GestureDetector(
      onTap: () => _openEditor(a),
      child: Pressable(
        external: true,
        handle: pressHandle,
        child: Stack(
          children: [
            Opacity(opacity: held ? 0.55 : 1, child: _cardBody(a, barColor)),
            // 按住时的提示层：告诉用户「松手是菜单、拖动是排序」
            if (held && !moved) _holdHint(),
          ],
        ),
      ),
    );
  }

  /// 长按按住时的浮层提示
  Widget _holdHint() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: AppPalette.c(0x1A3E8E6D),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(8),
              right: Radius.circular(16),
            ),
          ),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppPalette.c(0xE63E8E6D),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('拖动排序 · 松手取消',
                style: TextStyle(fontSize: 13, color: Colors.white)),
          ),
        ),
      ),
    );
  }

  /// 卡片主体（左侧色条 + 白卡）
  Widget _cardBody(Asset a, Color barColor) {
    final negative = a.amount < 0;
    return ClipRRect(
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(8),
            right: Radius.circular(16),
          ),
          child: Container(
            color: barColor,
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              color: AppPalette.c(0xFFFFFFFF),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                children: [
            // 图标（无底纹：直接摆放 emoji，与整体浅色调更统一）
            // v5.0.11：预览卡片图标放大（46→56 容器 / 24→34 图标）
            SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: EntryIcon(a.icon, size: 34),
              ),
            ),
            const SizedBox(width: 12),
            // 备注（主信息）+ 类型（副信息）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.note.isEmpty ? a.type : a.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.c(0xFF24382F))),
                  if (a.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(a.type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
                  ],
                ],
              ),
            ),
            // 金额（隐藏状态：统一为 ¥****；负资产红，其余黑色）
                Text(
                  _hideNumbers
                      ? '¥****'
                      : (negative
                          ? '-¥${(-a.amount).toStringAsFixed((-a.amount).truncateToDouble() == -a.amount ? 0 : 2)}'
                          : '¥${a.amount.toStringAsFixed(a.amount.truncateToDouble() == a.amount ? 0 : 2)}'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: negative
                        ? const Color(0xFFCB5C50)
                        : AppPalette.c(0xFF24382F),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

/// 一张可「长按拖拽排序」的资产卡片外壳。
///
/// 为什么要自己判定，而不直接把 onLongPress + 拖拽监听器叠在一起：
/// 卡片上的 [GestureDetector.onLongPress] 会先赢下手势竞技场，
/// 导致列表的延迟拖拽永远拿不到手势（实测拖拽完全不启动）。
/// 因此这里只保留拖拽监听器，用「按住后的位移」自己区分两种意图：
/// · 按住 500ms 后原地松手（位移 < 8px）→ 视为长按菜单；
/// · 按住后发生位移 → 视为拖拽排序，交还给 ReorderableListView。
class _CardShell extends StatefulWidget {
  final int index;
  final VoidCallback onHold;
  final ValueChanged<bool> onRelease;
  final Widget Function(bool held, bool moved) builder;
  /// 按压回弹的驱动句柄（卡片本体已有指针监听，故由这里代驱动）
  final PressableHandle pressHandle;

  const _CardShell({
    Key? key,
    required this.index,
    required this.onHold,
    required this.onRelease,
    required this.builder,
    required this.pressHandle,
  }) : super(key: key);

  @override
  State<_CardShell> createState() => _CardShellState();
}

class _CardShellState extends State<_CardShell> {
  /// 按住起点；非空表示正处于「已按下、等待松手判定」状态
  Offset? _downAt;

  /// 是否已越过 [_slop]（拖动 / 点击判定用）
  bool _moved = false;

  /// 长按提示是否已触发过（每轮按压只触发一次）
  bool _fired = false;

  /// 按住提示（半透明 + 「拖动排序·松手取消」）是否正在显示。
  ///
  /// 必须放在本 State 而不是父级的 `_pendingId`：
  /// 拖拽浮层是同一份 widget 在 Overlay 里的新实例，若提示由父级状态驱动，
  /// 浮层会带着「半透明 + 提示层」的快照飞起来，观感像卡片变形。
  /// 放在这里，浮层实例的 `_hinting` 初始就是 false，永远是干净的完整卡片。
  bool _hinting = false;

  /// 判定为「拖动」的最小位移（逻辑像素）
  static const double _slop = 8;

  void _onDown(PointerDownEvent e) {
    _downAt = e.position;
    _moved = false;
    _fired = false;
    // 按下即缩到 90%，并保持到这个手指抬起
    widget.pressHandle.press();
  }

  @override
  void dispose() {
    // 兜底：页面被 push 覆盖/销毁时收不到 PointerUp，
    // 必须主动释放，否则卡片会永久停在 90%，且该实例 _down 卡死
    // 会让这一页后续的按压全部失效。
    if (_downAt != null) widget.pressHandle.reset();
    super.dispose();
  }

  void _onMove(PointerMoveEvent e) {
    final start = _downAt;
    if (start == null) return;
    if (!_moved && (e.position - start).distance > _slop) {
      _moved = true;
      if (mounted) setState(() => _hinting = false);
    }
  }

  void _onUp(PointerUpEvent e) {
    final start = _downAt;
    _downAt = null;
    // 先释放：让弹簧动画立即起跑。
    // 之后 onRelease 可能弹菜单 / setState 重建卡片，那时再释放会更晚，
    // 卡片会先保持 90% 一段时间才开始回弹。
    _settle();
    if (start == null) return;
    widget.onRelease(_moved);
    if (mounted) setState(() => _moved = false);
  }

  void _onCancel(PointerCancelEvent e) {
    _downAt = null;
    _settle();
    if (mounted) setState(() => _moved = false);
  }

  /// 松手统一出口：从 90% 走弹簧动画回到 100%
  void _settle() {
    widget.pressHandle.release();
    if (mounted) setState(() => _hinting = false);
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return ReorderableDelayedDragStartListener(
      index: widget.index,
      child: Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        // 延迟拖拽在 500ms 后触发，与 Listener 的按压周期一致
        child: _HoldDetector(
          onHold: () {
            if (_fired) return;
            _fired = true;
            setState(() => _hinting = true);
            widget.onHold();
          },
          child: widget.builder(_hinting, _moved),
        ),
      ),
    );
  }
}

/// 指针按住 500ms 后回调一次 [onHold]（与延迟拖拽的阈值保持一致）
class _HoldDetector extends StatefulWidget {
  final VoidCallback onHold;
  final Widget child;

  const _HoldDetector({required this.onHold, required this.child});

  @override
  State<_HoldDetector> createState() => _HoldDetectorState();
}

class _HoldDetectorState extends State<_HoldDetector> {
  Timer? _timer;

  void _start() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), widget.onHold);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: widget.child,
    );
  }
}

// ==================== 解锁弹窗 ====================

class _PinUnlockDialog extends StatefulWidget {
  const _PinUnlockDialog({Key? key}) : super(key: key);

  @override
  State<_PinUnlockDialog> createState() => _PinUnlockDialogState();
}

class _PinUnlockDialogState extends State<_PinUnlockDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _forgot = false;
  late Future<String> _question;

  @override
  void initState() {
    super.initState();
    _question = AssetStorage.getQuestion();
  }

  Future<void> _submit() async {
    final pin = _ctrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    final ok = await AssetStorage.verifyPin(pin);
    if (ok) {
      if (mounted) Navigator.pop(context, true);
    } else {
      setState(() => _error = '密码不正确');
    }
  }

  Future<void> _resetByAnswer() async {
    final ans = _ctrl.text.trim();
    if (ans.isEmpty) return;
    final ok = await AssetStorage.verifyAnswer(ans);
    if (!ok) {
      setState(() => _error = '密保答案不正确');
      return;
    }
    // 弹出重置密码
    if (!mounted) return;
    final newPin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) {
        final p1 = TextEditingController();
        final p2 = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('重置密码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: p1,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '新密码（至少 4 位）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: p2,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: '再输入一遍'),
              ),
            ],
          ),
          actions: [
            Pressable(
              enabled: true,
              child: TextButton(
                onPressed: () async {
                  if (p1.text.trim().length >= 4 &&
                      p1.text.trim() == p2.text.trim()) {
                    await AssetStorage.resetPin(p1.text.trim());
                    Navigator.pop(c, p1.text.trim());
                  }
                },
                child: const Text('重置'),
              ),
            ),
          ],
        );
      },
    );
    if (newPin != null && mounted) {
      AppToast.show(context, '密码已重置，请使用新密码进入');
      setState(() {
        _forgot = false;
        _error = null;
        _ctrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return WillPopScope(
      // 侧滑 / 返回键一次即取消，回笔记主页
      onWillPop: () async {
        Navigator.pop(context, false);
        return false;
      },
      child: AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_forgot ? '回答密保问题' : '输入资产密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_forgot) ...[
              TextField(
                controller: _ctrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '密码',
                  errorText: _error,
                  errorStyle: const TextStyle(color: Color(0xFFCB5C50)),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const AppIcon(AppIcons.warn,
                        size: 16, color: Color(0xFFCB5C50)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFCB5C50),
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: Pressable(
                  enabled: true,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _forgot = true;
                      _error = null;
                      _ctrl.clear();
                    }),
                    child: const Text('忘记密码？',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ] else ...[
              FutureBuilder<String>(
                future: _question,
                builder: (c, snap) => Text(
                  snap.data ?? '',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '密保答案',
                  errorText: _error,
                  errorStyle: const TextStyle(color: Color(0xFFCB5C50)),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _resetByAnswer(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const AppIcon(AppIcons.warn,
                        size: 16, color: Color(0xFFCB5C50)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFCB5C50),
                              fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerLeft,
                child: Pressable(
                  enabled: true,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _forgot = false;
                      _error = null;
                      _ctrl.clear();
                    }),
                    child: const Text('返回输入密码',
                        style: TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('取消',
                  style: TextStyle(color: AppPalette.c(0xFF7C8F86))),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _forgot ? _resetByAnswer : _submit,
              child: Text('确认',
                  style: TextStyle(color: AppPalette.c(0xFF3E8E6D))),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 取消加密访问（验证身份）弹窗 ====================

class _DisablePinDialog extends StatefulWidget {
  const _DisablePinDialog({Key? key}) : super(key: key);

  @override
  State<_DisablePinDialog> createState() => _DisablePinDialogState();
}

class _DisablePinDialogState extends State<_DisablePinDialog> {
  /// 'pin' = 验证当前密码；'answer' = 验证密保答案
  String _mode = 'pin';
  final _vCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  late final Future<String> _question = AssetStorage.getQuestion();

  @override
  void dispose() {
    _vCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final v = _vCtrl.text.trim();
    if (v.isEmpty) {
      setState(() => _error = _mode == 'pin' ? '请输入当前密码' : '请输入密保答案');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = _mode == 'pin'
        ? await AssetStorage.verifyPin(v)
        : await AssetStorage.verifyAnswer(v);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = _mode == 'pin' ? '当前密码不正确' : '密保答案不正确';
      });
      return;
    }
    await AssetStorage.clearPin();
    if (mounted) Navigator.pop(context, true);
  }

  Widget _modeChip(String value, String label) {
    final sel = _mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _mode = value;
          _error = null;
          _vCtrl.clear();
        }),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? AppPalette.c(0xFF3E8E6D) : AppPalette.c(0xFFF5FAF7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel ? Colors.white : AppPalette.c(0xFF647A70))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return WillPopScope(
      onWillPop: () async => !_busy,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('取消加密访问'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('验证身份后，资产全景将不再需要密码即可进入',
                  style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
              const SizedBox(height: 14),
              Row(
                children: [
                  _modeChip('pin', '当前密码'),
                  const SizedBox(width: 8),
                  _modeChip('answer', '密保答案'),
                ],
              ),
              const SizedBox(height: 16),
              if (_mode == 'pin')
                TextField(
                  controller: _vCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '当前资产密码',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _confirm(),
                  onChanged: (_) => setState(() => _error = null),
                )
              else ...[
                FutureBuilder<String>(
                  future: _question,
                  builder: (c, snap) => Text(snap.data ?? '',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _vCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '密保答案',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _confirm(),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      const AppIcon(AppIcons.warn,
                          size: 16, color: Color(0xFFCB5C50)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(_error!,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFCB5C50),
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: Text('取消',
                  style: TextStyle(color: AppPalette.c(0xFF7C8F86))),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _busy ? null : _confirm,
              child: const Text('确认取消',
                  style: TextStyle(color: Color(0xFFCB5C50))),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 修改资产密码：身份验证弹窗 ====================
//
// v5.0.4：验证身份后不再在本弹窗里一步填完新密码，而是复用「开启加密访问」
// 同一套通用 3 步向导（pin_setup_wizard.dart：设置密码→确认密码→设置密保），
// 保证修改密码与开启加密访问的样式/流程完全一致。本弹窗只做身份验证。

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog({Key? key}) : super(key: key);

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  /// 'pin' = 验证当前密码；'answer' = 验证密保答案
  String _mode = 'pin';

  final _vCtrl = TextEditingController(); // 当前密码 / 密保答案
  bool _checking = false;
  String? _error;
  late Future<String> _question;

  @override
  void initState() {
    super.initState();
    _question = AssetStorage.getQuestion();
  }

  @override
  void dispose() {
    _vCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final v = _vCtrl.text.trim();
    if (v.isEmpty) {
      setState(() => _error = _mode == 'pin' ? '请输入当前密码' : '请输入密保答案');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = _mode == 'pin'
        ? await AssetStorage.verifyPin(v)
        : await AssetStorage.verifyAnswer(v);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _checking = false;
        _error = _mode == 'pin' ? '当前密码不正确' : '密保答案不正确';
      });
      return;
    }
    // 验证通过：关闭本弹窗，由调用方弹出 3 步向导收集新凭证
    Navigator.pop(context, true);
  }

  Widget _errorBox() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const AppIcon(AppIcons.warn, size: 16, color: Color(0xFFCB5C50)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(_error!,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFCB5C50),
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String value, String label) {
    final sel = _mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _mode = value;
          _error = null;
          _vCtrl.clear();
        }),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? AppPalette.c(0xFF3E8E6D) : AppPalette.c(0xFFF5FAF7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel ? Colors.white : AppPalette.c(0xFF647A70))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return WillPopScope(
      onWillPop: () async => !_checking,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('验证身份'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _modeChip('pin', '当前密码'),
                  const SizedBox(width: 8),
                  _modeChip('answer', '密保答案'),
                ],
              ),
              const SizedBox(height: 16),
              if (_mode == 'pin')
                TextField(
                  controller: _vCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '当前资产密码',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _checking ? null : _verify(),
                  onChanged: (_) => setState(() => _error = null),
                )
              else ...[
                FutureBuilder<String>(
                  future: _question,
                  builder: (c, snap) => Text(
                    snap.data ?? '',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _vCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '密保答案',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _checking ? null : _verify(),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
              _errorBox(),
            ],
          ),
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _checking ? null : () => Navigator.pop(context, false),
              child: Text('取消',
                  style: TextStyle(color: AppPalette.c(0xFF7C8F86))),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _checking ? null : _verify,
              child: Text(_checking ? '验证中…' : '下一步',
                  style: TextStyle(color: AppPalette.c(0xFF3E8E6D))),
            ),
          ),
        ],
      ),
    );
  }
}
