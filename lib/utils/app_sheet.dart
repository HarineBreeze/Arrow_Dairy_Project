import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';

/// 全站底部弹层统一入口（v4.9.28）。
///
/// 收敛此前的散装 `showModalBottomSheet`：圆角、遮罩、拖拽手柄、
/// 入场/退出时长全部收口到一处，避免各页面手感不一致
/// （有的 16 圆角有的 24、有的带手柄有的不带）。
///
/// 用法：
/// ```dart
/// final action = await AppSheet.show<String>(
///   context,
///   builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [...]),
/// );
/// ```
/// 内容区不要自己再画顶部手柄与顶部留白，本方法已统一提供。
class AppSheet {
  AppSheet._();

  /// 统一样式参数
  static const double radius = 24;

  /// 顶部拖拽手柄：36×4 圆角条，随主题明暗自动换色
  static Widget handle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Container(
        key: const ValueKey('app_sheet_handle'),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppPalette.c(0xFFDCE7E0),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  /// 弹出底部弹层。
  ///
  /// [isScrollControlled] 用于内容可能超过半屏的场景（表单、选择器）；
  /// 动作菜单保持默认的「半屏上限 + 拖拽收起」。
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool barrierDismissible = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: barrierDismissible,
      enableDrag: true,
      // v4.9.50：面板底色不再用 backgroundColor（该值在弹层创建时固定，
      // 深色模式抽屉内手动切换模式时不会刷新，只有重弹才恢复）。
      // 改为透明 + 内部 [_ThemedSheetSurface] 自绘底色，它订阅 AppThemeScope，
      // 主题/模式切换即重建，外圈与内部颜色同步更新。
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x66000000),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      ),
      clipBehavior: Clip.antiAlias,
      builder: (ctx) => _ThemedSheetSurface(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            handle(ctx),
            Flexible(child: builder(ctx)),
          ],
        ),
      ),
    );
  }
}

/// 弹层面板：订阅主题明暗，切换模式时自绘底色随之重建。
class _ThemedSheetSurface extends StatelessWidget {
  final Widget child;
  const _ThemedSheetSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    // 建立对 AppThemeScope 的依赖：主题/模式变化时本组件重建，
    // 面板底色读取的就是映射后的新值（深色下为深灰绿）。
    AppThemeScope.watch(context);
    return ColoredBox(color: AppPalette.c(0xFFFFFFFF), child: child);
  }
}
