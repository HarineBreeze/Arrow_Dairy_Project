import 'package:flutter/material.dart';

/// 全局去重提示（Toast）。
///
/// 问题背景：编辑页点「完成」时若校验不通过（如物品名称没填），
/// 每次点击都会 `showSnackBar` 一条。用户着急时会连点，
/// 于是提示一条接一条地排队/刷新，屏幕底部反复闪同一句话，观感很差。
///
/// 这里的策略：
/// - **同一句提示在展示期内只弹一次**：如果当前正要展示的提示与屏幕上
///   正在显示的那条内容一致，直接忽略（不重新弹、也不续命）；
/// - 不同内容的提示立即替换旧的（比如先提示「名称不能为空」，
///   补填后又提示「请选择日期」，应该马上换成新内容）；
/// - 记录展示期结束时间，期间内重复调用一律吞掉 —— 即使宿主页面
///   重建、SnackBar 被其它队列挤掉，也不会因为「看起来没了」而再弹一次；
/// - 展示期一过立即清空记录，保证之后同类提示还能正常再弹（不会永久静音）。
///
/// 实现上有个坑：**不要**在每次调用前都 `hideCurrentSnackBar`。
/// 那条「收起」指令会留在 messenger 的收尾状态里，紧接着弹出的新提示
/// 会被它自己吞掉，表现为「第一次有提示，之后再也不出现」。
/// 因此收起动作只发生在「内容确实变了」这一次，正常连点直接 return，
/// 根本不碰 messenger。
class AppToast {
  AppToast._();

  /// 当前提示的完整文案（含动作按钮，便于区分「同文案不同按钮」）
  static String? _current;

  /// 当前提示应当消失的时间点（到点前一律视为「还在显示」）
  static DateTime? _until;

  /// 提示停留时长。比 SnackBar 默认 4s 短一些：
  /// 校验类提示只需一眼就能读完，久留反而挡视线。
  static const Duration kDuration = Duration(milliseconds: 1600);

  /// 显示一条去重提示。
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
    //    少了这一步，提示早就消失了记录还在，同一句提示会**永远不再出现**。
    if (_until != null && !now.isBefore(_until!)) {
      _current = null;
      _until = null;
    }

    // 2) 同一句提示仍在展示期 → 直接忽略。
    //    这就是「反复点完成不要反复弹」的核心：不新建、不刷新、不续命。
    if (_current == tag && _until != null && now.isBefore(_until!)) return;

    // 3) 内容变了 → 清掉旧的再弹新的（不排队，屏幕底部只留一句话）。
    //
    //    踩过的坑：`hideCurrentSnackBar` 不能和随后的 `showSnackBar` 连着用，
    //    那条「收起」指令会留在 messenger 里，把紧接着的新提示吞掉
    //    （表现为「第一次有提示，之后再也不出现」）。这里改用 `clearSnackBars()`，
    //    且只在内容真的变化时执行 —— 正常连点都在第 2 步 return，根本不碰它。
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final hadOld = _current != null;
    _current = tag;
    _until = now.add(duration);

    if (hadOld) {
      try {
        messenger.clearSnackBars();
      } catch (_) {
        // messenger 已随页面销毁：提示自然随界面消失，忽略
      }
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// 立即清掉（页面销毁、或校验提示需要立刻消失时用）
  static void clear() {
    _current = null;
    _until = null;
  }

  /// 仅供测试：把「当前提示」标记成已经展示完毕，
  /// 用来验证「提示消失后还能再次弹出」（测试里时间不会自动流逝）。
  @visibleForTesting
  static void markExpiredForTest() => _until = null;

  /// 仅供测试：重置去重状态
  @visibleForTesting
  static void resetForTest() => clear();
}
