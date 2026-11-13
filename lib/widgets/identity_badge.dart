import 'package:flutter/material.dart';

import '../models/user_profile.dart';

/// 身份铭牌：昵称旁的小胶囊。
///
/// 视觉规范（与侧边栏、个人信息页共用一份实现）：
/// - 内测版：橙底 `#F08C3A` + 白字
/// - VIP：红底 `#CB5C50` + 白字
/// - 11px / w600 / 行高 1.2，左右 6px、上下 1.5px 内边距，圆角 8
///
/// badge 为空时返回零尺寸占位，调用方可无条件插入而不产生空行。
class IdentityBadge extends StatelessWidget {
  final String badge;

  const IdentityBadge({Key? key, required this.badge}) : super(key: key);

  /// 铭牌文案（未知 id 返回 null）
  static String? labelOf(String badge) {
    switch (badge) {
      case UserProfile.badgeBeta:
        return '内测版';
      case UserProfile.badgeVip:
        return 'VIP';
      default:
        return null;
    }
  }

  /// 铭牌底色
  static Color? colorOf(String badge) {
    switch (badge) {
      case UserProfile.badgeBeta:
        return const Color(0xFFF08C3A);
      case UserProfile.badgeVip:
        return const Color(0xFFCB5C50);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = labelOf(badge);
    final color = colorOf(badge);
    if (label == null || color == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
