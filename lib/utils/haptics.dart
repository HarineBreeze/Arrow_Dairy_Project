import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 统一的震动反馈入口。
///
/// 为什么不直接用 HapticFeedback：它走的是 Android View 的
/// `performHapticFeedback`，部分 ROM（含省电模式 / 系统「触感反馈」关闭）
/// 会被静默忽略，表现为「震动没了」。这里改为直接驱动系统 Vibrator，
/// 并保留 HapticFeedback 作为失败时的兜底。
class Haptics {
  static const MethodChannel _ch = MethodChannel('vector_diary/haptic');

  /// 是否可用原生通道（仅 Android）
  static bool get _native => !kIsWeb && Platform.isAndroid;

  /// 轻触：选择、切换、开关等（短 12ms，弱振幅）
  static Future<void> light() async {
    if (await _vibrate(12, 90)) return;
    await HapticFeedback.selectionClick();
  }

  /// 中等：确认删除、保存成功、长按弹窗（24ms，中等振幅）
  static Future<void> medium() async {
    if (await _vibrate(24, 160)) return;
    await HapticFeedback.mediumImpact();
  }

  /// 轻微：滑动到边界、翻页（8ms，弱振幅）
  static Future<void> tick() async {
    if (await _vibrate(8, 70)) return;
    await HapticFeedback.lightImpact();
  }

  /// 同步触发版本：立刻发出震动，不等待原生回执。
  /// 用于「长按弹菜单」这类场景 —— 若先 await 通道往返再弹菜单，
  /// 部分 ROM 会因 UI 已切到新页面/遮罩而丢弃这次振动。
  static void mediumNow() => _fireAndForget(24, 160, medium: true);

  static void lightNow() => _fireAndForget(12, 90);

  static void _fireAndForget(int ms, int amplitude, {bool medium = false}) {
    // 双保险：原生振动（可靠） + Flutter 触感（极端情况下兜底），
    // 两者都是「立即执行、不回调」，不会因为异步等待而错过时机。
    if (_native) {
      _ch.invokeMethod<bool>('vibrate', {'ms': ms, 'amplitude': amplitude});
    }
    if (medium) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  static Future<bool> _vibrate(int ms, int amplitude) async {
    if (!_native) return false;
    try {
      final ok = await _ch.invokeMethod<bool>('vibrate', {
        'ms': ms,
        'amplitude': amplitude,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}
