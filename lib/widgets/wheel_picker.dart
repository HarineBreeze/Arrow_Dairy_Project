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
  String title = '选择日期',
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
      title: title,
    ),
  );
}

class _DateWheelSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime minimum;
  final DateTime maximum;
  final String title;

  const _DateWheelSheet({
    required this.initial,
    required this.minimum,
    required this.maximum,
    this.title = '选择日期',
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
            title: widget.title,
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

/// 内嵌时间滚轮：两列（时 / 分），样式与日期滚轮完全一致。
class _InlineTimeWheel extends StatefulWidget {
  final int initialHour;
  final int initialMinute;
  final void Function(int hour, int minute) onChanged;

  const _InlineTimeWheel({
    required this.initialHour,
    required this.initialMinute,
    required this.onChanged,
  });

  @override
  State<_InlineTimeWheel> createState() => _InlineTimeWheelState();
}

class _InlineTimeWheelState extends State<_InlineTimeWheel> {
  late int _hour = widget.initialHour;
  late int _minute = widget.initialMinute;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: WheelColumn(
            items: [for (var h = 0; h < 24; h++) h],
            initialIndex: _hour.clamp(0, 23),
            unit: '时',
            onSelected: (v) {
              setState(() => _hour = v);
              widget.onChanged(_hour, _minute);
            },
          ),
        ),
        Expanded(
          child: WheelColumn(
            items: [for (var m = 0; m < 60; m++) m],
            initialIndex: _minute.clamp(0, 59),
            unit: '分',
            onSelected: (v) {
              setState(() => _minute = v);
              widget.onChanged(_hour, _minute);
            },
          ),
        ),
      ],
    );
  }
}

/// 滚轮时间选择器（时 / 分，24 小时制，样式与日期滚轮一致）。
Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initial,
  String title = '选择时间',
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
      title: title,
      child: SizedBox(
        height: kWheelHeight,
        child: _InlineTimeWheel(
          initialHour: hour,
          initialMinute: minute,
          onChanged: (h, m) {
            hour = h;
            minute = m;
          },
        ),
      ),
      onConfirm: () => Navigator.pop(ctx, TimeOfDay(hour: hour, minute: minute)),
    ),
  );
}

/// 滚轮日期 + 时间选择器（用于事件等需要精确到分钟的场景）。
///
/// **分两步**：先弹出「选择日期」（年 / 月 / 日），确定后再弹出「选择时间」
/// （时 / 分）。之前把两段滚轮塞在同一个弹层里，四列加两块内容挤在一起
/// 显得很杂，也容易误触到另一段；拆开之后每次只专注一件事，
/// 而且中途取消时间选择也不会丢掉已经选好的日期。
///
/// 返回：两步都确认 → 完整日期时间；日期那一步取消 → null。
Future<DateTime?> showWheelDateTimePicker(
  BuildContext context, {
  required DateTime initial,
  String dateTitle = '选择日期',
  String timeTitle = '选择时间',
  DateTime? minimum,
  DateTime? maximum,
}) async {
  final date = await showWheelDatePicker(
    context,
    initial: initial,
    minimum: minimum,
    maximum: maximum,
    title: dateTitle,
  );
  if (date == null) return null;

  final time = await showWheelTimePicker(
    context,
    initial: TimeOfDay(hour: initial.hour, minute: initial.minute),
    title: timeTitle,
  );
  // 时间那一步取消 = 默认沿用原来的时分，日期仍然保留（不白选一次）
  final km = time ?? TimeOfDay(hour: initial.hour, minute: initial.minute);
  return DateTime(date.year, date.month, date.day, km.hour, km.minute);
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
