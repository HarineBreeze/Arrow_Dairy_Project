import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'services/app_settings.dart';
import 'screens/home_screen.dart';
import 'theme/app_palette.dart';
import 'theme/app_theme_scope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 图片缓存上限：降采样后单张约 200–600KB，60MB / 300 张足够覆盖
  // 一屏到两屏的滚动预热；超出后按 LRU 回收，避免长时间浏览有图笔记后
  // 内存只涨不落（默认 100MB / 1000 张对手机端偏大）。
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 300;
  cache.maximumSizeBytes = 60 << 20;
  await AppSettings.load(); // 提前读入字体、主题模式等设置
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

/// 应用根：同时监听「字体」与「主题模式」两个设置项，任一变化都整体重建
/// MaterialApp，让 ThemeData 与全局语义色板 AppPalette 同步刷新。
///
/// 「跟随系统」时还要响应系统亮度变化：通过 WidgetsBindingObserver 的
/// didChangePlatformBrightness 触发重建（仅跟随系统模式需要，但统一重建
/// 更简单且无副作用）。系统亮度用 platformDispatcher.platformBrightness
/// 读取，不依赖 context 里是否已挂 MediaQuery。
class DiaryApp extends StatefulWidget {
  const DiaryApp({Key? key}) : super(key: key);

  @override
  State<DiaryApp> createState() => _DiaryAppState();
}

class _DiaryAppState extends State<DiaryApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangePlatformBrightness() {
    // 仅在跟随系统时才有实际影响，但统一 setState 让 themeMode 逻辑重算，
    // 保证 AppPalette.dark 与 MaterialApp 选中的主题始终一致。
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: AppSettings.themeModeNotifier,
      builder: (context, mode, _) => ValueListenableBuilder<String>(
        valueListenable: AppSettings.accentNotifier,
        builder: (context, accentId, _) => ValueListenableBuilder<String?>(
        valueListenable: AppSettings.fontNotifier,
        builder: (context, fontFamily, _) {
          // 每次重建先算出实际亮度，写入全局色板；AppPalette.c 会在
          // 之后各页面 build 时按此值取色，做到「一处切换，全局生效」。
          final platformBrightness =
              SchedulerBinding.instance.platformDispatcher.platformBrightness;
          final dark = AppSettings.resolveDark(mode, platformBrightness);
          AppPalette.dark = dark;
          AppPalette.accent = AccentCatalog.byId(accentId);

          return MaterialApp(
            title: '阿尤日记',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(fontFamily, Brightness.light),
            darkTheme: _buildTheme(fontFamily, Brightness.dark),
            // system 交给 Flutter 依系统亮度自动选 theme / darkTheme；
            // light / dark 为手动强制。与上面 AppPalette.dark 的解析一致。
            themeMode: _toThemeMode(mode),
            // v4.9.25：包一层主题重建作用域。所有页面 build 开头调用
            // AppThemeScope.watch(context) 后，明暗切换会令本 widget 更新，
            // 进而让全部页面重新 build —— 深色/浅色一次切换即全局到位，
            // 不必再滑一次侧边栏。State 原地保留，不丢导航栈与编辑内容。
            builder: (context, child) => AppThemeScope(
              dark: dark,
              accentId: accentId,
              child: child ?? const SizedBox.shrink(),
            ),
            home: const HomeScreen(),
          );
        },
        ),
      ),
    );
  }

  ThemeMode _toThemeMode(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  ThemeData _buildTheme(String? fontFamily, Brightness brightness) {
    // v4.9.43：主题色跟随用户选择（默认竹青，与 kPrimaryGreen 一致）
    final green = AppPalette.accentColor;
    final swatch = createBambooSwatch(green);
    final dark = brightness == Brightness.dark;

    // 深色主题下：卡片/画布/弹窗走深灰绿，正文走浅色，分隔线走深灰，
    // 顶栏走深墨绿；主色、开关、选框、文本选区仍保持竹青，跨主题一致。
    final base = ThemeData(
      brightness: brightness,
      // 字体设置全局生效：ThemeData 会把 fontFamily 合并进默认
      // TextTheme 的每一档，自定义的 bodyText1/2（未指定 family）
      // 在 merge 时也跟随继承
      fontFamily: fontFamily,
      primarySwatch: swatch,
      primaryColor: green,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF101613) : const Color(0xFFF5FAF7),
      // AppIcon 默认跟随 IconTheme；浅色钉深墨色，深色改浅色，
      // AppBar.foregroundColor(白) 会在此基础上对顶栏图标覆写
      iconTheme: IconThemeData(
          color: dark ? const Color(0xFFDDE9E1) : const Color(0xFF273830)),
      colorScheme: dark
          ? ColorScheme.dark(
              primary: green,
              secondary: Color(0xFF4B9C7D),
              surface: Color(0xFF18221E),
            )
          : ColorScheme.light(
              primary: green,
              secondary: Color(0xFF4B9C7D),
              surface: Color(0xFFFFFFFF),
            ),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF22342C) : green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: green,
        foregroundColor: Colors.white,
      ),
      cardColor: dark ? const Color(0xFF18221E) : Colors.white,
      canvasColor: dark ? const Color(0xFF18221E) : Colors.white,
      dialogBackgroundColor: dark ? const Color(0xFF18221E) : Colors.white,
      dividerColor: dark ? const Color(0xFF2A3830) : const Color(0xFFE8EDF5),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dark ? const Color(0xFF18221E) : Colors.white,
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
                : (dark
                    ? const Color(0xFF3A4C42)
                    : const Color(0xFFC6D6CD))),
      ),
      // 文本选区/光标：Android 默认取 colorScheme.primary 已是绿，
      // 这里显式钉死，iOS 等平台也不会再出现默认蓝
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: green,
        selectionColor: green.withOpacity(0.30),
        selectionHandleColor: green,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: green,
        linearTrackColor:
            dark ? const Color(0xFF233A2F) : const Color(0xFFE4F2EB),
        circularTrackColor:
            dark ? const Color(0xFF233A2F) : const Color(0xFFE4F2EB),
      ),
      textTheme: TextTheme(
        bodyText1: TextStyle(
            color: dark ? const Color(0xFFE9F2EB) : const Color(0xFF24382F),
            fontSize: 15,
            height: 1.6),
        bodyText2: TextStyle(
            color: dark ? const Color(0xFFA8BCB0) : const Color(0xFF647A70),
            fontSize: 13,
            height: 1.6),
      ),
    );
    return base;
  }
}
