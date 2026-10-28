import 'package:flutter/material.dart';

import 'theme.dart';
import 'side_bar.dart';
import 'pages/diary_page.dart';
import 'pages/items_page.dart';
import 'pages/countdown_page.dart';
import 'pages/assets_page.dart';

/// 静态预览包装：真实页面在「无导航上下文 / 固定窄宽」下渲染，
/// 仅供方案总览并排展示使用。
class UiSideBarStatic extends StatelessWidget {
  final UiTheme theme;
  final bool compact;

  const UiSideBarStatic({Key? key, required this.theme, this.compact = false})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: EdgeInsets.zero, size: const Size(248, 496)),
      child: UiSideBar(
        theme: theme,
        nickname: 'Harine',
        uid: 'ID：10001',
        currentTab: 'diary',
        onSelectTab: (_) {},
        onTapProfile: () {},
        onOpenSettings: () {},
      ),
    );
  }
}

class DiaryPageStatic extends StatelessWidget {
  final UiTheme theme;
  const DiaryPageStatic({Key? key, required this.theme}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: EdgeInsets.zero, size: const Size(248, 496)),
      child: UiDiaryPage(theme: theme, onOpenMenu: () {}),
    );
  }
}

class ItemsPageStatic extends StatelessWidget {
  final UiTheme theme;
  const ItemsPageStatic({Key? key, required this.theme}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: EdgeInsets.zero, size: const Size(248, 496)),
      child: UiItemsPage(theme: theme, onOpenMenu: () {}),
    );
  }
}

class CountdownPageStatic extends StatelessWidget {
  final UiTheme theme;
  const CountdownPageStatic({Key? key, required this.theme}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: EdgeInsets.zero, size: const Size(248, 496)),
      child: UiCountdownPage(theme: theme, onOpenMenu: () {}),
    );
  }
}

class AssetsPageStatic extends StatelessWidget {
  final UiTheme theme;
  const AssetsPageStatic({Key? key, required this.theme}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(padding: EdgeInsets.zero, size: const Size(248, 496)),
      child: UiAssetsPage(theme: theme, onOpenMenu: () {}),
    );
  }
}

/// 页面外壳（供总览使用）：统一圆角/描边
class UiPhoneShell extends StatelessWidget {
  final UiTheme theme;
  final Widget child;
  const UiPhoneShell({Key? key, required this.theme, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.pageBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
