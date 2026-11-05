import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/services/app_settings.dart';
import 'package:diary_app/utils/usable_days.dart';

/// 「可使用 x 天」公式的回归测试。
///
/// 公式是产品明确定义的口径，这里逐项钉死：
/// x = (总资产/月消费)×每月天数
/// y = x² / (24 × 每月天数)
/// 天数 = x + y×(年化利率−通胀率)，利率按百分比数值参与（3 表示 3%）
///
/// 手算基准（总资产 100000、月消费 5000、30 天、3%、2%）：
/// x = 20 × 30 = 600
/// y = 600² / (24 × 30) = 360000 / 720 = 500
/// 天数 = 600 + 500 × 1 = 1100
///
/// 关键区别（相对上一版的 (x+y)×利率差）：**只有 y 乘利率差，x 不乘**。
/// 所以利率差为 0 时结果是 x（600）而不是 0，这就是最容易写错的地方。
void main() {
  group('公式严格按字面实现', () {
    test('10万资产 / 月消费5000 → 1100 天', () {
      final d = UsableDays.compute(
        total: 100000,
        monthlyCost: 5000,
        daysPerMonth: 30,
        annualRate: 3,
        inflationRate: 2,
      );
      expect(d, closeTo(1100, 0.01));
    });

    test('x / y / 利率差三个中间量都对', () {
      final s = UsableDays.steps(
        total: 100000,
        monthlyCost: 5000,
        daysPerMonth: 30,
        annualRate: 3,
        inflationRate: 2,
      )!;
      expect(s['x'], closeTo(600, 1e-9));
      expect(s['y'], closeTo(500, 1e-9));
      expect(s['rateDiff'], closeTo(1, 1e-9));
      expect(s['days'], closeTo(1100, 0.01));
    });

    test('利率差为 0 时结果等于 x（不是 0）', () {
      // 上一版公式 (x+y)×利率差 在这里会得到 0，是错的：
      // 本金本身就能支撑 x 天，与利率无关
      final d = UsableDays.compute(
        total: 100000,
        monthlyCost: 5000,
        daysPerMonth: 30,
        annualRate: 2,
        inflationRate: 2,
      );
      expect(d, closeTo(600, 1e-9));
    });

    test('利率差越大，结果越大（x 恒定，只有 y 那部分变动）', () {
      double at(double rate) => UsableDays.compute(
            total: 100000,
            monthlyCost: 5000,
            daysPerMonth: 30,
            annualRate: rate,
            inflationRate: 2,
          )!;
      // 利率差 0 / 1 / 3 → 600 / 1100 / 2100（y = 500）
      expect(at(2), closeTo(600, 1e-9));
      expect(at(3), closeTo(1100, 1e-9));
      expect(at(5), closeTo(2100, 1e-9));
    });

    test('利率差为负时结果小于 x（扣减，但本金部分仍在）', () {
      // x = 600、y = 500、利率差 = -2 → 600 + 500 × (-2) = -400
      final d = UsableDays.compute(
        total: 100000,
        monthlyCost: 5000,
        daysPerMonth: 30,
        annualRate: 1,
        inflationRate: 3,
      );
      expect(d, lessThan(600));
      expect(d, closeTo(-400, 1e-9));
    });

    test('每月天数在 x 的分子、y 的分母中各出现一次', () {
      final d30 = UsableDays.compute(
        total: 60000,
        monthlyCost: 6000,
        daysPerMonth: 30,
        annualRate: 5,
        inflationRate: 2,
      )!;
      final d31 = UsableDays.compute(
        total: 60000,
        monthlyCost: 6000,
        daysPerMonth: 31,
        annualRate: 5,
        inflationRate: 2,
      )!;
      expect(d31, greaterThan(d30));
    });
  });

  group('无法计算的情形一律返回 null', () {
    test('总资产为空（设置里没填）', () {
      expect(
        UsableDays.compute(
          total: null,
          monthlyCost: 5000,
          daysPerMonth: 30,
          annualRate: 3,
          inflationRate: 2,
        ),
        isNull,
      );
    });

    test('月消费为 0：分母为 0，不能算出 Infinity', () {
      final d = UsableDays.compute(
        total: 100000,
        monthlyCost: 0,
        daysPerMonth: 30,
        annualRate: 3,
        inflationRate: 2,
      );
      expect(d, isNull);
    });

    test('总资产为 0 或负数', () {
      for (final t in [0.0, -1.0]) {
        expect(
          UsableDays.compute(
            total: t,
            monthlyCost: 5000,
            daysPerMonth: 30,
            annualRate: 3,
            inflationRate: 2,
          ),
          isNull,
          reason: 'total=$t',
        );
      }
    });

    test('每月天数为 0 或负数', () {
      for (final d in [0.0, -30.0]) {
        expect(
          UsableDays.compute(
            total: 100000,
            monthlyCost: 5000,
            daysPerMonth: d,
            annualRate: 3,
            inflationRate: 2,
          ),
          isNull,
          reason: 'days=$d',
        );
      }
    });
  });

  group('极端数值不产生 NaN / Infinity', () {
    test('超大总资产返回 null 或有限值，绝不是 Infinity', () {
      final d = UsableDays.compute(
        total: 1e308,
        monthlyCost: 1,
        daysPerMonth: 30,
        annualRate: 3,
        inflationRate: 2,
      );
      expect(d == null || d.isFinite, isTrue);
    });

    test('canCompute 与 compute 结论一致', () {
      expect(UsableDays.canCompute(total: 100000, monthlyCost: 5000), isTrue);
      expect(UsableDays.canCompute(total: null, monthlyCost: 5000), isFalse);
      expect(UsableDays.canCompute(total: 100000, monthlyCost: 0), isFalse);
    });
  });

  group('展示格式', () {
    test('数字部分不带单位（看板另有「天」小字）', () {
      expect(UsableDays.format(460), '460');
      expect(UsableDays.formatWithUnit(460), '460 天');
    });

    test('超过 1 万天压缩成「万」，避免长数字挤坏看板', () {
      expect(UsableDays.format(450600), '45.1万');
      expect(UsableDays.format(12000), '1.2万');
      expect(UsableDays.format(10000), '1万');
    });

    test('0 或负数显示 0', () {
      expect(UsableDays.format(0), '0');
      expect(UsableDays.format(-5), '0');
    });

    test('年数换算：365 天 = 1.0 年', () {
      expect(UsableDays.formatYears(365), '1.0 年');
      expect(UsableDays.formatYears(0), '');
    });
  });

  group('设置默认值', () {
    test('默认参数与产品定义一致（预算 3000、30 天、3%、2%）', () {
      // 直接读 AppSettings 的真实默认值，防止实现被悄悄改掉
      expect(AppSettings.usableMonthlyCost, 3000);
      expect(AppSettings.usableDaysPerMonth, 30);
      expect(AppSettings.annualRate, 3);
      expect(AppSettings.inflationRate, 2);
      // 没手填过 → 总资产为空，但会自动回落到净资产
      expect(AppSettings.usableTotal, isNull);
      expect(AppSettings.resolveTotal(netWorthFallback: 88888), 88888);
    });

    test('净资产为负或为 0 时不作为默认总资产', () {
      expect(AppSettings.resolveTotal(netWorthFallback: -1000), isNull);
      expect(AppSettings.resolveTotal(netWorthFallback: 0), isNull);
      expect(AppSettings.resolveTotal(netWorthFallback: null), isNull);
    });
  });

  group('设置持久化格式', () {
    test('参数能完整往返 JSON', () {
      final m = <String, dynamic>{
        'usableTotal': 100000.0,
        'usableMonthlyCost': 5000.0,
        'usableDaysPerMonth': 30.0,
        'annualRate': 3.0,
        'inflationRate': 2.0,
      };
      final back = jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
      expect(back['usableTotal'], 100000.0);
      expect(back['usableMonthlyCost'], 5000.0);
      expect(back['annualRate'], 3.0);
    });

    test('总资产为空时不写入该字段（读回为 null）', () {
      final m = <String, dynamic>{
        'usableMonthlyCost': 5000.0,
        'annualRate': 3.0,
      };
      final back = jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
      expect(back['usableTotal'], isNull);
    });
  });
}
