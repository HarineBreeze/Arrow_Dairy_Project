import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 页面内部横向手势（愿望单卡片攒钱滑动、日历翻月滑动等）进行期间置为 true，
/// 用于阻止主页手势把菜单拖出来。
///
/// 约定：横向手势冲突时，当前页面功能优先执行，菜单手势让位。
final ValueNotifier<bool> menuDragBlocked = ValueNotifier(false);

/// 页面手势闸门：包住会消费横向手势的组件（日历翻页、攒钱滑动等）。
/// 指针按下即标记 [menuDragBlocked]，菜单拖拽在移动判定时看到标记就让位；
/// 松手/取消后恢复。滑动进入菜单的动作不会误触发。
class PageGestureGate extends StatelessWidget {
  final Widget child;

  const PageGestureGate({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => menuDragBlocked.value = true,
      onPointerUp: (_) => menuDragBlocked.value = false,
      onPointerCancel: (_) => menuDragBlocked.value = false,
      child: child,
    );
  }
}
