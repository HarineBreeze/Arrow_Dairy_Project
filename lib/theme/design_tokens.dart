/// 设计规范 Token · v4.9 收敛后唯一口径
///
/// 背景：v4.8.x 期间圆角出现过 13 种、字号 24 种（含 11.5/12.5/13.5/14.5/15.5
/// 五个半像素值），同一个「卡片」身份下混着 14/16/17/18/20 五套圆角。
/// v4.9 起统一到下面的档位，**新增代码必须引用这里的常量，不得写字面量**。
///
/// 迁移对照（旧值 → 新档）：
/// - 圆角：14/17/18/20 → [AppRadius.card]；10/11/12 → [AppRadius.control]；
///   3/4/6/8 → [AppRadius.chip]；细分条与滑块保持 2（[AppRadius.hairline]）
/// - 字号：24/20 → [AppFont.pageTitle]；18 → [AppFont.sectionTitle]；
///   16/15.5/15/14.5 → [AppFont.body]；14/13.5/13/12.5/12 → [AppFont.caption]；
///   11.5/10.5/10/11 → [AppFont.label]
///
/// 例外（有意保留，不参与收敛）：
/// - 字号 32 资产看板大数字、28 笔记大标题、19 滚轮选择器、9.5 密码遮罩、8/7 极小角标
/// - 圆角 2 正负资产结构条 / 进度条 / 滑块；头像与心情圆点走圆形
class AppRadius {
  AppRadius._();

  /// 卡片、弹窗、底部抽屉：16
  static const double card = 16;

  /// 输入框、按钮、内层容器、侧边栏项：12
  static const double control = 12;

  /// 小卡、工具栏项、日期地点格、小标签：8
  static const double chip = 8;

  /// 细分条、进度条、滑块：2（非卡片语义，不参与收敛）
  static const double hairline = 2;

  /// 胶囊 / 头像：全圆
  static const double pill = 999;
}

class AppFont {
  AppFont._();

  /// 资产看板大数字：32
  static const double hero = 32;

  /// 笔记浏览页大标题：28
  static const double display = 28;

  /// 页面标题、编辑页标题输入：22
  static const double pageTitle = 22;

  /// 卡片标题、设置项、页内区块标题：17
  static const double sectionTitle = 17;

  /// 正文、输入框、按钮文字：15
  static const double body = 15;

  /// 辅助说明、时间戳、卡片副标题：13
  static const double caption = 13;

  /// 小标签、字段名、角标文字：11
  static const double label = 11;
}
