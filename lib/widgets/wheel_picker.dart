import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 滚轮式日期 / 时间选择器。
///
/// 自带惯性减速、刻度吸附（松手后缓动停到最近的整值）与边缘惯性回弹
/// （越界后回弹到边界），风格与 iOS 滚轮一致。
///
/// 日期**没有**直接用 [CupertinoDatePicker]：它的列顺序与列内内容
/// （`September` / `25` / `2025`）都跟随系统 locale，本项目没有接入
/// flutter_localizations，直接用它会出现「英文月名 + 日/月/年 顺序」。
/// 这里改为自绘三列（年 / 月 / 日），中文单位直接写在数字后面，
/// 顺序固定为 年 → 月 → 日。
const Color _kBlue = Color(0xFF3B6FE0);

/// 项高：每格滚轮高度。
const double kWheelItemExtent = 36;

/// 视口高度：正好露出 5 格，上下各留半格，提示可以继续滚。
const double kWheelHeight = kWheelItemExtent * 5;

/// 一列滚轮：数字 + 可选中缀（年 / 月 / 日 / 时 / 分）。
///
/// [items] 是这一列的可选值；[unit] 非空时，渲染为「12月」，
/// 但**只有数字**参与吸附居中，中缀偏在数字右侧，避免把数字挤歪。
class WheelColumn extends StatefulWidget {
  final List<int> items;
  final int initialIndex;
  final String unit;
  final ValueChanged<int> onSelected;

  const WheelColumn({
    Key? key,
    required this.items,
    required this.initialIndex,
    required this.onSelected,
    this.unit = '',
  }) : super(key: key);

  @override
  State<WheelColumn> createState() => WheelColumnState();
}

class WheelColumnState extends State<WheelColumn> {
  late FixedExtentScrollController _ctrl =
      FixedExtentScrollController(initialItem: widget.initialIndex);

  int get selectedIndex => _ctrl.selectedItem;

  /// 外部改值（如选 2 月后日期越界 → 回填）：不触发 onSelected。
  void jumpTo(int index) {
    if (!_ctrl.hasClients) return;
    final target = index.clamp(0, widget.items.length - 1);
    if (_ctrl.selectedItem == target) return;
    _ctrl.jumpToItem(target);
    setState(() {});
  }

  @override
  void didUpdateWidget(WheelColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      final target = selectedIndex.clamp(0, widget.items.length - 1);
      // 长度变了（如 2 月只有 28 天）→ 新建控制器，旧控制器在下一帧回收
      final oldCtrl = _ctrl;
      _ctrl = FixedExtentScrollController(initialItem: target);
      WidgetsBinding.instance.addPostFrameCallback((_) => oldCtrl.dispose());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kWheelHeight,
      child: CupertinoPicker.builder(
        scrollController: _ctrl,
        itemExtent: kWheelItemExtent,
        // 必须为 true：否则点击上下行无法吸附过去
        selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
          capStartEdge: false,
          capEndEdge: false,
        ),
        useMagnifier: true,
        magnification: 1.06,
        squeeze: 1.0,
        diameterRatio: 1.5,
        onSelectedItemChanged: (i) {
          widget.onSelected(widget.items[i]);
          setState(() {});
        },
        childCount: widget.items.length,
        itemBuilder: (context, i) => _WheelLabel(
          text: '${widget.items[i]}',
          unit: widget.unit,
        ),
      ),
    );
  }
}

/// 滚轮里的一格：数字居中，单位作为后缀贴在数字右边。
///
/// 用 Row + [MainAxisSize.min] 居中，单位不参与「数字居中」的计算基准 ——
/// 否则「9 日」和「28 日」会因为单位宽度让数字左右漂移。
class _WheelLabel extends StatelessWidget {
  final String text;
  final String unit;

  const _WheelLabel({required this.text, this.unit = ''});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            text,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2A3B52),
            ),
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF5A6B82),
              ),
            ),
        ],
      ),
    );
  }
}

/// 滚轮日期选择器（年 → 月 → 日，列顺序固定）。
Future<DateTime?> showWheelDatePicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? minimum,
  DateTime? maximum,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _DateWheelSheet(
      initial: initial,
      minimum: minimum ?? DateTime(2000),
      maximum: maximum ?? DateTime(2100),
    ),
  );
}

class _DateWheelSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime minimum;
  final DateTime maximum;

  const _DateWheelSheet({
    required this.initial,
    required this.minimum,
    required this.maximum,
  });

  @override
  State<_DateWheelSheet> createState() => _DateWheelSheetState();
}

class _DateWheelSheetState extends State<_DateWheelSheet> {
  final GlobalKey<WheelColumnState> _yearKey = GlobalKey();
  final GlobalKey<WheelColumnState> _monthKey = GlobalKey();
  final GlobalKey<WheelColumnState> _dayKey = GlobalKey();

  late int _year;
  late int _month;
  late int _day;

  int get _minYear => widget.minimum.year;
  int get _maxYear => widget.maximum.year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year.clamp(_minYear, _maxYear);
    _month = widget.initial.month.clamp(1, 12);
    _day = widget.initial.day.clamp(1, _daysIn(_year, _month));
  }

  static int _daysIn(int y, int m) => DateTime(y, m + 1, 0).day;

  /// 年月变化后修正日期：1 月 31 日切到 2 月自动变 28/29 日
  void _clampDay() {
    final maxDay = _daysIn(_year, _month);
    if (_day > maxDay) {
      _day = maxDay;
      _dayKey.currentState?.jumpTo(_day - 1);
    }
  }

  bool _outOfRange(int y, int m, int d) {
    final dt = DateTime(y, m, d);
    return dt.isBefore(DateTime(widget.minimum.year, widget.minimum.month,
            widget.minimum.day)) ||
        dt.isAfter(
            DateTime(widget.maximum.year, widget.maximum.month, widget.maximum.day));
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysIn(_year, _month);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHeader(
            title: '选择日期',
            onConfirm: () {
              if (_outOfRange(_year, _month, _day)) return;
              Navigator.pop(context, DateTime(_year, _month, _day));
            },
          ),
          Row(
            children: [
              Expanded(
                child: WheelColumn(
                  key: _yearKey,
                  items: [for (var y = _minYear; y <= _maxYear; y++) y],
                  initialIndex: _year - _minYear,
                  unit: '年',
                  onSelected: (v) => setState(() {
                    _year = v;
                    _clampDay();
                  }),
                ),
              ),
              Expanded(
                child: WheelColumn(
                  key: _monthKey,
                  items: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
                  initialIndex: _month - 1,
                  unit: '月',
                  onSelected: (v) => setState(() {
                    _month = v;
                    _clampDay();
                  }),
                ),
              ),
              Expanded(
                child: WheelColumn(
                  key: _dayKey,
                  items: [for (var d = 1; d <= days; d++) d],
                  initialIndex: (_day - 1).clamp(0, days - 1),
                  unit: '日',
                  onSelected: (v) => setState(() => _day = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
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
  var hour = initial.hour;
  var minute = initial.minute;
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
          _DateTimeWheel(
            initial: initial,
            minimum: minimum,
            maximum: maximum,
            onChanged: (d) {
              hour = d.hour;
              minute = d.minute;
            },
            onHourMinute: (h, m) {
              hour = h;
              minute = m;
            },
          ),
        ],
      ),
      onConfirm: () => Navigator.pop(
        ctx,
        DateTime(initial.year, initial.month, initial.day, hour, minute),
      ),
    ),
  );
}

/// 日期 + 时间两段滚轮：上段年月日（自绘中文），下段时 : 分（Cupertino 计时器）。
class _DateTimeWheel extends StatefulWidget {
  final DateTime initial;
  final DateTime? minimum;
  final DateTime? maximum;
  final ValueChanged<DateTime> onChanged;
  final void Function(int hour, int minute) onHourMinute;

  const _DateTimeWheel({
    required this.initial,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
    required this.onHourMinute,
  });

  @override
  State<_DateTimeWheel> createState() => _DateTimeWheelState();
}

class _DateTimeWheelState extends State<_DateTimeWheel> {
  late DateTime _date = widget.initial;

  @override
  Widget build(BuildContext context) {
    final min = widget.minimum ?? DateTime(2000);
    final max = widget.maximum ?? DateTime(2100);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: kWheelHeight,
          child: _InlineDateWheel(
            initial: _date,
            minimum: min,
            maximum: max,
            onChanged: (d) {
              setState(() => _date = DateTime(
                  d.year, d.month, d.day, _date.hour, _date.minute));
              widget.onChanged(_date);
            },
          ),
        ),
        const Divider(height: 1, color: Color(0xFFEEF1F6)),
        SizedBox(
          height: 180,
          child: CupertinoTimerPicker(
            mode: CupertinoTimerPickerMode.hm,
            initialTimerDuration:
                Duration(hours: _date.hour, minutes: _date.minute),
            onTimerDurationChanged: (d) {
              widget.onHourMinute(d.inHours, d.inMinutes % 60);
            },
          ),
        ),
      ],
    );
  }
}

/// 内嵌版「年 / 月 / 日」三列（与 [_DateWheelSheet] 共用同一套列逻辑）。
class _InlineDateWheel extends StatefulWidget {
  final DateTime initial;
  final DateTime minimum;
  final DateTime maximum;
  final ValueChanged<DateTime> onChanged;

  const _InlineDateWheel({
    required this.initial,
    required this.minimum,
    required this.maximum,
    required this.onChanged,
  });

  @override
  State<_InlineDateWheel> createState() => _InlineDateWheelState();
}

class _InlineDateWheelState extends State<_InlineDateWheel> {
  final GlobalKey<WheelColumnState> _dayKey = GlobalKey();

  late int _year = widget.initial.year;
  late int _month = widget.initial.month;
  late int _day = widget.initial.day;

  static int _daysIn(int y, int m) => DateTime(y, m + 1, 0).day;

  void _emit() {
    final maxDay = _daysIn(_year, _month);
    if (_day > maxDay) {
      _day = maxDay;
      _dayKey.currentState?.jumpTo(_day - 1);
    }
    widget.onChanged(DateTime(_year, _month, _day));
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysIn(_year, _month);
    return Row(
      children: [
        Expanded(
          child: WheelColumn(
            items: [
              for (var y = widget.minimum.year; y <= widget.maximum.year; y++) y
            ],
            initialIndex: _year - widget.minimum.year,
            unit: '年',
            onSelected: (v) {
              setState(() => _year = v);
              _emit();
            },
          ),
        ),
        Expanded(
          child: WheelColumn(
            items: const [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
            initialIndex: _month - 1,
            unit: '月',
            onSelected: (v) {
              setState(() => _month = v);
              _emit();
            },
          ),
        ),
        Expanded(
          child: WheelColumn(
            key: _dayKey,
            items: [for (var d = 1; d <= days; d++) d],
            initialIndex: (_day - 1).clamp(0, days - 1),
            unit: '日',
            onSelected: (v) {
              setState(() => _day = v);
              _emit();
            },
          ),
        ),
      ],
    );
  }
}

/// 底部弹层骨架：标题 + 滚轮 + 取消/确定。
class _SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onConfirm;

  const _SheetHeader({required this.title, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Padding(
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
    );
  }
}

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
          _SheetHeader(title: title, onConfirm: onConfirm),
          child,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
