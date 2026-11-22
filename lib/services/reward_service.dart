import '../models/user_profile.dart';
import 'user_storage.dart';

/// 杂货店商品类型：永久身份 / 限时 VIP 日卡 / 限时 VIP 周卡
enum ShopItemKind { badge, vipDayCard, vipWeekCard }

/// 首次新增奖励的类别（事件 / 物品 / 资产，各仅 1 次）
enum FirstAddKind { event, item, asset }

/// 灵感杂货店在售商品
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

/// 兑换码 / 灵感 / 杂货店的统一入口。
///
/// 规则（产品约定）：
/// - 同一个用户 ID 下，每个兑换码只能使用一次，重复输入返回「已使用过」
///   （用户 ID 即本机档案，记录在 [UserProfile.redeemedCodes] 里）；
/// - 兑换码不区分大小写，前后空格自动忽略；
/// - 灵感杂货店按「已拥有」判重，同一身份不重复扣分；
/// - 限时 VIP 道具（日卡 / 周卡）的时长累加到同一个到期时间上，
///   不覆盖原有剩余时间。
class RewardService {
  RewardService._();

  /// 每日首次发布笔记的灵感奖励
  static const int dailyWritePoints = 20;

  /// 首次新增事件 / 物品 / 资产的灵感奖励（每类仅 1 次）
  static const int firstAddPoints = 20;

  /// 写作里程碑：日记总数首次达到这些篇数时各奖励一次。
  /// 顺序固定（供特效按篇数取文案），判重靠 [UserProfile.claimedWriteMilestones]。
  static const List<int> writeMilestones = <int>[7, 30, 100, 200, 365, 500, 1000];

  /// 每个写作里程碑达成时奖励的灵感
  static const int milestonePoints = 20;

  /// VIP 日卡：每次累加 24 小时，单用户兑换次数上限
  static const Duration vipCardDuration = Duration(hours: 24);
  static const int vipCardMaxCount = 30;

  /// VIP 周卡：每次累加 7 天，单用户兑换次数上限
  static const Duration vipWeekCardDuration = Duration(days: 7);
  static const int vipWeekCardMaxCount = 6;

  /// 灵感兑换码 → 点数量（同一用户每码限用一次）
  static const Map<String, int> pointsCodes = {
    'ayouriji': 100,
  };

  /// 无限次使用的灵感兑换码 → 点数量（不记入已使用列表，可重复兑换）
  static const Map<String, int> unlimitedPointsCodes = {
    '17381113325': 1000,
  };

  /// 无限次使用的「扣分」兑换码 → 扣减数量（不记入已使用列表）。
  /// 用于运营/测试回收灵感：每次扣固定分值，灵感最低为 0、不会变负。
  static const Map<String, int> unlimitedDeductCodes = {
    '13031210237': 1000,
  };

  /// 无限次使用的「清除会员身份」兑换码。
  /// 使用后移除非普通版身份牌与 VIP 权益，并返还杂货店里非 VIP 身份牌的兑换次数。
  static const String noVipCode = 'novip';

  /// 兑换码 → 身份 id（限 1 次，写 redeemedCodes）
  ///
  /// v4.9.50：内测用的 3 个身份码改为不限次，移到 [unlimitedBadgeCodes]，
  /// 方便反复切换身份测试权益；本表保留给未来可能新增的限次身份码。
  static const Map<String, String> badgeCodes = <String, String>{};

  /// 不限次使用的身份兑换码（不查重、不写 redeemedCodes，可反复兑换）。
  /// 内测期间 vip / zhongshenvip / neice 随时可反复领取并立即佩戴。
  static const Map<String, String> unlimitedBadgeCodes = {
    'neice': UserProfile.badgeBeta,
    'vip': UserProfile.badgeVip,
    'zhongshenvip': UserProfile.badgeVipForever,
  };

  /// 灵感杂货店在售商品（永久身份 + 限时 VIP 道具）
  static const List<ShopBadge> shopBadges = [
    ShopBadge(
      id: UserProfile.badgeBirthday,
      name: '诞生日-身份',
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
      effectLabel: '有效期1天',
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
      return RedeemOutcome(true, '兑换成功，+$unlimited 点');
    }

    // 无限次扣分码：同样不查重、不记录；扣完最低为 0，绝不为负。
    // 提示语里报告「实际扣减」而不是固定值，避免余额不足时显示不实数字。
    final deduct = unlimitedDeductCodes[code];
    if (deduct != null) {
      final before = profile.points;
      profile.points = before > deduct ? before - deduct : 0;
      await UserStorage.save(profile);
      final actual = before - profile.points;
      return RedeemOutcome(true, '兑换成功，-$actual 点');
    }

    // 无限次「清除会员身份」码：不查重、不记录，每次都能用。
    // 移除非普通版身份牌 + VIP 权益；杂货店里的次数随计数清零自然返还。
    if (code == noVipCode) {
      final removed = profile.ownedBadges
          .where((b) => b != UserProfile.badgeNormal)
          .toList();
      profile.ownedBadges = [UserProfile.badgeNormal];
      if (profile.badge != UserProfile.badgeNormal) {
        profile.badge = UserProfile.badgeNormal;
      }
      profile.vipCardExpireAt = '';
      profile.vipCardCount = 0;
      profile.vipWeekCardCount = 0;
      await UserStorage.save(profile);
      final msg = removed.isEmpty
          ? '已是普通版，无需清除'
          : '已清除身份与会员权益：${removed.map(_badgeName).join('、')}';
      return RedeemOutcome(true, msg);
    }

    // 不限次身份码：不查重、不记录，每次都能兑换并立即佩戴。
    // 放在查重之前，避免内测期间这些码被历史记录挡住。
    final unlimitedBadge = unlimitedBadgeCodes[code];
    if (unlimitedBadge != null) {
      profile.badge = unlimitedBadge;
      if (!profile.ownedBadges.contains(unlimitedBadge)) {
        profile.ownedBadges.add(unlimitedBadge);
      }
      await UserStorage.save(profile);
      final name = _badgeName(unlimitedBadge);
      return RedeemOutcome(true, '兑换成功，已获得「$name」身份');
    }

    if (profile.redeemedCodes.contains(code)) {
      return const RedeemOutcome(false, '该兑换码已使用过');
    }

    final points = pointsCodes[code];
    if (points != null) {
      profile.points += points;
      profile.redeemedCodes.add(code);
      await UserStorage.save(profile);
      return RedeemOutcome(true, '兑换成功，+$points 点');
    }

    final badge = badgeCodes[code];
    if (badge != null) {
      profile.badge = badge;
      if (!profile.ownedBadges.contains(badge)) profile.ownedBadges.add(badge);
      profile.redeemedCodes.add(code);
      await UserStorage.save(profile);
      final name = _badgeName(badge);
      return RedeemOutcome(true, '兑换成功，已获得「$name」身份');
    }

    return const RedeemOutcome(false, '兑换码无效，请检查后重试');
  }

  /// 用灵感兑换永久身份：扣分 → 加入已拥有 → 立即佩戴。
  static Future<RedeemOutcome> buyBadge(String badgeId) async {
    final item = shopBadgeOf(badgeId);
    if (item == null) return const RedeemOutcome(false, '商品不存在');

    final profile = await UserStorage.load();
    if (profile.owns(badgeId)) {
      return const RedeemOutcome(false, '已拥有该身份');
    }
    if (profile.points < item.price) {
      final lack = item.price - profile.points;
      return RedeemOutcome(false, '灵感不足，还差 $lack 点');
    }

    profile.points -= item.price;
    profile.ownedBadges.add(badgeId);
    profile.badge = badgeId;
    await UserStorage.save(profile);
    return RedeemOutcome(true, '兑换成功，已佩戴「${item.name}」身份');
  }

  /// 用灵感兑换限时 VIP 道具（日卡 / 周卡）：
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
      return RedeemOutcome(false, '灵感不足，还差 $lack 点');
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
    final gain = item.kind == ShopItemKind.vipWeekCard ? '7天' : '1天';
    return RedeemOutcome(true, '兑换成功，VIP有效期增加$gain');
  }

  /// 切换当前佩戴的身份（永久拥有的牌随时可切；
  /// VIP 在限时权益生效期间也可切换佩戴）。
  static Future<RedeemOutcome> wearBadge(String badgeId) async {
    final profile = await UserStorage.load();
    final canWear = profile.owns(badgeId) ||
        (badgeId == UserProfile.badgeVip && profile.vipCardActive);
    if (!canWear) {
      return const RedeemOutcome(false, '尚未拥有该身份');
    }
    if (profile.badge == badgeId) {
      return const RedeemOutcome(false, '已是当前身份');
    }
    profile.badge = badgeId;
    await UserStorage.save(profile);
    return RedeemOutcome(true, '已切换为「${_badgeName(badgeId)}」');
  }

  /// 每日首次发布笔记：领取 20 点。
  ///
  /// 返回实际获得的灵感（当天已领过 / 读写失败返回 0）。
  /// 任何异常都吞掉 —— 灵感是附加激励，不能影响笔记保存本身。
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

  /// 首次新增事件 / 物品 / 资产的灵感奖励（每类仅 1 次，非每日）。
  /// 返回实际获得的灵感（该类别已领过 / 读写失败返回 0）。
  /// 与每日发布奖励相同：异常吞掉，不影响新增本身。
  static Future<int> awardFirstAdd(FirstAddKind kind) async {
    try {
      final profile = await UserStorage.load();
      final claimed = kind == FirstAddKind.event
          ? profile.firstEventReward
          : kind == FirstAddKind.item
              ? profile.firstItemReward
              : profile.firstAssetReward;
      if (claimed) return 0;
      if (kind == FirstAddKind.event) {
        profile.firstEventReward = true;
      } else if (kind == FirstAddKind.item) {
        profile.firstItemReward = true;
      } else {
        profile.firstAssetReward = true;
      }
      profile.points += firstAddPoints;
      await UserStorage.save(profile);
      return firstAddPoints;
    } catch (_) {
      return 0;
    }
  }

  /// 写作里程碑奖励：日记总数 [diaryCount] 首次达到某节点时 +20 灵感。
  ///
  /// - 一次可能跨过多个节点（如老用户升级后第一次写，或数据恢复），
  ///   按「已跨过且未领取」的节点全部补发，每个 +20；
  /// - 判重记录在 [UserProfile.claimedWriteMilestones]，删除日记后篇数回落
  ///   也不会重复发放；
  /// - 返回本次实际达成的节点列表（升序），空列表表示无新里程碑；
  /// - 与每日 / 首次奖励一致：异常吞掉，绝不影响笔记保存本身。
  static Future<List<int>> awardWriteMilestone(int diaryCount) async {
    try {
      final reached = writeMilestones
          .where((m) => diaryCount >= m)
          .toList();
      if (reached.isEmpty) return const <int>[];

      final profile = await UserStorage.load();
      final fresh = reached
          .where((m) => !profile.claimedWriteMilestones.contains(m))
          .toList();
      if (fresh.isEmpty) return const <int>[];

      profile.claimedWriteMilestones.addAll(fresh);
      profile.points += milestonePoints * fresh.length;
      await UserStorage.save(profile);
      return fresh;
    } catch (_) {
      return const <int>[];
    }
  }

  /// 是否拥有可解锁「提醒时间」的 VIP 类身份：
  /// 内测版 / VIP / 终身VIP 其一（拥有即可，无需佩戴；限时 VIP 生效中亦可）。
  static bool hasVipPrivilege(UserProfile p) {
    if (p.vipCardActive) return true;
    const vipBadges = {
      UserProfile.badgeBeta,
      UserProfile.badgeVip,
      UserProfile.badgeVipForever,
    };
    return p.ownedBadges.any(vipBadges.contains) ||
        vipBadges.contains(p.badge);
  }

  /// 免费用户最多可置顶的数量（笔记 / 事件分别计数）。
  static const int freePinLimit = 3;

  /// 新增置顶是否被数量上限拦截。
  /// [currentPinned] 为当前该类别已置顶的数量（尚未包含本次要置顶的条目）。
  /// 权益身份（内测版 / VIP / 终身VIP）不限；非权益用户已达 3 条即拦截。
  /// VIP 期间置顶、过期后仍置顶的条目不自动撤销，仅阻止再新增。
  static bool pinLimitReached(int currentPinned, UserProfile profile) {
    if (hasVipPrivilege(profile)) return false;
    return currentPinned >= freePinLimit;
  }

  /// 置顶超限提示语。[kind] 传 '笔记' 或 '事'。
  static String pinLimitMessage(String kind) =>
      '非VIP用户最多置顶$freePinLimit$kind哦～';

  static String _badgeName(String id) {
    // 兑换码获得的牌用固定名，避免被杂货店里的「VIP日卡」商品名顶掉
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
