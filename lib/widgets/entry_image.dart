import 'dart:io';

import 'package:flutter/material.dart';

import 'app_icons.dart';

/// 本地封面图（列表/浏览页/编辑页统一入口）。
///
/// 关键点：`cacheWidth` 按「逻辑显示宽 × 设备像素比」解码，
/// 而不是把 1600px 的原图整幅解到内存里再缩放 —— 列表里几十张图时，
/// 内存占用与滚动掉帧的差别非常明显（原图 1600×1200 ≈ 7.3MB/张）。
///
/// 解码完成前显示浅色占位，完成后再淡入，避免「白块闪烁 + 突然跳动」。
class EntryImage extends StatelessWidget {
  final String path;

  /// 图片在布局中的逻辑宽度，用于推算解码尺寸
  final double displayWidth;
  final BoxFit fit;
  final double iconSize;

  const EntryImage({
    Key? key,
    required this.path,
    required this.displayWidth,
    this.fit = BoxFit.cover,
    this.iconSize = 20,
  }) : super(key: key);

  /// 解码宽度上限：按显示宽度 × DPR，留 1.5 倍冗余适配不同屏幕；
  /// 下限 120 防止极小卡片解出糊图，上限 1600 与选图时的压缩上限一致。
  int _cacheWidth(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return (displayWidth * dpr * 1.5).round().clamp(120, 1600);
  }

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: fit,
      cacheWidth: _cacheWidth(context),
      // 换图（更换/裁剪后）时保留上一帧，不闪白
      gaplessPlayback: true,
      frameBuilder: (ctx, child, frame, wasSyncLoaded) {
        // 解码完成前显示浅色占位；完成后直接上帧。
        // 注意不要在这里包 AnimatedSwitcher/Stack —— 其内部 loose 约束
        // 会让小图按原始尺寸渲染而不是铺满显示区。
        if (wasSyncLoaded || frame != null) return child;
        return _placeholder();
      },
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  /// 解码中 / 文件缺失 / 损坏 时的浅色占位
  Widget _placeholder() {
    return ColoredBox(
      color: const Color(0xFFE4F2EB),
      child: Center(
        child: AppIcon(AppIcons.image, size: iconSize, color: const Color(0xFF8FA09A)),
      ),
    );
  }
}
