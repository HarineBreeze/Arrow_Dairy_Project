class DiaryEntry {
  final String id;
  String title;
  String subtitle;
  String content;
  String mood;
  String weather;
  String location;
  bool encrypted;
  String password;
  String passwordHint; // 忘记密码提示
  String passwordAnswer; // 提示答案
  bool pinned; // 置顶
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime publishDate;

  DiaryEntry({
    required this.id,
    this.title = '',
    this.subtitle = '',
    this.content = '',
    this.mood = '😊',
    this.weather = '☀️',
    this.location = '',
    this.encrypted = false,
    this.password = '',
    this.passwordHint = '',
    this.passwordAnswer = '',
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
    required this.publishDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'content': content,
      'mood': mood,
      'weather': weather,
      'location': location,
      'encrypted': encrypted,
      'password': password,
      'passwordHint': passwordHint,
      'passwordAnswer': passwordAnswer,
      'pinned': pinned,
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
      mood: json['mood'] as String? ?? '😊',
      weather: json['weather'] as String? ?? '☀️',
      location: json['location'] as String? ?? '',
      encrypted: json['encrypted'] as bool? ?? false,
      password: json['password'] as String? ?? '',
      createdAt: createdAt,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      publishDate: json['publishDate'] != null
          ? DateTime.parse(json['publishDate'] as String)
          : createdAt,
    );
  }
}
