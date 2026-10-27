import 'package:flutter/foundation.dart';

/// 愿望单卡片横向滑动（攒钱/减钱）期间置为 true，
/// 用于阻止主页左半屏手势把菜单拖出来。
final ValueNotifier<bool> menuDragBlocked = ValueNotifier(false);
