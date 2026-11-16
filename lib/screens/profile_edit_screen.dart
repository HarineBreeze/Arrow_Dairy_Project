import 'dart:io';
import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/app_motion.dart';
import '../utils/app_toast.dart';
import '../utils/haptics.dart';
import '../models/user_profile.dart';
import '../services/reward_service.dart';
import '../services/user_storage.dart';
import '../widgets/avatar.dart';
import '../widgets/identity_badge.dart';
import 'points_shop_screen.dart';
import '../widgets/unsaved_guard.dart';
import '../widgets/pressable.dart';
import '../widgets/save_done_button.dart';
import '../widgets/save_bar.dart';

import '../theme/app_palette.dart';
class ProfileEditScreen extends StatefulWidget {
  final UserProfile profile;

  /// 仅测试使用：替换真实切牌实现（避免 widget 测试里走真实文件 IO）
  @visibleForTesting
  final Future<RedeemOutcome> Function(String badgeId)? wearOverride;

  /// 仅测试使用：替换积分商城页面（默认打开真实的 [PointsShopScreen]）
  @visibleForTesting
  final Widget Function()? shopBuilder;

  /// 仅测试使用：替换档案读取（商城返回后刷新积分用）
  @visibleForTesting
  final Future<UserProfile> Function()? loadOverride;

  /// 仅测试使用：替换剪贴板写入（避免 widget 测试里平台通道挂起）
  @visibleForTesting
  final Future<void> Function(String text)? clipboardOverride;

  const ProfileEditScreen({
    Key? key,
    required this.profile,
    this.wearOverride,
    this.shopBuilder,
    this.loadOverride,
    this.clipboardOverride,
  }) : super(key: key);

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _nicknameCtrl;
  late String _gender;
  late String _avatarPath;
  bool _saving = false;

  /// 身份牌 / 积分是本页的即时状态：切换身份牌、商城消费后立即刷新，
  /// 与昵称性别的「编辑后保存」互不干扰。
  late String _badge;
  late int _points;
  late List<String> _ownedBadges;

  /// VIP 日卡是否生效中（生效期间 VIP 也在可佩戴列表里）
  late bool _vipActive;

  /// 当前生效的 VIP 日卡到期时间（用于选择页展示「剩余x天」）
  late DateTime? _vipExpireAt;

  /// 用户 ID / 使用天数（只读信息，来自档案）
  late String _userId;
  late int _usedDays;


  final GlobalKey<SaveDoneButtonState> _doneKey =
      GlobalKey<SaveDoneButtonState>();


  /// 进入页面时的内容快照，用于判断是否有未保存的修改
  String _initial = '';

  /// 当前编辑内容（用于 dirty 比较）
  String _snapshot() => [_nicknameCtrl.text, _gender, _avatarPath].join('\u0001');

  bool get _dirty => _snapshot() != _initial;

  /// 主动返回（AppBar 返回键 / 系统返回键）：有改动时弹框，确定即放弃保存返回
  Future<bool> _handleLeave() => confirmLeaveIfDirty(context, dirty: _dirty);

  @override
  void initState() {
    super.initState();
    _nicknameCtrl = TextEditingController(text: widget.profile.nickname);
    _gender = widget.profile.gender;
    _avatarPath = widget.profile.avatarPath;
    _badge = widget.profile.badge;
    _points = widget.profile.points;
    _ownedBadges = List<String>.from(widget.profile.ownedBadges);
    _vipActive = widget.profile.vipCardActive;
    _vipExpireAt = widget.profile.vipCardExpireTime;
    _userId = widget.profile.userId;
    _usedDays = widget.profile.usedDays;
    _initial = _snapshot();
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (file == null) return;
      final dir = await getApplicationDocumentsDirectory();
      final newPath =
          '${dir.path}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(file.path).copy(newPath);
      if (!mounted) return;
      setState(() => _avatarPath = newPath);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '选择头像失败，请重试');
    }
  }

  /// 资料页没有必填校验，保留接口一致性（返回 null 表示通过）
  String? _validate() => null;

  Future<void> _save() async {
    setState(() => _saving = true);
    final name = _nicknameCtrl.text.trim();
    // 以磁盘上的最新档案为基底，只覆盖本页编辑的三个字段：
    // 直接 new UserProfile 会把积分、身份牌、兑换记录一起清空。
    final profile = await UserStorage.load();
    profile.nickname = name.isEmpty ? UserProfile.defaultNickname : name;
    profile.gender = _gender;
    profile.avatarPath = _avatarPath;
    await UserStorage.save(profile);
    if (!mounted) return;
    // 落盘完成：续播对勾 + 粒子，播完由 onDone 返回
    _doneKey.currentState?.finish();
  }

  /// 重读档案：商城消费后刷新本页展示
  Future<void> _refresh() async {
    final p = await (widget.loadOverride ?? UserStorage.load)();
    if (!mounted) return;
    setState(() {
      _badge = p.badge;
      _points = p.points;
      _ownedBadges = List<String>.from(p.ownedBadges);
      _vipActive = p.vipCardActive;
      _vipExpireAt = p.vipCardExpireTime;
      _userId = p.userId;
      _usedDays = p.usedDays;
    });
  }

  /// 选择身份牌：底部选项卡，列出可佩戴的牌
  /// （已拥有的恒在；VIP日卡生效期间 VIP 也在列）
  Future<void> _pickBadge() async {
    final options = List<String>.from(_ownedBadges);
    if (_vipActive && !options.contains(UserProfile.badgeVip)) {
      options.add(UserProfile.badgeVip);
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppPalette.c(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '选择身份牌',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.c(0xFF24382F),
                ),
              ),
            ),
            for (final id in options)
              InkWell(
                key: ValueKey('badge_option_$id'),
                onTap: () => Navigator.pop(ctx, id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      // 只保留身份牌胶囊本身，旁边不再重复放一份名称文字
                      IdentityBadge(badge: id),
                      const Spacer(),
                      // 右侧显示有效期：永久拥有 →「永久」，限时牌 →「剩余x天」
                      Text(
                        UserProfile.validityLabel(
                          id,
                          owned: _ownedBadges.contains(id),
                          // VIP 行只要档案里有生效中的限时权益就传到期时间，
                          // 让「剩余x天」随日卡 / 周卡的实际购买天数增加。
                          expiresAt:
                              id == UserProfile.badgeVip ? _vipExpireAt : null,
                        ),
                        key: ValueKey('badge_validity_$id'),
                        style: TextStyle(
                            fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
                      ),
                      const SizedBox(width: 10),
                      if (id == _badge)
                        const AppIcon(AppIcons.check,
                            size: 20, color: Color(0xFF3E8E6D))
                      else
                        const SizedBox(width: 20),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final outcome = await (widget.wearOverride ?? RewardService.wearBadge)(picked);
    if (!mounted) return;
    if (!outcome.ok) {
      AppToast.show(context, outcome.message);
      return;
    }
    Haptics.light();
    AppToast.show(context, outcome.message);
    // 切牌成功即当前牌已变，直接更新展示，无需再读盘
    setState(() => _badge = picked);
  }

  /// 进入积分商城
  Future<void> _openShop() async {
    await Navigator.push(
      context,
      AppMotion.slide(
        widget.shopBuilder?.call() ?? const PointsShopScreen(),
      ),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleLeave,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('个人信息'),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back),
          tooltip: '返回',
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  buildAppAvatar(
                    UserProfile(avatarPath: _avatarPath),
                    radius: 48,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF3E8E6D),
                        shape: BoxShape.circle,
                      ),
                      child: const AppIcon(AppIcons.camera,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '点击更换头像',
              style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
            ),
            const SizedBox(height: 28),
            _buildIdentityCard(),
            const SizedBox(height: 16),
            // 昵称 / 性别 / 用户ID / 使用时间合为一张白卡：
            // 四行值统一从同一条竖线开始，性别选择、ID 复制都是行内点击
            _buildFieldCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNicknameField(),
                  Divider(height: 1, color: AppPalette.c(0xFFEEF4F0)),
                  _buildGenderRow(),
                  Divider(height: 1, color: AppPalette.c(0xFFEEF4F0)),
                  _buildUserIdRow(),
                  Divider(height: 1, color: AppPalette.c(0xFFEEF4F0)),
                  _buildUsedDaysRow(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: _buildSaveBar(),
        ),
      ),
    ),
    );
  }


  /// 保存栏：点完成后取消按钮淡出让出整行，完成按钮收缩成居中圆形，
  /// 打勾描边 + 粒子迸发，停留片刻再保存返回。
  Widget _buildSaveBar() {
    return SaveBar(
      saveKey: _doneKey,
      color: Theme.of(context).colorScheme.primary,
      onCancel: _saving ? null : () => Navigator.pop(context),
      validate: _validate,
      onSave: _save,
      onDone: () {
        if (mounted) Navigator.pop(context, true);
      },
    );
  }


  /// 身份牌与积分：数据来自 user_profile.json（兑换码 / 发布奖励 / 商城消费）。
  /// 两行都可点：身份牌行切佩戴、积分行进商城。
  Widget _buildIdentityCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildIdentityRow(
            label: '身份牌',
            onTap: _pickBadge,
            trailing: IdentityBadge(badge: _badge),
          ),
          Divider(height: 1, color: AppPalette.c(0xFFEEF4F0)),
          _buildIdentityRow(
            label: '积分',
            onTap: _openShop,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$_points',
                  style: const TextStyle(
                    fontSize: 17,
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
          ),
        ],
      ),
    );
  }

  /// 一行「标题 — 值 ›」，右侧统一带箭头提示可点
  Widget _buildIdentityRow({
    required String label,
    required VoidCallback onTap,
    required Widget trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 15, color: AppPalette.c(0xFF24382F)),
            ),
            const Spacer(),
            trailing,
            const SizedBox(width: 4),
            AppIcon(AppIcons.chevR, size: 16, color: AppPalette.c(0xFFC6D6CD)),
          ],
        ),
      ),
    );
  }

  /// 白底圆角信息卡：昵称 / 性别沿用身份牌卡片的视觉（白底 16 圆角）
  Widget _buildFieldCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.c(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  /// 四行信息共用的标签列：固定宽度，保证右侧的值都从同一条竖线起、
  /// 性别的当前值与昵称输入内容左对齐。
  Widget _buildFieldLabel(String text) => SizedBox(
        width: 76,
        child: Text(
          text,
          style: TextStyle(fontSize: 15, color: AppPalette.c(0xFF24382F)),
        ),
      );

  Widget _buildNicknameField() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildFieldLabel('昵称'),
        Expanded(
          child: TextField(
            controller: _nicknameCtrl,
            maxLength: 10,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: UserProfile.defaultNickname,
              hintStyle: TextStyle(color: AppPalette.c(0xFF8FA09A)),
              border: InputBorder.none,
              counterText: '',
            ),
          ),
        ),
        // 计数器必须监听控制器实时刷新：之前是普通 Text，只在整页重建时
        // 读取一次长度 —— 打字过程中计数器一直停在初始值（默认昵称恰好
        // 10 个字符时测试也没暴露出来）。
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _nicknameCtrl,
          builder: (_, v, __) => Text(
            '${v.text.length}/10',
            style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
          ),
        ),
      ],
    );
  }

  /// 性别：三个选项收拢到右侧右箭头里，当前值按昵称同款样式展示。
  Widget _buildGenderRow() {
    return SizedBox(
      height: 48,
      child: InkWell(
        key: const ValueKey('profile-gender-row'),
        onTap: _pickGender,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildFieldLabel('性别'),
            Expanded(
              child: Text(
                _genderLabel(_gender),
                style: TextStyle(fontSize: 15, color: AppPalette.c(0xFF24382F)),
              ),
            ),
            AppIcon(AppIcons.chevR, size: 16, color: AppPalette.c(0xFFC6D6CD)),
          ],
        ),
      ),
    );
  }

  String _genderLabel(String value) {
    switch (value) {
      case 'male':
        return '男';
      case 'female':
        return '女';
      default:
        return '无';
    }
  }

  /// 性别选择弹层（与身份牌选择同款：标题 + 选项 + 当前项打勾）
  Future<void> _pickGender() async {
    const options = <String, String>{
      '男': 'male',
      '女': 'female',
      '无': '',
    };
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppPalette.c(0xFFFFFFFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(
                '选择性别',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.c(0xFF24382F),
                ),
              ),
            ),
            for (final entry in options.entries)
              InkWell(
                key: ValueKey(
                    'gender_option_${entry.value.isEmpty ? 'none' : entry.value}'),
                onTap: () => Navigator.pop(ctx, entry.value),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Text(entry.key,
                          style: TextStyle(
                              fontSize: 14, color: AppPalette.c(0xFF647A70))),
                      const Spacer(),
                      if (_gender == entry.value)
                        const AppIcon(AppIcons.check,
                            size: 20, color: Color(0xFF3E8E6D)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _gender = picked);
  }

  /// 用户 ID：淡灰只读文字，点击整行复制到剪贴板。
  Widget _buildUserIdRow() {
    return SizedBox(
      height: 48,
      child: InkWell(
        key: const ValueKey('profile-user-id-row'),
        onTap: _copyUserId,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildFieldLabel('用户ID'),
            Expanded(
              child: Text(
                _userId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyUserId() async {
    final copy = widget.clipboardOverride ??
        (String t) => Clipboard.setData(ClipboardData(text: t));
    await copy(_userId);
    if (!mounted) return;
    AppToast.show(context, '已复制用户ID');
  }

  /// 使用时间：自用户 ID 注册日起至今天共多少天（只读）。
  Widget _buildUsedDaysRow() {
    return SizedBox(
      height: 48,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildFieldLabel('使用时间'),
          Expanded(
            child: Text(
              '已使用 $_usedDays 天',
              style: TextStyle(fontSize: 13, color: AppPalette.c(0xFF8FA09A)),
            ),
          ),
        ],
      ),
    );
  }
}
