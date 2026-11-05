import 'dart:math' as math;

/// 资产看板「可使用 x 天」的计算规则。
///
/// ## 公式（按产品定义，严格照此实现）
/// ```
/// x = (总资产 / 月消费) × 每月天数
/// y = (x² / 24) × 每月天数
/// 可使用天数 = (x + y) × (年化利率 - 通胀率)
/// ```
///
/// 其中年化利率与通胀率以**百分比数值**参与运算（3 表示 3%，
/// 即 (3 - 2) = 1），不是小数。这是产品明确定义的口径，不要「修正」成
/// 0.01 —— 那会让结果差 100 倍。
///
/// ## 为什么单独抽出来
/// 这是纯数值计算，抽成纯函数后可以精确覆盖边界：
/// 总资产为空、月消费为 0、利率不大于通胀（结果为 0 或负）、
/// 极端大数溢出等 —— 这些在 UI 上很难逐一验证。
class UsableDays {
  UsableDays._();

  /// 月消费为 0（或负数）时无法计算：分母为 0 会得到 Infinity
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
  /// [annualRate] / [inflationRate] 是百分比数值（3 = 3%）。
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
    final y = (x * x / 24) * daysPerMonth;
    final days = (x + y) * (annualRate - inflationRate);

    if (!days.isFinite) return null;
    return days;
  }

  /// 展示用文本：不足 1 天显示 0，超过 1 万天用「万天」压缩，
  /// 避免「43964 天」这种长数字把看板挤变形。
  static String format(double days) {
    if (!days.isFinite || days <= 0) return '0 天';
    if (days >= 10000) {
      final w = days / 10000;
      return '${w.toStringAsFixed(w >= 100 ? 0 : 1)} 万天';
    }
    return '${days.round()} 天';
  }

  /// 按天数换算成年，用于下方小字说明（保留 1 位小数）
  static String formatYears(double days) {
    if (!days.isFinite || days <= 0) return '';
    final years = days / 365;
    if (!years.isFinite || years > 9999) return '';
    return '${years.toStringAsFixed(1)} 年';
  }

  /// 调试/自检用：返回 x、y、结果三个中间量
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
    final y = (x * x / 24) * daysPerMonth;
    return {
      'x': x,
      'y': y,
      'rateDiff': annualRate - inflationRate,
      'days': d,
    };
  }

  /// 平方根等极端值保护：供 UI 侧判断是否需要显示「数值异常」
  static bool isSuspicious(double days) =>
      !days.isFinite || days > math.pow(10, 9);
}
