import 'package:flutter/widgets.dart';

/// 页面内部横向手势（日历翻月、愿望单攒钱滑动、置顶横滑卡带等）进行期间置为
/// true，主页据此让出本次滑动，**不再**把侧边菜单拖出来。
///
/// 语义：「优先级」而非「禁用」——只影响当前这一次滑动；松手后立刻恢复，
/// 页面其它区域、空白区域右滑依旧可以拉出菜单。
final ValueNotifier<bool> menuDragBlocked = ValueNotifier(false);

/// 页面手势闸门：包住会消费横向手势的组件。
///
/// 判定优先级（依次）：
/// 1. 子组件内的横向可滚动列表真实产生了滚动（ScrollNotification）
///    → 立刻置 [menuDragBlocked]，并在本次手势内保持；
/// 2. 该列表已滑到尽头、继续朝尽头方向滑动（无法再滚）
///    → **不拦**，让菜单接管（这是「左右滑不冲突」的情形）；
/// 3. 非可滚动组件（日历翻页、攒钱滑动）按位移方向判定：
///    横向位移超过 [activationSlop] 且明显大于纵向 → 拦。
///
/// 这样既保证「有页面功能时功能优先」，又不会像先前那样按下即拦、
/// 导致菜单手势在整块区域内都失效。
class PageGestureGate extends StatefulWidget {
  final Widget child;

  /// 子组件消费的手势轴向（null = 由位移方向自动判定）
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

  /// 本次手势内是否已经确认「页面功能正在执行」
  bool _owned = false;

  void _claim() {
    if (_owned) return;
    _owned = true;
    menuDragBlocked.value = true;
  }

  void _release() {
    _down = null;
    if (_owned) {
      _owned = false;
      menuDragBlocked.value = false;
    }
  }

  @override
  void dispose() {
    if (_owned) menuDragBlocked.value = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification) {
          // 新的一次手势开始（含新一轮 fling）
          if (!_owned) _down = null;
          return false;
        }
        if (n is ScrollUpdateNotification) {
          final d = n.scrollDelta ?? 0;
          final horizontal = n.metrics.axis == Axis.horizontal;
          // 纵向列表滚动：与横向菜单手势无冲突，不拦
          if (!horizontal) return false;
          final atStart = n.metrics.pixels <= n.metrics.minScrollExtent + 0.5;
          final atEnd = n.metrics.pixels >= n.metrics.maxScrollExtent - 0.5;
          // 已经到尽头还朝尽头方向滑 → 没有可执行的页面功能，交给菜单
          final towardStart = d > 0; // pixels 减小 = 朝起点
          final atEdge = (towardStart && atStart) || (!towardStart && atEnd);
          if (d.abs() > 0.01 && atEdge) return false;
          _claim();
          return false;
        }
        if (n is ScrollEndNotification) {
          // fling 可能仍在继续，等下一轮 Start 再复位
          return false;
        }
        return false;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          _down = e.position;
          _owned = false;
        },
        onPointerMove: (e) {
          if (_owned) return;
          final down = _down;
          if (down == null) return;
          final d = e.position - down;
          final dx = d.dx.abs();
          final dy = d.dy.abs();
          // 纵向为主 → 明确不是横向功能，不拦
          if (dy > dx) return;
          final axis = widget.swipeAxis;
          final horizontal = axis == null || axis == Axis.horizontal;
          final along = horizontal ? dx : dy;
          final across = horizontal ? dy : dx;
          if (along > widget.activationSlop && along > across * 1.2) {
            _claim();
          }
        },
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: widget.child,
      ),
    );
  }
}
