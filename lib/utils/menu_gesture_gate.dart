import 'package:flutter/widgets.dart';

/// 页面内部横向手势（愿望单卡片攒钱滑动、日历翻月滑动等）进行期间置为 true，
/// 用于阻止主页手势把菜单拖出来。
///
/// 约定：横向手势冲突时，当前页面功能优先执行，菜单手势让位。
final ValueNotifier<bool> menuDragBlocked = ValueNotifier(false);

/// 页面手势闸门：包住会消费横向手势的组件（日历翻页、攒钱滑动、横滑卡带等）。
/// 指针按下即标记 [menuDragBlocked]，菜单拖拽在移动判定时看到标记就让位；
/// 松手/取消后恢复。滑动进入菜单的动作不会误触发。
///
/// 注意：闸门只是「按下即拦」，如果子组件本身并不消费该方向手势（例如横滑卡带
/// 里只有一张卡、或用户实际在纵向滚动），菜单手势就会一直让位。
/// 因此对已知轴向的组件请传 [swipeAxis]，闸门会等指针朝该方向真正移动
/// 超过 [activationSlop] 后再拦，纵向滚动与「横滑到尽头后」都不受影响。
class PageGestureGate extends StatefulWidget {
  final Widget child;

  /// 子组件消费的手势轴向（null = 只要按下就拦，兼容旧的日历/攒钱滑动用法）
  final Axis? swipeAxis;

  /// 朝 [swipeAxis] 方向移动超过该距离才认定是横向手势
  final double activationSlop;

  const PageGestureGate({
    Key? key,
    required this.child,
    this.swipeAxis,
    this.activationSlop = 8,
  }) : super(key: key);

  @override
  State<PageGestureGate> createState() => _PageGestureGateState();
}

class _PageGestureGateState extends State<PageGestureGate> {
  Offset? _down;

  void _release() {
    _down = null;
    menuDragBlocked.value = false;
  }

  @override
  void dispose() {
    menuDragBlocked.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _down = e.position;
        if (widget.swipeAxis == null) menuDragBlocked.value = true;
      },
      onPointerMove: (e) {
        if (widget.swipeAxis == null || menuDragBlocked.value) return;
        final down = _down;
        if (down == null) return;
        final d = e.position - down;
        final dx = d.dx.abs();
        final dy = d.dy.abs();
        final horizontal = widget.swipeAxis == Axis.horizontal;
        final along = horizontal ? dx : dy;
        final across = horizontal ? dy : dx;
        // 确实是沿子组件手势方向在移动 → 拦下菜单拖拽
        if (along > widget.activationSlop && along > across) {
          menuDragBlocked.value = true;
        }
      },
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: widget.child,
    );
  }
}
