import '../models/user_profile.dart';
import 'user_storage.dart';

/// 商城商品类型：永久身份牌 / 限时 VIP 日卡
enum ShopItemKind { badge, vipDayCard }

/// 积分商城在售商品
class ShopBadge {
  final String id;
  final String name;
  final int price;
  final ShopItemKind kind;

  /// 商品说明（卡片上的一行小字，空 = 不显示）
  final String desc;

  const ShopBadge({
    required this.id,
    required this.name,
    required this.price,
    this.kind = ShopItemKind.badge,
    this.desc = '',
  });
}

/// 兑换码 / 积分 / 商城的统一入口。
///
/// 规则（产品约定）：
/// - 同一个用户 ID 下，每个兑换码只能使用一次，重复输入返回「已使用过」
///   （用户 ID 即本机档案，记录在 [UserProfile.redeemedCodes] 里）；
/// - 兑换码不区分大小写，前后空格自动忽略；
/// - 积分商城按「已拥有」判重，同一身份牌不重复扣分。
class RewardService {
  RewardService._();

  /// 每日首次发布笔记的积分奖励
  static const int dailyWritePoints = 20;

  /// VIP 日卡：有效期与单用户兑换次数上限
  static const Duration vipCardDuration = Duration(hours: 24);
  static const int vipCardMaxCount = 30;

  /// 积分兑换码 → 积分数量
  static const Map<String, int> pointsCodes = {
    'ayouriji': 100,
  };

  /// 兑换码 → 身份牌 id
  static const Map<String, String> badgeCodes = {
    'neice': UserProfile.badgeBeta,
    'vip': UserProfile.badgeVip,
  };

  /// 积分商城在售商品（身份牌 + 限时卡）
  static const List<ShopBadge> shopBadges = [
    ShopBadge(
      id: UserProfile.badgeBirthday,
      name: '诞生日',
      price: 50,
    ),
    ShopBadge(
      id: UserProfile.badgeVip,
      name: 'VIP日卡',
      price: 200,
      kind: ShopItemKind.vipDayCard,
      desc: '兑换后立即生效，24小时内佩戴VIP身份牌',
    ),
  ];

  /// 按 id 取在售商品（不在售返回 null）
  static ShopBadge? shopBadgeOf(String id) {
    for (final item in shopBadges) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// 兑换码兑换。message 直接用于 AppToast 提示。
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
      if (!profile.ownedBadges.contains(badge)) profile.ownedBadges.add(badge);
      profile.redeemedCodes.add(code);
      await UserStorage.save(profile);
      final name = _badgeName(badge);
      return RedeemOutcome(true, '兑换成功，已获得「$name」身份牌');
    }

    return const RedeemOutcome(false, '兑换码无效，请检查后重试');
  }

  /// 用积分兑换身份牌：扣分 → 加入已拥有 → 立即佩戴。
  static Future<RedeemOutcome> buyBadge(String badgeId) async {
    final item = shopBadgeOf(badgeId);
    if (item == null) return const RedeemOutcome(false, '商品不存在');

    final profile = await UserStorage.load();
    if (profile.owns(badgeId)) {
      return const RedeemOutcome(false, '已拥有该身份牌');
    }
    if (profile.points < item.price) {
      final lack = item.price - profile.points;
      return RedeemOutcome(false, '积分不足，还差 $lack 积分');
    }

    profile.points -= item.price;
    profile.ownedBadges.add(badgeId);
    profile.badge = badgeId;
    await UserStorage.save(profile);
    return RedeemOutcome(true, '兑换成功，已佩戴「${item.name}」身份牌');
  }

  /// 用积分兑换 VIP 日卡：扣分 → 计次数 → 记 24 小时到期时间 → 立即佩戴。
  /// VIP 不进已拥有列表（非永久），到期后由档案归一逻辑换回普通版。
  static Future<RedeemOutcome> buyVipCard(String badgeId) async {
    final item = shopBadgeOf(badgeId);
    if (item == null || item.kind != ShopItemKind.vipDayCard) {
      return const RedeemOutcome(false, '商品不存在');
    }

    final profile = await UserStorage.load();
    if (profile.vipCardCount >= vipCardMaxCount) {
      return const RedeemOutcome(false, '已达兑换上限（$vipCardMaxCount 次）');
    }
    if (profile.points < item.price) {
      final lack = item.price - profile.points;
      return RedeemOutcome(false, '积分不足，还差 $lack 积分');
    }

    profile.points -= item.price;
    profile.vipCardCount += 1;
    profile.vipCardExpireAt =
        DateTime.now().add(vipCardDuration).toIso8601String();
    profile.badge = UserProfile.badgeVip;
    await UserStorage.save(profile);
    return RedeemOutcome(true, '兑换成功，VIP身份牌生效24小时');
  }

  /// 切换当前佩戴的身份牌（永久拥有的牌随时可切；
  /// VIP 在日卡生效期间也可切换佩戴）。
  static Future<RedeemOutcome> wearBadge(String badgeId) async {
    final profile = await UserStorage.load();
    final canWear = profile.owns(badgeId) ||
        (badgeId == UserProfile.badgeVip && profile.vipCardActive);
    if (!canWear) {
      return const RedeemOutcome(false, '尚未拥有该身份牌');
    }
    if (profile.badge == badgeId) {
      return const RedeemOutcome(false, '已是当前身份牌');
    }
    profile.badge = badgeId;
    await UserStorage.save(profile);
    return RedeemOutcome(true, '已切换为「${_badgeName(badgeId)}」');
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

  static String _badgeName(String id) {
    // 兑换码获得的牌用固定名，避免被商城里的「VIP日卡」商品名顶掉
    switch (id) {
      case UserProfile.badgeBeta:
        return '内测版';
      case UserProfile.badgeVip:
        return 'VIP';
    }
    for (final item in shopBadges) {
      if (item.id == id) return item.name;
    }
    return '普通版';
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
