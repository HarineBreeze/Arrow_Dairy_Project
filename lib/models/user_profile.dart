import 'dart:math';

class UserProfile {
  /// 默认昵称：用户从未设置过昵称时展示这个名字。
  static const String defaultNickname = 'AyoDiray';

  /// 身份牌 id：普通版（灰底白字）。默认佩戴、不可丢弃，始终在已拥有列表里。
  static const String badgeNormal = 'normal';

  /// 身份牌 id：内测版（橙底白字）
  static const String badgeBeta = 'beta';

  /// 身份牌 id：VIP（红底白字）
  static const String badgeVip = 'vip';

  /// 身份牌 id：诞生日（绿底白字，积分商城兑换）
  static const String badgeBirthday = 'birthday';

  String nickname;
  String gender; // 'male' | 'female' | ''
  String avatarPath; // 空 = 默认头像

  /// 积分余额（兑换码 / 每日首次发布 / 商城消费）
  int points;

  /// 当前佩戴的身份牌，默认 [badgeNormal]
  String badge;

  /// 已拥有的身份牌（[badgeNormal] 恒在首位，其余由兑换码 / 积分商城获得）
  List<String> ownedBadges;

  /// 已使用过的兑换码（同一用户 ID 下每码只能用一次）
  List<String> redeemedCodes;

  /// 最近一次「每日首次发布」奖励的日期（yyyy-MM-dd），空 = 从未领取
  String lastWriteReward;

  /// 已兑换「VIP日卡」的次数（单用户上限见 RewardService.vipCardMaxCount）
  int vipCardCount;

  /// 当前生效的 VIP 日卡到期时间（ISO 8601），空 = 没有生效中的日卡
  String vipCardExpireAt;

  /// 用户 ID：首次启动生成后固化到档案，可在个人信息页复制。
  /// 同一份档案（同一用户）下兑换码使用次数以此为准。
  String userId;

  /// 用户注册日（yyyy-MM-dd），即用户 ID 生成当天；「使用时间」由此计算。
  String registeredAt;

  UserProfile({
    this.nickname = defaultNickname,
    this.gender = '',
    this.avatarPath = '',
    this.points = 0,
    this.badge = badgeNormal,
    List<String>? ownedBadges,
    List<String>? redeemedCodes,
    this.lastWriteReward = '',
    this.vipCardCount = 0,
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

  /// 生成一个新的用户 ID：`AYO-<时间戳36进制>-<4位随机码>`。
  /// 去掉了易混淆的 0/O/1/I，方便用户手动抄写。
  static String newUserId() {
    final stamp =
        DateTime.now().microsecondsSinceEpoch.toRadixString(36).toUpperCase();
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final r = Random();
    final tail =
        List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
    return 'AYO-$stamp-$tail';
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

  /// 身份牌在「选择身份牌」弹层里展示的有效期文案：
  /// 永久拥有的牌显示「永久」；限时牌（VIP 日卡）显示「剩余x天」。
  /// 不足 1 天按 1 天显示，避免刚兑换完就出现「剩余0天」。
  static String validityLabel(String id,
      {required bool owned, DateTime? expiresAt}) {
    if (!owned &&
        id == badgeVip &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt)) {
      final hours = expiresAt.difference(DateTime.now()).inHours;
      final days = (hours / 24).ceil();
      return '剩余${days < 1 ? 1 : days}天';
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

  /// 是否已拥有某个身份牌
  bool owns(String badgeId) => ownedBadges.contains(badgeId);

  /// VIP 日卡到期时间（未设置返回 null）
  DateTime? get vipCardExpireTime =>
      vipCardExpireAt.isEmpty ? null : DateTime.tryParse(vipCardExpireAt);

  /// VIP 日卡是否生效中（兑换时刻起 24 小时内）
  bool get vipCardActive {
    final t = vipCardExpireTime;
    return t != null && DateTime.now().isBefore(t);
  }

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'gender': gender,
        'avatarPath': avatarPath,
        'points': points,
        'badge': badge,
        'ownedBadges': ownedBadges,
        'redeemedCodes': redeemedCodes,
        'lastWriteReward': lastWriteReward,
        'vipCardCount': vipCardCount,
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

    // VIP 日卡到期摘牌：VIP 戴在身上、不在已拥有列表（非兑换码获得）、
    // 且带日卡痕迹（有到期时间或兑换次数）时，过期即换回普通版。
    // 没有日卡痕迹的旧档案 VIP（升级前遗留）保持原样，继续视作永久拥有。
    var vipCardWorn = false;
    if (current == badgeVip &&
        !(rawOwned ?? const <String>[]).contains(badgeVip)) {
      final expireAt = json['vipCardExpireAt'] as String? ?? '';
      final count = (json['vipCardCount'] as num?)?.toInt() ?? 0;
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
      points: (json['points'] as num?)?.toInt() ?? 0,
      badge: current,
      ownedBadges: rawOwned,
      redeemedCodes:
          (json['redeemedCodes'] as List?)?.map((e) => e.toString()).toList() ??
              <String>[],
      lastWriteReward: json['lastWriteReward'] as String? ?? '',
      vipCardCount: (json['vipCardCount'] as num?)?.toInt() ?? 0,
      vipCardExpireAt: json['vipCardExpireAt'] as String? ?? '',
      initialUserId: json['userId'] as String?,
      initialRegisteredAt: json['registeredAt'] as String?,
    );
    if (vipCardWorn) {
      // 撤销构造器对「当前佩戴牌」的自动补入：日卡 VIP 只是临时佩戴，
      // 不能混进已拥有列表变成永久牌
      profile.ownedBadges.remove(badgeVip);
    }
    return profile;
  }
}
