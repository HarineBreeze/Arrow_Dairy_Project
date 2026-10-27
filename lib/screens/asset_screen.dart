import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/asset.dart';
import '../services/asset_storage.dart';
import 'asset_edit_screen.dart';

/// 资产图景主页。进入前需通过密码（首次先设置）。
/// 返回 true 表示确认完成（供外部回调刷新）。
class AssetScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  /// 用户在密码页点了「取消」时回调，由首页切回笔记主页
  final VoidCallback? onCancel;
  const AssetScreen({Key? key, this.onOpenMenu, this.onCancel})
      : super(key: key);

  @override
  State<AssetScreen> createState() => AssetScreenState();
}

class AssetScreenState extends State<AssetScreen> {
  List<Asset> _assets = [];
  bool _loading = true;
  bool _unlocked = false;
  String _typeFilter = '全部'; // 全部 | 总资产 | 负资产 | 现金流
  String _signFilter = '全部'; // 全部 | 金额为正 | 金额为负
  bool _hideNumbers = false; // 看板数字是否隐藏（默认显示）

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final hasPin = await AssetStorage.hasPin();
    if (hasPin) {
      // 已设置密码：先解锁
      await _askUnlock();
    } else {
      await _askSetup();
    }
    if (!mounted) return;
    if (!_unlocked) {
      // 用户取消（或侧滑）→ 交回首页
      if (widget.onCancel != null) widget.onCancel!();
      return;
    }
    await _load();
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

  Future<void> _askSetup() async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PinSetupDialog(),
    );
    _unlocked = r == true;
  }

  Future<void> _askUnlock() async {
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PinUnlockDialog(),
    );
    _unlocked = r == true;
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
            ListTile(
              leading: const Icon(Icons.lock_outline, color: Color(0xFF3B6FE0)),
              title: const Text('修改资产密码'),
              subtitle: const Text('可通过当前密码或密保问题验证',
                  style: TextStyle(fontSize: 12, color: Color(0xFF9AA8BF))),
              onTap: () {
                Navigator.pop(ctx);
                _openChangePin();
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 44,
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

  /// 长按（500ms 系统默认）弹出编辑/删除选框
  void _showCardMenu(Asset a) {
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
                  _assets.removeWhere((e) => e.id == a.id);
                  await AssetStorage.save(_assets);
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
                child: Text('资产图景',
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
                onPressed: _unlocked ? _openSettings : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading || !_unlocked
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  color: const Color(0xFF3B6FE0),
                  onRefresh: _load,
                  child: _filtered.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 200),
                            Center(
                              child: Text(
                                  _hasFilter
                                      ? '没有符合条件的资产卡片\n试试调整筛选条件'
                                      : '还没有资产卡片\n点右下角 + 添加第一笔',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      color: Color(0xFF9AA8BF),
                                      height: 1.8)),
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                          children: [
                            _buildOverview(),
                            const SizedBox(height: 14),
                            ..._filtered.map(_buildCard),
                          ],
                        ),
                ),
        ),
      ],
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
                  HapticFeedback.selectionClick();
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
              _statItem('现金流', _cashFlow, const Color(0xFFD6FFDF)),
              _statItem('理财资产', _investTotal, Colors.white),
            ],
          ),
        ],
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

  Widget _buildCard(Asset a) {
    final negative = a.amount < 0;
    final invest = _investTypes.contains(a.type);
    return GestureDetector(
      onTap: () => _openEditor(a),
      onLongPress: () => _showCardMenu(a),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
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
            // 金额
            Text(
              negative
                  ? '-¥${(-a.amount).toStringAsFixed((-a.amount).truncateToDouble() == -a.amount ? 0 : 2)}'
                  : '¥${a.amount.toStringAsFixed(a.amount.truncateToDouble() == a.amount ? 0 : 2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: invest
                    ? const Color(0xFF3B6FE0)
                    : (negative
                        ? const Color(0xFFE06A6A)
                        : const Color(0xFF2A9D5C)),
              ),
            ),
          ],
        ),
      ),
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
        title: const Text('设置资产密码'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('进入资产图景需要输入密码，密码仅保存在本机',
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
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('取消',
                style: TextStyle(color: Color(0xFF8A9AB0))),
          ),
          TextButton(
            onPressed: _saving ? null : _submit,
            child: Text('确认',
                style: TextStyle(
                    color: _valid
                        ? const Color(0xFF3B6FE0)
                        : const Color(0xFF9AA8BF))),
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
            TextButton(
              onPressed: () async {
                if (p1.text.trim().length >= 4 &&
                    p1.text.trim() == p2.text.trim()) {
                  await AssetStorage.resetPin(p1.text.trim());
                  Navigator.pop(c, p1.text.trim());
                }
              },
              child: const Text('重置'),
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
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消',
                style: TextStyle(color: Color(0xFF8A9AB0))),
          ),
          TextButton(
            onPressed: _forgot ? _resetByAnswer : _submit,
            child: Text('确认',
                style: const TextStyle(color: Color(0xFF3B6FE0))),
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
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('取消',
                style: TextStyle(color: Color(0xFF8A9AB0))),
          ),
          TextButton(
            onPressed: _saving ? null : (_verified ? _save : _verify),
            child: Text(_verified ? '保存' : '下一步',
                style: const TextStyle(color: Color(0xFF3B6FE0))),
          ),
        ],
      ),
    );
  }
}
