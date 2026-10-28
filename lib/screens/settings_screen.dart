import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_settings.dart';
import '../services/backup_service.dart';
import '../utils/app_version.dart';
import 'font_picker_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _diaryCount = 0;
  int _itemCount = 0;
  int _assetCount = 0;
  int _countdownCount = 0;
  bool _exporting = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final data = await BackupService.collect();
    if (!mounted) return;
    setState(() {
      _diaryCount = data.entries.length;
      _itemCount = data.items.length;
      _assetCount = data.assets.length;
      _countdownCount = data.countdowns.length;
    });
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await BackupService.exportToFile();
      if (!mounted) return;
      setState(() => _exporting = false);
      await Share.shareXFiles(
        [XFile(path, mimeType: 'application/json')],
        text: '「矢量日记」数据备份文件，可用于换机恢复',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 10, 10),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导出失败，请重试')),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is String ? e : '备份文件无效')),
        );
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
              style: TextStyle(fontSize: 14, color: Color(0xFF5A6B82), height: 1.6),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child:
                    const Text('覆盖导入', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;

        setState(() => _importing = true);
        await BackupService.applyBackup(data);
        await _loadStats();
        if (!mounted) return;
        setState(() => _importing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '导入成功：${data.entries.length} 条笔记、${data.items.length} 件物资、${data.assets.length} 笔资产、${data.countdowns.length} 个事件')),
        );
        Navigator.pop(context, true);
        return;
      }

      // 增添合并：保留现有数据，只补充备份中多出来的条目
      setState(() => _importing = true);
      final merged = await BackupService.mergeBackup(data);
      await _loadStats();
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(merged.isEmpty
              ? '合并完成：没有可合并的新内容'
              : '合并完成：新增 ${merged.added} 条，更新 ${merged.updated} 条'),
        ),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入失败，请重试')),
      );
    }
  }

  /// 导入方式选择弹窗：完全覆盖 / 增添合并
  Future<ImportMode?> _askImportMode(BackupData data) async {
    ImportMode selected = ImportMode.merge; // 默认更安全的一项
    return showDialog<ImportMode>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('导入备份'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '该备份包含 ${data.entries.length} 条笔记、${data.items.length} 件物资、${data.assets.length} 笔资产、${data.countdowns.length} 个事件。',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF8A99B3), height: 1.6),
              ),
              const SizedBox(height: 12),
              _modeTile(
                ctx,
                label: '增添合并',
                desc: '保留现有数据，只补充备份中新增的条目',
                value: ImportMode.merge,
                group: selected,
                onTap: () =>
                    setDialogState(() => selected = ImportMode.merge),
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
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消',
                  style: TextStyle(color: Color(0xFF8A99B3))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('确定',
                  style: TextStyle(
                      color: Color(0xFF3B6FE0), fontWeight: FontWeight.w600)),
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
          color: sel ? const Color(0xFFDCE7FF) : const Color(0xFFF6F8FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? const Color(0xFF3B6FE0) : const Color(0xFFE8EDF5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              sel
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: sel ? const Color(0xFF3B6FE0) : const Color(0xFFC4CEDD),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? const Color(0xFF3B6FE0)
                              : const Color(0xFF2A3B52))),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8A99B3),
                          height: 1.5)),
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                const Text('数据备份',
                    style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9AA8BF),
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
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EDF5)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_outlined,
                          size: 16, color: Color(0xFF9AA8BF)),
                      const SizedBox(width: 6),
                      Text('当前数据：$_diaryCount 条笔记 · $_itemCount 件物资 · $_assetCount 笔资产 · $_countdownCount 个事件',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF9AA8BF))),
                    ],
                  ),
                ),
                _buildItem(
                  icon: Icons.ios_share,
                  iconColor: const Color(0xFF3B6FE0),
                  title: '导出数据',
                  subtitle: '生成 .json 备份文件，可分享到微信、网盘、电脑或本地文件夹',
                  busy: _exporting,
                  onTap: _export,
                ),
                const Divider(height: 1, indent: 52),
                _buildItem(
                  icon: Icons.download,
                  iconColor: const Color(0xFF34A853),
                  title: '导入数据',
                  subtitle: '可选「增添合并」或「完全覆盖」，会自动校验文件',
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
                        color: Color(0xFF9AA8BF),
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
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8EDF5)),
            ),
            child: _buildItem(
              icon: Icons.font_download_outlined,
              iconColor: const Color(0xFF3B6FE0),
              title: '笔记字体',
              subtitle:
                  '当前：${FontCatalog.nameOf(AppSettings.fontFamilyId.isEmpty ? null : AppSettings.fontFamilyId) ?? '默认字体'}',
              busy: false,
              onTap: () async {
                await Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 300),
                    reverseTransitionDuration:
                        const Duration(milliseconds: 300),
                    pageBuilder: (_, __, ___) => const FontPickerScreen(),
                    transitionsBuilder: (_, animation, __, child) {
                      final curved = CurvedAnimation(
                          parent: animation, curve: Curves.easeOutCubic);
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(curved),
                        child: child,
                      );
                    },
                  ),
                );
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: 16),
          // 底部居中版本号（灰字，随发版同步更新 AppVersion.displayVersion）
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Text(
                AppVersion.displayVersion,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFFB4BECD),
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
          border: Border.all(color: const Color(0xFF3B6FE0), width: 1.2),
        ),
        alignment: Alignment.center,
        child: const Text(
          '!',
          style: TextStyle(
            fontSize: 10,
            height: 1,
            fontWeight: FontWeight.w700,
            color: Color(0xFF3B6FE0),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 20, color: iconColor),
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
                          color: Color(0xFF2A3B52))),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9AA8BF))),
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
              const Icon(Icons.chevron_right, color: Color(0xFFC4CEDD)),
          ],
        ),
      ),
    );
  }
}
