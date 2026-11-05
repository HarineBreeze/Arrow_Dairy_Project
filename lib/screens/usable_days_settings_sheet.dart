import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_settings.dart';
import '../utils/app_toast.dart';
import '../utils/haptics.dart';
import '../utils/usable_days.dart';
import '../widgets/app_icons.dart';
import '../widgets/pressable.dart';

/// 「可使用天数」参数设置弹窗。
///
/// 由看板卡片「净资产」旁的圈叹号按钮打开。五个参数：
/// - 总资产：默认取当前净资产（可手动改成别的数）
/// - 月消费（每月预算）：默认 3000
/// - 每月天数：默认 30
/// - 年化利率：默认 3（百分比数值）
/// - 通胀率：默认 2（百分比数值）
///
/// 保存后返回 true，调用方据此刷新卡片。
class UsableDaysSettingsSheet extends StatefulWidget {
  /// 当前净资产：总资产输入框的默认值与占位提示都用它。
  final double? netWorth;

  const UsableDaysSettingsSheet({Key? key, this.netWorth}) : super(key: key);

  /// 以底部弹窗形式呈现
  static Future<bool?> show(BuildContext context, {double? netWorth}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UsableDaysSettingsSheet(netWorth: netWorth),
    );
  }

  @override
  State<UsableDaysSettingsSheet> createState() =>
      _UsableDaysSettingsSheetState();
}

class _UsableDaysSettingsSheetState extends State<UsableDaysSettingsSheet> {
  late final TextEditingController _total;
  late final TextEditingController _cost;
  late final TextEditingController _days;
  late final TextEditingController _rate;
  late final TextEditingController _infl;

  @override
  void initState() {
    super.initState();
    // 没手填过 → 直接带入当前净资产，省得用户还要自己抄一遍
    final t = AppSettings.resolveTotal(netWorthFallback: widget.netWorth);
    _total = TextEditingController(
      text: t == null ? '' : _trimNum(t),
    );
    _cost = TextEditingController(text: _trimNum(AppSettings.usableMonthlyCost));
    _days = TextEditingController(text: _trimNum(AppSettings.usableDaysPerMonth));
    _rate = TextEditingController(text: _trimNum(AppSettings.annualRate));
    _infl = TextEditingController(text: _trimNum(AppSettings.inflationRate));
    // 任一输入变化都重算预览
    for (final c in [_total, _cost, _days, _rate, _infl]) {
      c.addListener(_recalc);
    }
    // 初值是在上面直接赋给 controller 的，赋值时 listener 还没挂上，
    // 不会触发 _recalc —— 不在这里主动算一次，首帧 _previewDays 会是 null，
    // 参数明明填满也会误报「参数不完整，无法计算」。
    _computePreviewNow();
  }

  @override
  void dispose() {
    for (final c in [_total, _cost, _days, _rate, _infl]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 去掉无意义的 .0 尾巴：30.0 → 30
  static String _trimNum(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.round().toString();
    return v.toString();
  }

  static double _parse(TextEditingController c) {
    final s = c.text.trim();
    if (s.isEmpty) return 0;
    return double.tryParse(s) ?? 0;
  }

  double? _previewDays;
  bool _recalcScheduled = false;

  /// 按当前输入立刻算一次预览。
  ///
  /// 初始化时直接调用（赋值阶段不触发 listener）；运行期由 [_recalc]
  /// 合并到下一帧调用，避免每敲一个字符都 setState。
  void _computePreviewNow() {
    final totalText = _total.text.trim();
    final days = UsableDays.compute(
      total: totalText.isEmpty ? null : double.tryParse(totalText),
      monthlyCost: _parse(_cost),
      daysPerMonth: _parse(_days),
      annualRate: _parse(_rate),
      inflationRate: _parse(_infl),
    );
    _previewDays = days;
  }

  void _recalc() {
    // 输入时每敲一个字符都会触发，合并到一帧内算一次
    if (_recalcScheduled) return;
    _recalcScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recalcScheduled = false;
      if (!mounted) return;
      setState(_computePreviewNow);
    });
  }

  Future<void> _save() async {
    final totalText = _total.text.trim();
    final total = totalText.isEmpty ? null : double.tryParse(totalText);

    // 总资产填了但不是合法数字 → 明确报错，不静默丢弃
    if (totalText.isNotEmpty && total == null) {
      AppToast.show(context, '总资产请填写有效数字');
      return;
    }

    final days = _parse(_days);
    if (days <= 0) {
      AppToast.show(context, '每月天数需大于 0');
      return;
    }

    Haptics.mediumNow();
    await AppSettings.setUsableParams(
      total: total,
      monthlyCost: _parse(_cost),
      daysPerMonth: days,
      annualRate: _parse(_rate),
      inflationRate: _parse(_infl),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7F9FD),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖动条
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD5DDEA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
                child: Row(
                  children: [
                    const Text('可使用天数',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2A3B52))),
                    const SizedBox(width: 6),
                    const Text('参数',
                        style: TextStyle(
                            fontSize: 12, color: Color(0xFF9AA8BF))),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context, false),
                      icon: const AppIcon(AppIcons.close,
                          size: 20, color: Color(0xFF9AA8BF)),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(
                        label: '总资产',
                        hint: '默认取当前净资产',
                        controller: _total,
                        allowDecimal: true,
                      ),
                      _field(
                        label: '每月预算',
                        hint: '3000',
                        controller: _cost,
                        allowDecimal: true,
                      ),
                      _field(
                        label: '每月天数',
                        hint: '30',
                        controller: _days,
                        allowDecimal: false,
                      ),
                      _field(
                        label: '年化利率',
                        hint: '3',
                        suffix: '%',
                        controller: _rate,
                        allowDecimal: true,
                      ),
                      _field(
                        label: '通胀率',
                        hint: '2',
                        suffix: '%',
                        controller: _infl,
                        allowDecimal: true,
                      ),
                      const SizedBox(height: 6),
                      _buildPreview(),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: Pressable(
                    enabled: true,
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        primary: const Color(0xFF3B6FE0),
                        onPrimary: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('保存',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 结果预览 + 提示语。
  ///
  /// 不展示计算公式与中间量（x / y）——用户要的只是「能用多少天」以及
  /// 一眼能看懂的异常提示。
  Widget _buildPreview() {
    final totalText = _total.text.trim();
    final rateDiff = _parse(_rate) - _parse(_infl);
    final d = _previewDays;

    String body;
    Color color;
    if (totalText.isEmpty) {
      body = '填写总资产后即可算出「可使用 x 天」';
      color = const Color(0xFF9AA8BF);
    } else if (d == null) {
      body = _parse(_cost) <= 0
          ? '每月预算需大于 0 才能计算'
          : '参数不完整，无法计算';
      color = const Color(0xFFF08C3A);
    } else if (rateDiff <= 0) {
      // 差值原本是百分数（5 - 2 = 3），提示里带上 %，用户才知道是 3 个百分点
      body = '年化利率需大于通胀率，否则可使用天数不会增加'
          '（当前差值 ${_trimNum(rateDiff)}%）';
      color = const Color(0xFFF08C3A);
    } else if (UsableDays.isSuspicious(d)) {
      body = '数值异常偏大，请检查总资产与月消费';
      color = const Color(0xFFE0576A);
    } else {
      body = '';
      color = const Color(0xFF2A9D5C);
    }
    // 到这里 d 一定非空（前面 d == null 已单独分支），用局部变量固化提升
    final double dd = d ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (body.isNotEmpty) ...[
            Text(body,
                style: TextStyle(fontSize: 12.5, color: color, height: 1.5)),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                const Text('可使用 ',
                    style:
                        TextStyle(fontSize: 13, color: Color(0xFF8A99B3))),
                Text(UsableDays.format(dd),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: color)),
                if (UsableDays.formatYears(dd).isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text('（${UsableDays.formatYears(dd)}）',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF9AA8BF))),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool allowDecimal,
    String? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: Color(0xFF2A3B52))),
          ),
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE8EDF5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.numberWithOptions(
                          decimal: allowDecimal, signed: false),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          allowDecimal
                              ? RegExp(r'[0-9.]')
                              : RegExp(r'[0-9]'),
                        ),
                      ],
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF2A3B52)),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: hint,
                        hintStyle: const TextStyle(
                            fontSize: 13, color: Color(0xFFC4CEDD)),
                      ),
                    ),
                  ),
                  if (suffix != null)
                    Text(suffix,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF9AA8BF))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
