import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 滚轮式日期/时间选择器。
///
/// 使用 [CupertinoDatePicker] / [CupertinoTimerPicker]：它们是滚轮结构，
/// 自带惯性减速、刻度吸附（松手自动吸附到最近的整值）与边缘惯性回弹，
/// 正好符合「带惯性减速、刻度吸附和惯性回弹」的要求。
const Color _kBlue = Color(0xFF3B6FE0);

/// 滚轮日期选择器（年 / 月 / 日）。
Future<DateTime?> showWheelDatePicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? minimum,
  DateTime? maximum,
}) {
  var selected = DateTime(initial.year, initial.month, initial.day);
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _WheelSheet(
      title: '选择日期',
      child: SizedBox(
        height: 216,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: selected,
          minimumDate: minimum ?? DateTime(2000),
          maximumDate: maximum ?? DateTime(2100),
          onDateTimeChanged: (d) =>
              selected = DateTime(d.year, d.month, d.day),
        ),
      ),
      onConfirm: () => Navigator.pop(ctx, selected),
    ),
  );
}

/// 滚轮时间选择器（时 : 分，24 小时制）。
Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
}) {
  var hour = initial.hour;
  var minute = initial.minute;
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _WheelSheet(
      title: '选择时间',
      child: SizedBox(
        height: 216,
        child: CupertinoTimerPicker(
          mode: CupertinoTimerPickerMode.hm,
          initialTimerDuration: Duration(hours: hour, minutes: minute),
          onTimerDurationChanged: (d) {
            hour = d.inHours;
            minute = d.inMinutes % 60;
          },
        ),
      ),
      onConfirm: () => Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute)),
    ),
  );
}

/// 滚轮日期 + 时间选择器（年 / 月 / 日 + 时 : 分），用于倒数日等需要精确到分钟的场景。
Future<DateTime?> showWheelDateTimePicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? minimum,
  DateTime? maximum,
}) {
  var selected = initial;
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _WheelSheet(
      title: '选择事件日',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 180,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: selected,
              minimumDate: minimum ?? DateTime(2000),
              maximumDate: maximum ?? DateTime(2100),
              onDateTimeChanged: (d) => selected = DateTime(
                  d.year, d.month, d.day, selected.hour, selected.minute),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEF1F6)),
          SizedBox(
            height: 180,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              use24hFormat: true,
              initialDateTime: selected,
              onDateTimeChanged: (d) => selected = DateTime(
                  selected.year, selected.month, selected.day, d.hour, d.minute),
            ),
          ),
        ],
      ),
      onConfirm: () => Navigator.pop(ctx, selected),
    ),
  );
}

/// 底部弹层骨架：标题 + 滚轮 + 取消/确定。
class _WheelSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onConfirm;

  const _WheelSheet({
    required this.title,
    required this.child,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消',
                      style: TextStyle(fontSize: 16, color: Color(0xFF5A6B82))),
                ),
                Expanded(
                  child: Center(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2A3B52))),
                  ),
                ),
                TextButton(
                  onPressed: onConfirm,
                  child: const Text('确定',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _kBlue)),
                ),
              ],
            ),
          ),
          child,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
