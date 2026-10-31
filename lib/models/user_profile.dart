class UserProfile {
  /// 默认昵称：用户从未设置过昵称时展示这个名字。
  static const String defaultNickname = 'ArrowDiary';

  String nickname;
  String gender; // 'male' | 'female' | ''
  String avatarPath; // 空 = 默认头像

  UserProfile(
      {this.nickname = defaultNickname, this.gender = '', this.avatarPath = ''});

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'gender': gender,
        'avatarPath': avatarPath,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        // 旧数据里昵称为空的也落到默认昵称
        nickname: (json['nickname'] as String? ?? '').isEmpty
            ? defaultNickname
            : json['nickname'] as String,
        gender: json['gender'] as String? ?? '',
        avatarPath: json['avatarPath'] as String? ?? '',
      );
}
