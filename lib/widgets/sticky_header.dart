import 'package:flutter/material.dart';

/// 列表中的一次「段头」声明：吸附时显示 [builder]，列表内正常位置也显示它。
class StickySection {
  /// 段头视觉高度（含内边距）。吸附层优先用实测高度，此值仅作兜底。
  final double height;

  /// 构造段头。列表内与吸附层共用，保证视觉一致。
  final Widget Function() builder;

  /// 吸附层是否需要接收手势（如置顶横滑卡带要能左右滑动、点卡片）。
  /// 默认 false：吸附层套 [IgnorePointer]，点击/折叠手势穿透到列表里的真实标题。
  final bool interactive;

  const StickySection({
    required this.height,
    required this.builder,
    this.interactive = false,
  });
}

/// 可滚动列表 + 吸顶分段标题。
///
/// ## 为什么不用 ListView.builder
/// `ListView` 是懒构建的：段头一旦滚出视口，它的 Element 就被回收，
/// `currentContext` 变空 —— 而「判断该不该吸顶」恰恰发生在它离开视口的
/// 那一刻，于是永远判定不到（实测：jumpTo 之后 `find.text('置顶')`
/// 直接拿到 0 个）。
///
/// 这里改用 `SingleChildScrollView + Column`：所有子项一次性构建、常驻，
/// RenderBox 永远可测，段头位置判定就没有时序问题。
/// 代价是全量构建 —— 两个主页的分组项都只有几十个，可以接受。
///
/// ## 吸顶策略
/// 每个段头都会「粘」在顶部：滚动到它上面时固定，下一段头把它顶走。
class StickySectionList extends StatefulWidget {
  final List<Object> children;
  final EdgeInsets padding;
  final ScrollPhysics? physics;

  /// 吸附层底色：必须与该处列表背景一致，否则段头下面会透出卡片
  final Color background;

  /// 吸顶层顶部内边距（与列表 padding.top 对齐）
  final double topInset;

  final ScrollController? controller;

  const StickySectionList({
    Key? key,
    required this.children,
    required this.background,
    this.padding = const EdgeInsets.only(bottom: 96),
    this.physics,
    this.topInset = 0,
    this.controller,
  }) : super(key: key);

  @override
  State<StickySectionList> createState() => _StickySectionListState();
}

class _StickySectionListState extends State<StickySectionList> {
  final GlobalKey _viewportKey = GlobalKey();
  final ScrollController _own = ScrollController();

  /// 每个段头一个 key，用来读它在视口内的位置
  List<GlobalKey> _keys = [];
  List<StickySection> _sections = [];

  ScrollController get _ctrl => widget.controller ?? _own;

  @override
  void initState() {
    super.initState();
    _sync();
    _ctrl.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(StickySectionList old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _own).removeListener(_onScroll);
      _ctrl.addListener(_onScroll);
    }
    final before = _sections.length;
    _sync();
    if (before != _sections.length) setState(() {});
  }

  @override
  void dispose() {
    (widget.controller ?? _own).removeListener(_onScroll);
    _own.dispose();
    super.dispose();
  }

  void _sync() {
    final secs = <StickySection>[
      for (final c in widget.children)
        if (c is StickySection) c
    ];
    if (secs.length != _sections.length) {
      _keys = [for (var i = 0; i < secs.length; i++) GlobalKey()];
    }
    _sections = secs;
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  /// 找出当前应该吸附的段头，以及它被下一段头顶走的位移
  _Stuck? _resolve() {
    // 没滚动过就不要吸附：列表顶部第一段本来就原位显示，
    // 再叠一层会让标题重叠、且退出时来不及消失
    if (!_ctrl.hasClients || _ctrl.offset <= 0.5) return null;
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return null;
    final origin = viewport.localToGlobal(Offset.zero).dy;
    final inset = widget.topInset;

    var hit = -1;
    var hitHeight = 0.0;
    var nextTop = double.infinity;
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy - origin;
      if (top <= inset + 0.5) {
        hit = i;
        hitHeight = box.size.height;
      } else {
        nextTop = top;
        break;
      }
    }
    if (hit < 0) return null;
    final push = nextTop == double.infinity
        ? 0.0
        : (nextTop - inset - hitHeight);
    return _Stuck(hit, push < 0 ? 0.0 : push, hitHeight);
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var k = 0;
    for (final c in widget.children) {
      if (c is StickySection) {
        children.add(KeyedSubtree(key: _keys[k++], child: c.builder()));
      } else {
        children.add(c as Widget);
      }
    }

    final stuck = _resolve();
    return Stack(
      key: _viewportKey,
      children: [
        SingleChildScrollView(
          controller: _ctrl,
          physics: widget.physics,
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
        if (stuck != null)
          Positioned(
            left: 0,
            right: 0,
            top: widget.topInset - stuck.push,
            child: _sections[stuck.index].interactive
                ? Container(
                    color: widget.background,
                    height: stuck.height,
                    alignment: Alignment.centerLeft,
                    child: _sections[stuck.index].builder(),
                  )
                : IgnorePointer(
                    // 吸附层不吃点击：折叠手势要落到列表里那个真实标题上
                    child: Container(
                      color: widget.background,
                      height: stuck.height,
                      alignment: Alignment.centerLeft,
                      child: _sections[stuck.index].builder(),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// 吸附中的段头：index + 被下一段顶走的像素数 + 实测高度
class _Stuck {
  final int index;
  final double push;
  final double height;
  const _Stuck(this.index, this.push, this.height);
}
