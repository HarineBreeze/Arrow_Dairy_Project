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
      title: '矢量日记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF3B6FE0),
        scaffoldBackgroundColor: const Color(0xFFF3F6FB),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF3B6FE0),
          secondary: Color(0xFF5B7FB8),
          surface: Color(0xFFFFFFFF),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3B6FE0),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF3B6FE0),
          foregroundColor: Colors.white,
        ),
        textTheme: const TextTheme(
          bodyText1: TextStyle(
              color: Color(0xFF2A3B52), fontSize: 15, height: 1.6),
          bodyText2: TextStyle(
              color: Color(0xFF5A6B82), fontSize: 14, height: 1.6),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
