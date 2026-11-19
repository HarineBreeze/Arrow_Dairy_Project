class DiaryEntry {
  final String id;
  String title;
  String subtitle;
  String content;
  String formats; // 富文本排版（JSON 字符串），空串表示无格式
  String imagePath; // 首图本地路径，空串 = 无图
  String location;
  bool encrypted;
  String password;
  String passwordHint; // 忘记密码提示
  String passwordAnswer; // 提示答案
  bool pinned; // 置顶
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime publishDate;

  /// v4.9.37「未来信件」：可见日期（00:00，按自然日比较）。
  /// null = 普通笔记；非 null 且未到该日期 = 封存中（按加密样式显示、不可打开/编辑）。
  /// 到期后自动还原为普通笔记，不改动本字段（保留设置痕迹）。
  DateTime? revealAt;

  DiaryEntry({
    required this.id,
    this.title = '',
    this.subtitle = '',
    this.content = '',
    this.formats = '',
    this.imagePath = '',
    this.location = '',
    this.encrypted = false,
    this.password = '',
    this.passwordHint = '',
    this.passwordAnswer = '',
    this.pinned = false,
    this.revealAt,
    required this.createdAt,
    required this.updatedAt,
    required this.publishDate,
  });

  /// 是否为未来信件
  bool get isFutureLetter => revealAt != null;

  /// 指定时刻是否仍在封存期（未到可见日期）。按自然日比较：
  /// 只有到了 revealAt 当天 00:00 之后才算开封。
  bool isSealedAt(DateTime now) {
    final r = revealAt;
    if (r == null) return false;
    return now.isBefore(DateTime(r.year, r.month, r.day));
  }

  /// 便捷：以当前时间判断是否封存中
  bool get isSealed => isSealedAt(DateTime.now());

  /// 是否已到可见日期（自然日）
  bool isRevealedAt(DateTime now) => revealAt != null && !isSealedAt(now);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'content': content,
      'formats': formats,
      'imagePath': imagePath,
      'location': location,
      'encrypted': encrypted,
      'password': password,
      'passwordHint': passwordHint,
      'passwordAnswer': passwordAnswer,
      'pinned': pinned,
      'revealAt': revealAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'publishDate': publishDate.toIso8601String(),
    };
  }

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.parse(json['createdAt'] as String);
    return DiaryEntry(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      content: json['content'] as String? ?? '',
      formats: json['formats'] as String? ?? '',
      // 旧数据没有该字段：按无图渲染，零迁移
      // 旧备份里的 mood / weather 字段不再读取，自动无视
      imagePath: json['imagePath'] as String? ?? '',
      location: json['location'] as String? ?? '',
      encrypted: json['encrypted'] as bool? ?? false,
      password: json['password'] as String? ?? '',
      passwordHint: json['passwordHint'] as String? ?? '',
      passwordAnswer: json['passwordAnswer'] as String? ?? '',
      pinned: json['pinned'] as bool? ?? false,
      // v4.9.37：旧数据无 revealAt → null（普通笔记），零迁移
      revealAt: json['revealAt'] != null
          ? DateTime.tryParse(json['revealAt'] as String)
          : null,
      createdAt: createdAt,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      publishDate: json['publishDate'] != null
          ? DateTime.parse(json['publishDate'] as String)
          : createdAt,
    );
  }
}
