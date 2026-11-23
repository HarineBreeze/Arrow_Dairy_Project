import 'package:flutter/material.dart';

import '../services/app_lock_storage.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
import '../utils/app_toast.dart';
import '../utils/haptics.dart';
import '../widgets/app_icons.dart';
import '../widgets/pattern_lock_view.dart';
import '../widgets/pressable.dart';

/// ============================================================
/// 隐私锁设置向导（首次开启）
/// 返回 true = 设置成功；false / null = 用户取消（调用方据此关闭隐私锁）。
/// 密保问题与答案必填。取消按钮一次即返回。
/// ============================================================
class AppLockSetupDialog extends StatefulWidget {
  const AppLockSetupDialog({Key? key}) : super(key: key);

  @override
  State<AppLockSetupDialog> createState() => _AppLockSetupDialogState();
}

class _AppLockSetupDialogState extends State<AppLockSetupDialog> {
  AppLockType _type = AppLockType.password;
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  final _qCtrl = TextEditingController(text: '你的生日是几号？');
  final _aCtrl = TextEditingController();

  List<int> _pattern1 = const [];
  List<int> _pattern2 = const [];
  int _step = 0; // 手势阶段：0 画一次，1 再画一次确认
  String? _tip;
  bool _saving = false;

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    _qCtrl.dispose();
    _aCtrl.dispose();
    super.dispose();
  }

  void _cancel() {
    Haptics.light();
    Navigator.pop(context, false);
  }

  String? get _missingCommon {
    if (_qCtrl.text.trim().isEmpty) return '请填写密保问题';
    if (_aCtrl.text.trim().isEmpty) return '请填写密保答案（必填）';
    return null;
  }

  Future<void> _submit() async {
    final common = _missingCommon;
    if (common != null) {
      setState(() => _tip = common);
      return;
    }
    if (_type == AppLockType.password) {
      final p1 = _p1.text.trim();
      if (p1.isEmpty) {
        setState(() => _tip = '请设置密码（至少 4 位）');
        return;
      }
      if (p1.length < 4) {
        setState(() => _tip = '密码至少 4 位');
        return;
      }
      if (p1 != _p2.text.trim()) {
        setState(() => _tip = '两次输入的密码不一致');
        return;
      }
    } else {
      if (!isValidPattern(_pattern1) || !isValidPattern(_pattern2)) {
        setState(() => _tip = '手势至少连接 4 个点');
        return;
      }
      if (patternToString(_pattern1) != patternToString(_pattern2)) {
        setState(() => _tip = '两次绘制的手势不一致，请重画');
        return;
      }
    }

    setState(() {
      _saving = true;
      _tip = null;
    });
    await AppLockStorage.saveLock(
      type: _type,
      pin: _type == AppLockType.password ? _p1.text.trim() : '',
      pattern: _type == AppLockType.gesture
          ? patternToString(_pattern1)
          : '',
      question: _qCtrl.text.trim(),
      answer: _aCtrl.text,
    );
    if (mounted) Navigator.pop(context, true);
  }

  Widget _tipRow() {
    if (_tip == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const AppIcon(AppIcons.warn, size: 16, color: Color(0xFFCB5C50)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(_tip!,
                style: const TextStyle(fontSize: 13, color: Color(0xFFCB5C50))),
          ),
        ],
      ),
    );
  }

  Widget _typeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFF1F5F2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _type = AppLockType.password;
                _tip = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _type == AppLockType.password
                      ? AppPalette.c(0xFFFFFFFF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _type == AppLockType.password
                      ? [
                          BoxShadow(
                              color: AppPalette.c(0xFF1A3327).withOpacity(0.08),
                              blurRadius: 6)
                        ]
                      : null,
                ),
                child: Center(
                  child: Text('密码解锁',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: _type == AppLockType.password
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: _type == AppLockType.password
                              ? AppPalette.c(0xFF3E8E6D)
                              : AppPalette.c(0xFF647A70))),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _type = AppLockType.gesture;
                _tip = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _type == AppLockType.gesture
                      ? AppPalette.c(0xFFFFFFFF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _type == AppLockType.gesture
                      ? [
                          BoxShadow(
                              color: AppPalette.c(0xFF1A3327).withOpacity(0.08),
                              blurRadius: 6)
                        ]
                      : null,
                ),
                child: Center(
                  child: Text('手势解锁',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: _type == AppLockType.gesture
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: _type == AppLockType.gesture
                              ? AppPalette.c(0xFF3E8E6D)
                              : AppPalette.c(0xFF647A70))),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _credentialPart() {
    if (_type == AppLockType.password) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        ],
      );
    }
    // 手势：分两次绘制
    return Column(
      children: [
        Text(
          _step == 0 ? '绘制解锁手势（至少 4 个点）' : '再次绘制以确认',
          style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF647A70)),
        ),
        const SizedBox(height: 8),
        PatternLockView(
          onCompleted: (path) {
            if (_step == 0) {
              setState(() {
                _pattern1 = path;
                _step = 1;
                _tip = null;
              });
            } else {
              setState(() {
                _pattern2 = path;
                _tip = null;
              });
            }
          },
        ),
        const SizedBox(height: 4),
        Pressable(
          child: TextButton(
            onPressed: () => setState(() {
              _step = 0;
              _pattern1 = const [];
              _pattern2 = const [];
              _tip = null;
            }),
            child: Text('重画',
                style: TextStyle(color: AppPalette.c(0xFF7C8F86))),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    return WillPopScope(
      onWillPop: () async {
        _cancel();
        return false;
      },
      child: AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('设置隐私锁'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('开启后，每次打开 App 都需解锁；凭证仅保存在本机',
                  style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
              const SizedBox(height: 14),
              _typeSelector(),
              const SizedBox(height: 16),
              _credentialPart(),
              const SizedBox(height: 16),
              Text('密保（忘记密码/手势时用于重置，必填）',
                  style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
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
              _tipRow(),
            ],
          ),
        ),
        actions: [
          Pressable(
            child: TextButton(
              onPressed: _saving ? null : _cancel,
              child:
                  Text('取消', style: TextStyle(color: AppPalette.c(0xFF7C8F86))),
            ),
          ),
          Pressable(
            child: TextButton(
              onPressed: _saving ? null : _submit,
              child: Text('确认',
                  style: TextStyle(
                      color: AppPalette.c(0xFF3E8E6D))),
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// 启动解锁界面（冷启动）
/// [onUnlocked] 验证成功后回调，调用方切到主界面。
/// ============================================================
class AppLockUnlockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const AppLockUnlockScreen({Key? key, required this.onUnlocked})
      : super(key: key);

  @override
  State<AppLockUnlockScreen> createState() => _AppLockUnlockScreenState();
}

class _AppLockUnlockScreenState extends State<AppLockUnlockScreen> {
  AppLockType _type = AppLockType.password;
  final _pinCtrl = TextEditingController();
  List<int> _pattern = const [];
  String? _tip;
  bool _checking = false;
  bool _forgot = false;

  final _answerCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _newPattern = ValueNotifier<List<int>>(const []);
  String _question = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final type = await AppLockStorage.loadType();
    if (!mounted) return;
    setState(() => _type = type);
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _answerCtrl.dispose();
    _newPinCtrl.dispose();
    _newPattern.dispose();
    super.dispose();
  }

  void _ok() {
    Haptics.medium();
    widget.onUnlocked();
  }

  Future<void> _verifyPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _tip = '请输入密码');
      return;
    }
    setState(() {
      _checking = true;
      _tip = null;
    });
    final ok = await AppLockStorage.verifyPin(pin);
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) {
      _ok();
    } else {
      setState(() => _tip = '密码错误，请重试');
    }
  }

  Future<void> _verifyPattern(List<int> path) async {
    if (!isValidPattern(path)) {
      setState(() => _tip = '手势至少连接 4 个点');
      return;
    }
    setState(() {
      _checking = true;
      _tip = null;
    });
    final ok = await AppLockStorage.verifyPattern(patternToString(path));
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (!ok) _tip = '手势错误，请重试';
    });
    if (ok) _ok();
  }

  Future<void> _enterForgot() async {
    final q = await AppLockStorage.getQuestion();
    if (!mounted) return;
    setState(() {
      _question = q;
      _forgot = true;
      _tip = null;
    });
  }

  Future<void> _resetByAnswer() async {
    final answer = _answerCtrl.text.trim();
    if (answer.isEmpty) {
      setState(() => _tip = '请输入密保答案');
      return;
    }
    setState(() {
      _checking = true;
      _tip = null;
    });
    final ok = await AppLockStorage.verifyAnswer(answer);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _checking = false;
        _tip = '密保答案错误';
      });
      return;
    }
    // 密保通过：校验新凭证
    if (_type == AppLockType.password) {
      final np = _newPinCtrl.text.trim();
      if (np.length < 4) {
        setState(() {
          _checking = false;
          _tip = '新密码至少 4 位';
        });
        return;
      }
      await AppLockStorage.reset(type: AppLockType.password, pin: np);
    } else {
      final np = _newPattern.value;
      if (!isValidPattern(np)) {
        setState(() {
          _checking = false;
          _tip = '新手势至少连接 4 个点';
        });
        return;
      }
      await AppLockStorage.reset(
          type: AppLockType.gesture, pattern: patternToString(np));
    }
    if (!mounted) return;
    AppToast.show(context, '已重置，请重新解锁');
    setState(() {
      _checking = false;
      _forgot = false;
      _tip = null;
      _pinCtrl.clear();
      _answerCtrl.clear();
      _newPinCtrl.clear();
      _newPattern.value = const [];
    });
  }

  Widget _tipRow() {
    if (_tip == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const AppIcon(AppIcons.warn, size: 16, color: Color(0xFFCB5C50)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(_tip!,
                style: const TextStyle(fontSize: 13, color: Color(0xFFCB5C50))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    return Scaffold(
      backgroundColor: AppPalette.c(0xFFF7FAF8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(AppIcons.lock,
                    size: 52, color: AppPalette.c(0xFF3E8E6D)),
                const SizedBox(height: 16),
                Text(_forgot ? '重置隐私锁' : '已锁定',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.c(0xFF24382F))),
                const SizedBox(height: 8),
                Text(
                  _forgot ? '回答密保问题以重设解锁凭证' : '请输入凭证解锁阿尤日记',
                  style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
                ),
                const SizedBox(height: 28),
                if (!_forgot) ...[
                  if (_type == AppLockType.password) ...[
                    TextField(
                      controller: _pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 12,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '密码',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _tip = null),
                      onSubmitted: (_) => _checking ? null : _verifyPin(),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _checking ? null : _verifyPin,
                        style: ElevatedButton.styleFrom(
                          primary: AppPalette.c(0xFF3E8E6D),
                          onPrimary: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(_checking ? '验证中…' : '解锁',
                            style: const TextStyle(
                                fontSize: 15, color: Colors.white)),
                      ),
                    ),
                  ] else ...[
                    PatternLockView(onCompleted: _verifyPattern),
                  ],
                  _tipRow(),
                  const SizedBox(height: 20),
                  Pressable(
                    child: TextButton(
                      onPressed: _enterForgot,
                      child: Text('忘记密码/手势？',
                          style:
                              TextStyle(color: AppPalette.c(0xFF7C8F86))),
                    ),
                  ),
                ] else ...[
                  Text(_question,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.c(0xFF24382F))),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _answerCtrl,
                    decoration: const InputDecoration(
                      labelText: '密保答案',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => _tip = null),
                  ),
                  const SizedBox(height: 16),
                  if (_type == AppLockType.password)
                    TextField(
                      controller: _newPinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 12,
                      decoration: const InputDecoration(
                        labelText: '新密码（至少 4 位）',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() => _tip = null),
                    )
                  else
                    Column(
                      children: [
                        Text('绘制新手势',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppPalette.c(0xFF647A70))),
                        PatternLockView(
                          onCompleted: (path) => _newPattern.value = path,
                        ),
                      ],
                    ),
                  _tipRow(),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Pressable(
                          child: OutlinedButton(
                            onPressed: () => setState(() {
                              _forgot = false;
                              _tip = null;
                            }),
                            child: Text('返回',
                                style: TextStyle(
                                    color: AppPalette.c(0xFF7C8F86))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _checking ? null : _resetByAnswer,
                          style: ElevatedButton.styleFrom(
                            primary: AppPalette.c(0xFF3E8E6D),
                            onPrimary: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(_checking ? '处理中…' : '确认重置',
                              style: const TextStyle(
                                  fontSize: 15, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
