# 阿尤日记 · 项目交接摘要

> 截至 **v4.9.32**（versionCode 139，commit `9324d18`）。
> 本文件是跨设备 / 跨会话接手的**唯一入口**：新会话先读它，即可无缝续接，无需重新口述背景。
> 关键信息均以源码为准，文中标注了对应文件与行号/符号，便于核对。

---

## 0. 项目速览

| 项 | 值 |
|---|---|
| 名称 / 包名 | 阿尤日记 / `com.shiguang.diary_app` |
| 仓库 | `HarineBreeze/Arrow_Dairy_Project`（main 分支） |
| 技术栈 | Flutter 3（Dart），无任何网络库；纯本地 JSON 存储 |
| 核心依赖 | `path_provider`、`image_picker`、`file_picker`、`share_plus`、`path`、`cupertino_icons` |
| 当前定位 | **离线单机版生活账本**：日记 + 物品 + 资产 + 倒计时四模块打通 |
| 商业模式现状 | 全功能免费；积分/徽章/兑换码/VIP 为荣誉与留存体系，不锁功能 |

---

## 1. 目录与架构地图

```
lib/
├─ main.dart                    入口：主题订阅、路由表
├─ models/                      diary_entry / item / asset / countdown_event / user_profile
├─ services/                    各 *_storage（本地 JSON 读写）、app_settings、backup_service、
│                                reward_service（积分/兑换码/商城）、countdown_reminder
├─ screens/                     18 个页面（见下）
├─ widgets/                     通用组件（pressable / app_icons / save_bar / rich_note_text 等）
├─ theme/                       app_palette（语义色板）、app_theme_scope（明暗即时重建）
└─ utils/                       app_motion / app_sheet / app_toast / haptics / app_version 等
```

**18 个页面**：home（日记主页）、edit（笔记编辑）、note_view（笔记浏览）、item_list / item_edit（物品）、asset_screen / asset_edit（资产）、countdown_screen / countdown_edit（事件）、global_search、trash（回收站）、points_shop（积分商城）、profile_edit（个人信息）、settings、side_menu（侧边栏）、font_picker、image_crop、usable_days_settings_sheet。

**本地存储文件**（均在 `getApplicationDocumentsDirectory()` 下）：

| 文件 | 内容 |
|---|---|
| `diaries.json` / `items.json` / `assets.json` / `countdowns.json` | 四类主数据 |
| `trash.json` | 回收站（保留 7 天） |
| `user_profile.json` | 档案：昵称/性别/头像/积分/徽章/VIP 时效/userId/注册日 |
| `user_id_seq.json` | 用户 ID 顺序发号（与档案分离，删档不回退） |
| `asset_pin.json` | 资产页密码 |
| `app_settings.json` | 主题模式 / 字体 / 震动总开关 |

> 资产密码用 `b ^ 0x5A` 逐字节混淆后存储（`asset_storage.dart:66`），非强加密，仅为防止误看。

---

## 2. UI 设计规则（必须遵守）

### 2.1 色彩体系 —— 语义色板 `AppPalette`（`lib/theme/app_palette.dart`）

**铁律：代码里不直接写深色判断，一律走 `AppPalette.c(argb)` / `.surface` / `.topBar`。**

- `c(int argb)`：**浅色模式原样返回**传入色值（保证既有精确颜色断言零回归），深色模式查 `darkMap` 转换，未登记的颜色保持原值。
- `surface` = `c(0xFFFFFFFF)`：白色卡片/容器/弹窗背景，深色下为 `0xFF18221E`。项目约 84 处白卡片统一走它。
- `topBar`：实心顶栏背景，浅色竹青 `0xFF3E8E6D` / 深色深墨绿 `0xFF22342C`。
- 半透明顶栏色块 `0xB3/0xCC/0xE6 3E8E6D`（70%/80%/90% 绿）在深色下统一映射为 `0xFF22342C`，避免"深色页顶亮绿块"。`0xB33E8E6D` 是各主页顶栏标准色。
- `darkMap` **只登记中性色**（页面底/卡片底/文字/边框/顶栏色块）。品牌色与语义色一律不登记、跨主题保持原值：
  - 主色竹青 `0xFF3E8E6D`、警示红 `0xFFCB5C50`、橙 `0xFFF08C3A`
  - 身份牌色、图表色、渐变、半透明黑白遮罩
- 主文字 `0xFF24382F`（深）→ `0xFFE9F2EB`（浅）；次要 `0xFF647A70` → `0xFFA8BCB0`；辅助 `0xFF8FA09A` → `0xFF90A69A`。
- 顶栏/主色块上的前景文字与图标**始终 `Colors.white`**，不参与映射。
- 主题模式三态 `AppThemeMode { system, light, dark }`，持久化到 `app_settings.json` 的 `themeMode` 字段。
- 深浅切换靠 `AppThemeScope`（InheritedWidget，`lib/theme/app_theme_scope.dart`）：所有页面 build 订阅，切换即时全量重建且保留 State / 导航栈。

### 2.2 圆角档位（实际统计频次）

| 档位 | 语义 | 使用 |
|---|---|---|
| **16** | 卡片、弹窗、底部抽屉 | 68 处（最多） |
| **12** | 输入框、按钮、内层容器、侧栏项 | 49 处 |
| **8** | 小卡、工具栏项、日期地点格、小标签 | 24 处 |
| **2** | 细分条、进度条、滑块（非卡片语义） | 7 处 |
| 999 | 胶囊 / 头像 | 圆形场景 |

> 历史注记：曾有 `design_tokens.dart`（AppRadius/AppFont）试图固化档位，但零引用，已在 v4.9.32 删除。**档位靠约定维持，不要写字面量之外的新值**；若新增档位请在本文登记。

### 2.3 字号档位（实际统计频次）

| 档位 | 语义 |
|---|---|
| **15**（112 处）/ **13**（145 处） | 正文 / 辅助说明、时间戳、卡片副标题（两大主力） |
| **11** | 小标签、字段名、角标 |
| **17** | 卡片标题、设置项、页内区块标题 |
| **22** | 页面标题、编辑页标题输入 |
| **32** | 资产看板大数字 |

> 历史遗留例外值仍在用：14、19（滚轮选择器）、12、9.5（密码遮罩）、9 / 8 / 7（极小角标）。新代码优先用上表档位，不要再造半像素值（11.5/12.5/13.5/14.5/15.5）。

### 2.4 边距 / 间距常用档位

高频值（按频次）：**16、20、12、14、8、10、24、6、4**（px）。

- 页面左右安全边距：`16`
- 卡片内边距：`14` 横向 / `12~16` 纵向
- 控件间距：`8` / `12`
- 列表项间隔：`10`
- 区块间距：`20` / `24`
- 密集元素：`4` / `6`

### 2.5 顶栏高度（v4.9.31 统一）

- **所有主页与对应编辑页 / 浏览页顶栏高度统一 `48`**（AppBar `toolbarHeight: 48`）。
- 各主页顶栏自定义色 `0xB33E8E6D`（70% 绿）；编辑页 AppBar 同色 `AppPalette.c(0xB33E8E6D)`。
- 笔记浏览页：返回键与右上图标热区均 `48×48`（`leadingWidth: 48` + 图标 `BoxConstraints.tightFor(48,48)`）。
- 右上「更多」图标为**横三点** `AppIcons.moreH`（v4.9.28 从竖三点改来）。

---

## 3. 交互逻辑与动效规范

### 3.1 全局动效 `AppMotion`（`lib/utils/app_motion.dart`）

- 页面转场时长 `300ms`，曲线 `easeOutCubic`，入场/退场对称。
- `AppMotion.slide(page)`：新页从右推入（Offset 1→0），旧页向左让出 25%（0→-0.25），避免来回晃眼。**新增页面转场一律用它，不要各自复制 `_slideRoute`**。
- 列表滚动超过 `600px` 才显示「回顶」按钮。

### 3.2 按压回弹 `Pressable`（`lib/widgets/pressable.dart`）

- 按下缩到 **90%**（90ms 干脆），松手弹簧回弹 **1.00→1.02→1.00**（420ms）。
- 用 `Transform.scale` 纯绘制变换（不参与布局/命中），`Listener` 原始指针事件（不抢 InkWell/GestureDetector 的手势竞技场）。
- 必须用 `AnimationController.unbounded`，否则弹簧过冲被 `[0,1]` 钳掉。
- 已有指针监听的卡片（资产卡拖拽）用 `external: true` + `PressableHandle` 由外层驱动，避免叠加 Listener。

### 3.3 震动反馈 `Haptics`（`lib/utils/haptics.dart`）

- 单一来源：Android 直驱原生 Vibrator（MethodChannel `vector_diary/haptic`），失败才退回 `HapticFeedback`；**绝不两路同发**（会互相取消）。
- 分级：`light()` 12ms（选择/开关/切换）、`medium()` 24ms（删除确认/保存成功/长按菜单）、`tick()` 8ms（边界/翻页）；`mediumNow()` / `lightNow()` 同步触发，用于"弹菜单前先震"。
- 节流：最小间隔 40ms，丢弃密集重复请求；`throttleEnabled` 测试可关。
- **全局总开关 `Haptics.enabled`**：设置页「震动」Switch（与深色模式同款），关闭后所有点位静默；开启瞬间震一次确认。持久化到 `app_settings.json`。

### 3.4 底部弹层 `AppSheet`（`lib/utils/app_sheet.dart`）

- 全站统一入口，**不要再用散装 `showModalBottomSheet`**（v4.9.28 已迁移全站 21 处）。
- 圆角 `24`，顶部拖拽手柄 `36×4`（`AppSheet.handle(context)`），遮罩 `0x66000000`，`enableDrag: true`。
- 内容区**不要自己画顶部手柄与留白**，本方法已统一提供。
- 确认/取消按钮：统一为**右下角文字按钮**，「完成/确定」主色强调、「取消」灰色次级，**无底纹色块、无描边**（v4.9.29/30）。

### 3.5 其它关键交互

| 交互 | 实现 | 位置 |
|---|---|---|
| 双击顶栏回顶 | `GestureDetector.onDoubleTap` → `_scrollToTop()` | home |
| 下拉刷新 | `RefreshIndicator` | home / asset / countdown / item_list |
| 长按卡片菜单 | 长按 → Haptics.mediumNow() → `AppSheet` 动作菜单；含编辑/删除/分享等 | 各主页 |
| 笔记页「更多」 | `showMenu` 从按钮处弹下拉（编辑/删除/分享），弹层外截图截不到 | note_view |
| 单选输入回车链 | `textInputAction: next` + `onSubmitted → 下一 FocusNode.requestFocus()`；末项 `done` 收键盘 | 各编辑页 |
| 搜索高亮 | `RichNoteText` 接收 `searchQuery`，命中浅黄底 `0xFFFFF0B3` + 深墨字 `0xFF24382F`（深色可见） | note_view / search |
| 回收站 | 7 天保留；还原/删除均二次确认；支持选择模式多选、全部还原 | trash |
| 删除确认 | 部分危险操作二次确认弹窗（`showDialog<bool>`） | trash 等 |
| 未保存守卫 | 退出编辑页时提示是否丢弃（`unsaved_guard.dart`） | 各编辑页 |
| 空态 | `empty_state.dart`：图标 + 说明文字（尚未加行动按钮，属待优化项） | 通用 |

### 3.6 主题与显示

- 设置页分组：**外观**（深色模式 / 跟随系统 / 字体）、**反馈**（震动）、**数据**（导出/导入）、**活动**（兑换码）。
- 字体：可切换，设置持久化，切换全站即时生效。
- 每日首次发布笔记 +20 积分（`RewardService.dailyWritePoints`）。

---

## 4. 发版标准化流程（每次改动必须完整走完）

1. **改代码**，同步两处版本号：
   - `pubspec.yaml` → `version: x.y.z+build`（build 每次 +1）
   - `lib/utils/app_version.dart` → `displayVersion = 'Vx.y.z'`
2. **静态分析**：`flutter --no-version-check analyze`，要求 **0 error / 0 warning**（info 为历史基线，允许）。
3. **全量测试**：`flutter --no-version-check test`，要求全绿（当前 442 项）。
   - 新增改动必须配套回归测试（历史命名 `test/vXXYY_features_test.dart`）。
4. **巡检截图目检**（可选但建议）：写临时 `test/_inspect_*_test.dart`，用 `--dart-define=TARGET=xxx` 出图，`ViewImage` 目检浅/深两态。
   - 注意：`showMenu` 弹层在 `RepaintBoundary` 外截不到；CJK 字体需 `runAsync` 加载；`pumpAndSettle` 遇粒子动画会卡，用有限帧 pump；搜索页截图常有花屏（已知工具问题），靠 widget 测试覆盖。
5. **构建**：`ANDROID_SDK_ROOT=/opt/android-sdk flutter build apk --release`。
6. **复制 + 核验**：`cp build/app/outputs/flutter-apk/app-release.apk /workspace/ArrowDiary_V.x.y.z.apk`；用 `/opt/android-sdk/build-tools/33.0.0/aapt dump badging` 核验 versionCode/versionName。
7. **提交推送**：`git add -A && git commit -m "vX.Y.Z: ..." && git push origin main`（网络常波动，带 3~4 次重试循环）。
8. **Release**：
   ```bash
   GH_TOKEN=$(git remote get-url origin | sed -E 's#.*x-access-token:([^@]+)@.*#\1#') \
     gh release create V.x.y.z /workspace/ArrowDiary_V.x.y.z.apk \
     --title "阿尤日记 V.x.y.z" --notes "..."
   ```
   随后 `gh release view ... --json assets` 核验附件 `state=uploaded`。
9. **present_files**：呈现 APK + Release 链接。

> APK 命名固定 `ArrowDiary_V.x.y.z.apk`；Release tag 固定 `V.x.y.z`。

---

## 5. 版本历史（v4.9.15 → v4.9.32）

| 版本 | 关键变更 |
|---|---|
| v4.9.15 | 笔记分享长图（底部信息条：Logo/应用名/日期时间地点） |
| v4.9.16 | 分享图信息条上移内容区正下方、去多余白区 |
| v4.9.17 | 兑换码体系 + 积分 + 每日发布 +20；长按菜单加分享 |
| v4.9.18 | 身份牌体系（普通/内测/VIP/诞生日）、每 ID 每码限兑一次 |
| v4.9.19 | 积分商城 VIP 日卡（200 积分 / 24h / 限 30） |
| v4.9.20 | 待办回车续行；回收站选择模式；积分商城整卡兑换 |
| v4.9.21 | 待办输入法回车修复；资产看板图标对齐；个人信息白卡化 |
| v4.9.22 | 回收站抽屉改长按菜单；身份牌有效期显示；用户 ID/注册日/使用时间 |
| v4.9.23 | 用户 ID 改 10001 起顺序号；VIP 时效累加；VIP 周卡；终身 VIP 铭牌 |
| v4.9.24 | **深色模式**：AppPalette 语义色板、双主题、84 处白卡映射、顶栏深墨绿 |
| v4.9.25 | 修复深色切换需滑侧栏才全量刷新（AppThemeScope）；多处深色细节 |
| v4.9.26 | 设置页「字体」并入「外观」；事件/物品编辑页选项改行式（标签+值+箭头） |
| v4.9.27 | 输入回车跳转链；双击顶栏回顶；搜索命中逐条跳转+深色；笔记「更多」菜单；注册日格式化；VIP 日卡口径「1天」 |
| v4.9.28 | 搜索页去命中条/选框；更多改横三点；图片全屏查看；全站 AppSheet；震动总开关 |
| v4.9.29 | 弹层按钮去底纹收右下角；排序选项去描边；图片查看改纯淡入 |
| v4.9.30 | 确认按钮去色块改文字；回收站提示语吸附底部；移除图片预览入口 |
| v4.9.31 | 编辑页/浏览页顶栏颜色统一 70% 绿、高度统一 48 |
| v4.9.32 | **清理冗余代码**（8 项死代码 + 5 处双分号），纯整洁度维护 |

---

## 6. 商业化与激励体系现状

> 详细码表见 `docs/redeem_codes.md`。

- **用户 ID**：10001 起纯数字顺序号，`user_id_seq.json` 独立发号；旧 `AYO-xxxx` 自动迁移。
- **积分**：每日首发 +20；兑换码发放/扣减；商城消费。
- **身份牌**：普通（灰）/ 内测版（橙）/ VIP（红）/ 终身 VIP / 诞生日（绿）；个人信息页可切换佩戴。
- **VIP 时效道具**：日卡（+24h，限 30）/ 周卡（+7d，限 6），共用 `vipCardExpireAt`，**在原剩余时间上累加**；到期自动摘牌。限时 VIP 不进 `ownedBadges`。
- **兑换码**：`ayouriji`/`neice`/`vip`/`zhongshenvip` 限 1 次；`17381113325`（+1000）、`13031210237`（-1000）无限次。
- 核心实现：`lib/services/reward_service.dart`、`lib/models/user_profile.dart`、`lib/widgets/identity_badge.dart`。

---

## 7. 已定战略决策（跨会话必须延续）

### 7.1 上云方向（用户已拍板，尚未开工）

1. **目标模式**：联网化；**云服务 VIP 收费，其它用户仍存本地**。
2. **数据主权铁律**：本地为根、云为可选镜像。免费=完整功能；付费=多设备同步便利；**欠费/断网绝不锁数据**，到期可一键导出全量回本地。
3. **双轨合并 VIP**：现有积分兑换的限时 VIP（日卡/周卡）自动赋予等时长云同步体验，作为付费试用装；荣誉徽章独立存在，不绑架功能。
4. **差异化定位**：数据主权 + 四模块打通；主标语"记日记、管物品、理资产、数日子——数据默认只在手机里，想上云再付费"。
5. **合规红线**：Google Play 数字商品必须走 Play Billing、iOS 必须 IAP（否则拒审）；日记属敏感个人信息，上云需隐私政策/用户协议/加密说明/备案。
6. **架构建议**：一期整包上传+时间戳仲裁（复用 `BackupService.mergeBackup` 按 id 合并逻辑），二期按 id 增量；老用户本地 uid 用绑定码认领到云端；WiFi+变更后 30s 合并上传。

### 7.2 差异化卖点（对外口径）

- 四模块打通（日记/物品/资产/倒计时），`@物品引用` 跨模块联动 —— 结构性护城河。
- 免费用户拿到完整产品，不是阉割版 —— 订阅制泛滥下的稀缺承诺。
- 数据主权可分叉、可视化加密封条卡、手工级视觉一致性。

---

## 8. 技术债与待办

| 组 | 状态 | 内容 |
|---|---|---|
| A 组死代码 | ✅ v4.9.32 已清 | design_tokens 死文件、_StripeBandPainter、_closeToolbar、_decoration、两处 _openSearch、_saving、_hlNames/_currentMark、_fitSize |
| B 组笔误 | ✅ v4.9.32 已清 | 5 处 `;;` 双分号 |
| **C 组冗余参数** | ⬜ 未动 | `UserProfile.validityLabel` 的 `owned`（注释自认兼容参数，函数体未用，改签名需连带改 10+ 调用/测试）；`_DashedRRectPainter` 的 dashWidth/dashGap/strokeWidth（全用默认值） |
| **E 组 lint** | ⬜ 未动 | 约 117 条 info：`prefer_const_constructors`、未用 import、`use_build_context_synchronously` 等，仅整洁度 |
| 兼容逻辑 | ✅ v4.9.33 精简 | `diary_entry` 的 mood / weather 已彻底删除；旧备份含这两个字段时 `fromJson` 不再读取，自动无视、不报错、不回写 |
| 兼容逻辑 | ⛔ 勿删 | `countdown_event.loop`、`app_settings` 旧开关/主题缺字段回落、`asset_storage` 理财→基金迁移、`trash_storage` 旧档兜底、`todo_text` 旧 `[ ]/[x]` 格式 —— 老用户数据升级路径 |

### 产品待优化（灵感池，未立项）

可撤销删除（Toast+撤销，替代反复确认）、列表左滑操作、`empty_state` 空态加行动按钮、滚动时顶栏渐显、长按预览气泡、编辑自动留草稿、触感分级语义化。

---

## 9. 交接检查清单（新会话开场）

- [ ] 读本文件 + `docs/redeem_codes.md`
- [ ] `git status` 确认干净；`git log -1` 确认版本
- [ ] 如需改代码：analyze 0/0 → 全量测试 → （可选）截图目检 → 构建 → commit/push → Release → present_files
- [ ] 版本号两处同步（pubspec + app_version.dart），build +1
- [ ] 涉及 UI：遵守 §2 色板/圆角/字号/边距/顶栏，动效走 AppMotion/AppSheet/Pressable/Haptics
- [ ] 涉及上云：遵守 §7 数据主权铁律与双轨 VIP 方案
