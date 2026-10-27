import 'package:flutter/material.dart';

/// 全局统一的骨架屏组件。
///
/// 所有主页（写日记 / 物资清单 / 倒数日 / 资产全景）首屏加载时都用 [ListSkeleton]，
/// 保证切换主页时的加载观感完全一致。后续新增主页直接复用即可。
///
/// 设计要点：
/// - 呼吸动画统一 1100ms 往复（0.4 ~ 0.65 透明度），多个骨架块共用一个控制器；
/// - 卡片内只用 Column + Container 拼装，避免 Row 的 const 构造限制（Flutter 3.0）；
/// - 不接收手势，全部为 [NeverScrollableScrollPhysics]，加载态下不可滚动。

/// 骨架块的颜色（随呼吸系数变化）
const Color _kSkeletonBase = Color(0xFFE4E9F2);

/// 呼吸动画驱动的骨架容器：内部所有 [SkeletonBlock] 共享同一个透明度。
class SkeletonShimmer extends StatefulWidget {
  final Widget child;

  const SkeletonShimmer({Key? key, required this.child}) : super(key: key);

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl!,
      builder: (context, _) {
        final op = 0.4 + 0.25 * _ctrl!.value; // 0.4 ~ 0.65
        return _SkeletonScope(
          opacity: op,
          child: widget.child,
        );
      },
    );
  }
}

/// 把呼吸透明度传给子级的 [SkeletonBlock]，避免每块都建一个 AnimatedBuilder
class _SkeletonScope extends InheritedWidget {
  final double opacity;

  const _SkeletonScope({required this.opacity, required Widget child})
      : super(child: child);

  static double of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SkeletonScope>();
    return scope?.opacity ?? 0.5;
  }

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) =>
      oldWidget.opacity != opacity;
}

/// 单个骨架色块（圆角矩形 / 圆形）
class SkeletonBlock extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  const SkeletonBlock({
    Key? key,
    this.width,
    required this.height,
    this.radius = 6,
    this.circle = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final op = _SkeletonScope.of(context);
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: _kSkeletonBase.withOpacity(op),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// 单张骨架卡片：顶部圆形头像 + 标题长条，下方两条正文（第二条 60% 宽）
class SkeletonCard extends StatelessWidget {
  /// 是否显示顶部「头像 + 标题」行（卡片类列表用 true，纯文本行用 false）
  final bool withAvatar;

  const SkeletonCard({Key? key, this.withAvatar = true}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (withAvatar) ...[
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  const SkeletonBlock(height: 28, circle: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      alignment: Alignment.centerLeft,
                      child: const SkeletonBlock(height: 12, width: 9999),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SkeletonBlock(height: 10, width: 9999),
          const SizedBox(height: 8),
          const FractionallySizedBox(
            widthFactor: 0.6,
            alignment: Alignment.centerLeft,
            child: SkeletonBlock(height: 10, width: 9999),
          ),
        ],
      ),
    );
  }
}

/// 列表骨架：主页通用首屏加载占位（3 张卡片）
class ListSkeleton extends StatelessWidget {
  /// 卡片数量，默认 3 张，够填满一屏
  final int count;

  /// 外层内边距，各主页可按自己的列表内距覆盖
  final EdgeInsetsGeometry padding;

  /// 卡片是否带「头像 + 标题」行
  final bool withAvatar;

  const ListSkeleton({
    Key? key,
    this.count = 3,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 96),
    this.withAvatar = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        children: List<Widget>.generate(
          count,
          (i) => SkeletonCard(withAvatar: withAvatar),
        ),
      ),
    );
  }
}
