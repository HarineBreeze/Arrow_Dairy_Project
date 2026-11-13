import 'package:flutter/material.dart';

import '../models/user_profile.dart';

/// 身份牌：昵称旁的小胶囊。
///
/// 视觉规范（与侧边栏、个人信息页、积分商城共用一份实现）：
/// - 普通版：灰底 `#8FA09A` + 白字（默认佩戴）
/// - 内测版：橙底 `#F08C3A` + 白字
/// - VIP：红底 `#CB5C50` + 白字
/// - 诞生日：绿底 `#3E8E6D` + 白字
/// - 11px / w600 / 行高 1.2，左右 6px、上下 1.5px 内边距，圆角 8
///
/// 未知 id 返回零尺寸占位，调用方可无条件插入而不产生空行。
class IdentityBadge extends StatelessWidget {
  final String badge;

  /// 放大倍数：积分商城的商品预览用它把牌放大到可看清的尺寸
  final double scale;

  const IdentityBadge({Key? key, required this.badge, this.scale = 1})
      : super(key: key);

  /// 是否普通版（空值按普通版处理，兼容旧档案）
  static bool isNormal(String badge) =>
      badge.isEmpty || badge == UserProfile.badgeNormal;

  /// 身份牌文案（未知 id 返回 null）
  static String? labelOf(String badge) {
    switch (badge) {
      case '':
      case UserProfile.badgeNormal:
        return '普通版';
      case UserProfile.badgeBeta:
        return '内测版';
      case UserProfile.badgeVip:
        return 'VIP';
      case UserProfile.badgeBirthday:
        return '诞生日';
      default:
        return null;
    }
  }

  /// 身份牌底色
  static Color? colorOf(String badge) {
    switch (badge) {
      case '':
      case UserProfile.badgeNormal:
        return const Color(0xFF8FA09A);
      case UserProfile.badgeBeta:
        return const Color(0xFFF08C3A);
      case UserProfile.badgeVip:
        return const Color(0xFFCB5C50);
      case UserProfile.badgeBirthday:
        return const Color(0xFF3E8E6D);
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
      padding: EdgeInsets.symmetric(
        horizontal: 6 * scale,
        vertical: 1.5 * scale,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8 * scale),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11 * scale,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
