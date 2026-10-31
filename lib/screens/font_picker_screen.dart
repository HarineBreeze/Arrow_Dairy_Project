import 'package:flutter/material.dart';
import '../utils/app_toast.dart';
import '../services/app_settings.dart';

/// 字体选择页：预览文字直接以对应字体渲染（字体均打包在 APK 内）。
class FontPickerScreen extends StatefulWidget {
  const FontPickerScreen({Key? key}) : super(key: key);

  @override
  State<FontPickerScreen> createState() => _FontPickerScreenState();
}

class _FontPickerScreenState extends State<FontPickerScreen> {
  @override
  Widget build(BuildContext context) {
    final current = AppSettings.fontFamilyId;
    return Scaffold(
      appBar: AppBar(title: const Text('字体')),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: FontCatalog.fonts.length,
        itemBuilder: (context, i) {
          final f = FontCatalog.fonts[i];
          final id = f['id']!;
          final selected = current == id;
          final previewStyle = TextStyle(
            fontSize: 17,
            height: 1.5,
            color: const Color(0xFF2A3B52),
            fontFamily: id.isEmpty ? null : id,
          );
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: selected ? const Color(0xFFEAF1FF) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  await AppSettings.setFontFamily(id);
                  if (!mounted) return;
                  setState(() {});
                  // 连点字体卡片时只提示最后选中的那一个
                  AppToast.show(
                      context,
                      id.isEmpty ? '已恢复默认字体' : '已切换为「${f['name']}」');
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF3B6FE0)
                          : const Color(0xFFE8EDF5),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 名称行：用该字体渲染名称，直观展示风格
                            Text(
                              id.isEmpty
                                  ? '默认字体 · 跟随系统'
                                  : '${f['name']} · ${f['desc']}',
                              style: id.isEmpty
                                  ? const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF2A3B52))
                                  : previewStyle.copyWith(
                                      fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '今天下了很大的雨，我撑着伞走了很久。ABC 123',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: previewStyle.copyWith(fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (selected)
                        const Icon(Icons.check_circle,
                            color: Color(0xFF3B6FE0), size: 22)
                      else
                        const Icon(Icons.radio_button_unchecked,
                            color: Color(0xFFC4CEDD), size: 22),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
