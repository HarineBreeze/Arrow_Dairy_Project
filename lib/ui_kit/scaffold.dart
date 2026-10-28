import 'package:flutter/material.dart';
import 'theme.dart';

/// 页面骨架：统一「顶栏 → 大标题（可选）→ 统计条（可选）→ 内容区」的节奏，
/// 四套方案共用同一骨架，只换视觉令牌。
class UiScaffold extends StatelessWidget {
  final UiTheme theme;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? statsBar;
  final Widget? filterBar;
  final Widget child;
  final VoidCallback onOpenMenu;

  const UiScaffold({
    Key? key,
    required this.theme,
    required this.title,
    required this.onOpenMenu,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.statsBar,
    this.filterBar,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final hero = theme.titleLayout == UiTitleLayout.hero;
    final top = MediaQuery.of(context).padding.top;

    return Container(
      color: theme.pageBg,
      child: Column(
        children: [
          _buildHeader(context, top, hero),
          if (hero)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 25,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: theme.textPrimary,
                      ),
                    ),
                  ),
                  if (subtitle != null)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 3, left: 8),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1.1,
                            color: theme.textTertiary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (statsBar != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: statsBar,
            ),
          if (filterBar != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: filterBar,
            ),
          const SizedBox(height: 4),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double statusBarHeight, bool hero) {
    final canPop = Navigator.of(context).canPop();
    final showMenu = !canPop;

    switch (theme.headerStyle) {
      case UiHeaderStyle.gradientBleed:
        return Container(
          padding: EdgeInsets.only(top: statusBarHeight),
          decoration: BoxDecoration(gradient: theme.headerGradient),
          child: Column(
            children: [
              SizedBox(
                height: hero ? 0 : 52,
                child: hero
                    ? null
                    : Row(
                        children: [
                          _navButton(
                            context: context,
                            icon: showMenu ? Icons.menu : Icons.arrow_back,
                            onTap: () => showMenu
                                ? onOpenMenu()
                                : Navigator.of(context).maybePop(),
                            color: Colors.white,
                          ),
                          Expanded(
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          ..._tintedActions(Colors.white),
                          const SizedBox(width: 2),
                        ],
                      ),
              ),
            ],
          ),
        );
      case UiHeaderStyle.solidFlat:
      case UiHeaderStyle.glass:
        final isGlass = theme.headerStyle == UiHeaderStyle.glass;
        return Container(
          padding: EdgeInsets.only(top: statusBarHeight),
          decoration: BoxDecoration(
            color: isGlass
                ? theme.menuBg.withOpacity(0.72)
                : (hero ? Colors.transparent : theme.cardBg),
            border: Border(
              bottom: BorderSide(
                color: isGlass ? theme.divider : Colors.transparent,
              ),
            ),
          ),
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                _navButton(
                  context: context,
                  icon: showMenu ? Icons.menu : Icons.arrow_back,
                  onTap: () => showMenu
                      ? onOpenMenu()
                      : Navigator.of(context).maybePop(),
                  color: theme.textPrimary,
                ),
                if (!hero)
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                  )
                else
                  const Expanded(child: SizedBox()),
                ..._tintedActions(theme.textSecondary),
                const SizedBox(width: 2),
              ],
            ),
          ),
        );
    }
  }

  /// actions 默认按「白/灰」两套顶栏自动着色
  List<Widget> _tintedActions(Color tint) {
    if (actions.isEmpty) return const [];
    return actions
        .map((w) => w is UiHeaderAction
            ? UiHeaderAction(icon: w.icon, tint: tint, onTap: w.onTap)
            : w)
        .toList();
  }

  Widget _navButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, size: 22, color: color),
        ),
      ),
    );
  }
}

/// 顶栏右侧图标：颜色由 UiScaffold 按顶栏风格自动覆盖
class UiHeaderAction extends StatelessWidget {
  final IconData icon;
  final Color? tint;
  final VoidCallback? onTap;

  const UiHeaderAction({
    Key? key,
    required this.icon,
    this.tint,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 46,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Icon(icon, size: 20, color: tint ?? Colors.white70),
      ),
    );
  }
}

/// 统一卡片容器：四套方案只改圆角 / 描边 / 阴影
class UiCard extends StatelessWidget {
  final UiTheme theme;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const UiCard({
    Key? key,
    required this.theme,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? theme.cardBg,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        border: theme.cardBorder == null
            ? null
            : Border.all(color: theme.cardBorder!),
        boxShadow: theme.isDark || theme.cardBorder != null
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.045),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: child,
    );
  }
}

/// 统一分组头
class UiSectionHeader extends StatelessWidget {
  final UiTheme theme;
  final String title;
  final int count;
  final Color dotColor;
  final bool expanded;
  final VoidCallback? onTap;

  const UiSectionHeader({
    Key? key,
    required this.theme,
    required this.title,
    required this.count,
    required this.dotColor,
    this.expanded = true,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: theme.textPrimary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: TextStyle(fontSize: 12, color: theme.textTertiary),
        ),
        const SizedBox(width: 6),
        if (onTap != null)
          Icon(
            expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 16,
            color: theme.textTertiary,
          ),
      ],
    );

    Widget body;
    switch (theme.sectionHeaderStyle) {
      case UiSectionHeaderStyle.bar:
        body = Row(
          children: [
            Container(
              width: 3.5,
              height: 14,
              decoration: BoxDecoration(
                color: dotColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            label,
          ],
        );
        break;
      case UiSectionHeaderStyle.pill:
        body = Container(
          padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
          decoration: BoxDecoration(
            color: dotColor.withOpacity(theme.isDark ? 0.18 : 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.isDark ? theme.textPrimary : dotColor,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(fontSize: 11.5, color: theme.textTertiary),
              ),
            ],
          ),
        );
        break;
      case UiSectionHeaderStyle.plain:
        body = Row(
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1.6,
                fontWeight: FontWeight.w600,
                color: theme.textSecondary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(height: 1, color: theme.divider),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.6,
                color: theme.textTertiary,
              ),
            ),
          ],
        );
        break;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
        child: body,
      ),
    );
  }
}

/// 统一筛选胶囊
class UiChip extends StatelessWidget {
  final UiTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const UiChip({
    Key? key,
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final solid = selected && theme.chipSolid;
    return Material(
      color: solid
          ? theme.accent
          : (selected ? theme.accent.withOpacity(0.10) : Colors.transparent),
      borderRadius: BorderRadius.circular(theme.chipRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(theme.chipRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(theme.chipRadius),
            border: Border.all(
              color: selected
                  ? (theme.chipSolid ? theme.accent : theme.accent)
                  : theme.divider,
              width: selected && !theme.chipSolid ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: solid ? Colors.white : (selected ? theme.accent : theme.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一统计条（顶栏下方的数据带）
class UiStatsBar extends StatelessWidget {
  final UiTheme theme;
  final List<UiStat> stats;

  const UiStatsBar({Key? key, required this.theme, required this.stats})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bleed = theme.headerStyle == UiHeaderStyle.gradientBleed;
    final bg = bleed ? Colors.white.withOpacity(0.16) : theme.surfaceAlt;
    final labelColor = bleed ? Colors.white70 : theme.textTertiary;
    final valueColor = bleed ? Colors.white : theme.textPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(theme.cardRadius),
        border: bleed
            ? null
            : Border.all(color: theme.divider),
      ),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 24,
                color: bleed ? Colors.white24 : theme.divider,
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stats[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: labelColor),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        stats[i].value,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          color: stats[i].valueColor ?? valueColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class UiStat {
  final String label;
  final String value;
  final Color? valueColor;
  const UiStat(this.label, this.value, {this.valueColor});
}
