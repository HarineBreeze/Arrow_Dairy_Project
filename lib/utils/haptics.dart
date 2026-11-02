import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 统一的震动反馈入口。
///
/// ## 为什么不用 HapticFeedback 作为主路径
/// `HapticFeedback` 走的是 Android View 的 `performHapticFeedback`，
/// 依赖「系统触感反馈」开关与当前窗口的 `hapticFeedbackEnabled`。
/// 部分 ROM（含省电模式、系统「触感反馈」关闭、窗口被遮罩替换）
/// 会静默忽略它，表现为「震动没了」。所以主路径直接驱动系统 Vibrator。
///
/// ## 关键教训：不要同时发两次振动
/// `Vibrator.vibrate()` 每收到一次新请求，就会 **取消正在进行的振动**。
/// 早期实现为了「双保险」同时调用原生 Vibrator 和 HapticFeedback，
/// 两次请求间隔只有几微秒，后一次把前一次打断；而 HapticFeedback
/// 本身又可能被系统忽略 —— 结果就是一次都震不出来。
///
/// 现在改为 **单一来源**：Android 只走原生 Vibrator，失败才退回
/// HapticFeedback；并且同一时刻只保留一个未完成的请求。
class Haptics {
  static const MethodChannel _ch = MethodChannel('vector_diary/haptic');

  /// 最近一次震动的时间，用于丢弃「同一瞬间的重复请求」。
  ///
  /// 列表快速滑动、连续点击时，手指会产生一串几何级数的触发，
  /// 每次都发振动会让马达来不及起振，听感上反而是「没震」。
  static DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 两次震动之间的最小间隔。小于它的重复请求直接丢弃。
  static const Duration _minGap = Duration(milliseconds: 40);

  /// 是否启用节流（测试里关掉，避免用例之间互相吞掉请求）
  static bool throttleEnabled = true;

  /// 仅用于测试：重置节流状态
  @visibleForTesting
  static void resetThrottle() {
    _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// 轻触：选择、切换、开关等（短 12ms，弱振幅）
  static Future<void> light() async {
    if (!_accept()) return;
    if (await _vibrate(12, 90)) return;
    await _fallback(medium: false);
  }

  /// 中等：确认删除、保存成功、长按弹窗（24ms，中等振幅）
  static Future<void> medium() async {
    if (!_accept()) return;
    if (await _vibrate(24, 160)) return;
    await _fallback(medium: true);
  }

  /// 轻微：滑动到边界、翻页（8ms，弱振幅）
  static Future<void> tick() async {
    if (!_accept()) return;
    if (await _vibrate(8, 70)) return;
    await _fallback(medium: false);
  }

  /// 同步触发版本：立刻发出震动，不等待原生回执。
  ///
  /// 用于「长按弹菜单」这类场景 —— 若先 await 通道往返再弹菜单，
  /// 部分 ROM 会因 UI 已切到新页面/遮罩而丢弃这次振动。
  static void mediumNow() {
    if (!_accept()) return;
    _fireAndForget(24, 160, medium: true);
  }

  static void lightNow() {
    if (!_accept()) return;
    _fireAndForget(12, 90, medium: false);
  }

  /// 统一的节流判定：太密的请求直接丢弃。
  static bool _accept() {
    if (!throttleEnabled) return true;
    final now = DateTime.now();
    if (now.difference(_lastAt) < _minGap) return false;
    _lastAt = now;
    return true;
  }

  static void _fireAndForget(int ms, int amplitude, {required bool medium}) {
    // 不在这里判断平台：直接尝试原生通道，通道不存在（非 Android、
    // 测试环境、引擎未就绪）时 catchError 会自动退回 HapticFeedback。
    // 这样「平台判断」只剩一处（Channel 是否可用），测试也能覆盖主路径。
    if (kIsWeb) {
      _fallback(medium: medium);
      return;
    }
    try {
      _ch
          .invokeMethod<bool>('vibrate', {'ms': ms, 'amplitude': amplitude})
          .then((ok) {
        if (ok != true) _fallback(medium: medium);
      }).catchError((Object _) {
        _fallback(medium: medium);
      });
    } catch (_) {
      _fallback(medium: medium);
    }
  }

  static Future<void> _fallback({required bool medium}) async {
    try {
      if (medium) {
        await HapticFeedback.mediumImpact();
      } else {
        await HapticFeedback.selectionClick();
      }
    } catch (_) {
      // 系统完全不支持触感反馈：静默跳过，不向上抛
    }
  }

  static Future<bool> _vibrate(int ms, int amplitude) async {
    if (kIsWeb) return false;
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

  /// 振动自检：读取原生侧报告的设备振动状态。
  ///
  /// 返回字段：
  /// - `hasVibrator` 是否有振动马达（平板/模拟器常为 false）
  /// - `hasAmplitudeControl` 是否支持振幅控制（仅 Android 8+）
  /// - `powerSaveMode` 是否处于省电模式（true 时系统禁用振动）
  /// - `ringerMode` 0=静音 1=振动 2=正常
  /// - `sdkInt` Android 版本号
  ///
  /// 通道未注册 / 调用失败时返回 null。
  static Future<Map<String, dynamic>?> diagnose() async {
    if (kIsWeb) return null;
    try {
      final raw = await _ch.invokeMethod<Map>('diagnose');
      return raw?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
}
