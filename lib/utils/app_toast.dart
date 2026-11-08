import 'dart:async';

import 'package:flutter/material.dart';

/// 全局去重提示（Toast）。
///
/// 问题背景：编辑页点「完成」时若校验不通过（如物品名称没填），
/// 每次点击都会弹一条提示。用户着急时会连点，
/// 于是提示一条接一条地排队/刷新，屏幕底部反复闪同一句话，观感很差。
///
/// 这里的策略：
/// - **同一句提示在展示期内只弹一次**：如果当前正要展示的提示与屏幕上
///   正在显示的那条内容一致，直接忽略（不重新弹、也不续命）；
/// - 不同内容的提示立即替换旧的（比如先提示「名称不能为空」，
///   补填后又提示「请选择日期」，应该马上换成新内容）；
/// - 记录展示期结束时间，期间内重复调用一律吞掉 —— 即使宿主页面
///   重建，也不会因为「看起来没了」而再弹一次；
/// - 展示期一过立即清空记录，保证之后同类提示还能正常再弹（不会永久静音）。
///
/// 呈现方式：**模态底部抽屉** —— 带半透明遮罩，从下至上滑入，
/// 停留 [kDuration] 后自动收回；点遮罩、点提示本身都会提前关闭。
class AppToast {
  AppToast._();

  /// 当前提示的文案标签（用于去重）
  static String? _current;

  /// 当前提示应当消失的时间点（到点前一律视为「还在显示」）
  static DateTime? _until;

  /// 当前打开抽屉的关闭动作（内容变化 / clear 时调用）。
  /// 抽屉一旦因任何原因关闭（含自动到点）即被置空，重复调用是 no-op。
  static void Function()? _dismiss;

  /// 自动收回的定时器：抽屉提前关闭时取消，避免留下无效回弹
  static Timer? _autoTimer;

  /// 提示停留时长。校验类提示只需一眼就能读完，久留反而挡视线。
  static const Duration kDuration = Duration(milliseconds: 1600);

  /// 显示一条去重提示（模态底部抽屉）。
  ///
  /// [key] 用于区分「同一类提示」，默认用文案本身。
  /// 例如「请填写事件名称」与「请填写物品名称」是两条不同提示，
  /// 会互相替换；而连续两次「请填写物品名称」只会显示一次。
  static void show(
    BuildContext context,
    String message, {
    String? key,
    Duration duration = kDuration,
  }) {
    final tag = key ?? message;
    final now = DateTime.now();

    // 1) 展示期已过 → 清空记录，让判断回到干净状态。
    if (_until != null && !now.isBefore(_until!)) {
      _current = null;
      _until = null;
    }

    // 2) 同一句提示仍在展示期 → 直接忽略。
    //    这就是「反复点完成不要反复弹」的核心：不新建、不刷新、不续命。
    if (_current == tag && _until != null && now.isBefore(_until!)) return;

    _current = tag;
    _until = now.add(duration);

    // 3) 内容变了 → 关掉旧抽屉再弹新的（不排队，底部只留一句话）。
    final dismissOld = _dismiss;
    _dismiss = null;
    dismissOld?.call();

    try {
      // useRootNavigator：抽屉盖在最顶层，不被宿主页面的局部 Navigator 影响
      final future = showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        // 半透明遮罩：点遮罩即可提前关闭
        barrierColor: Colors.black26,
        isDismissible: true,
        enableDrag: false,
        builder: (sheetCtx) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Material(
              color: const Color(0xFF24382F),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(sheetCtx).pop(),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(18, 15, 18,
                      15 + MediaQuery.of(sheetCtx).padding.bottom),
                  child: Text(
                    message,
                    style: const TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: Colors.white,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ),
          );
        },
      );

      // 关闭动作：只对 root navigator 的这一条路由生效。
      // whenComplete 先把 _dismiss 置空（防重复 pop 弹掉别的页面），
      // 再释放去重记录，让后续同类提示能再次弹出。
      final sheetCtx = context;
      _dismiss = () {
        _dismiss = null;
        try {
          final nav = Navigator.of(sheetCtx, rootNavigator: true);
          if (nav.canPop()) nav.pop();
        } catch (_) {}
      };

      future.whenComplete(() {
        _autoTimer?.cancel();
        _autoTimer = null;
        _dismiss = null;
        if (_current == tag) {
          _current = null;
          _until = null;
        }
      });

      // 到点自动收回
      _autoTimer?.cancel();
      _autoTimer = Timer(duration, () => _dismiss?.call());
    } catch (_) {
      // context 已随页面销毁：提示自然不弹，忽略
      _dismiss = null;
    }
  }

  /// 立即清掉（页面销毁、或校验提示需要立刻消失时用）
  static void clear() {
    _current = null;
    _until = null;
    _autoTimer?.cancel();
    _autoTimer = null;
    final d = _dismiss;
    _dismiss = null;
    d?.call();
  }

  /// 仅供测试：把「当前提示」标记成已经展示完毕，
  /// 用来验证「提示消失后还能再次弹出」（测试里时间不会自动流逝）。
  @visibleForTesting
  static void markExpiredForTest() => _until = null;

  /// 仅供测试：重置去重状态
  @visibleForTesting
  static void resetForTest() => clear();
}
