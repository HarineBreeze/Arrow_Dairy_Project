import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/diary_entry.dart';
import '../models/item.dart';
import 'app_toast.dart';
import 'haptics.dart';
import 'share_image.dart';

/// 分享图生成器签名（测试可注入替身，避免 real async 截图流程）
typedef ShareCapture = Future<File?> Function(
    BuildContext context, DiaryEntry entry, List<Item> items);

/// 分享一篇笔记：生成带品牌落款的长图 → 调起系统分享面板。
///
/// 浏览页顶栏的「分享」与主页卡片长按菜单的「分享」共用这一条链路，
/// 保证两处生成的图完全一致（宽度、信息条、品牌露出都相同）。
///
/// 交互约定：
/// - 生成期间挡一个不可关闭的进度弹窗；
/// - 生成失败 → 「分享图生成失败，请重试」；
/// - 分享面板调起失败 → 「分享失败，请重试」。
Future<void> shareEntryImage(
  BuildContext context,
  DiaryEntry entry, {
  List<Item>? items,
  ShareCapture? capture,
}) async {
  // 先取根导航器：等截图完成时页面可能已被返回键关闭，
  // 但进度弹窗挂在根导航器上，仍需要由这里负责关掉。
  final NavigatorState navigator;
  try {
    navigator = Navigator.of(context, rootNavigator: true);
  } catch (_) {
    return;
  }

  Haptics.light();
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const ShareProgressDialog(),
  ));

  File? file;
  try {
    file = await (capture ?? captureShareCard)(
        context, entry, items ?? const <Item>[]);
  } catch (_) {
    file = null;
  }
  try {
    if (navigator.canPop()) navigator.pop();
  } catch (_) {
    // 页面已销毁：弹窗随路由一起消失，无需处理
  }

  if (file == null) {
    AppToast.show(context, '分享图生成失败，请重试');
    return;
  }
  try {
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: entry.title.isNotEmpty ? '「阿尤日记」· ${entry.title}' : '来自「阿尤日记」',
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 10, 10),
    );
  } catch (_) {
    AppToast.show(context, '分享失败，请重试');
  }
}

/// 分享图生成期间的进度弹窗：不可点掉，生成完由调用方关闭。
class ShareProgressDialog extends StatelessWidget {
  const ShareProgressDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6),
            ),
            SizedBox(height: 14),
            Text(
              '正在生成分享图…',
              style: TextStyle(fontSize: 14, color: Color(0xFF24382F)),
            ),
          ],
        ),
      ),
    );
  }
}
