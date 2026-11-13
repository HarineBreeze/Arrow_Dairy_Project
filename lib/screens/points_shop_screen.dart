import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/reward_service.dart';
import '../services/user_storage.dart';
import '../utils/app_toast.dart';
import '../utils/haptics.dart';
import '../widgets/identity_badge.dart';
import '../widgets/pressable.dart';

/// 积分商城：用积分兑换身份牌。
///
/// 版式沿用全 App 的「页面底色 + 白色圆角卡 + 灰色节标题」节奏：
/// 顶部是积分余额卡，下面按品类分组（当前只有身份牌一类）。
///
/// 兑换规则：积分足够才能兑换，已拥有的商品不重复扣分；兑换成功后
/// 自动佩戴，用户也可以回个人信息页切回其它已拥有的牌。
class PointsShopScreen extends StatefulWidget {
  /// 仅测试使用：替换档案读取（避免 widget 测试里走真实文件 IO）
  @visibleForTesting
  final Future<UserProfile> Function()? loadOverride;

  /// 仅测试使用：替换真实兑换实现
  @visibleForTesting
  final Future<RedeemOutcome> Function(String badgeId)? buyOverride;

  const PointsShopScreen({Key? key, this.loadOverride, this.buyOverride})
      : super(key: key);

  @override
  State<PointsShopScreen> createState() => _PointsShopScreenState();
}

class _PointsShopScreenState extends State<PointsShopScreen> {
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await (widget.loadOverride ?? UserStorage.load)();
    if (!mounted) return;
    setState(() => _profile = p);
  }

  Future<void> _buy(ShopBadge item) async {
    final profile = _profile;
    if (profile == null) return;

    // 二次确认：积分是不可逆消耗，跟删除一样走两段式
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('兑换身份牌', style: TextStyle(fontSize: 17)),
        content: Text(
          '使用 ${item.price} 积分兑换「${item.name}」身份牌？\n'
          '当前积分 ${profile.points}，兑换后剩余 ${profile.points - item.price}。',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                '确认兑换',
                style: TextStyle(
                  color: Color(0xFF3E8E6D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final outcome =
        await (widget.buyOverride ?? RewardService.buyBadge)(item.id);
    if (!mounted) return;
    if (outcome.ok) Haptics.light();
    AppToast.show(context, outcome.message);
    // 无论成功与否都重读一次：成功时刷新余额与「已拥有」状态
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    return Scaffold(
      appBar: AppBar(title: const Text('积分商城')),
      body: profile == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _buildBalanceCard(profile),
                const SizedBox(height: 20),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '身份牌',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8FA09A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                for (final item in RewardService.shopBadges)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildGoodsCard(profile, item),
                  ),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '积分可通过每日首次发布笔记、参与活动获得。\n'
                    '身份牌兑换后会立即佩戴，可在个人信息页随时更换。',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.7,
                      color: Color(0xFFB2C2BA),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// 积分余额卡：左侧说明、右侧大数字，与个人信息页的积分栏同款配色
  Widget _buildBalanceCard(UserProfile profile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE4F2EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: AppIcon(AppIcons.gift, size: 20, color: Color(0xFF3E8E6D)),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '我的积分',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF24382F),
              ),
            ),
          ),
          Text(
            '${profile.points}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3E8E6D),
            ),
          ),
          const SizedBox(width: 3),
          const Text(
            '分',
            style: TextStyle(fontSize: 13, color: Color(0xFF8FA09A)),
          ),
        ],
      ),
    );
  }

  /// 商品卡：上方是身份牌大预览与价格，下方是整行按钮
  Widget _buildGoodsCard(UserProfile profile, ShopBadge item) {
    final owned = profile.owns(item.id);
    final affordable = profile.points >= item.price;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 放大 1.6 倍的牌，作为商品预览（与佩戴时同一套配色）
              IdentityBadge(badge: item.id, scale: 1.6),
              const Spacer(),
              Text(
                '${item.price} 积分',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3E8E6D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '佩戴后显示在昵称旁',
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFF8FA09A),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: Material(
              color: owned
                  ? const Color(0xFFF2F6F4)
                  : (affordable
                      ? const Color(0xFF3E8E6D)
                      : const Color(0xFFF2F6F4)),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: owned || !affordable ? null : () => _buy(item),
                child: Center(
                  child: Text(
                    owned
                        ? '已拥有'
                        : (affordable ? '兑换' : '积分不足'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: owned || !affordable
                          ? const Color(0xFF8FA09A)
                          : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
