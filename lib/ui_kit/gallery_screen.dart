import 'package:flutter/material.dart';

import 'theme.dart';
import 'showcase_screen.dart';
import 'static_wrappers.dart';

/// UI 方案总览：四套成套设计并排展示（每套含菜单侧边栏 + 四主页）
class UiGalleryScreen extends StatelessWidget {
  const UiGalleryScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101319),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                itemCount: UiTheme.all.length,
                separatorBuilder: (_, __) => const SizedBox(height: 22),
                itemBuilder: (_, i) => _SetBlock(theme: UiTheme.all[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white70),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UI 方案预览',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '四套成套设计 · 同一排版逻辑，不同视觉语言',
                  style: TextStyle(fontSize: 11.5, color: Colors.white38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetBlock extends StatelessWidget {
  final UiTheme theme;
  const _SetBlock({Key? key, required this.theme}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF191D26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.accent.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: theme.accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                theme.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  theme.tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white38),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: theme.accent.withOpacity(0.16),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => UiShowcaseScreen(theme: theme),
                )),
                child: Text(
                  '交互预览',
                  style: TextStyle(fontSize: 12, color: theme.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 522,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _thumb(theme, '菜单侧边栏', UiSideBarStatic(theme: theme)),
                _thumb(theme, '笔记主页', DiaryPageStatic(theme: theme)),
                _thumb(theme, '物资清单', ItemsPageStatic(theme: theme)),
                _thumb(theme, '倒数日', CountdownPageStatic(theme: theme)),
                _thumb(theme, '资产全景', AssetsPageStatic(theme: theme)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb(UiTheme theme, String label, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.4,
                color: theme.accent,
              ),
            ),
          ),
          UiPhoneShell(
            theme: theme,
            child: SizedBox(width: 248, height: 496, child: child),
          ),
        ],
      ),
    );
  }
}
