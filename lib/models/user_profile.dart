import 'package:flutter/foundation.dart';

class UserProfile {
  /// 默认昵称：用户从未设置过昵称时展示这个名字。
  static const String defaultNickname = 'AyoDiray';

  /// 身份 id：普通版（灰底白字）。默认佩戴、不可丢弃，始终在已拥有列表里。
  static const String badgeNormal = 'normal';

  /// 身份 id：内测版（橙底白字）
  static const String badgeBeta = 'beta';

  /// 身份 id：VIP（红底白字）
  static const String badgeVip = 'vip';

  /// 身份 id：诞生日（绿底白字，灵感杂货店兑换）
  static const String badgeBirthday = 'birthday';

  /// 身份 id：终身VIP（红底白字，兑换码 `zhongshenvip` 获得，永久有效）
  static const String badgeVipForever = 'vip_forever';

  /// 顺序用户 ID 的起点：从 10001 起，每份新档案递增 1。
  static const int userIdStart = 10001;

  /// 进程内已分配的最大序号。正式档案的序列由 [UserStorage] 持久化到磁盘，
  /// 启动时用磁盘序列播种，保证跨重启仍单调不减、不重复发号。
  static int _lastUserId = userIdStart - 1;

  String nickname;
  String gender; // 'male' | 'female' | ''
  String avatarPath; // 空 = 默认头像

  /// 生日（yyyy-MM-dd），空 = 未设置；在档案页用年月日滚轮选择。
  /// 与注册日 registeredAt 相互独立：注册日是系统生成的不可改，生日是用户自填。
  String birthday;

  /// 剩余灵感（兑换码 / 每日首次发布 / 杂货店消费）
  int points;

  /// 当前佩戴的身份，默认 [badgeNormal]
  String badge;

  /// 已拥有的身份（[badgeNormal] 恒在首位，其余由兑换码 / 灵感杂货店获得）
  List<String> ownedBadges;

  /// 已使用过的兑换码（同一用户 ID 下每码只能用一次）
  List<String> redeemedCodes;

  /// 最近一次「每日首次发布」奖励的日期（yyyy-MM-dd），空 = 从未领取
  String lastWriteReward;

  /// 已兑换「VIP日卡」的次数（单用户上限见 RewardService.vipCardMaxCount）
  int vipCardCount;

  /// 已兑换「VIP周卡」的次数（单用户上限见 RewardService.vipWeekCardMaxCount）
  int vipWeekCardCount;

  /// VIP 权益到期时间（ISO 8601）。日卡 / 周卡都累加到这个时间上，
  /// 空 = 没有生效中的限时 VIP 权益。
  String vipCardExpireAt;

  /// 用户 ID：从 10001 起的顺序数，首次启动分配后固化到档案，
  /// 可在档案页复制、侧边栏展示。
  String userId;

  /// 用户注册日（yyyy-MM-dd），即用户 ID 生成当天；「使用时间」由此计算。
  String registeredAt;

  UserProfile({
    this.nickname = defaultNickname,
    this.gender = '',
    this.avatarPath = '',
    this.birthday = '',
    this.points = 0,
    this.badge = badgeNormal,
    List<String>? ownedBadges,
    List<String>? redeemedCodes,
    this.lastWriteReward = '',
    this.vipCardCount = 0,
    this.vipWeekCardCount = 0,
    this.vipCardExpireAt = '',
    String? initialUserId,
    String? initialRegisteredAt,
  })  : ownedBadges = _normalizeOwned(ownedBadges, badge),
        redeemedCodes = redeemedCodes ?? <String>[],
        userId = (initialUserId == null || initialUserId.isEmpty)
            ? newUserId()
            : initialUserId,
        registeredAt = (initialRegisteredAt == null ||
                initialRegisteredAt.isEmpty)
            ? dayKey(DateTime.now())
            : initialRegisteredAt;

  /// 用磁盘上持久化的「已分配最大序号」播种内存序列（只升不降）。
  static void seedUserIdSeq(int lastAssigned) {
    if (lastAssigned > _lastUserId) _lastUserId = lastAssigned;
  }

  /// 仅供测试：把内存序列重置回起点，保证「从 10001 开始」可精确断言。
  @visibleForTesting
  static void resetUserIdSeq() => _lastUserId = userIdStart - 1;

  /// 分配下一个顺序用户 ID（纯数字字符串，如 `10001`）。
  /// 正式档案的发号与持久化由 UserStorage.allocateUserId 负责，
  /// 这里只保证进程内直接构造的临时对象也不会重复。
  static String newUserId() {
    _lastUserId += 1;
    return '$_lastUserId';
  }

  /// `yyyy-MM-dd` 日期键
  static String dayKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';

  /// 使用时间：自注册日起至今天共多少天（注册当天记为第 1 天）。
  /// 只按自然日计算，避免时分秒导致显示差一天；解析失败时回落为 1。
  int get usedDays {
    final reg = DateTime.tryParse(registeredAt);
    if (reg == null) return 1;
    final now = DateTime.now();
    final a = DateTime(reg.year, reg.month, reg.day);
    final b = DateTime(now.year, now.month, now.day);
    return b.difference(a).inDays + 1;
  }

  /// 限时权益的剩余天数（按 24 小时一天向上取整，不足 1 天按 1 天）。
  /// 无到期时间 / 已过期返回 0。
  /// 日卡与周卡累加到同一个到期时间后，这里会自然随实际购买天数增加。
  static int daysLeft(DateTime? expiresAt) {
    if (expiresAt == null || !DateTime.now().isBefore(expiresAt)) return 0;
    final hours = expiresAt.difference(DateTime.now()).inHours;
    final days = (hours / 24).ceil();
    return days < 1 ? 1 : days;
  }

  /// 身份在「选择身份」弹层里展示的有效期文案：
  /// VIP 行只要存在生效中的限时权益（日卡 / 周卡累计）就显示「剩余x天」，
  /// 天数随实际购买累加；其余牌以及没有限时权益的 VIP 显示「永久」。
  /// [owned] 保留为兼容参数（是否永久拥有），不再影响限时权益的展示。
  static String validityLabel(String id,
      {required bool owned, DateTime? expiresAt}) {
    if (id == badgeVip && expiresAt != null) {
      final left = daysLeft(expiresAt);
      if (left > 0) return '剩余${left}天';
    }
    return '永久';
  }

  /// 已拥有列表归一：普通版恒在首位、去重、当前佩戴的牌必须在列表里。
  static List<String> _normalizeOwned(List<String>? owned, String current) {
    final list = <String>[badgeNormal];
    for (final id in owned ?? const <String>[]) {
      if (id.isNotEmpty && !list.contains(id)) list.add(id);
    }
    if (current.isNotEmpty && !list.contains(current)) list.add(current);
    return list;
  }

  /// 是否已拥有某个身份
  bool owns(String badgeId) => ownedBadges.contains(badgeId);

  /// VIP 权益到期时间（未设置返回 null）
  DateTime? get vipCardExpireTime =>
      vipCardExpireAt.isEmpty ? null : DateTime.tryParse(vipCardExpireAt);

  /// 限时 VIP 权益是否生效中
  bool get vipCardActive {
    final t = vipCardExpireTime;
    return t != null && DateTime.now().isBefore(t);
  }

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'gender': gender,
        'avatarPath': avatarPath,
        'birthday': birthday,
        'points': points,
        'badge': badge,
        'ownedBadges': ownedBadges,
        'redeemedCodes': redeemedCodes,
        'lastWriteReward': lastWriteReward,
        'vipCardCount': vipCardCount,
        'vipWeekCardCount': vipWeekCardCount,
        'vipCardExpireAt': vipCardExpireAt,
        'userId': userId,
        'registeredAt': registeredAt,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    // v4.9.17 及以前没有 ownedBadges，badge 为空表示「没有铭牌」。
    // 这里把空值当作普通版，并把旧数据里已佩戴的牌补进已拥有列表，
    // 避免升级后原有的内测版 / VIP 变成不可用。
    final rawBadge = json['badge'] as String? ?? '';
    var current = rawBadge.isEmpty ? badgeNormal : rawBadge;
    final rawOwned =
        (json['ownedBadges'] as List?)?.map((e) => e.toString()).toList();

    // 限时 VIP 到期摘牌：VIP 戴在身上、不在已拥有列表（非永久获得）、
    // 且带限时卡痕迹（有到期时间或兑换次数）时，过期即换回普通版。
    // 没有痕迹的旧档案 VIP（升级前遗留）保持原样，继续视作永久拥有。
    var vipCardWorn = false;
    if (current == badgeVip &&
        !(rawOwned ?? const <String>[]).contains(badgeVip)) {
      final expireAt = json['vipCardExpireAt'] as String? ?? '';
      final count = ((json['vipCardCount'] as num?)?.toInt() ?? 0) +
          ((json['vipWeekCardCount'] as num?)?.toInt() ?? 0);
      if (expireAt.isNotEmpty || count > 0) {
        final expireTime = DateTime.tryParse(expireAt);
        final active = expireTime != null && DateTime.now().isBefore(expireTime);
        if (!active) current = badgeNormal;
        vipCardWorn = active;
      }
    }

    final profile = UserProfile(
      // 旧数据里昵称为空的也落到默认昵称
      nickname: (json['nickname'] as String? ?? '').isEmpty
          ? defaultNickname
          : json['nickname'] as String,
      gender: json['gender'] as String? ?? '',
      avatarPath: json['avatarPath'] as String? ?? '',
      // 旧档案无 birthday 字段：回落空串（未设置），零迁移
      birthday: json['birthday'] as String? ?? '',
      points: (json['points'] as num?)?.toInt() ?? 0,
      badge: current,
      ownedBadges: rawOwned,
      redeemedCodes:
          (json['redeemedCodes'] as List?)?.map((e) => e.toString()).toList() ??
              <String>[],
      lastWriteReward: json['lastWriteReward'] as String? ?? '',
      vipCardCount: (json['vipCardCount'] as num?)?.toInt() ?? 0,
      vipWeekCardCount: (json['vipWeekCardCount'] as num?)?.toInt() ?? 0,
      vipCardExpireAt: json['vipCardExpireAt'] as String? ?? '',
      initialUserId: json['userId'] as String?,
      initialRegisteredAt: json['registeredAt'] as String?,
    );
    if (vipCardWorn) {
      // 撤销构造器对「当前佩戴牌」的自动补入：限时 VIP 只是临时佩戴，
      // 不能混进已拥有列表变成永久牌
      profile.ownedBadges.remove(badgeVip);
    }
    return profile;
  }
}
