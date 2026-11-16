import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/reward_service.dart';
import '../services/user_storage.dart';
import '../utils/app_toast.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
/// 积分商城：用积分兑换身份牌 / 限时 VIP 权益。
///
/// 版式沿用全 App 的「页面底色 + 白色圆角卡 + 灰色节标题」节奏：
/// 顶部是积分余额卡，下面是「道具兑换」分组里的商品卡
/// （名称 + 备注 + 价格 + 已兑/上限）。
///
/// 商品卡本身就是按钮（带按压缩放回弹）：
/// - 已拥有 / 积分不足 / 达到兑换上限：卡片置灰，点击给出对应提示；
/// - 可兑换：点击弹确认框「是否要花费 x 积分兑换？」。
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

  /// 商品是否已不可再兑（限时 VIP 卡看次数上限；永久牌看已拥有）
  bool _soldOut(UserProfile p, ShopBadge item) {
    if (item.isVipTimeCard) return item.usedCount(p) >= item.limit;
    return p.owns(item.id);
  }

  Future<void> _onTapItem(UserProfile profile, ShopBadge item) async {
    if (_soldOut(profile, item)) {
      _toast(item.isVipTimeCard
          ? '已达兑换上限（${item.limit} 次）'
          : '已拥有「${item.name}」');
      return;
    }
    if (profile.points < item.price) {
      _toast('积分不足，还差 ${item.price - profile.points} 积分');
      return;
    }

    final isTimeCard = item.isVipTimeCard;
    // 二次确认：积分是不可逆消耗，跟删除一样走两段式
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.c(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Text(
          isTimeCard
              ? '是否要花费 ${item.price} 积分兑换「${item.name}」？\n'
                  '兑换后立即生效，${item.effectLabel}。'
              : '是否要花费 ${item.price} 积分兑换「${item.name}」？',
          style: const TextStyle(fontSize: 13, height: 1.7),
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
                '确认',
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

    final outcome = await (widget.buyOverride ??
        (isTimeCard ? RewardService.buyVipCard : RewardService.buyBadge))(
        item.id);
    if (!mounted) return;
    if (outcome.ok) Haptics.light();
    _toast(outcome.message);
    // 无论成功与否都重读一次：成功时刷新余额与已购状态
    await _load();
  }

  void _toast(String msg) => AppToast.show(context, msg);

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
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
                Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '道具兑换',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppPalette.c(0xFF8FA09A),
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
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '积分是兑换道具的货币，可通过参与活动的方式获得',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.7,
                      color: AppPalette.c(0xFFB2C2BA),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// 积分余额卡：左侧「我的积分」、右侧大数字。
  /// 不加图标与底纹，文字与下方商品卡名称同一条左对齐线。
  Widget _buildBalanceCard(UserProfile profile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '我的积分',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppPalette.c(0xFF24382F),
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
          Text(
            '分',
            style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
          ),
        ],
      ),
    );
  }

  /// 商品卡：名称 + 备注 + 价格 + 兑换次数，整卡可点（按压缩放回弹）
  Widget _buildGoodsCard(UserProfile profile, ShopBadge item) {
    final soldOut = _soldOut(profile, item);
    final affordable = profile.points >= item.price;
    final enabled = !soldOut && affordable;
    // 不可兑换时整卡置灰，只保留极淡的边界感
    final cardColor = enabled ? AppPalette.c(0xFFFFFFFF) : AppPalette.c(0xFFF2F6F4);
    final titleColor =
        enabled ? AppPalette.c(0xFF24382F) : AppPalette.c(0xFF8FA09A);
    final priceColor =
        enabled ? const Color(0xFF3E8E6D) : AppPalette.c(0xFFB2C2BA);

    // 兑换次数用「已兑/上限」的紧凑数字（如 0/6、2/30）。
    // 永久牌只有一次，拥有即记 1；限时卡按各自累计次数计。
    final used = item.usedCount(profile);

    return Pressable(
      enabled: true,
      child: GestureDetector(
        key: ValueKey('shop-item-${item.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTapItem(profile, item),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${item.price} 积分',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: priceColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      item.note,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppPalette.c(0xFF8FA09A),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 兑换次数：无底纹，字色与商品备注同款淡灰
                  Text(
                    '$used/${item.limit}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.c(0xFF8FA09A),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
