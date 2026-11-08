import 'package:file_picker/file_picker.dart';
import '../widgets/app_icons.dart';
import 'package:flutter/material.dart';

import '../utils/app_motion.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/app_toast.dart';
import '../services/app_settings.dart';
import '../services/backup_service.dart';
import '../utils/app_version.dart';
import '../utils/haptics.dart';
import '../widgets/pressable.dart';
import 'font_picker_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _exporting = false;
  bool _importing = false;

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
            content: const Text(
              '导入后将覆盖当前手机上的全部数据，原有内容无法恢复。',
              style: TextStyle(
                  fontSize: 13, color: Color(0xFF647A70), height: 1.6),
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
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF7C8F86), height: 1.6),
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
                    const Text('取消', style: TextStyle(color: Color(0xFF7C8F86))),
              ),
            ),
            Pressable(
              enabled: true,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('确定',
                    style: TextStyle(
                        color: Color(0xFF3E8E6D), fontWeight: FontWeight.w600)),
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
          color: sel ? const Color(0xFFE4F2EB) : const Color(0xFFF5FAF7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? const Color(0xFF3E8E6D) : const Color(0xFFE8EDF5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(
              sel ? AppIcons.radioOn : AppIcons.radioOff,
              size: 18,
              color: sel ? const Color(0xFF3E8E6D) : const Color(0xFFC6D6CD),
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
                              ? const Color(0xFF3E8E6D)
                              : const Color(0xFF24382F))),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF7C8F86), height: 1.5)),
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
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      // 版本号固定在整个页面最底部（不随列表滚动），列表内容在其上方滚动
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Row(
                    children: [
                      const Text('数据备份',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8FA09A),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      // 教程入口：标题旁的蓝色圈叹号，点击弹出换机/导入说明
                      _buildInfoDot(onTap: () => _showBackupTutorial(context)),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8EDF5)),
                  ),
                  child: Column(
                    children: [
                      _buildItem(
                        icon: AppIcons.share,
                        iconColor: const Color(0xFF3E8E6D),
                        title: '导出数据',
                        subtitle: '以 JSON 格式保存数据到本地',
                        busy: _exporting,
                        onTap: _export,
                      ),
                      const Divider(height: 1, indent: 52),
                      _buildItem(
                        icon: AppIcons.download,
                        iconColor: const Color(0xFF3E8E6D),
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
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Row(
                    children: [
                      const Text('笔记字体',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8FA09A),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      _buildInfoDot(
                        onTap: () => _showFontScopeTip(context),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8EDF5)),
                  ),
                  child: _buildItem(
                    icon: AppIcons.fontType,
                    iconColor: const Color(0xFF3E8E6D),
                    title: '笔记字体',
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
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('反馈',
                      style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8FA09A),
                          fontWeight: FontWeight.w600)),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE8EDF5)),
                  ),
                  child: _buildItem(
                    icon: AppIcons.vibrate,
                    // 与导出/导入等其它功能项同款主色（图标 + 0.1 透明度底纹）
                    iconColor: const Color(0xFF3E8E6D),
                    title: '振动测试',
                    subtitle: '点击触发一次震动，并检测设备振动状态',
                    busy: false,
                    onTap: _testHaptics,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          // 底部居中版本号（灰字，随发版同步更新 AppVersion.displayVersion）
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 10),
            child: Center(
              child: Text(
                AppVersion.displayVersion,
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFB2C2BA),
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分组标题旁的蓝色圈叹号（提示入口）
  Widget _buildInfoDot({required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF3E8E6D), width: 1.2),
        ),
        alignment: Alignment.center,
        child: const Text(
          '!',
          style: TextStyle(
            fontSize: 11,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3E8E6D),
          ),
        ),
      ),
    );
  }

  /// 笔记字体作用范围提示
  void _showFontScopeTip(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('笔记字体', style: TextStyle(fontSize: 17)),
        content: const Text(
          '该字体设置仅作用于笔记浏览页面。',
          style: TextStyle(fontSize: 13, height: 1.6),
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

  /// 振动自检：触发一次震动，并把设备振动状态读出来展示。
  ///
  /// 震动在真机上「感觉不到」时，靠原生侧回报的真实状态能立刻区分
  /// 是代码问题还是设备/系统设置问题——省电模式、静音、无振动马达
  /// 这些是代码修不了的，继续盲改代码只会让问题永远定位不到。
  Future<void> _testHaptics() async {
    // 先触发一次中等震动，让用户当场感受
    await Haptics.medium();

    final info = await Haptics.diagnose();
    if (!mounted) return;

    if (info == null) {
      // 原生通道没响应：这是代码/构建问题，不是设备问题
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('振动测试', style: TextStyle(fontSize: 17)),
          content: const Text(
            '原生振动通道没有响应。\n\n'
            '这通常意味着安装包的原生代码未生效，'
            '请尝试卸载后重新安装最新版本。',
            style: TextStyle(fontSize: 13, height: 1.6),
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
      return;
    }

    final hasVibrator = info['hasVibrator'] == true;
    final powerSave = info['powerSaveMode'] == true;
    final ringer = info['ringerMode'] ?? -1;

    final List<String> issues = [];
    if (!hasVibrator) {
      issues.add('• 此设备没有振动马达（平板或模拟器），无法产生任何震动');
    }
    if (powerSave) {
      issues.add('• 当前处于省电模式，系统会禁用振动');
    }
    if (ringer == 0) {
      issues.add('• 当前为静音模式');
    }

    final String verdict = issues.isEmpty
        ? '设备振动功能正常。\n\n'
            '如果刚才没有感觉到震动，请检查系统「触感反馈」开关是否打开。'
        : '${issues.join('\n')}\n\n请关闭相应设置后再试。';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('振动测试', style: TextStyle(fontSize: 17)),
        content: Text(
          '刚才手机震动了一下。\n\n$verdict',
          style: const TextStyle(fontSize: 13, height: 1.6),
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
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF24382F))),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF8FA09A))),
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
              const AppIcon(AppIcons.chevR, color: Color(0xFFC6D6CD)),
          ],
        ),
      ),
    );
  }
}
