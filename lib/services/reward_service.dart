import '../models/user_profile.dart';
import 'user_storage.dart';

/// 商城商品类型：永久身份牌 / 限时 VIP 日卡 / 限时 VIP 周卡
enum ShopItemKind { badge, vipDayCard, vipWeekCard }

/// 积分商城在售商品
class ShopBadge {
  final String id;
  final String name;
  final int price;
  final ShopItemKind kind;

  /// 商品备注（卡片上的一行小字）
  final String note;

  /// 每人限兑次数（永久牌为 1；VIP日卡 30；VIP周卡 6）
  final int limit;

  /// 限时卡每次兑换累加到 VIP 权益到期时间上的时长（永久牌为 Duration.zero）
  final Duration duration;

  /// 确认框里的「有效期xx」文案
  final String effectLabel;

  const ShopBadge({
    required this.id,
    required this.name,
    required this.price,
    this.kind = ShopItemKind.badge,
    this.note = '',
    this.limit = 1,
    this.duration = Duration.zero,
    this.effectLabel = '',
  });

  /// 是否是「在原剩余时间上累加」的限时 VIP 道具
  bool get isVipTimeCard =>
      kind == ShopItemKind.vipDayCard || kind == ShopItemKind.vipWeekCard;

  /// 该商品在本档案里已兑换的次数
  int usedCount(UserProfile p) {
    if (kind == ShopItemKind.vipDayCard) return p.vipCardCount;
    if (kind == ShopItemKind.vipWeekCard) return p.vipWeekCardCount;
    return p.owns(id) ? 1 : 0;
  }
}

/// 兑换码 / 积分 / 商城的统一入口。
///
/// 规则（产品约定）：
/// - 同一个用户 ID 下，每个兑换码只能使用一次，重复输入返回「已使用过」
///   （用户 ID 即本机档案，记录在 [UserProfile.redeemedCodes] 里）；
/// - 兑换码不区分大小写，前后空格自动忽略；
/// - 积分商城按「已拥有」判重，同一身份牌不重复扣分；
/// - 限时 VIP 道具（日卡 / 周卡）的时长累加到同一个到期时间上，
///   不覆盖原有剩余时间。
class RewardService {
  RewardService._();

  /// 每日首次发布笔记的积分奖励
  static const int dailyWritePoints = 20;

  /// VIP 日卡：每次累加 24 小时，单用户兑换次数上限
  static const Duration vipCardDuration = Duration(hours: 24);
  static const int vipCardMaxCount = 30;

  /// VIP 周卡：每次累加 7 天，单用户兑换次数上限
  static const Duration vipWeekCardDuration = Duration(days: 7);
  static const int vipWeekCardMaxCount = 6;

  /// 积分兑换码 → 积分数量（同一用户每码限用一次）
  static const Map<String, int> pointsCodes = {
    'ayouriji': 100,
  };

  /// 无限次使用的积分兑换码 → 积分数量（不记入已使用列表，可重复兑换）
  static const Map<String, int> unlimitedPointsCodes = {
    '17381113325': 1000,
  };

  /// 无限次使用的「扣分」兑换码 → 扣减数量（不记入已使用列表）。
  /// 用于运营/测试回收积分：每次扣固定分值，积分最低为 0、不会变负。
  static const Map<String, int> unlimitedDeductCodes = {
    '13031210237': 1000,
  };

  /// 兑换码 → 身份牌 id
  static const Map<String, String> badgeCodes = {
    'neice': UserProfile.badgeBeta,
    'vip': UserProfile.badgeVip,
    'zhongshenvip': UserProfile.badgeVipForever,
  };

  /// 积分商城在售商品（永久身份牌 + 限时 VIP 道具）
  static const List<ShopBadge> shopBadges = [
    ShopBadge(
      id: UserProfile.badgeBirthday,
      name: '诞生日-身份牌',
      price: 50,
      note: '纪念APP正式上线，1年后下架',
      limit: 1,
    ),
    ShopBadge(
      id: UserProfile.badgeVip,
      name: 'VIP日卡',
      price: 200,
      kind: ShopItemKind.vipDayCard,
      note: '兑换后可获得VIP权益1日',
      limit: vipCardMaxCount,
      duration: vipCardDuration,
      effectLabel: '有效期24小时',
    ),
    ShopBadge(
      id: 'vipWeekCard',
      name: 'VIP周卡',
      price: 1400,
      kind: ShopItemKind.vipWeekCard,
      note: '兑换后可获得VIP权益7日',
      limit: vipWeekCardMaxCount,
      duration: vipWeekCardDuration,
      effectLabel: '有效期7天',
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

    // 无限次兑换码：不查重、不记录，每次都能兑换
    final unlimited = unlimitedPointsCodes[code];
    if (unlimited != null) {
      profile.points += unlimited;
      await UserStorage.save(profile);
      return RedeemOutcome(true, '兑换成功，+$unlimited 积分');
    }

    // 无限次扣分码：同样不查重、不记录；扣完最低为 0，绝不为负。
    // 提示语里报告「实际扣减」而不是固定值，避免余额不足时显示不实数字。
    final deduct = unlimitedDeductCodes[code];
    if (deduct != null) {
      final before = profile.points;
      profile.points = before > deduct ? before - deduct : 0;
      await UserStorage.save(profile);
      final actual = before - profile.points;
      return RedeemOutcome(true, '兑换成功，-$actual 积分');
    }

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

  /// 用积分兑换永久身份牌：扣分 → 加入已拥有 → 立即佩戴。
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

  /// 用积分兑换限时 VIP 道具（日卡 / 周卡）：
  /// 扣分 → 计次数 → 在当前 VIP 剩余时间基础上累加时长 → 立即佩戴。
  /// VIP 不进已拥有列表（非永久），到期后由档案归一逻辑换回普通版。
  static Future<RedeemOutcome> buyVipCard(String itemId) async {
    final item = shopBadgeOf(itemId);
    if (item == null || !item.isVipTimeCard) {
      return const RedeemOutcome(false, '商品不存在');
    }

    final profile = await UserStorage.load();
    if (item.usedCount(profile) >= item.limit) {
      return RedeemOutcome(false, '已达兑换上限（${item.limit} 次）');
    }
    if (profile.points < item.price) {
      final lack = item.price - profile.points;
      return RedeemOutcome(false, '积分不足，还差 $lack 积分');
    }

    final now = DateTime.now();
    final base = profile.vipCardExpireTime;
    // 剩余时间仍在生效 → 在它基础上累加；已过期 / 从未兑换 → 从现在起算。
    final start = (base != null && base.isAfter(now)) ? base : now;

    profile.points -= item.price;
    profile.vipCardExpireAt = start.add(item.duration).toIso8601String();
    if (item.kind == ShopItemKind.vipWeekCard) {
      profile.vipWeekCardCount += 1;
    } else {
      profile.vipCardCount += 1;
    }
    profile.badge = UserProfile.badgeVip;
    await UserStorage.save(profile);
    final gain = item.kind == ShopItemKind.vipWeekCard ? '7天' : '24小时';
    return RedeemOutcome(true, '兑换成功，VIP有效期增加$gain');
  }

  /// 切换当前佩戴的身份牌（永久拥有的牌随时可切；
  /// VIP 在限时权益生效期间也可切换佩戴）。
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
      case UserProfile.badgeVipForever:
        return '终身VIP';
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
