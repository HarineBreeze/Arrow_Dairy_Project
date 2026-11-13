import '../models/user_profile.dart';
import 'user_storage.dart';

/// 兑换码 / 积分的统一入口。
///
/// 规则（产品约定）：
/// - 每个兑换码在单台设备上只能兑换一次，重复输入返回「已使用过」；
/// - 兑换码不区分大小写，前后空格自动忽略；
/// - 积分用途后续规划，当前只累计余额。
class RewardService {
  RewardService._();

  /// 每日首次发布笔记的积分奖励
  static const int dailyWritePoints = 20;

  /// 积分兑换码 → 积分数量
  static const Map<String, int> pointsCodes = {
    'ayouriji': 100,
  };

  /// 铭牌兑换码 → 铭牌 id
  static const Map<String, String> badgeCodes = {
    'neice': UserProfile.badgeBeta,
    'vip': UserProfile.badgeVip,
  };

  /// 兑换结果。message 直接用于 AppToast 提示。
  static Future<RedeemOutcome> redeem(String rawCode) async {
    final code = rawCode.trim().toLowerCase();
    if (code.isEmpty) return const RedeemOutcome(false, '请输入兑换码');

    final profile = await UserStorage.load();
    if (profile.redeemedCodes.contains(code)) {
      return const RedeemOutcome(false, '该兑换码已使用过');
    }

    final points = pointsCodes[code];
    if (points != null) {
      profile.points += points;
      profile.redeemedCodes.add(code);
      await UserStorage.save(profile);
      return RedeemOutcome(true, '兑换成功，+$points 积分');
    }

    final badge = badgeCodes[code];
    if (badge != null) {
      profile.badge = badge;
      profile.redeemedCodes.add(code);
      await UserStorage.save(profile);
      return RedeemOutcome(
        true,
        badge == UserProfile.badgeVip
            ? '兑换成功，已获得「VIP」铭牌'
            : '兑换成功，已获得「内测版」铭牌',
      );
    }

    return const RedeemOutcome(false, '兑换码无效，请检查后重试');
  }

  /// 每日首次发布笔记：领取 20 积分。
  ///
  /// 返回实际获得的积分（当天已领过 / 读写失败返回 0）。
  /// 任何异常都吞掉 —— 积分是附加激励，不能影响笔记保存本身。
  static Future<int> awardDailyWrite() async {
    try {
      final today = _dayKey(DateTime.now());
      final profile = await UserStorage.load();
      if (profile.lastWriteReward == today) return 0;
      profile.points += dailyWritePoints;
      profile.lastWriteReward = today;
      await UserStorage.save(profile);
      return dailyWritePoints;
    } catch (_) {
      return 0;
    }
  }

  static String _dayKey(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }
}

class RedeemOutcome {
  final bool ok;
  final String message;
  const RedeemOutcome(this.ok, this.message);
}
