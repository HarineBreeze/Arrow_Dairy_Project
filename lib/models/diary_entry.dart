class DiaryEntry {
  final String id;
  String title;
  String content;
  String mood;
  String weather;
  final DateTime createdAt;
  DateTime updatedAt;

  DiaryEntry({
    required this.id,
    this.title = '',
    this.content = '',
    this.mood = '😊',
    this.weather = '☀️',
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'mood': mood,
      'weather': weather,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    return DiaryEntry(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      mood: json['mood'] as String? ?? '😊',
      weather: json['weather'] as String? ?? '☀️',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
