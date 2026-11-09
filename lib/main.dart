import 'package:flutter/material.dart';
import 'services/app_settings.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 图片缓存上限：降采样后单张约 200–600KB，60MB / 300 张足够覆盖
  // 一屏到两屏的滚动预热；超出后按 LRU 回收，避免长时间浏览有图笔记后
  // 内存只涨不落（默认 100MB / 1000 张对手机端偏大）。
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 300;
  cache.maximumSizeBytes = 60 << 20;
  await AppSettings.load(); // 提前读入手写体等设置
  runApp(const DiaryApp());
}

/// 竹青主题色 #3E8E6D。
const Color kPrimaryGreen = Color(0xFF3E8E6D);

/// 由主题色生成 Material 色阶 swatch。
///
/// 必须设置 primarySwatch：不设置时默认是 Colors.blue，所有未显式指定
/// 颜色的控件（复选框、开关、单选、进度条、选中高亮等）都会回落到
/// Material 蓝 —— 这是「全局换成绿色后还有蓝色残留」的主要来源。
MaterialColor createBambooSwatch(Color color) {
  final swatch = <int, Color>{};
  // 50/100/.../900：与纯白按比例混合生成浅阶，向黑压深生成深阶
  for (final strength in [0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]) {
    final f = 1 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      ((color.red * f) + (255 - 255 * f)).round(),
      ((color.green * f) + (255 - 255 * f)).round(),
      ((color.blue * f) + (255 - 255 * f)).round(),
      1,
    );
  }
  return MaterialColor(color.value, swatch);
}

class DiaryApp extends StatelessWidget {
  const DiaryApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 字体在设置页切换后，主题整体重建 → 全 App 生效
    return ValueListenableBuilder<String?>(
      valueListenable: AppSettings.fontNotifier,
      builder: (context, fontFamily, _) => MaterialApp(
        title: '阿尤日记',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(fontFamily),
        home: const HomeScreen(),
      ),
    );
  }

  ThemeData _buildTheme(String? fontFamily) {
    const green = kPrimaryGreen;
    final swatch = createBambooSwatch(green);
    return ThemeData(
      // 字体设置全局生效：ThemeData 会把 fontFamily 合并进默认
      // TextTheme 的每一档，自定义的 bodyText1/2（未指定 family）
      // 在 merge 时也跟随继承
      fontFamily: fontFamily,
      primarySwatch: swatch,
      primaryColor: green,
      scaffoldBackgroundColor: const Color(0xFFF5FAF7),
      // AppIcon 默认跟随 IconTheme；此处钉死深墨色，
      // AppBar.foregroundColor(白) 会在此基础上对顶栏图标覆写
      iconTheme: const IconThemeData(color: Color(0xFF273830)),
      colorScheme: const ColorScheme.light(
        primary: green,
        secondary: Color(0xFF4B9C7D),
        surface: Color(0xFFFFFFFF),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: green,
        foregroundColor: Colors.white,
      ),
      // 选框类控件：激活态统一竹青，未选中态走各自默认
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? green : null),
      ),
      radioTheme: RadioThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? green : null),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected) ? Colors.white : null),
        trackColor: MaterialStateProperty.resolveWith((states) =>
            states.contains(MaterialState.selected)
                ? green
                : const Color(0xFFC6D6CD)),
      ),
      // 文本选区/光标：Android 默认取 colorScheme.primary 已是绿，
      // 这里显式钉死，iOS 等平台也不会再出现默认蓝
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: green,
        selectionColor: green.withOpacity(0.30),
        selectionHandleColor: green,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: green,
        linearTrackColor: Color(0xFFE4F2EB),
        circularTrackColor: Color(0xFFE4F2EB),
      ),
      textTheme: const TextTheme(
        bodyText1:
            TextStyle(color: Color(0xFF24382F), fontSize: 15, height: 1.6),
        bodyText2:
            TextStyle(color: Color(0xFF647A70), fontSize: 13, height: 1.6),
      ),
    );
  }
}
