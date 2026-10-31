import 'package:flutter/material.dart';

import 'pressable.dart';
import 'save_done_button.dart';

/// 编辑页底部「取消 + 完成」保存栏。
///
/// - 未点击：取消（左）+ 完成（右）左右分布，两个按钮都可见、可点。
/// - 点击完成：取消按钮淡出并让出宽度，完成按钮收缩成居中圆形，
///   打勾 + 粒子，播完回调 [onDone] 返回上一页。
///
/// 用 Row 而非 Stack：旧实现把整宽完成按钮叠在取消之上，取消被遮盖；
/// 且旧实现拿不到 [SaveDoneButtonState] 时回退成「已收缩」，首帧就把取消隐藏。
class SaveBar extends StatefulWidget {
  final GlobalKey<SaveDoneButtonState> saveKey;
  final Color color;

  /// 取消回调；为 null 表示取消不可点（保存中）。
  final VoidCallback? onCancel;

  final String? Function()? validate;
  final VoidCallback? onSave;
  final VoidCallback onDone;

  const SaveBar({
    Key? key,
    required this.saveKey,
    required this.color,
    this.onCancel,
    this.validate,
    this.onSave,
    required this.onDone,
  }) : super(key: key);

  @override
  State<SaveBar> createState() => _SaveBarState();
}

class _SaveBarState extends State<SaveBar> {
  Animation<double>? _anim;

  @override
  void initState() {
    super.initState();
    // 首帧后完成按钮的 State 才挂到 GlobalKey 上，此时再订阅它的收缩动画。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _attach();
    });
  }

  @override
  void didUpdateWidget(SaveBar old) {
    super.didUpdateWidget(old);
    _attach();
  }

  void _attach() {
    final a = widget.saveKey.currentState?.collapse;
    if (identical(a, _anim)) return;
    _anim?.removeListener(_onTick);
    _anim = a;
    _anim?.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _anim?.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _attach();
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final t = (_anim?.value ?? 0).clamp(0.0, 1.0);
          final cancelW = (constraints.maxWidth / 2) * (1 - t);
          final gapW = 12.0 * (1 - t);
          return Row(
            children: [
              SizedBox(
                width: cancelW,
                child: Opacity(
                  opacity: (1 - t * 2.0).clamp(0.0, 1.0),
                  child: IgnorePointer(
                    ignoring: t > 0 || widget.onCancel == null,
                    child: Pressable(
                      enabled: true,
                      child: OutlinedButton(
                        onPressed: widget.onCancel,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFF3B6FE0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('取消',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: gapW),
              Expanded(
                child: SaveDoneButton(
                  key: widget.saveKey,
                  color: widget.color,
                  validate: widget.validate,
                  onTap: widget.onSave,
                  onDone: widget.onDone,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
