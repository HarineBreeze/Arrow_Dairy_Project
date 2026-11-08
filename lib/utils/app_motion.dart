import 'package:flutter/material.dart';

/// 全局动效常量与统一页面转场。
///
/// 之前 home / asset / countdown / search / item / settings 各自复制了一份
/// `_slideRoute`，时长与曲线不完全一致（有的 300ms，有的曲线不同），
/// 表现为「这页快那页慢」。集中到这里后改一处即全局生效。
class AppMotion {
  AppMotion._();

  /// 页面进入 / 退出时长
  static const Duration pageDuration = Duration(milliseconds: 300);

  /// 页面转场曲线（入场与退场共用，保证往返对称）
  static const Curve pageCurve = Curves.easeOutCubic;

  /// 列表滚动超过该距离才显示「回顶」按钮
  static const double backToTopThreshold = 600;

  /// 通用右侧滑入转场：新页从右推入，旧页轻微左移让位。
  /// 旧实现只有新页滑入，返回时旧页是静止的，观感偏「生硬」。
  static Route<T> slide<T>(Widget page, {String? name}) {
    return PageRouteBuilder<T>(
      settings: RouteSettings(name: name),
      transitionDuration: pageDuration,
      reverseTransitionDuration: pageDuration,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: pageCurve);
        final incoming = Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved);
        // 被覆盖的旧页向左让出 25% 宽度（比 100% 更轻，避免来回晃眼）
        final outgoing = Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.25, 0),
        ).animate(CurvedAnimation(
          parent: secondaryAnimation,
          curve: pageCurve,
        ));
        // 同一个 builder 同时服务「新页滑入」与「旧页让位」两种局面：
        // 新页读 animation，旧页读 secondaryAnimation，内外两层各管一个。
        return SlideTransition(
          position: incoming,
          child: SlideTransition(position: outgoing, child: child),
        );
      },
    );
  }
}
