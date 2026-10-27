import 'package:flutter/material.dart';

/// 全局「未保存修改」拦截。
///
/// 用法：编辑页把 [WillPopScope.onWillPop] 与 AppBar 返回按钮都指向
/// [confirmLeaveIfDirty]；页面自己维护一个 `_dirty` 判断。
///
/// 规则（用户确认）：
/// - 没有改动 → 直接返回 true，不打扰用户；
/// - 有改动 → 弹框「有未保存的修改哦，确认返回吗?」；
///   - 「取消」：留在页面，由用户自己决定是否点保存；
///   - 「确认」：放弃保存，直接返回。
///
/// 返回 true 表示允许离开当前页面；false 表示留在页面。
Future<bool> confirmLeaveIfDirty(
  BuildContext context, {
  required bool dirty,
}) async {
  if (!dirty) return true;

  final discard = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        '有未保存的修改哦，确认返回吗?',
        style: TextStyle(fontSize: 16, color: Color(0xFF2B3A55)),
      ),
      content: const Text(
        '返回后本次修改不会保存。',
        style: TextStyle(fontSize: 13, color: Color(0xFF8A99B3), height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消',
              style: TextStyle(color: Color(0xFF8A99B3), fontSize: 14)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('确定',
              style: TextStyle(
                  color: Color(0xFF3B6FE0),
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  // 取消 → 留在页面自己决定是否保存；确定 → 放弃修改直接返回
  return discard == true;
}
