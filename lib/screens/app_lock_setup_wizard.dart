import 'package:flutter/material.dart';

import '../services/app_lock_storage.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
import '../utils/haptics.dart';
import '../widgets/app_icons.dart';
import '../widgets/pattern_lock_view.dart';
import '../widgets/pressable.dart';

/// ============================================================
/// 隐私锁设置向导（v5.0.2 起拆成 4 个独立弹窗）
///
/// 流程固定：选择隐私锁形式 → 设置密码 → 确认密码 → 设置密保。
/// 其中手势锁的「密码」步骤即九宫格手势，「确认密码」即再次绘制。
/// 任一步中断（取消 / 返回键 / 点遮罩 / 校验不通过放弃）都返回 false，
/// 不写入任何凭证、不改动已有锁状态。
///
/// 返回 true = 4 步全部完成且已保存；false = 中途取消。
/// ============================================================

/// 向导步骤枚举（供测试与步骤文案映射使用）
enum AppLockSetupStep { type, credential, confirm, security }

/// 各步骤标题；手势锁时凭据两步文案换成「手势」。
String lockStepTitle(AppLockSetupStep step, AppLockType type) {
  final gesture = type == AppLockType.gesture;
  switch (step) {
    case AppLockSetupStep.type:
      return '选择隐私锁形式';
    case AppLockSetupStep.credential:
      return gesture ? '设置解锁手势' : '设置密码';
    case AppLockSetupStep.confirm:
      return gesture ? '确认解锁手势' : '确认密码';
    case AppLockSetupStep.security:
      return '设置密保';
  }
}

/// 4 步向导。传递 [initialType] 可预选形式（关闭重开时仍从第一步开始，
/// 但允许带入上次类型以便测试；正常开启不传）。
// 受控弹窗链：设置页在向导期间始终挂载，跨 await 使用其 context 是安全的。
// ignore_for_file: use_build_context_synchronously

Future<bool> showAppLockSetupWizard(
  BuildContext context, {
  AppLockType? initialType,

  /// 仅测试使用：替换真实的保存实现，避免 widget 测试走文件 IO。
  Future<void> Function({
    required AppLockType type,
    required String pin,
    required String pattern,
    required String question,
    required String answer,
  })? saveOverride,
}) async {
  // 第 1 步：选择形式
  final type = await _showStep<AppLockType>(
    context,
    step: AppLockSetupStep.type,
    builder: (ctx) => _TypeStep(initial: initialType),
  );
  if (type == null) return false;

  // 第 2 步：设置密码 / 手势
  final credential = await _showStep<String>(
    context,
    step: AppLockSetupStep.credential,
    type: type,
    builder: (ctx) => _CredentialStep(type: type),
  );
  if (credential == null) return false;

  // 第 3 步：确认密码 / 手势
  final confirmed = await _showStep<bool>(
    context,
    step: AppLockSetupStep.confirm,
    type: type,
    builder: (ctx) => _ConfirmStep(type: type, expected: credential),
  );
  if (confirmed != true) return false;

  // 第 4 步：设置密保
  final security = await _showStep<_SecurityData>(
    context,
    step: AppLockSetupStep.security,
    type: type,
    builder: (ctx) => const _SecurityStep(),
  );
  if (security == null) return false;

  final pin = type == AppLockType.password ? credential : '';
  final pattern = type == AppLockType.gesture ? credential : '';
  if (saveOverride != null) {
    await saveOverride(
      type: type,
      pin: pin,
      pattern: pattern,
      question: security.question,
      answer: security.answer,
    );
  } else {
    await AppLockStorage.saveLock(
      type: type,
      pin: pin,
      pattern: pattern,
      question: security.question,
      answer: security.answer,
    );
  }
  return true;
}

/// 统一的步骤弹窗壳：主题色 / 深浅模式 / 圆角 / 按钮与全站一致。
Future<T?> _showStep<T>(
  BuildContext context, {
  required AppLockSetupStep step,
  AppLockType? type,
  required WidgetBuilder builder,
}) {
  final displayType = type ?? AppLockType.password;
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _StepFrame<T>(
      step: step,
      type: displayType,
      title: lockStepTitle(step, displayType),
      builder: builder,
    ),
  );
}

/// 步骤外壳：标题 + 进度 + 内容 + 取消按钮。返回键 / 取消都视为整体取消。
class _StepFrame<T> extends StatelessWidget {
  final AppLockSetupStep step;
  final AppLockType type;
  final String title;
  final WidgetBuilder builder;

  const _StepFrame({
    Key? key,
    required this.step,
    required this.type,
    required this.title,
    required this.builder,
  }) : super(key: key);

  int get _index => AppLockSetupStep.values.indexOf(step) + 1;

  void _cancel(BuildContext context) {
    Haptics.light();
    Navigator.pop<T>(context);
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    final accent = AppPalette.accentColor;
    return WillPopScope(
      onWillPop: () async {
        _cancel(context);
        return false;
      },
      child: AlertDialog(
        key: ValueKey('app_lock_step_${step.name}'),
        backgroundColor: AppPalette.c(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_index / 4',
              style: TextStyle(fontSize: 11, color: accent),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                  fontSize: 17,
                  color: AppPalette.c(0xFF24382F),
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        content: SingleChildScrollView(child: builder(context)),
      ),
    );
  }
}

/// 每步底部操作行：取消（左）+ 主按钮（右），无底纹、缩小、整体右对齐。
/// 取消与主按钮同处一行，任一取消都向向导返回 null（即整体取消）。
Widget _stepActionRow({
  required BuildContext context,
  required String label,
  required VoidCallback onSubmit,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Pressable(
        child: TextButton(
          onPressed: () {
            Haptics.light();
            Navigator.pop(context);
          },
          child: Text('取消',
              style:
                  TextStyle(fontSize: 13, color: AppPalette.c(0xFF7C8F86))),
        ),
      ),
      const SizedBox(width: 8),
      Pressable(
        child: TextButton(
          onPressed: onSubmit,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: AppPalette.accentColor,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    ],
  );
}

/// 第 1 步：选择形式（默认密码，选中即高亮，底部「下一步」）。
class _TypeStep extends StatefulWidget {
  final AppLockType? initial;
  const _TypeStep({this.initial});

  @override
  State<_TypeStep> createState() => _TypeStepState();
}

class _TypeStepState extends State<_TypeStep> {
  late AppLockType _type = widget.initial ?? AppLockType.password;

  Widget _tile(AppLockType value, String label, String iconPath) {
    final selected = _type == value;
    final accent = AppPalette.accentColor;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = value;
          Haptics.light();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            // 选中底纹由当前主题色淡化而来，5 套主题 / 深浅模式自动跟随。
            color: selected
                ? Color.alphaBlend(
                    accent.withOpacity(0.12), AppPalette.c(0xFFFFFFFF))
                : AppPalette.c(0xFFF5F8F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              AppIcon(iconPath,
                  size: 24,
                  color: selected ? accent : AppPalette.c(0xFF7C8F86)),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: selected ? accent : AppPalette.c(0xFF647A70),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('选择解锁方式，开启后每次打开 App 需先解锁。',
            style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF7C8F86))),
        const SizedBox(height: 16),
        Row(children: [
          _tile(AppLockType.password, '数字密码', AppIcons.lock),
          const SizedBox(width: 12),
          _tile(AppLockType.gesture, '九宫格手势', AppIcons.event),
        ]),
        const SizedBox(height: 16),
        _stepActionRow(
          context: context,
          label: '下一步',
          onSubmit: () => Navigator.pop<AppLockType>(context, _type),
        ),
      ],
    );
  }
}

/// 第 2 步：设置密码 / 首次绘制手势。
class _CredentialStep extends StatefulWidget {
  final AppLockType type;
  const _CredentialStep({required this.type});

  @override
  State<_CredentialStep> createState() => _CredentialStepState();
}

class _CredentialStepState extends State<_CredentialStep> {
  final _ctrl = TextEditingController();
  List<int> _pattern = const [];
  String? _tip;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _valid => widget.type == AppLockType.password
      ? _ctrl.text.trim().length >= 4
      : isValidPattern(_pattern);

  void _submit() {
    if (!_valid) {
      setState(() => _tip = widget.type == AppLockType.password
          ? '密码至少 4 位'
          : '手势至少连接 4 个点');
      return;
    }
    final value = widget.type == AppLockType.password
        ? _ctrl.text.trim()
        : patternToString(_pattern);
    Navigator.pop<String>(context, value);
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.type == AppLockType.password
              ? '输入 4 位以上数字密码。'
              : '在九宫格上绘制解锁手势（至少连接 4 个点）。',
          style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF7C8F86)),
        ),
        const SizedBox(height: 12),
        if (widget.type == AppLockType.password)
          TextField(
            controller: _ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 12,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: '密码（至少 4 位）',
                counterText: '',
                border: OutlineInputBorder()),
            onChanged: (_) => setState(() => _tip = null),
          )
        else
          Center(
            child: PatternLockView(onCompleted: (path) {
              setState(() {
                _pattern = path;
                _tip = null;
              });
            }),
          ),
        if (_tip != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_tip!,
                style: const TextStyle(fontSize: 13, color: Color(0xFFCB5C50))),
          ),
        const SizedBox(height: 12),
        _stepActionRow(
          context: context,
          label: '下一步',
          onSubmit: _submit,
        ),
      ],
    );
  }
}

/// 第 3 步：确认密码 / 再次绘制手势。不一致提示重输，不写入任何数据。
class _ConfirmStep extends StatefulWidget {
  final AppLockType type;
  final String expected;
  const _ConfirmStep({required this.type, required this.expected});

  @override
  State<_ConfirmStep> createState() => _ConfirmStepState();
}

class _ConfirmStepState extends State<_ConfirmStep> {
  final _ctrl = TextEditingController();
  List<int> _pattern = const [];
  String? _tip;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final value = widget.type == AppLockType.password
        ? _ctrl.text.trim()
        : patternToString(_pattern);
    final valid = widget.type == AppLockType.password
        ? value.length >= 4
        : isValidPattern(_pattern);
    if (!valid) {
      setState(() => _tip = widget.type == AppLockType.password
          ? '密码至少 4 位'
          : '手势至少连接 4 个点');
      return;
    }
    if (value != widget.expected) {
      setState(() => _tip = widget.type == AppLockType.password
          ? '两次输入的密码不一致，请重新输入'
          : '两次绘制的手势不一致，请重新绘制');
      return;
    }
    Navigator.pop<bool>(context, true);
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.type == AppLockType.password
              ? '请再次输入刚才设置的密码。'
              : '请再次绘制刚才的手势。',
          style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF7C8F86)),
        ),
        const SizedBox(height: 12),
        if (widget.type == AppLockType.password)
          TextField(
            controller: _ctrl,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 12,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: '再次输入密码',
                counterText: '',
                border: OutlineInputBorder()),
            onChanged: (_) => setState(() => _tip = null),
          )
        else
          Center(
            child: PatternLockView(onCompleted: (path) {
              setState(() {
                _pattern = path;
                _tip = null;
              });
            }),
          ),
        if (_tip != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_tip!,
                style: const TextStyle(fontSize: 13, color: Color(0xFFCB5C50))),
          ),
        const SizedBox(height: 12),
        _stepActionRow(
          context: context,
          label: '下一步',
          onSubmit: _submit,
        ),
      ],
    );
  }
}

class _SecurityData {
  final String question;
  final String answer;
  const _SecurityData({required this.question, required this.answer});
}

/// 第 4 步：密保问题 + 答案（必填）。
class _SecurityStep extends StatefulWidget {
  const _SecurityStep();

  @override
  State<_SecurityStep> createState() => _SecurityStepState();
}

class _SecurityStepState extends State<_SecurityStep> {
  final _q = TextEditingController(text: '你的生日是几号？');
  final _a = TextEditingController();
  String? _tip;

  @override
  void dispose() {
    _q.dispose();
    _a.dispose();
    super.dispose();
  }

  void _submit() {
    if (_q.text.trim().isEmpty) {
      setState(() => _tip = '请填写密保问题');
      return;
    }
    if (_a.text.trim().isEmpty) {
      setState(() => _tip = '请填写密保答案（必填）');
      return;
    }
    Navigator.pop<_SecurityData>(context,
        _SecurityData(question: _q.text.trim(), answer: _a.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('忘记密码 / 手势时，可用密保答案重置。',
            style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF7C8F86))),
        const SizedBox(height: 12),
        TextField(
          controller: _q,
          maxLength: 30,
          decoration: const InputDecoration(
              labelText: '密保问题', counterText: '', border: OutlineInputBorder()),
          onChanged: (_) => setState(() => _tip = null),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _a,
          maxLength: 30,
          decoration: const InputDecoration(
              labelText: '密保答案', counterText: '', border: OutlineInputBorder()),
          onChanged: (_) => setState(() => _tip = null),
        ),
        if (_tip != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_tip!,
                style: const TextStyle(fontSize: 13, color: Color(0xFFCB5C50))),
          ),
        const SizedBox(height: 12),
        _stepActionRow(
          context: context,
          label: '完成',
          onSubmit: _submit,
        ),
      ],
    );
  }
}

/// ============================================================
/// 关闭隐私锁：验证当前凭证，验证通过才允许关闭。
/// 返回 true = 验证通过（调用方执行 clearLock）；false / null = 取消或验证失败。
/// ============================================================
class AppLockVerifyDialog extends StatefulWidget {
  /// 仅测试使用：替换真实的凭证校验，避免 widget 测试走文件 IO。
  final Future<bool> Function(AppLockType type, String value)? verifyOverride;
  /// 仅测试使用：替换当前锁类型读取。
  final Future<AppLockType>? typeOverride;

  const AppLockVerifyDialog({
    Key? key,
    this.verifyOverride,
    this.typeOverride,
  }) : super(key: key);

  @override
  State<AppLockVerifyDialog> createState() => _AppLockVerifyDialogState();
}

class _AppLockVerifyDialogState extends State<AppLockVerifyDialog> {
  AppLockType _type = AppLockType.password;
  final _ctrl = TextEditingController();
  List<int> _pattern = const [];
  String? _tip;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    final future = widget.typeOverride ?? AppLockStorage.loadType();
    future.then((t) {
      if (mounted) setState(() => _type = t);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _cancel() {
    Haptics.light();
    Navigator.pop<bool>(context, false);
  }

  Future<void> _verify() async {
    final value = _type == AppLockType.password
        ? _ctrl.text.trim()
        : patternToString(_pattern);
    final valid = _type == AppLockType.password
        ? value.isNotEmpty
        : isValidPattern(_pattern);
    if (!valid) {
      setState(() => _tip = _type == AppLockType.password
          ? '请输入当前密码'
          : '请绘制当前手势（至少 4 个点）');
      return;
    }
    setState(() {
      _checking = true;
      _tip = null;
    });
    final ok = widget.verifyOverride != null
        ? await widget.verifyOverride!(_type, value)
        : _type == AppLockType.password
            ? await AppLockStorage.verifyPin(value)
            : await AppLockStorage.verifyPattern(value);
    if (!mounted) return;
    if (ok) {
      Haptics.medium();
      Navigator.pop<bool>(context, true);
    } else {
      setState(() {
        _checking = false;
        _tip = _type == AppLockType.password ? '密码错误，请重试' : '手势错误，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    final accent = AppPalette.accentColor;
    return WillPopScope(
      onWillPop: () async {
        _cancel();
        return false;
      },
      child: AlertDialog(
        key: const ValueKey('app_lock_verify_dialog'),
        backgroundColor: AppPalette.c(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        title: Text('验证隐私锁',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppPalette.c(0xFF24382F))),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('请输入当前解锁凭证以确认关闭。',
                  style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF7C8F86))),
              const SizedBox(height: 12),
              if (_type == AppLockType.password)
                TextField(
                  controller: _ctrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: '当前密码',
                      counterText: '',
                      border: OutlineInputBorder()),
                  onChanged: (_) => setState(() => _tip = null),
                )
              else
                Center(
                  child: PatternLockView(onCompleted: (path) {
                    setState(() {
                      _pattern = path;
                      _tip = null;
                    });
                  }),
                ),
              if (_tip != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_tip!,
                      style: const TextStyle(fontSize: 13, color: Color(0xFFCB5C50))),
                ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        actions: [
          Pressable(
            child: TextButton(
              onPressed: _cancel,
              child: Text('取消',
                  style: TextStyle(color: AppPalette.c(0xFF7C8F86))),
            ),
          ),
          Pressable(
            child: TextButton(
              onPressed: _checking ? null : _verify,
              child: Text(_checking ? '验证中…' : '确认关闭',
                  style: TextStyle(color: accent)),
            ),
          ),
        ],
      ),
    );
  }
}
