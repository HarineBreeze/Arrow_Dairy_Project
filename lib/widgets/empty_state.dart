import 'package:flutter/material.dart';

/// 全局统一的空状态引导组件。
///
/// 所有主页（写日记 / 物资清单 / 倒数日 / 资产全景）在「一条数据都没有」或
/// 「筛选后无结果」时都用 [EmptyState]，后续新增主页直接复用，无需再各写一套。
///
/// 视觉规范：
/// - emoji 图标 56px
/// - 主文案 16px，颜色 0xFF2B3A55
/// - 副文案 13px，颜色 0xFF9AA8BF，行高 1.7
/// - 默认居中，顶部留白由 [topGap] 控制（列表里用 SizedBox 撑开时可为 0）
class EmptyState extends StatelessWidget {
  /// 顶部留白（在列表内单独撑开时用）
  final double topGap;

  /// 图标（emoji 或字符）
  final String icon;

  /// 主文案，如「还没有倒数日」
  final String title;

  /// 副文案，如「点右下角 + 添加第一个」
  final String subtitle;

  /// 可选的操作按钮文案，不传则不显示按钮
  final String? actionLabel;

  /// 操作按钮回调
  final VoidCallback? onAction;

  const EmptyState({
    Key? key,
    this.topGap = 180,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (topGap > 0) SizedBox(height: topGap),
        Text(icon, style: const TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            color: Color(0xFF2B3A55),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF9AA8BF),
            height: 1.7,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 20),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              primary: const Color(0xFF3B6FE0),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(actionLabel!,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }

  /// 在可滚动容器（ListView / CustomScrollView）里使用的版本：
  /// 自动撑满一屏宽度，方便直接放进 `children`。
  Widget inScroll() {
    return SizedBox(
      width: double.infinity,
      child: this,
    );
  }
}
