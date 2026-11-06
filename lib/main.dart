import 'package:flutter/material.dart';
import 'services/app_settings.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load(); // 提前读入手写体等设置
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
        primaryColor: const Color(0xFF3E8E6D),
        scaffoldBackgroundColor: const Color(0xFFF5FAF7),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF3E8E6D),
          secondary: Color(0xFF4B9C7D),
          surface: Color(0xFFFFFFFF),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF3E8E6D),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF3E8E6D),
          foregroundColor: Colors.white,
        ),
        textTheme: const TextTheme(
          bodyText1: TextStyle(
              color: Color(0xFF24382F), fontSize: 15, height: 1.6),
          bodyText2: TextStyle(
              color: Color(0xFF647A70), fontSize: 14, height: 1.6),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
