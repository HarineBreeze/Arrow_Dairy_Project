import 'dart:math' as math;

/// 资产看板「可使用 x 天」的计算规则。
///
/// ## 公式（按产品定义，严格照此实现）
/// ```
/// x = (总资产 / 月消费) × 每月天数
/// y = x² / (24 × 每月天数)
/// 可使用天数 = x + y × (年化利率 - 通胀率)
/// ```
///
/// 注意三点，写错任何一个都会让结果明显偏离预期：
/// 1. 只有 **y** 乘利率差，x 不乘。利率差为 0 时结果应等于 x
///    （本金能支撑的天数），而不是 0。
/// 2. y 的分母是 **(24 × 每月天数)**，不是 24。写成 24 会让 y 大约
///    大出「每月天数」倍。
/// 3. 年化利率与通胀率以**百分比数值**传入（3 表示 3%），但参与运算时
///    必须换算成小数（÷100）。界面标着 `%` 就意味着 5% = 0.05 ——
///    直接拿 5 去乘，等于按 500% 的收益率放大，结果会差 100 倍。
///    换算在 [compute] 内部完成，调用方仍只需传界面上的数字。
///
/// ## 为什么单独抽出来
/// 这是纯数值计算，抽成纯函数后可以精确覆盖边界：总资产为空、
/// 月消费为 0、利率不大于通胀、极端大数溢出等 —— 这些在 UI 上很难逐一验证。
class UsableDays {
  UsableDays._();

  /// 参数是否足够计算：总资产 > 0 且月消费 > 0。
  ///
  /// 月消费为 0 时做分母会得到 Infinity，必须在入口拦住。
  static bool canCompute({
    required double? total,
    required double monthlyCost,
  }) {
    if (total == null) return false;
    if (!total.isFinite || total <= 0) return false;
    if (!monthlyCost.isFinite || monthlyCost <= 0) return false;
    return true;
  }

  /// 核心计算。返回 null 表示无法计算（参数缺失或非法）。
  ///
  /// [annualRate] / [inflationRate] 传**百分比数值**（3 = 3%），
  /// 内部会 ÷100 换算成小数再参与运算。
  /// [daysPerMonth] 传 0 或负数视为参数非法。
  static double? compute({
    required double? total,
    required double monthlyCost,
    required double daysPerMonth,
    required double annualRate,
    required double inflationRate,
  }) {
    if (!canCompute(total: total, monthlyCost: monthlyCost)) return null;
    if (!daysPerMonth.isFinite || daysPerMonth <= 0) return null;

    final t = total!;
    final x = (t / monthlyCost) * daysPerMonth;
    final y = (x * x) / (24 * daysPerMonth);
    // 百分数换算成小数：5% - 2% = 0.03，而不是 3。
    // 只让 y 乘利率差：x 是本金的直接支撑天数，不受利率影响。
    final rateDiff = (annualRate - inflationRate) / 100;
    final days = x + y * rateDiff;

    if (!days.isFinite) return null;
    return days;
  }

  /// 数字部分（不含「天」），用于看板大字显示，与净资产同一排版。
  ///
  /// 不足 1 天显示 0；超过 1 万天压缩成「1.2万」，
  /// 否则「43964」这种长度会撑破看板。
  static String format(double days) {
    if (!days.isFinite || days <= 0) return '0';
    if (days >= 10000) {
      final w = days / 10000;
      return '${_trim(w.toStringAsFixed(w >= 100 ? 0 : 1))}万';
    }
    return days.round().toString();
  }

  /// 带单位的完整文本（弹窗预览、无障碍朗读用）
  static String formatWithUnit(double days) =>
      (days.isFinite && days > 0) ? '${format(days)} 天' : '0 天';

  /// 去掉多余的小数尾巴：2.0 → 2，2.50 → 2.5
  static String _trim(String s) {
    if (!s.contains('.')) return s;
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// 按天数换算成年，用于小字说明（保留 1 位小数）
  static String formatYears(double days) {
    if (!days.isFinite || days <= 0) return '';
    final years = days / 365;
    if (!years.isFinite || years > 9999) return '';
    return '${years.toStringAsFixed(1)} 年';
  }

  /// 自检用：返回 x、y、利率差（已换算成小数）、结果四个中间量
  static Map<String, double>? steps({
    required double? total,
    required double monthlyCost,
    required double daysPerMonth,
    required double annualRate,
    required double inflationRate,
  }) {
    final d = compute(
      total: total,
      monthlyCost: monthlyCost,
      daysPerMonth: daysPerMonth,
      annualRate: annualRate,
      inflationRate: inflationRate,
    );
    if (d == null) return null;
    final x = (total! / monthlyCost) * daysPerMonth;
    final y = (x * x) / (24 * daysPerMonth);
    return {
      'x': x,
      'y': y,
      // 与 compute 同口径：小数，不是百分数
      'rateDiff': (annualRate - inflationRate) / 100,
      'days': d,
    };
  }

  /// 数值是否异常（用来提示用户检查输入，而不是显示一个怪数字）
  static bool isSuspicious(double days) =>
      !days.isFinite || days > math.pow(10, 9);
}
