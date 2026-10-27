import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_settings.dart';
import '../services/backup_service.dart';
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

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导入备份'),
          content: Text(
              '该备份包含 ${data.entries.length} 条笔记、${data.items.length} 件物资、${data.assets.length} 笔资产。\n\n导入后将覆盖当前手机上的全部数据，确定继续吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('导入',
                  style: TextStyle(color: Color(0xFF3B6FE0))),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      setState(() => _importing = true);
      await BackupService.applyBackup(data);
      await _loadStats();
      if (!mounted) return;
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '导入成功：${data.entries.length} 条笔记、${data.items.length} 件物资、${data.assets.length} 笔资产')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('数据备份',
                style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9AA8BF),
                    fontWeight: FontWeight.w600)),
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
                      Text('当前数据：$_diaryCount 条笔记 · $_itemCount 件物资 · $_assetCount 笔资产',
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
                  subtitle: '选择任意文件即可，会自动校验是否为备份文件',
                  busy: _importing,
                  onTap: _import,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text('显示',
                style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9AA8BF),
                    fontWeight: FontWeight.w600)),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '换机流程：旧手机「导出数据」→ 把文件传到新手机 → 新手机「导入数据」。\n\n从微信导入：先在微信中点开文件 → 右上角「…」→「保存到手机」，再在导入的文件选择器里进入「内部存储 / Download / WeiXin」目录选择（选择器里可点左上角菜单浏览全部文件夹）。',
              style: TextStyle(fontSize: 12, color: Color(0xFF9AA8BF)),
            ),
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
