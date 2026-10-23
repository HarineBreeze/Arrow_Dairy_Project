class UserProfile {
  String nickname;
  String gender; // 'male' | 'female' | ''
  String avatarPath; // 空 = 默认头像

  UserProfile({this.nickname = '', this.gender = '', this.avatarPath = ''});

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'gender': gender,
        'avatarPath': avatarPath,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        nickname: json['nickname'] as String? ?? '',
        gender: json['gender'] as String? ?? '',
        avatarPath: json['avatarPath'] as String? ?? '',
      );
}
