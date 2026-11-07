import 'package:flutter/material.dart';

import 'app_icons.dart';
import 'lucide_icons.dart';

/// 统一渲染「图标值」：全站存储的图标字符串（资产/物品/日记心情天气/事件）。
///
/// 存储值有三种来源，[EntryIcon] 全部兼容：
/// - **预设 emoji**（旧数据 + 各选择器写入的值）：命中 [Lucide.byEmoji]
///   映射 → 用 [AppIcon] 渲染 Lucide 细线图标；
/// - **`@lucide:name`**（保留的显式标识，供未来扩展）：直接查 [Lucide.paths]；
/// - **其它任意文本**（用户自定义 emoji 输入）：原样 [Text] 渲染，
///   自定义选项不受影响。
///
/// 数据层继续存 emoji 字符串：老用户数据零迁移，选择器写入的值不变，
/// 只有渲染层从「系统 emoji 字形」切换成 Lucide 细线图形。
class EntryIcon extends StatelessWidget {
  /// 存储的图标值（emoji / `@lucide:name` / 自定义文本）
  final String value;

  /// 渲染尺寸（图标边长 / 文本字号）
  final double size;

  /// 图标颜色（仅 Lucide 路径生效；自定义 emoji 保持彩色字形）
  final Color? color;

  const EntryIcon(
    this.value, {
    Key? key,
    this.size = 24,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final path = Lucide.pathFor(value);
    if (path != null) {
      return AppIcon(path,
          size: size, color: color ?? const Color(0xFF24382F));
    }
    return Text(value, style: TextStyle(fontSize: size, height: 1.0));
  }
}
