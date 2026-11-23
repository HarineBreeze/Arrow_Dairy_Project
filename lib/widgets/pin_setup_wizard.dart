import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
import '../utils/haptics.dart';
import 'pressable.dart';

/// ============================================================
/// 通用「设置密码」分步向导（v5.0.3）
///
/// 与隐私锁向导同一套主题化步骤弹窗设计：
///   - 3 步：设置密码 → 确认密码 → 密保（资产页加密访问）
///   - 2 步：设置密码 → 密保（笔记页单篇加密）
/// 任一步取消 / 返回都整体取消，返回 null；不产生半成品。
/// 本组件只收集输入，不落盘；由调用方决定如何保存。
/// ============================================================

class PinSetupResult {
  final String pin;
  final String question;
  final String answer;
  const PinSetupResult({
    required this.pin,
    required this.question,
    required this.answer,
  });
}

/// 资产页：3 步（设置密码 → 确认密码 → 密保）。
Future<PinSetupResult?> showPinSetupWizard3(BuildContext context) =>
    _showWizard(context, confirm: true);

/// 笔记页：2 步（设置密码 → 密保）。
Future<PinSetupResult?> showPinSetupWizard2(BuildContext context) =>
    _showWizard(context, confirm: false);

Future<PinSetupResult?> _showWizard(
  BuildContext context, {
  required bool confirm,
}) async {
  // ignore: use_build_context_synchronously
  final pin = await _showStep<String>(
    context,
    step: 1,
    total: confirm ? 3 : 2,
    title: '设置密码',
    hint: '输入至少 4 位数字密码。',
  );
  if (pin == null) return null;

  if (confirm) {
    // ignore: use_build_context_synchronously
    final again = await _showStep<String>(
      context,
      step: 2,
      total: 3,
      title: '确认密码',
      hint: '请再次输入刚才设置的密码。',
      expected: pin,
    );
    if (again == null) return null;
  }

  // ignore: use_build_context_synchronously
  final security = await _showStep<_SecurityData>(
    context,
    step: confirm ? 3 : 2,
    total: confirm ? 3 : 2,
    title: '设置密保',
    hint: '忘记密码时，可用密保答案找回。',
    security: true,
  );
  if (security == null) return null;
  return PinSetupResult(
    pin: pin,
    question: security.question,
    answer: security.answer,
  );
}

class _SecurityData {
  final String question;
  final String answer;
  const _SecurityData({required this.question, required this.answer});
}

Future<T?> _showStep<T>(
  BuildContext context, {
  required int step,
  required int total,
  required String title,
  required String hint,
  String? expected,
  bool security = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _StepFrame<T>(
      step: step,
      total: total,
      title: title,
      hint: hint,
      expected: expected,
      security: security,
    ),
  );
}

class _StepFrame<T> extends StatelessWidget {
  final int step;
  final int total;
  final String title;
  final String hint;
  final String? expected;
  final bool security;

  const _StepFrame({
    Key? key,
    required this.step,
    required this.total,
    required this.title,
    required this.hint,
    this.expected,
    required this.security,
  }) : super(key: key);

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
        key: ValueKey('pin_setup_step_$step'),
        backgroundColor: AppPalette.c(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$step / $total',
                style: TextStyle(fontSize: 11, color: accent)),
            const SizedBox(height: 4),
            Text(title,
                style: TextStyle(
                    fontSize: 17,
                    color: AppPalette.c(0xFF24382F),
                    fontWeight: FontWeight.w600)),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        content: SingleChildScrollView(
          child: _StepContent<T>(
            hint: hint,
            expected: expected,
            security: security,
            isLast: step == total,
          ),
        ),
      ),
    );
  }
}

class _StepContent<T> extends StatefulWidget {
  final String hint;
  final String? expected;
  final bool security;
  final bool isLast;
  const _StepContent({
    Key? key,
    required this.hint,
    this.expected,
    required this.security,
    required this.isLast,
  }) : super(key: key);

  @override
  State<_StepContent<T>> createState() => _StepContentState<T>();
}

class _StepContentState<T> extends State<_StepContent<T>> {
  final _pin = TextEditingController();
  final _q = TextEditingController(text: '你的生日是几号？');
  final _a = TextEditingController();
  String? _tip;

  @override
  void dispose() {
    _pin.dispose();
    _q.dispose();
    _a.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.security) {
      final value = _pin.text.trim();
      if (value.length < 4) {
        setState(() => _tip = '密码至少 4 位');
        return;
      }
      if (widget.expected != null && value != widget.expected) {
        setState(() => _tip = '两次输入的密码不一致，请重新输入');
        return;
      }
      Navigator.pop<T>(context, value as T);
      return;
    }
    if (_q.text.trim().isEmpty) {
      setState(() => _tip = '请填写密保问题');
      return;
    }
    if (_a.text.trim().isEmpty) {
      setState(() => _tip = '请填写密保答案（必填）');
      return;
    }
    Navigator.pop<T>(
        context,
        _SecurityData(
          question: _q.text.trim(),
          answer: _a.text.trim(),
        ) as T);
  }

  @override
  Widget build(BuildContext context) {
    AppThemeScope.watch(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.hint,
            style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF7C8F86))),
        const SizedBox(height: 12),
        if (!widget.security)
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 12,
            autofocus: true,
            decoration: InputDecoration(
              labelText:
                  widget.expected != null ? '再输入一遍密码' : '密码（至少 4 位）',
              counterText: '',
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() => _tip = null),
          )
        else ...[
          TextField(
            controller: _q,
            maxLength: 30,
            decoration: const InputDecoration(
                labelText: '密保问题',
                counterText: '',
                border: OutlineInputBorder()),
            onChanged: (_) => setState(() => _tip = null),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _a,
            maxLength: 30,
            decoration: const InputDecoration(
                labelText: '密保答案',
                counterText: '',
                border: OutlineInputBorder()),
            onChanged: (_) => setState(() => _tip = null),
          ),
        ],
        if (_tip != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_tip!,
                style: const TextStyle(fontSize: 13, color: Color(0xFFCB5C50))),
          ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Pressable(
              child: TextButton(
                onPressed: () {
                  Haptics.light();
                  Navigator.pop<T>(context);
                },
                child: Text('取消',
                    style: TextStyle(
                        fontSize: 13, color: AppPalette.c(0xFF7C8F86))),
              ),
            ),
            const SizedBox(width: 8),
            Pressable(
              child: TextButton(
                onPressed: _submit,
                child: Text(widget.isLast ? '完成' : '下一步',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppPalette.accentColor,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
