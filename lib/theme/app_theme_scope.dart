import 'package:flutter/material.dart';

import 'app_palette.dart';

/// 主题重建作用域（v4.9.25 深色切换即时刷新修复）。
///
/// 背景：项目里颜色几乎都通过静态 [AppPalette.c] 读取全局 [AppPalette.dark]，
/// 而非 `Theme.of(context)`。切换主题时 MaterialApp 的 theme/darkTheme 会换，
/// 但 `home: const HomeScreen()` 与已 push 的路由页面不会因此重建 —— 只有
/// 自身监听了 themeModeNotifier 的组件（如设置页「外观」分组）会刷新，
/// 其余区域要等滑一次侧边栏触发 HomeScreen 重建才整体变色。
///
/// 方案：把本 widget 挂在 MaterialApp.builder 处包住整个 Navigator，
/// 各页面 build 开头调用 [watch] 建立依赖。主题明暗变化时本 widget 的
/// [dark] 改变，[updateShouldNotify] 返回 true，所有调用过 [watch] 的页面
/// element 会被标记为需要重建 —— 于是 build 重新执行、[AppPalette.c] 按新
/// 明暗取色，一次切换即全量刷新。
///
/// 与「给 MaterialApp / 页面换 ValueKey 强制重建」不同，本方案走的是
/// InheritedWidget 依赖传播：只重新执行 build，State 对象原地保留，
/// 不会丢失正在编辑的笔记、滚动位置或导航栈。
class AppThemeScope extends InheritedWidget {
  final bool dark;

  const AppThemeScope({
    Key? key,
    required this.dark,
    required Widget child,
  }) : super(key: key, child: child);

  /// 建立对主题明暗的重建依赖，返回当前是否深色。
  ///
  /// 顺带把值同步回全局静态色板，保证本帧内 build 中任一
  /// [AppPalette.c] 调用都读到与 MaterialApp.theme 一致的明暗，
  /// 避免出现「主题已切、静态色板还是旧值」的错位。
  ///
  /// 首页 / 各路由页面在 build 开头调用即可；脱离 DiaryApp 单独 pump
  /// 的 widget 测试因无祖先 scope，会安全回退到 [AppPalette.dark]。
  static bool watch(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    if (scope == null) return AppPalette.dark;
    AppPalette.dark = scope.dark;
    return scope.dark;
  }

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) => dark != oldWidget.dark;
}
