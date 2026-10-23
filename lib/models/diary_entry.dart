class DiaryEntry {
  final String id;
  String title;
  String content;
  String mood;
  String weather;
  String location;
  bool encrypted;
  String password;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime publishDate;

  DiaryEntry({
    required this.id,
    this.title = '',
    this.content = '',
    this.mood = '😊',
    this.weather = '☀️',
    this.location = '',
    this.encrypted = false,
    this.password = '',
    required this.createdAt,
    required this.updatedAt,
    required this.publishDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'mood': mood,
      'weather': weather,
      'location': location,
      'encrypted': encrypted,
      'password': password,
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
