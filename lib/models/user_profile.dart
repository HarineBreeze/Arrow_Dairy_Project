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

  UserProfile({
    this.nickname = defaultNickname,
    this.gender = '',
    this.avatarPath = '',
    this.points = 0,
    this.badge = badgeNormal,
    List<String>? ownedBadges,
    List<String>? redeemedCodes,
    this.lastWriteReward = '',
  })  : ownedBadges = _normalizeOwned(ownedBadges, badge),
        redeemedCodes = redeemedCodes ?? <String>[];

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

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'gender': gender,
        'avatarPath': avatarPath,
        'points': points,
        'badge': badge,
        'ownedBadges': ownedBadges,
        'redeemedCodes': redeemedCodes,
        'lastWriteReward': lastWriteReward,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    // v4.9.17 及以前没有 ownedBadges，badge 为空表示「没有铭牌」。
    // 这里把空值当作普通版，并把旧数据里已佩戴的牌补进已拥有列表，
    // 避免升级后原有的内测版 / VIP 变成不可用。
    final rawBadge = json['badge'] as String? ?? '';
    final current = rawBadge.isEmpty ? badgeNormal : rawBadge;
    return UserProfile(
      // 旧数据里昵称为空的也落到默认昵称
      nickname: (json['nickname'] as String? ?? '').isEmpty
          ? defaultNickname
          : json['nickname'] as String,
      gender: json['gender'] as String? ?? '',
      avatarPath: json['avatarPath'] as String? ?? '',
      points: (json['points'] as num?)?.toInt() ?? 0,
      badge: current,
      ownedBadges:
          (json['ownedBadges'] as List?)?.map((e) => e.toString()).toList(),
      redeemedCodes:
          (json['redeemedCodes'] as List?)?.map((e) => e.toString()).toList() ??
              <String>[],
      lastWriteReward: json['lastWriteReward'] as String? ?? '',
    );
  }
}
