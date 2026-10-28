import 'package:flutter/material.dart';

import 'theme.dart';
import 'side_bar.dart';
import 'pages/diary_page.dart';
import 'pages/items_page.dart';
import 'pages/countdown_page.dart';
import 'pages/assets_page.dart';

/// UI 方案预览页：一套方案内「菜单侧边栏 + 四主页」成套展示，
/// 侧边栏可从左侧滑出（或点左上角菜单），与正式 App 交互一致。
class UiShowcaseScreen extends StatefulWidget {
  final UiTheme theme;

  const UiShowcaseScreen({Key? key, required this.theme}) : super(key: key);

  @override
  State<UiShowcaseScreen> createState() => _UiShowcaseScreenState();
}

class _UiShowcaseScreenState extends State<UiShowcaseScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _menuController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 0,
  );
  late final Animation<double> _menuAnim =
      CurvedAnimation(parent: _menuController, curve: Curves.easeOutCubic);

  String _tab = 'diary';
  double? _dragBase;
  double _dx = 0;
  double _dy = 0;
  bool _dragActive = false;

  UiTheme get t => widget.theme;

  @override
  void dispose() {
    _menuController.dispose();
    super.dispose();
  }

  void _openMenu() => _menuController.forward();
  void _closeMenu() => _menuController.reverse();

  void _onDragStart(DragStartDetails d) {
    _menuController.stop();
    _dragBase = _menuAnim.value;
    _dx = 0;
    _dy = 0;
    _dragActive = false;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final base = _dragBase;
    if (base == null) return;
    _dx += d.delta.dx;
    _dy += d.delta.dy;
    if (!_dragActive) {
      if (_dx.abs() > _dy.abs()) {
        _dragActive = true;
      } else {
        return;
      }
    }
    final w = MediaQuery.of(context).size.width * 3 / 4;
    _menuController.value = (base + _dx / w).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragBase == null) return;
    _dragBase = null;
    if (!_dragActive) return;
    final vx = d.velocity.pixelsPerSecond.dx;
    if (vx < -600) {
      _closeMenu();
    } else if (vx > 600 || _menuController.value > 0.45) {
      _openMenu();
    } else {
      _closeMenu();
    }
  }

  void _onDragCancel() {
    if (!_dragActive) return;
    _dragBase = null;
    _menuController.value > 0.45 ? _openMenu() : _closeMenu();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.pageBg,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _menuAnim,
            builder: (context, _) {
              final menuWidth = MediaQuery.of(context).size.width * 3 / 4;
              return Stack(
                children: [
                  Transform.translate(
                    offset: Offset(menuWidth * _menuAnim.value, 0),
                    child: _buildPage(),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _menuAnim.value <= 0,
                      child: GestureDetector(
                        onTap: _closeMenu,
                        child: ColoredBox(
                          color: Colors.black
                              .withOpacity(_menuAnim.value * 0.42),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: menuWidth,
                    child: Transform.translate(
                      offset: Offset(-menuWidth * (1 - _menuAnim.value), 0),
                      child: Material(
                        color: t.menuBg,
                        elevation: 10,
                        child: SafeArea(
                          bottom: false,
                          child: UiSideBar(
                            theme: t,
                            nickname: 'Harine',
                            uid: 'ID：10001',
                            currentTab: _tab,
                            onTapProfile: _closeMenu,
                            onOpenSettings: _closeMenu,
                            onSelectTab: (id) {
                              setState(() => _tab = id);
                              _closeMenu();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // 手势层
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width / 2,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: _onDragStart,
              onPanUpdate: _onDragUpdate,
              onPanEnd: _onDragEnd,
              onPanCancel: _onDragCancel,
            ),
          ),
          Positioned(
            left: MediaQuery.of(context).size.width / 3,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 2 / 3,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: _onDragStart,
              onPanUpdate: _onDragUpdate,
              onPanEnd: _onDragEnd,
              onPanCancel: _onDragCancel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_tab) {
      case 'items':
        return UiItemsPage(theme: t, onOpenMenu: _openMenu);
      case 'countdown':
        return UiCountdownPage(theme: t, onOpenMenu: _openMenu);
      case 'assets':
        return UiAssetsPage(theme: t, onOpenMenu: _openMenu);
      case 'diary':
      default:
        return UiDiaryPage(theme: t, onOpenMenu: _openMenu);
    }
  }
}
