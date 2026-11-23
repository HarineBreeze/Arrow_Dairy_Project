import 'package:flutter/material.dart';

import '../services/app_lock_storage.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
import '../utils/app_toast.dart';
import '../utils/haptics.dart';
import '../widgets/app_icons.dart';
import '../widgets/pattern_lock_view.dart';
import '../widgets/pressable.dart';

/// 隐私锁设置向导已拆到 [app_lock_setup_wizard.dart]（v5.0.2），
/// 本文件只保留冷启动解锁屏。

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
