import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/asset.dart';
import '../services/asset_storage.dart';
import 'asset_edit_screen.dart';

/// 资产图景主页。进入前需通过密码（首次先设置）。
/// 返回 true 表示确认完成（供外部回调刷新）。
class AssetScreen extends StatefulWidget {
  final VoidCallback? onOpenMenu;
  const AssetScreen({Key? key, this.onOpenMenu}) : super(key: key);

  @override
  State<AssetScreen> createState() => AssetScreenState();
}

class AssetScreenState extends State<AssetScreen> {
  List<Asset> _assets = [];
  bool _loading = true;
  bool _unlocked = false;

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
    if (!_unlocked) return;
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
    final r = await Navigator.push<Asset>(
      context,
      _slideRoute(AssetEditScreen()),
    );
    if (r != null) {
      _assets.add(r);
      await AssetStorage.save(_assets);
      if (mounted) setState(() {});
    }
  }

  // ---------- 密码流程 ----------

  PageRouteBuilder<Asset> _slideRoute(Widget page) =>
      PageRouteBuilder<Asset>(
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
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PinSetupDialog(),
    );
    _unlocked = true;
  }

  Future<void> _askUnlock() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _PinUnlockDialog(),
    );
    _unlocked = true;
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

  // ---------- 操作 ----------

  Future<void> _openEditor([Asset? asset]) async {
    final r = await Navigator.push<Asset>(
      context,
      _slideRoute(AssetEditScreen(asset: asset)),
    );
    if (r == 'deleted') {
      _assets.removeWhere((e) => e.id == asset!.id);
      await AssetStorage.save(_assets);
      if (mounted) setState(() {});
      return;
    }
    if (r != null) {
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
              const SizedBox(width: 48),
            ],
          ),
        ),
        Expanded(
          child: _loading || !_unlocked
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  color: const Color(0xFF3B6FE0),
                  onRefresh: _load,
                  child: _assets.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 200),
                            Center(
                              child: Text('还没有资产卡片\n点右下角 + 添加第一笔',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
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
                            ..._assets.map(_buildCard),
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
          const Text('净资产',
              style: TextStyle(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            '¥${net.toStringAsFixed(net.truncateToDouble() == net ? 0 : 2)}',
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, double value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          const SizedBox(height: 2),
          Text(
            value < 0
                ? '-¥${(-value).toStringAsFixed((-value).truncateToDouble() == -value ? 0 : 2)}'
                : '¥${value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2)}',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------- 资产卡片 ----------

  Widget _buildCard(Asset a) {
    final negative = a.amount < 0;
    return GestureDetector(
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
            // 名（类型）+ 备注
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.type,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2A3B52))),
                  if (a.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(a.note,
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
                color: negative ? const Color(0xFFE06A6A) : const Color(0xFF2A9D5C),
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

  bool get _valid =>
      _p1.text.trim().length >= 4 &&
      _p1.text.trim() == _p2.text.trim() &&
      _qCtrl.text.trim().isNotEmpty &&
      _aCtrl.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (!_valid) return;
    setState(() => _saving = true);
    await AssetStorage.savePin(
      pin: _p1.text.trim(),
      question: _qCtrl.text.trim(),
      answer: _aCtrl.text,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
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
                onChanged: (_) => setState(() {}),
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
                onChanged: (_) => setState(() {}),
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
                onChanged: (_) => setState(() {}),
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
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: Text('完成',
                style: TextStyle(
                    color: _valid ? const Color(0xFF3B6FE0) : Colors.grey)),
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
    final ok = await AssetStorage.verifyPin(_ctrl.text.trim());
    if (ok) {
      if (mounted) Navigator.pop(context);
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
      Navigator.pop(context); // 关闭解锁框，让用户用新密码进入
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
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
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 6),
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
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _resetByAnswer(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 6),
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
            onPressed: _forgot ? _resetByAnswer : _submit,
            child: Text(_forgot ? '重置密码' : '进入',
                style: const TextStyle(color: Color(0xFF3B6FE0))),
          ),
        ],
      ),
    );
  }
}
