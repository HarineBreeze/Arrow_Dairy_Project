class UserProfile {
  /// 默认昵称：用户从未设置过昵称时展示这个名字。
  static const String defaultNickname = 'AyoDiray';

  /// 身份铭牌 id：内测版（橙底白字）
  static const String badgeBeta = 'beta';

  /// 身份铭牌 id：VIP（红底白字）
  static const String badgeVip = 'vip';

  String nickname;
  String gender; // 'male' | 'female' | ''
  String avatarPath; // 空 = 默认头像

  /// 积分余额（兑换码 / 每日首次发布获得，用途后续规划）
  int points;

  /// 身份铭牌：'' = 无，[badgeBeta] / [badgeVip]
  String badge;

  /// 已使用过的兑换码（每个码只能兑换一次）
  List<String> redeemedCodes;

  /// 最近一次「每日首次发布」奖励的日期（yyyy-MM-dd），空 = 从未领取
  String lastWriteReward;

  UserProfile({
    this.nickname = defaultNickname,
    this.gender = '',
    this.avatarPath = '',
    this.points = 0,
    this.badge = '',
    List<String>? redeemedCodes,
    this.lastWriteReward = '',
  }) : redeemedCodes = redeemedCodes ?? <String>[];

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'gender': gender,
        'avatarPath': avatarPath,
        'points': points,
        'badge': badge,
        'redeemedCodes': redeemedCodes,
        'lastWriteReward': lastWriteReward,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        // 旧数据里昵称为空的也落到默认昵称
        nickname: (json['nickname'] as String? ?? '').isEmpty
            ? defaultNickname
            : json['nickname'] as String,
        gender: json['gender'] as String? ?? '',
        avatarPath: json['avatarPath'] as String? ?? '',
        // 旧档案没有这些字段：积分从 0 开始、无铭牌、无兑换记录
        points: (json['points'] as num?)?.toInt() ?? 0,
        badge: json['badge'] as String? ?? '',
        redeemedCodes:
            (json['redeemedCodes'] as List?)?.map((e) => e.toString()).toList() ??
                <String>[],
        lastWriteReward: json['lastWriteReward'] as String? ?? '',
      );
}
