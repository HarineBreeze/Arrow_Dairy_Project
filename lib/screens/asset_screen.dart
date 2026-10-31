import 'dart:async';

import 'package:flutter/material.dart';
import '../models/asset.dart';
import '../services/asset_storage.dart';
import '../services/trash_storage.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_skeleton.dart';
import 'asset_edit_screen.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';

/// 资产全景主页。默认无需密码即可查看；
/// 开启「加密访问」后，进入本页需先输入密码解锁。
/// 返回 true 表示确认完成（供外部回调刷新）。
class AssetScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  /// 用户在密码页点了「取消」时回调，由首页切回笔记主页（保留兼容，正常不再触发）
  final VoidCallback? onCancel;
  const AssetScreen({Key? key, this.onOpenMenu, this.onCancel})
      : super(key: key);

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
    }
  }

  // ---------- 密码流程 ----------

  PageRouteBuilder<dynamic> _slideRoute(Widget page) =>
      PageRouteBuilder<dynamic>(
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: Text('设置',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            // 加密访问开关（在上方）
            ListTile(
              leading: Icon(
                  _hasPin ? Icons.lock : Icons.lock_open,
                  color: const Color(0xFF3B6FE0)),
              title: const Text('设置加密访问'),
              subtitle: Text(
                  _hasPin
                      ? '已开启：进入资产全景需输入密码'
                      : '未开启：进入资产全景无需密码',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9AA8BF))),
              trailing: Switch(
                value: _hasPin,
                activeColor: const Color(0xFF3B6FE0),
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
              leading: Icon(Icons.password,
                  color: _hasPin
                      ? const Color(0xFF3B6FE0)
                      : const Color(0xFFC3CCDA)),
              enabled: _hasPin,
              title: Text('修改资产密码',
                  style: TextStyle(
                      color: _hasPin
                          ? const Color(0xFF2A3B52)
                          : const Color(0xFFB4C0D2))),
              subtitle: Text(
                  _hasPin ? '可通过当前密码或密保问题验证' : '开启加密访问后可修改',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9AA8BF))),
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

  /// 开启加密访问：设置密码（两次）+ 密保问题与答案
  Future<void> _openSetupPin() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PinSetupDialog(),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _hasPin = true;
      _unlocked = true; // 刚设置完密码，本次访问无需再解锁
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已开启加密访问')),
    );
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已取消加密访问')),
    );
  }

  Future<void> _openChangePin() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ChangePinDialog(),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('资产密码已更新')),
      );
    }
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Widget group(String title, List<String> options,
                String current, ValueChanged<String> onPick) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9AA8BF),
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
                                ? const Color(0xFF3B6FE0)
                                : const Color(0xFFF5F7FB),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(o,
                              style: TextStyle(
                                fontSize: 13,
                                color: sel
                                    ? Colors.white
                                    : const Color(0xFF5A6B82),
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
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    group('按资产类型', ['全部', '总资产', '负资产', '现金流', '理财金'],
                        _typeFilter, (v) => _typeFilter = v),
                    group('按资产性质', ['全部', '金额为正', '金额为负'],
                        _signFilter, (v) => _signFilter = v),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: Pressable(
                              enabled: true,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  primary: const Color(0xFF5A6B82),
                                  side: const BorderSide(
                                      color: Color(0xFFD6DCE8)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
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
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: Pressable(
                              enabled: true,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  primary: const Color(0xFF3B6FE0),
                                  onPrimary: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  setState(() {});
                                },
                                child: const Text('确定'),
                              ),
                            ),
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
    final r = await Navigator.push<dynamic>(
      context,
      _slideRoute(AssetEditScreen(asset: asset)),
    );
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
    }
  }

  // ---------- 拖拽排序 ----------

  /// 当前被手指压住、正等待「原地松手 / 拖走」判定的卡片
  String? _pendingId;

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
    final inner = child is Padding ? child.child! : child;
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Transform.scale(
          scale: 1.03,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              // 细描边让浮层在被拖到白色邻卡上方时仍有一条清晰轮廓，
              // 避免两张白卡叠在一起被误读为「嵌套」
              border: Border.all(color: const Color(0x1F2A3B52)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x262A3B52),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: inner,
          ),
        ),
      ),
    );
  }

  /// ReorderableListView 回调：下标以「含看板」的完整列表为准（看板固定在第 0 位）。
  /// 这里把列表下标换算成业务列表下标，再落到 _assets 的真实位置，
  /// 因此即使正处于筛选状态，拖拽也只会在可见卡片所在的真实位置之间移动。
  void _onReorder(int oldIndex, int newIndex) {
    // 看板（第 0 项）不参与排序
    if (oldIndex == 0) return;
    if (newIndex == 0) return; // 不允许拖到看板之前

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
              leading: const Icon(Icons.edit_outlined, color: Color(0xFF3B6FE0)),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                _openEditor(a);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除',
                  style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    title: const Text('删除这张资产卡片?'),
                    content: const Text('删除后可在「回收站」保留 7 天，期间可还原'),
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
                                style: TextStyle(color: Colors.red))),
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
    return Column(
      children: [
        // 顶栏：与物资清单同款
        Container(
          height: 48,
          color: const Color(0xB33B6FE0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: widget.onOpenMenu,
              ),
              const Expanded(
                child: Text('资产全景',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
              IconButton(
                icon: Icon(Icons.filter_list,
                    color: _hasFilter ? const Color(0xFFFFD666) : Colors.white),
                tooltip: '筛选',
                onPressed: _unlocked ? _openFilterSheet : null,
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
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
                      color: const Color(0xFF3B6FE0),
                      onRefresh: _load,
                      child: _filtered.isEmpty
                          ? ListView(
                              // 空态也要可滚动，否则无法下拉刷新
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
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
                              itemBuilder: (context, i) {
                                if (i == 0) {
                                  // 第 0 项是数据看板：key 用非整数的 ValueKey('overview')，
                                  // 它排在全部下标 x.5 之前，因此与排序计算天然不冲突
                                  return Column(
                                    key: const ValueKey('asset-overview'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildOverview(),
                                      const SizedBox(height: 14),
                                    ],
                                  );
                                }
                                final a = _filtered[i - 1];
                                // key 必须挂在 ListView 的直接子项上。
                                // 长按语义由 _CardShell 统一裁决：按住 → 松手判定菜单/排序
                                final handle = PressableHandle();
                                // 卡片间距放在列表项外层（而非卡片内部 margin）：
                                // 拖拽浮层的投影要紧贴卡片本体，透明的 margin
                                // 区域会让阴影透出来形成一块灰色「背板」
                                return Padding(
                                  key: ValueKey('asset-${a.id}'),
                                  padding:
                                      const EdgeInsets.only(bottom: 10),
                                  child: _CardShell(
                                    index: i,
                                    held: _pendingId == a.id,
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
          const Icon(Icons.lock_outline, size: 44, color: Color(0xFFC3CCDA)),
          const SizedBox(height: 12),
          const Text('资产全景已加密',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2A3B52))),
          const SizedBox(height: 6),
          const Text('输入密码后查看',
              style: TextStyle(fontSize: 13, color: Color(0xFF9AA8BF))),
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
    final net = _netWorth;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3B6FE0), Color(0xFF5B8AF0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('净资产',
                  style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(width: 4),
              // 隐藏/显示看板数字（默认显示）
              GestureDetector(
                onTap: () {
                  // 小眼睛：同步触发中震动，切换金额可见性给予明确触感
                  Haptics.mediumNow();
                  setState(() => _hideNumbers = !_hideNumbers);
                },
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    _hideNumbers
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 16,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _hideNumbers ? '****' : _money(net),
            style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statItem('总资产', _totalAssets, Colors.white),
              _statItem('负资产', _totalDebt, const Color(0xFFFFD9DC)),
              _statItem('现金流', _cashFlow, Colors.white),
              _statItem('理财资产', _investTotal, Colors.white),
            ],
          ),
          // 正/负资产结构条（绿=正资产，红=负资产），无文字标注
          // 留白只加在真正出现结构条时，避免无资产时空出 12px
          const SizedBox(height: 12),
          _buildStructureBar(),
        ],
      ),
    );
  }

  /// 数据看板下方的资产性质结构条：绿=正资产、红=负资产，按金额占比分配宽度。
  /// 无论是否有数据都会绘制（无数据时显示一条半透明中性底），保证入口位置稳定。
  Widget _buildStructureBar() {
    final pos = _totalAssets.abs();
    final neg = _totalDebt.abs();
    final total = pos + neg;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        key: const ValueKey('asset-structure-bar'),
        height: 7,
        width: double.infinity,
        child: total <= 0
            ? const ColoredBox(color: Color(0x40FFFFFF))
            : Row(
                children: [
                  if (pos > 0)
                    Expanded(
                      flex: (pos / total * 1000).round().clamp(1, 999),
                      child: const ColoredBox(color: Color(0xFF2A9D5C)),
                    ),
                  if (neg > 0)
                    Expanded(
                      flex: (neg / total * 1000).round().clamp(1, 999),
                      child: const ColoredBox(color: Color(0xFFE0576A)),
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
              style: const TextStyle(fontSize: 11, color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(
            _money(value),
            style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600, color: color),
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
        ? const Color(0xFFE0576A)
        : (invest ? const Color(0xFF3B6FE0) : const Color(0xFF2A9D5C));
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
            color: const Color(0x1A3B6FE0),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(6),
              right: Radius.circular(14),
            ),
          ),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xE63B6FE0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('拖动排序 · 松手取消',
                style: TextStyle(fontSize: 12, color: Colors.white)),
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
            left: Radius.circular(6),
            right: Radius.circular(14),
          ),
          child: Container(
            color: barColor,
            padding: const EdgeInsets.only(left: 4),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                children: [
            // 图标
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(a.icon, style: const TextStyle(fontSize: 24)),
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
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2A3B52))),
                  if (a.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(a.type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF9AA8BF))),
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
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: negative
                        ? const Color(0xFFE06A6A)
                        : const Color(0xFF2A3B52),
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
  final bool held;
  final VoidCallback onHold;
  final ValueChanged<bool> onRelease;
  final Widget Function(bool held, bool moved) builder;
  /// 按压回弹的驱动句柄（卡片本体已有指针监听，故由这里代驱动）
  final PressableHandle pressHandle;

  const _CardShell({
    Key? key,
    required this.index,
    required this.held,
    required this.onHold,
    required this.onRelease,
    required this.builder,
    required this.pressHandle,
  }) : super(key: key);

  @override
  State<_CardShell> createState() => _CardShellState();
}

class _CardShellState extends State<_CardShell> {
  /// 按住起点；非空表示正处于「已长按、等待松手判定」状态
  Offset? _downAt;
  bool _moved = false;
  bool _fired = false;

  /// 判定为「拖动」的最小位移（逻辑像素）
  static const double _slop = 8;

  void _onDown(PointerDownEvent e) {
    _downAt = e.position;
    _moved = false;
    _fired = false;
    widget.pressHandle.press();
  }

  void _onMove(PointerMoveEvent e) {
    final start = _downAt;
    if (start == null) return;
    if (!_moved && (e.position - start).distance > _slop) {
      _moved = true;
      if (mounted) setState(() {});
    }
  }

  void _onUp(PointerUpEvent e) {
    final start = _downAt;
    _downAt = null;
    widget.pressHandle.release();
    if (start == null) return;
    widget.onRelease(_moved);
    if (mounted) setState(() => _moved = false);
  }

  void _onCancel(PointerCancelEvent e) {
    _downAt = null;
    widget.pressHandle.release();
    if (mounted) setState(() => _moved = false);
  }

  @override
  Widget build(BuildContext context) {
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
            widget.onHold();
          },
          child: widget.builder(widget.held, _moved),
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
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: widget.child,
    );
  }
}

// ==================== 首次设置密码弹窗 ====================

class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog({Key? key}) : super(key: key);

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  final _qCtrl = TextEditingController(text: '你的生日是几号？');
  final _aCtrl = TextEditingController();
  bool _saving = false;
  String? _tip; // 确认时未填全的提示

  bool get _valid =>
      _p1.text.trim().length >= 4 &&
      _p1.text.trim() == _p2.text.trim() &&
      _qCtrl.text.trim().isNotEmpty &&
      _aCtrl.text.trim().isNotEmpty;

  /// 逐项检查，返回第一条不满足的提示；全部满足返回 null
  String? get _missing {
    final p1 = _p1.text.trim();
    final p2 = _p2.text.trim();
    if (p1.isEmpty) return '请先设置密码（至少 4 位）';
    if (p1.length < 4) return '密码至少 4 位';
    if (p2.isEmpty) return '请再输入一遍密码';
    if (p1 != p2) return '两次输入的密码不一致';
    if (_qCtrl.text.trim().isEmpty) return '请填写密保问题';
    if (_aCtrl.text.trim().isEmpty) return '请填写密保答案';
    return null;
  }

  Future<void> _submit() async {
    final miss = _missing;
    if (miss != null) {
      setState(() => _tip = miss);
      return;
    }
    setState(() {
      _saving = true;
      _tip = null;
    });
    await AssetStorage.savePin(
      pin: _p1.text.trim(),
      question: _qCtrl.text.trim(),
      answer: _aCtrl.text,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 侧滑 / 返回键一次即取消
      onWillPop: () async {
        Navigator.pop(context, false);
        return false;
      },
      child: AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('开启加密访问'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('开启后，进入资产全景需输入密码；密码仅保存在本机',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9AA8BF))),
              const SizedBox(height: 14),
              TextField(
                controller: _p1,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: '密码（至少 4 位）',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _tip = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _p2,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 12,
                decoration: InputDecoration(
                  labelText: '再输入一遍',
                  counterText: '',
                  border: const OutlineInputBorder(),
                  errorText: (_p2.text.isNotEmpty &&
                          _p2.text.trim() != _p1.text.trim())
                      ? '两次输入不一致'
                      : null,
                ),
                onChanged: (_) => setState(() => _tip = null),
              ),
              const SizedBox(height: 14),
              const Text('密保（忘记密码时用于重置）',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9AA8BF))),
              const SizedBox(height: 8),
              TextField(
                controller: _qCtrl,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '密保问题',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _tip = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _aCtrl,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '密保答案',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _tip = null),
              ),
              if (_tip != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: Color(0xFFD9534F)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_tip!,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFD9534F))),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: const Text('取消',
                  style: TextStyle(color: Color(0xFF8A9AB0))),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _saving ? null : _submit,
              child: Text('确认',
                  style: TextStyle(
                      color: _valid
                          ? const Color(0xFF3B6FE0)
                          : const Color(0xFF9AA8BF))),
            ),
          ),
        ],
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('密码已重置，请使用新密码进入')),
      );
      setState(() {
        _forgot = false;
        _error = null;
        _ctrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  errorStyle: const TextStyle(color: Color(0xFFD9534F)),
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
                    const Icon(Icons.error_outline,
                        size: 16, color: Color(0xFFD9534F)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFD9534F),
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
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '密保答案',
                  errorText: _error,
                  errorStyle: const TextStyle(color: Color(0xFFD9534F)),
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
                    const Icon(Icons.error_outline,
                        size: 16, color: Color(0xFFD9534F)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFFD9534F),
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
              child: const Text('取消',
                  style: TextStyle(color: Color(0xFF8A9AB0))),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _forgot ? _resetByAnswer : _submit,
              child: Text('确认',
                  style: const TextStyle(color: Color(0xFF3B6FE0))),
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
            color: sel ? const Color(0xFF3B6FE0) : const Color(0xFFF3F6FB),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel ? Colors.white : const Color(0xFF5A6B82))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              const Text('验证身份后，资产全景将不再需要密码即可进入',
                  style: TextStyle(fontSize: 13, color: Color(0xFF9AA8BF))),
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
                          fontSize: 14, fontWeight: FontWeight.w500)),
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
                      const Icon(Icons.error_outline,
                          size: 16, color: Color(0xFFD9534F)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(_error!,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFD9534F),
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
              child: const Text('取消',
                  style: TextStyle(color: Color(0xFF8A9AB0))),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _busy ? null : _confirm,
              child: const Text('确认取消',
                  style: TextStyle(color: Color(0xFFD9534F))),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 修改资产密码弹窗 ====================

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog({Key? key}) : super(key: key);

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  /// 'pin' = 验证当前密码；'answer' = 验证密保答案
  String _mode = 'pin';

  final _vCtrl = TextEditingController(); // 当前密码 / 密保答案
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  final _qCtrl = TextEditingController();
  final _aCtrl = TextEditingController();

  bool _verified = false; // 验证通过后显示新密码表单
  bool _saving = false;
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
    _p1.dispose();
    _p2.dispose();
    _qCtrl.dispose();
    _aCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final v = _vCtrl.text.trim();
    if (v.isEmpty) {
      setState(() => _error = _mode == 'pin' ? '请输入当前密码' : '请输入密保答案');
      return;
    }
    final ok = _mode == 'pin'
        ? await AssetStorage.verifyPin(v)
        : await AssetStorage.verifyAnswer(v);
    if (!mounted) return;
    if (!ok) {
      setState(() =>
          _error = _mode == 'pin' ? '当前密码不正确' : '密保答案不正确');
      return;
    }
    setState(() {
      _verified = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    final p1 = _p1.text.trim();
    final p2 = _p2.text.trim();
    if (p1.length < 4) {
      setState(() => _error = '新密码至少 4 位');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = '两次输入的新密码不一致');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await AssetStorage.updatePin(
      newPin: p1,
      question: _qCtrl.text,
      answer: _aCtrl.text,
    );
    if (mounted) Navigator.pop(context, true);
  }

  Widget _errorBox() {
    if (_error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFD9534F)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(_error!,
                style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFD9534F),
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
            color: sel ? const Color(0xFF3B6FE0) : const Color(0xFFF3F6FB),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel ? Colors.white : const Color(0xFF5A6B82))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => !_saving,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_verified ? '设置新密码' : '验证身份'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _verified
                ? [
                    TextField(
                      controller: _p1,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 12,
                      decoration: const InputDecoration(
                        labelText: '新密码（至少 4 位）',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _p2,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 12,
                      decoration: const InputDecoration(
                        labelText: '再输入一遍新密码',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    const SizedBox(height: 14),
                    const Text('如需同时修改密保，可填写下面两项（选填）',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF9AA8BF))),
                    const SizedBox(height: 8),
                    FutureBuilder<String>(
                      future: _question,
                      builder: (c, snap) => TextField(
                        controller: _qCtrl,
                        maxLength: 30,
                        decoration: InputDecoration(
                          labelText: '密保问题',
                          hintText: snap.data ?? '',
                          counterText: '',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _aCtrl,
                      maxLength: 30,
                      decoration: const InputDecoration(
                        labelText: '密保答案',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    _errorBox(),
                  ]
                : [
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
                        onSubmitted: (_) => _verify(),
                        onChanged: (_) => setState(() => _error = null),
                      )
                    else ...[
                      FutureBuilder<String>(
                        future: _question,
                        builder: (c, snap) => Text(
                          snap.data ?? '',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500),
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
                        onSubmitted: (_) => _verify(),
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
              onPressed: _saving ? null : () => Navigator.pop(context, false),
              child: const Text('取消',
                  style: TextStyle(color: Color(0xFF8A9AB0))),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: _saving ? null : (_verified ? _save : _verify),
              child: Text(_verified ? '保存' : '下一步',
                  style: const TextStyle(color: Color(0xFF3B6FE0))),
            ),
          ),
        ],
      ),
    );
  }
}
