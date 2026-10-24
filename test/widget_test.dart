import 'package:flutter_test/flutter_test.dart';

import 'package:diary_app/main.dart';
import 'package:diary_app/utils/rich_text.dart';

void main() {
  testWidgets('App 启动冒烟测试', (WidgetTester tester) async {
    await tester.pumpWidget(const DiaryApp());
    await tester.pump();
    expect(find.byType(DiaryApp), findsOneWidget);
  });

  test('富文本解析：#话题', () {
    final segs = RichTextParser.parse('今天读了一本书 #读书笔记 很棒', {});
    final topics = RichTextParser.extractTopics('今天读了一本书 #读书笔记 很棒');
    expect(topics, ['读书笔记']);
    expect(segs.any((s) => s.type == 'topic' && s.value == '读书笔记'), true);
  });

  test('富文本解析：@物品名最长匹配', () {
    final segs = RichTextParser.parse('新买的耳机到了 @A7C2 音质不错', {'A7C2', 'A7'});
    final mention = segs.firstWhere((s) => s.type == 'mention');
    expect(mention.value, 'A7C2');
    expect(mention.text, '@A7C2');
  });

  test('富文本解析：非物品名的 @ 保持普通文本', () {
    final segs = RichTextParser.parse('邮箱 @someone 未知', {'A7C2'});
    expect(segs.every((s) => s.type != 'mention'), true);
  });
}
