import 'package:file_picker/file_picker.dart';
import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';

import '../utils/app_motion.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/app_toast.dart';
import '../services/app_settings.dart';
import '../services/app_lock_storage.dart';
import '../services/backup_service.dart';
import '../services/reward_service.dart';
import '../services/user_storage.dart';
import '../models/user_profile.dart';
import '../utils/app_sheet.dart';
import '../utils/app_version.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';
import '../widgets/identity_badge.dart';
import 'app_lock_setup_wizard.dart';
import 'font_picker_screen.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme_scope.dart';
class SettingsScreen extends StatefulWidget {
  /// 仅测试使用：替换真实的兑换实现（避免 widget 测试里走真实文件 IO）
  @visibleForTesting
  final Future<RedeemOutcome> Function(String code)? redeemOverride;

  /// 仅测试使用：注入隐私锁初始状态，避免走真实文件 IO
  @visibleForTesting
  final bool? lockStateOverride;

  const SettingsScreen({Key? key, this.redeemOverride, this.lockStateOverride})
      : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _exporting = false;
  bool _importing = false;
  bool _lockEnabled = false;

  @override
  void initState() {
    super.initState();
    if (widget.lockStateOverride != null) {
      _lockEnabled = widget.lockStateOverride!;
    } else {
      AppLockStorage.hasLock().then((v) {
        if (mounted) setState(() => _lockEnabled = v);
      });
    }
  }

  /// 隐私锁开关（v5.0.2）：
  /// - 开启：走 4 步向导（形式→密码→确认→密保），任一步取消都不开启。
  /// - 关闭：必须先验证当前凭证，验证通过才删除锁文件。
  /// 关闭后锁文件被删除，重新开启必然走完整向导设置新密码，不沿用旧凭证。
  Future<void> _onLockToggle(bool value) async {
    Haptics.light();
    if (!value) {
      final verified = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AppLockVerifyDialog(),
      );
      if (verified != true) {
        // 取消或验证失败 → 保持开启（锁文件不动）
        if (mounted) setState(() => _lockEnabled = true);
        return;
      }
      await AppLockStorage.clearLock();
      if (mounted) setState(() => _lockEnabled = false);
      if (mounted) AppToast.show(context, '隐私锁已关闭');
      return;
    }
    final ok = await showAppLockSetupWizard(context);
    if (ok && mounted) {
      setState(() => _lockEnabled = true);
      AppToast.show(context, '隐私锁已开启，下次打开 App 需解锁');
    } else {
      // 任一步取消 → 保持关闭（不写入任何凭证）
      if (mounted) setState(() => _lockEnabled = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await BackupService.exportToFile();
      if (!mounted) return;
      setState(() => _exporting = false);
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/json')],
        text: '「阿尤日记」数据备份文件，可用于换机恢复',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 10, 10),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _exporting = false);
      AppToast.show(context, '导出失败，请重试');
    }
  }

  Future<void> _import() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        // 不按扩展名过滤：部分文件管理器对 json 过滤支持差，
        // 且微信保存的文件可能无扩展名，交给 App 自行校验内容
        type: FileType.any,
      );
      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;

      BackupData data;
      try {
        data = await BackupService.parseBackupFile(path);
      } catch (e) {
        if (!mounted) return;
        // 不同错误原因视为不同提示，各自可弹一次
        AppToast.show(context, e is String ? e : '备份文件无效');
        return;
      }
      if (!mounted) return;

      // 第一步：选择导入方式（完全覆盖 / 增添合并）
      final mode = await _askImportMode(data);
      if (mode == null || !mounted) return;

      if (mode == ImportMode.overwrite) {
        // 覆盖是破坏性操作，追加二次确认
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('确认完全覆盖?'),
            content: Text(
              '导入后将覆盖当前手机上的全部数据，原有内容无法恢复。',
              style: TextStyle(
                  fontSize: 13, color: AppPalette.c(0xFF647A70), height: 1.6),
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
                  child: const Text('覆盖导入', style: TextStyle(color: Color(0xFFCB5C50))),
                ),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;

        setState(() => _importing = true);
        await BackupService.applyBackup(data);
        if (!mounted) return;
        setState(() => _importing = false);
        AppToast.show(
            context,
            '导入成功：${data.entries.length} 条笔记、${data.items.length} 件物品、'
            '${data.assets.length} 笔资产、${data.countdowns.length} 个事件');
        Navigator.pop(context, true);
        return;
      }

      // 增添合并：保留现有数据，只补充备份中多出来的条目
      setState(() => _importing = true);
      final merged = await BackupService.mergeBackup(data);
      if (!mounted) return;
      setState(() => _importing = false);
      AppToast.show(
          context,
          merged.isEmpty
              ? '合并完成：没有可合并的新内容'
              : '合并完成：新增 ${merged.added} 条，更新 ${merged.updated} 条');
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _importing = false);
      AppToast.show(context, '导入失败，请重试');
    }
  }

  /// 导入方式选择弹窗：完全覆盖 / 增添合并
  Future<ImportMode?> _askImportMode(BackupData data) async {
    ImportMode selected = ImportMode.merge; // 默认更安全的一项
    return showDialog<ImportMode>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('导入备份'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '该备份包含 ${data.entries.length} 条笔记、${data.items.length} 件物资、${data.assets.length} 笔资产、${data.countdowns.length} 个事件。',
                style: TextStyle(
                    fontSize: 13, color: AppPalette.c(0xFF7C8F86), height: 1.6),
              ),
              const SizedBox(height: 12),
              _modeTile(
                ctx,
                label: '增添合并',
                desc: '保留现有数据，只补充备份中新增的条目',
                value: ImportMode.merge,
                group: selected,
                onTap: () => setDialogState(() => selected = ImportMode.merge),
              ),
              const SizedBox(height: 8),
              _modeTile(
                ctx,
                label: '完全覆盖',
                desc: '清空当前数据，全部替换为备份内容',
                value: ImportMode.overwrite,
                group: selected,
                onTap: () =>
                    setDialogState(() => selected = ImportMode.overwrite),
              ),
            ],
          ),
          actions: [
            Pressable(
              enabled: true,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    Text('取消', style: TextStyle(color: AppPalette.c(0xFF7C8F86))),
              ),
            ),
            Pressable(
              enabled: true,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: Text('确定',
                    style: TextStyle(
                        color: AppPalette.c(0xFF3E8E6D), fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeTile(
    BuildContext ctx, {
    required String label,
    required String desc,
    required ImportMode value,
    required ImportMode group,
    required VoidCallback onTap,
  }) {
    final sel = value == group;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? AppPalette.c(0xFFE4F2EB) : AppPalette.c(0xFFF5FAF7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(
              sel ? AppIcons.radioOn : AppIcons.radioOff,
              size: 18,
              color: sel ? AppPalette.c(0xFF3E8E6D) : AppPalette.c(0xFFC6D6CD),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? AppPalette.c(0xFF3E8E6D)
                              : AppPalette.c(0xFF24382F))),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: TextStyle(
                          fontSize: 13, color: AppPalette.c(0xFF7C8F86), height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // v4.9.25：订阅主题明暗，切换深色模式时整页重新 build
    AppThemeScope.watch(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      // 版本号放在列表内容最底部，随页面滚动到底可见（不再吸底常驻）。
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        children: [
                _buildAppearanceSection(context),
                const SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('隐私',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppPalette.c(0xFF8FA09A),
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppPalette.c(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _buildSwitchItem(
                    icon: AppIcons.lock,
                    title: '隐私锁',
                    subtitle: _lockEnabled
                        ? '已开启，每次打开 App 需解锁'
                        : '打开 App 无需解锁',
                    value: _lockEnabled,
                    enabled: true,
                    switchKey: 'privacy_lock_switch',
                    onChanged: _onLockToggle,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Row(
                    children: [
                      Text('数据备份',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppPalette.c(0xFF8FA09A),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      // 教程入口：标题旁的蓝色圈叹号，点击弹出换机/导入说明
                      _buildInfoDot(onTap: () => _showBackupTutorial(context)),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppPalette.c(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildItem(
                        icon: AppIcons.share,
                        iconColor: AppPalette.c(0xFF3E8E6D),
                        title: '导出数据',
                        subtitle: '以 JSON 格式保存数据到本地',
                        busy: _exporting,
                        onTap: _export,
                      ),
                      const Divider(height: 1, indent: 52),
                      _buildItem(
                        icon: AppIcons.download,
                        iconColor: AppPalette.c(0xFF3E8E6D),
                        title: '导入数据',
                        subtitle: '支持增添合并或完全覆盖两种导入方式',
                        busy: _importing,
                        onTap: _import,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('活动',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppPalette.c(0xFF8FA09A),
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppPalette.c(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _buildItem(
                    icon: AppIcons.gift,
                    iconColor: AppPalette.c(0xFF3E8E6D),
                    title: '兑换码',
                    subtitle: '参与活动获得兑换码',
                    busy: false,
                    onTap: _redeemCode,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('反馈',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppPalette.c(0xFF8FA09A),
                          fontWeight: FontWeight.w600)),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppPalette.c(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  // v4.9.28：「振动测试」改为「震动」开关，与深色模式同款
                  // 开关交互；关闭后全局所有震点点位静默。
                  child: ValueListenableBuilder<bool>(
                    valueListenable: AppSettings.hapticsNotifier,
                    builder: (context, on, _) => _buildSwitchItem(
                      icon: AppIcons.vibrate,
                      title: '震动',
                      subtitle: on ? '操作时有触感反馈' : '全局不再震动',
                      value: on,
                      enabled: true,
                      onChanged: (v) {
                        AppSettings.setHapticsEnabled(v);
                        // 开启瞬间震一次，让用户当场确认已生效
                        if (v) Haptics.medium();
                      },
                    ),
                  ),
                ),
          const SizedBox(height: 16),
          // 版本号置于列表内容最底部，滑到底才可见（灰字，随发版同步）
          Center(
            child: Padding(
              padding: EdgeInsets.only(top: 6, bottom: 10),
              child: Text(
                AppVersion.displayVersion,
                style: TextStyle(
                  fontSize: 11,
                  color: AppPalette.c(0xFFB2C2BA),
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 兑换码弹窗：输入 → 兑换 → 顶部提示结果。
  ///
  /// 码表见 `RewardService` 与 `docs/redeem_codes.md`：
  /// - `ayouriji` → +100 点（限 1 次）
  /// - `neice` / `vip` / `zhongshenvip` → 身份（限 1 次，后者为终身VIP）
  /// - `17381113325` → +1000 点（不限次数）
  /// - `13031210237` → -1000 点（不限次数，最低 0）
  /// 限次码每用户只能用一次；无限次码不写已用记录。
  Future<void> _redeemCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.c(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('兑换码', style: TextStyle(fontSize: 17)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v),
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: '请输入兑换码',
            hintStyle: TextStyle(color: AppPalette.c(0xFF8FA09A)),
          ),
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ),
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(
                '兑换',
                style: TextStyle(
                  color: AppPalette.c(0xFF3E8E6D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (code == null || !mounted) return;
    if (code.trim().isEmpty) return;

    final outcome = await (widget.redeemOverride ?? RewardService.redeem)(code);
    if (!mounted) return;
    Haptics.light();
    AppToast.show(context, outcome.message);
  }

  /// 分组标题旁的蓝色圈叹号（提示入口）
  /// v4.9.25：视觉圈缩小并与标题行居中对齐，外层点击热区不随之缩小
  /// （仍保持约 20×20，满足最小点按面积），只缩小看得见的圈与叹号。
  Widget _buildInfoDot({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: SizedBox(
            width: 12,
            height: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppPalette.c(0xFF3E8E6D), width: 1),
              ),
              child: Center(
                child: Text(
                  '!',
                  style: TextStyle(
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.c(0xFF3E8E6D),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 数据备份教程弹窗（原先直接铺在设置页底部，改为标题旁圈叹号触发）
  void _showBackupTutorial(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('数据备份说明', style: TextStyle(fontSize: 17)),
        content: const SingleChildScrollView(
          child: Text(
            '换机流程：旧手机「导出数据」→ 把文件传到新手机 → 新手机「导入数据」。\n\n'
            '从微信导入：先在微信中点开文件 → 右上角「…」→「保存到手机」，'
            '再在导入的文件选择器里进入「内部存储 / Download / WeiXin」目录选择'
            '（选择器里可点左上角菜单浏览全部文件夹）。',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        actions: [
          Pressable(
            enabled: true,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ),
        ],
      ),
    );
  }

  /// 「外观」分组：深色模式 / 字体 / 主题色。
  ///
  /// v4.9.48：「深色模式」行点击打开抽屉，内含「跟随系统 / 深色模式」两个
  /// 震动同款开关（跟随系统开启时深色开关置灰禁用）；本行副标题仍反映
  /// 当前深浅状态（跟随系统时追加「（跟随系统）」）。
  /// 用 ValueListenableBuilder 监听 themeModeNotifier，切换后立即刷新副标题。
  Widget _buildAppearanceSection(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: AppSettings.themeModeNotifier,
      builder: (context, mode, _) {
        final followSystem = mode == AppThemeMode.system;
        // 跟随系统时，副标题显示系统当前亮度解析出的值
        final systemDark = MediaQuery.platformBrightnessOf(context) ==
            Brightness.dark;
        final darkOn = followSystem
            ? systemDark
            : mode == AppThemeMode.dark;
        final darkSubtitle =
            '${darkOn ? '已开启' : '已关闭'}${followSystem ? '（跟随系统）' : ''}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('外观',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppPalette.c(0xFF8FA09A),
                      fontWeight: FontWeight.w600)),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppPalette.c(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildItem(
                    icon: AppIcons.moon,
                    iconColor: AppPalette.c(0xFF3E8E6D),
                    title: '深色模式',
                    subtitle: darkSubtitle,
                    busy: false,
                    onTap: _pickThemeMode,
                  ),
                  Divider(
                      height: 1,
                      indent: 52,
                      color: AppPalette.c(0xFFE8EDF5)),
                  // v4.9.26：字体并入「外观」分组，作为本卡第二行
                  _buildItem(
                    icon: AppIcons.fontType,
                    iconColor: AppPalette.c(0xFF3E8E6D),
                    title: '字体',
                    subtitle:
                        '当前：${FontCatalog.nameOf(AppSettings.fontFamilyId.isEmpty ? null : AppSettings.fontFamilyId) ?? '默认字体'}',
                    busy: false,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        AppMotion.slide(
                          const FontPickerScreen(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                  Divider(
                      height: 1,
                      indent: 52,
                      color: AppPalette.c(0xFFE8EDF5)),
                  // v4.9.43：主题色并入「外观」分组，作为本卡第三行
                  _buildItem(
                    icon: AppIcons.sun,
                    iconColor: AppPalette.accentColor,
                    title: '主题色',
                    subtitle:
                        '当前：${AccentCatalog.byId(AppSettings.accentId).name}',
                    busy: false,
                    onTap: _pickAccent,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// v4.9.48：深色模式编辑抽屉改为「震动同款」双开关：
  /// - 「跟随系统」开关：开 → AppThemeMode.system；关 → 按下方深色开关当前
  ///   显示值回落到 dark / light（保持用户眼前看到的深浅，不跳变）。
  /// - 「深色模式」开关：非跟随系统时可用，开 → dark，关 → light；
  ///   跟随系统开启时置灰禁用，显示值仍跟随系统当前亮度（如实反映状态）。
  /// 用 StatefulBuilder 让开关切换即时刷新抽屉内部；写回 AppSettings 后
  /// themeModeNotifier 会同步刷新设置页副标题与全局主题。
  Future<void> _pickThemeMode() async {
    await AppSheet.show<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final systemDark =
              MediaQuery.platformBrightnessOf(sheetCtx) == Brightness.dark;
          final mode = AppSettings.themeMode;
          final followSystem = mode == AppThemeMode.system;
          // 深色开关显示值：跟随系统时取系统亮度解析值，手动时取手动值
          final darkSwitchOn =
              followSystem ? systemDark : mode == AppThemeMode.dark;

          void toggleFollow(bool v) {
            Haptics.light();
            AppSettings.setThemeMode(
              v
                  ? AppThemeMode.system
                  : (darkSwitchOn ? AppThemeMode.dark : AppThemeMode.light),
            );
            setSheetState(() {});
          }

          void toggleDark(bool v) {
            if (followSystem) return;
            Haptics.light();
            AppSettings.setThemeMode(v ? AppThemeMode.dark : AppThemeMode.light);
            setSheetState(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Container(
                decoration: BoxDecoration(
                  color: AppPalette.c(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSwitchItem(
                      icon: AppIcons.sun,
                      title: '跟随系统',
                      subtitle: followSystem
                          ? '已开启，深浅色随系统自动切换'
                          : '已关闭，可手动设置下方开关',
                      value: followSystem,
                      enabled: true,
                      onChanged: toggleFollow,
                      switchKey: 'theme-follow-system',
                    ),
                    Divider(
                        height: 1,
                        indent: 52,
                        color: AppPalette.c(0xFFE8EDF5)),
                    _buildSwitchItem(
                      icon: AppIcons.moon,
                      title: '深色模式',
                      subtitle: followSystem
                          ? '跟随系统开启时不可手动设置'
                          : (darkSwitchOn ? '已开启，使用深色外观' : '已关闭，使用浅色外观'),
                      value: darkSwitchOn,
                      enabled: !followSystem,
                      onChanged: toggleDark,
                      switchKey: 'theme-dark-mode',
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSwitchItem({
    required String icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    String? switchKey,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: AppIcon(icon,
                  size: 22,
                  color: enabled
                      ? AppPalette.c(0xFF3E8E6D)
                      : AppPalette.c(0xFFC6D6CD)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? AppPalette.c(0xFF24382F)
                            : AppPalette.c(0xFF8FA09A))),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
              ],
            ),
          ),
          Switch(
            key: switchKey == null ? null : ValueKey(switchKey),
            value: value,
            onChanged: enabled ? onChanged : null,
            activeColor: AppPalette.c(0xFF3E8E6D),
          ),
        ],
      ),
    );
  }

  /// 主题色抽屉。v5.0.5 起：竹青 / 墨灰免费，暖棕需灵感杂货店 1400 点兑换，
  /// 藕粉 / 雾蓝 / 霞紫 VIP 专属。VIP 过期后已设置的主题色保留、可切回免费色，
  /// 但不可再选其它 VIP 色。未解锁的暖棕置灰，点击引导去杂货店。
  Future<void> _pickAccent() async {
    final profile = await UserStorage.load();
    if (!mounted) return;
    final bool vip = RewardService.hasVipPrivilege(profile);
    final current = AppSettings.accentId;
    // 已解锁的兑换型主题；当前正在使用的也算（避免升级后正在用暖棕的老用户被锁死）
    final unlockedAccents = <String>{
      ...profile.ownedAccents,
      if (current == 'amber') 'amber',
    };
    final chosen = await AppSheet.show<String>(
      context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppPalette.c(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (final s in AccentCatalog.styles)
                      _accentRow(ctx, s, current, vip, unlockedAccents),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen != current) {
      await AppSettings.setAccentId(chosen);
      if (mounted) setState(() {});
    }
  }

  Widget _accentRow(BuildContext ctx, AccentStyle s, String current, bool vip,
      Set<String> unlockedAccents) {
    // 兑换型（暖棕）：需已解锁，或为当前正在使用的主题
    final shopReady = !s.needsShop || unlockedAccents.contains(s.id);
    // 可选项：免费色 / 已兑换的主题 / 或当前正戴着（VIP 过期时仍可保留）
    final canPick = shopReady && (!s.vip || vip || s.id == current);
    final selected = s.id == current;
    return InkWell(
      onTap: () {
        if (canPick) {
          Haptics.light();
          Navigator.pop(ctx, s.id);
        } else if (!shopReady) {
          // v5.0.5：暖棕未兑换——引导去灵感杂货店
          AppToast.show(context, '未解锁，赶紧前往灵感杂货店兑换吧～');
        } else {
          AppToast.show(context, '${s.name}是VIP专属权益，请充值后再尝试～');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppPalette.c(0xFFE4F2EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Opacity(
              opacity: canPick ? 1.0 : 0.45,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Color(0xFF000000 | s.rgb),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: canPick ? 1.0 : 0.45,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(s.name,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.normal,
                              color: AppPalette.c(0xFF24382F))),
                    ),
                    if (s.vip) ...[
                      const SizedBox(width: 6),
                      Transform.scale(
                        scale: 0.8,
                        child: IdentityBadge(badge: UserProfile.badgeVip),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: AppIcon(AppIcons.check,
                    size: 16, color: AppPalette.accentColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem({
    required String icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 去底纹：仅保留图标本体，固定 36×36 让标题与次行对齐
            // （修复：原底纹容器未设 alignment，图标贴左上角错位）
            SizedBox(
              width: 36,
              height: 36,
              child: Center(child: AppIcon(icon, size: 22, color: iconColor)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.c(0xFF24382F))),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13, color: AppPalette.c(0xFF8FA09A))),
                ],
              ),
            ),
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              AppIcon(AppIcons.chevR, color: AppPalette.c(0xFFC6D6CD)),
          ],
        ),
      ),
    );
  }
}
