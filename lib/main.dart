import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const DiaryApp());
}

class DiaryApp extends StatelessWidget {
  const DiaryApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '拾光日记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFD98E63),
        scaffoldBackgroundColor: const Color(0xFFFAF5F0),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFD98E63),
          secondary: Color(0xFF8C6B5A),
          surface: Color(0xFFFFFFFF),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFAF5F0),
          foregroundColor: Color(0xFF4A3B33),
          elevation: 0,
          centerTitle: true,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFD98E63),
          foregroundColor: Colors.white,
        ),
        textTheme: const TextTheme(
          bodyText1: TextStyle(color: Color(0xFF4A3B33), fontSize: 15, height: 1.6),
          bodyText2: TextStyle(color: Color(0xFF6B5B50), fontSize: 14, height: 1.6),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
