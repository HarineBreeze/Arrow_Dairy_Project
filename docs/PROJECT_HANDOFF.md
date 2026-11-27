# 阿尤日记 · 项目交接与推进指南

> 截至 **v5.0.8**（versionCode 166，全量 **652** 项测试通过）。
> v5.0.2 / v5.0.3 由电脑端发布：隐私锁 4 步向导（`app_lock_setup_wizard.dart`）、关闭验证、深色默认关闭、通用密码向导 `pin_setup_wizard.dart`（3 步资产 / 2 步笔记）、多页 UI 优化。
> **v5.0.4**（本会话叠加）：① 深色模式下向导「未选中项」由亮灰白改为同主题暗底纹（`0xFFF5F8F6` 登记进 darkMap → `0xFF233A2F`，随主题色变）；② 修改资产密码在验证身份后复用通用 3 步向导（设置密码→确认密码→设置密保），与「开启加密访问」样式/流程完全一致。版本号顺延至 5.0.4 是因为远程已有 v5.0.3 tag。
> **v5.0.5**：① 笔记预览卡图片由 4:3 改为 **1:1** 方图（卡片高度与编辑页尺寸不变，文字区自然左移）；② **暖棕**主题从免费改为「灵感杂货店」**1400 点永久兑换**（商品名「主题·暖棕」），位置移到墨灰与藕粉之间；未解锁时置灰，点击提示「未解锁，赶紧前往灵感杂货店兑换吧～」。
> **v5.0.6**：① 主页置顶卡带去掉「置顶 x 篇」小标题，卡片上移且上下留白相等（`pinned-rail` top/bottom 各 6，配合列表 paddingTop 8 = 14）；② 笔记数据栏 / 物品数据栏上下留白 14 → 10，整条高度收窄；③ 杂货店身份商品「诞生日-身份」改名「身份·诞生日」（与「主题·暖棕」同格式）。
> 本文件是跨设备 / 跨会话接手的**唯一入口**：新会话先完整读它，即可无缝续接，无需重新口述背景。
> 关键信息均以源码为准，文中标注对应文件或符号，便于核对。改代码前务必读完 §2 规范与 §4 发版流程。

---

## 0. 项目速览

| 项 | 值 |
|---|---|
| 名称 / 包名 | 阿尤日记（AyoDiray）/ `com.Ayo.diary_app`（v4.9.50 由 `com.shiguang.diary_app` 改名；Flutter 包名 `ayodiray`） |
| 仓库 | `HarineBreeze/Arrow_Dairy_Project`（main 分支） |
| 技术栈 | Flutter 3（Dart），**无任何网络依赖**；纯本地 JSON 存储 |
| 核心依赖 | `path_provider`、`image_picker`、`file_picker`、`share_plus`、`path`、`cupertino_icons` |
| 当前定位 | **离线单机版生活账本**：日记 + 物品 + 资产 + 倒计时四模块打通 |
| 商业模式现状 | 免费用户功能完整；**灵感兑换的 VIP 权益解锁若干增值项**（VIP 主题色 3 套、VIP 信纸 3 款、未来信件、事件到期提醒、回收站 30 天、置顶不限量），不锁核心记录功能 |
| 本地 / 构建目录 | 代码 `/workspace/diary_app`；APK 交付 `/workspace/ArrowDiary_V.x.y.z.apk` |
| Android SDK | `ANDROID_SDK_ROOT=/opt/android-sdk`（环境变量默认缺失，构建时须显式指定） |

---

## 1. 目录与架构地图

```
lib/
├─ main.dart                    入口：DiaryApp 主题订阅（themeModeNotifier / 系统亮度）、路由表
├─ models/                      diary_entry / item / asset / countdown_event / user_profile
├─ services/                    各 *_storage（本地 JSON 读写）、app_settings、backup_service、
│                                reward_service（灵感/兑换码/杂货店/VIP）、各类 *_reminder 通知
├─ screens/                     19 个页面（见下）
├─ widgets/                     通用组件（pressable / app_icons / save_bar / stationery_paper 等）
├─ theme/                       app_palette（语义色板 + 主题色）、app_theme_scope（明暗即时重建）
└─ utils/                       app_motion / app_sheet / app_toast / haptics / stationery /
                                writing_prompts / usable_days / app_version 等
```

**19 个页面**：home（日记主页）、edit（笔记编辑）、note_view（笔记浏览）、item_list / item_edit（物品）、asset_screen / asset_edit（资产）、countdown_screen / countdown_edit（事件）、global_search、trash（回收站）、points_shop（灵感杂货店）、profile_edit（档案）、settings、side_menu（侧边栏）、font_picker、image_crop、usable_days_settings_sheet、app_lock_screen（隐私锁设置/解锁，v5.0.1）。

**本地存储文件**（均在 `getApplicationDocumentsDirectory()` 下）：

| 文件 | 内容 |
|---|---|
| `diaries.json` / `items.json` / `assets.json` / `countdowns.json` | 四类主数据 |
| `trash.json` | 回收站（普通 7 天 / 权益身份 30 天，见 §6.3） |
| `user_profile.json` | 档案：昵称/性别/生日/头像/灵感/徽章/VIP 时效/userId/注册日 |
| `user_id_seq.json` | 用户 ID 顺序发号（与档案分离，删档不回退） |
| `asset_pin.json` | 资产页密码 |
| `app_settings.json` | 主题模式 `themeMode` / 字体 / 震动总开关 / 主题色 `accentId` / 可使用天数参数 |

> 资产密码用 `b ^ 0x5A` 逐字节混淆后存储（`asset_storage.dart`），非强加密，仅为防止误看。

---

## 2. UI 与代码规范（改代码前必须遵守）

### 2.1 色彩体系 —— 语义色板 `AppPalette`（`lib/theme/app_palette.dart`）

**铁律 1：代码里不直接写深色判断，一律走 `AppPalette.c(argb)` / `.surface` / `.topBar` / `.accentColor`。**
**铁律 2：不写死绿色主色字面量，凡主色相关一律走 `AppPalette.c(0xFF3E8E6D)` 或 `.accentColor`，让主题色切换能全局生效。**

- `c(int argb)`：**浅色竹青模式原样返回**传入色值（保证既有精确颜色断言零回归）；深色模式查 `darkMap` 转换；主题色切换时把「绿色家族」色值重映射到当前 `accent`。未登记颜色保持原值。
- `surface` = `c(0xFFFFFFFF)`：白色卡片/容器/弹窗背景。
- `topBar`：实心顶栏背景，随主题色/明暗取色。
- `accentColor` = `Color(0xFF000000 | accent.rgb)`：当前主题主色（按钮、高亮字、置顶边框、图标色）。
- `toastBg`：AppToast 背景，竹青返回原深墨值，其它主题返回各自深色顶栏色。
- 半透明顶栏色块 `0xB33E8E6D`（70% 绿）是各主页顶栏标准色。
- `darkMap` **只登记中性色**（页面底/卡片底/文字/边框/顶栏色块）；品牌色与语义色不登记、跨主题保持原值。
- 顶栏/主色块上的前景文字与图标**始终 `Colors.white`**，不参与映射。
- 主题模式三态 `AppThemeMode { system, light, dark }`，持久化到 `app_settings.json` 的 `themeMode`。
- 深浅切换靠 `AppThemeScope`（InheritedWidget）：所有页面 build 订阅，即时全量重建且保留 State / 导航栈。

### 2.2 主题色体系（v4.9.43 起，`AccentStyle` / `AccentCatalog`）

- 6 套主题色（**v5.0.5 顺序**）：`bamboo` 竹青（默认）/ `ink` 墨灰（免费）/ `amber` 暖棕（**杂货店 1400 点永久兑换**）/ `lotus` 藕粉 / `ocean` 雾蓝 / `violet` 霞紫（VIP 3 套）。
  > v4.9.50 起暖棕 / 墨灰由 VIP 改为免费；v5.0.0 新增霞紫（VIP）；**v5.0.5 暖棕取消免费**，移到墨灰与藕粉之间，改为 `needsShop: true`，由 `RewardService.buyThemeAccent` 解锁并写入 `UserProfile.ownedAccents`。
- 每套 `AccentStyle` 提供浅色 `rgb / tintRgb / pageRgb` 与深色 `darkTop / darkTint / darkPage / darkSurface / darkTintBg`。**竹青全套与原写死值逐字节一致**，保证零回归。
- **新增主题色**：只需在 `AccentCatalog.styles` 末尾加一条 `AccentStyle`（填齐 8 个色值 + `vip` / `needsShop` 判定），设置页抽屉会遍历 `styles` 自动接入、自动加 VIP 角标；无需改 `AppPalette.c()` 的映射表（它按 `accent` 当前值动态重映射）。
- 切换主题色时 `AppPalette.c()` 会把整族颜色重映射：按钮、标签底、置顶边框、页面底、卡片底、顶栏、高亮字一起换色。
- 设置页「主题色」抽屉：VIP 过期后保留已设主题色、可切回竹青，但不可再选其它 VIP 色；**兑换型（暖棕）未解锁时整行置灰（opacity 0.45），点击提示「未解锁，赶紧前往灵感杂货店兑换吧～」**；当前正在使用的暖棕视为已解锁（避免老用户升级后被锁死）（`settings_screen.dart:_pickAccent` / `_accentRow`）。
- **新增任何页面背景/卡片底/顶栏取色，都必须走主题色字段，不要写死中性色**——否则会出现"别的页面都换色、就这页还是淡绿"的 bug（v4.9.44/45/46 连修三轮的问题）。

### 2.3 圆角 / 字号 / 边距档位

| 类别 | 常用档位 |
|---|---|
| 圆角 | **16**（卡片/弹窗/抽屉，最多）、**12**（输入框/按钮/内层容器）、**8**（小卡/工具栏项）、2（细分条/进度条）、999（胶囊/头像） |
| 字号 | **15 / 13**（正文 / 辅助，两大主力）、11（小标签/角标）、17（卡片标题/设置项）、22（页面标题）、32（资产大数字） |
| 边距 | **16、20、12、14、8、10、24、6、4**；页面左右安全边距 16，卡片内边距 14 横 / 12~16 纵 |

> 不要造新档位或半像素字号（11.5/13.5 等）。历史例外值 14、19（滚轮）、12、9.5（密码遮罩）、9/8/7（极小角标）仅限既有代码。

### 2.4 顶栏高度（v4.9.31 统一）

- 所有主页与对应编辑页 / 浏览页顶栏高度统一 `48`（`toolbarHeight: 48`）。
- 各主页顶栏色 `0xB33E8E6D`（70% 绿，走 `AppPalette.c()`）；编辑页 AppBar 同色。
- 笔记浏览页：返回键与右上图标热区均 `48×48`（`leadingWidth: 48` + `BoxConstraints.tightFor(48,48)`）。
- 右上「更多」为**横三点** `AppIcons.moreH`。

---

## 3. 交互逻辑与动效规范

### 3.1 全局动效 `AppMotion`（`lib/utils/app_motion.dart`）
- 页面转场 `300ms` / `easeOutCubic`。`AppMotion.slide(page)`：新页从右推入，旧页左让 25%。**新增页面转场一律用它**。

### 3.2 按压回弹 `Pressable`（`lib/widgets/pressable.dart`）
- 按下缩到 90%（90ms），松手弹簧 1.00→1.02→1.00（420ms）。`Transform.scale` + `Listener` 原始指针，不抢手势竞技场。必须用 `AnimationController.unbounded`。

### 3.3 震动反馈 `Haptics`（`lib/utils/haptics.dart`）
- Android 直驱原生 Vibrator（MethodChannel `vector_diary/haptic`），失败才退回 `HapticFeedback`；**绝不两路同发**。
- 分级：`light()` / `medium()` / `tick()`（8ms），`mediumNow()` / `lightNow()` 同步触发。节流最小间隔 40ms。
- 全局总开关 `Haptics.enabled`（设置页「震动」Switch），关闭后所有点位静默；持久化 `app_settings.json`。

### 3.4 底部弹层 `AppSheet`（`lib/utils/app_sheet.dart`）
- 全站统一入口，**不要再用散装 `showModalBottomSheet`**。圆角 24，手柄 36×4，遮罩 `0x66000000`，可拖拽。
- 内容区不要自己画顶部手柄与留白。确认/取消按钮统一右下角文字按钮（无底纹、无描边）。
- **抽屉标题规则（多轮迭代结论）**：编辑页/选择类抽屉普遍**不要标题**——身份抽屉「选择身份」、性别抽屉「选择性别」、可使用天数「可使用天数 参数」、事件类型/重复规则/到期提醒、物品/资产类型与状态、主题色抽屉的标题与提示语，均已移除。

### 3.5 其它关键交互

| 交互 | 实现 | 位置 |
|---|---|---|
| 双击顶栏回顶 | `GestureDetector.onDoubleTap` → `_scrollToTop()` | home |
| 下拉刷新 | `RefreshIndicator` | home / asset / countdown / item_list |
| 长按卡片菜单 | 长按 → `Haptics.mediumNow()` → `AppSheet` 动作菜单 | 各主页 |
| 笔记页「更多」 | `showMenu` 从按钮处弹下拉（编辑/删除/分享） | note_view |
| 单选输入回车链 | `next` + `onSubmitted → 下一 FocusNode`；末项 `done` 收键盘 | 各编辑页 |
| 搜索高亮 | `RichNoteText` + `searchQuery`，命中浅黄底 + 深墨字（深色可见） | note_view / search |
| 回收站 | 普通 7 天 / VIP 30 天；还原/删除二次确认；选择模式多选、全部还原 | trash |
| 未保存守卫 | 退出编辑页提示丢弃（`unsaved_guard.dart`） | 各编辑页 |
| 内容信息吸底取消 | 笔记浏览页时间/地点、回收站提示语均置于**滚动内容最底部**（滑到底才可见，非固定吸附视口） | note_view / trash（v4.9.48） |
| 空态 | `empty_state.dart`：图标 + 说明文字（尚无行动按钮，待优化） | 通用 |

### 3.6 设置页结构（v5.0.1 现状）

分组（自上而下）：**外观** → **隐私**（v5.0.1 新增）→ **数据备份**（导出/导入）→ **活动**（兑换码）→ **反馈**（震动 Switch）。
「外观」卡三行：深色模式 / 字体 / 主题色。其中：

- **深色模式**：右箭头，点击开抽屉，内含**两个震动同款 Switch**——「跟随系统」与「深色模式」（key：`theme-follow-system` / `theme-dark-mode`）。跟随系统开启时深色开关置灰禁用；原「已开启/已关闭」二行已合并为单一「深色模式」开关。
- **字体**：进入 `FontPickerScreen`。
- **主题色**：进抽屉选 6 套主题色（竹青 / 墨灰免费、暖棕需杂货店兑换、藕粉 / 雾蓝 / 霞紫为 VIP，限制见 §2.2）。

**隐私锁（v5.0.1）**：「隐私锁」Switch（key `privacy_lock_switch`），仅 **冷启动** 校验一次（解锁后本次会话不再验证）。
- 首次开启 → `AppLockSetupDialog`：选「密码」或「九宫格手势」，两次输入/绘制 + **密保问题与答案必填**；点「取消」→ 返回并保持关闭（不写凭证）。
- 关闭 → 直接删除锁文件（`AppLockStorage.clearLock()`），无需验证。
- 存储 `services/app_lock_storage.dart`（独立 `app_lock.json`，混淆存储，与资产密码 `asset_pin.json` 互不干扰）；手势组件 `widgets/pattern_lock_view.dart`（至少 4 点，`patternToString`/`isValidPattern`）。
- 冷启动门禁在 `main.dart` 的 `_LockGate`：有锁先显示 `AppLockUnlockScreen`（支持密码/手势验证 + 忘记密码走密保重置），成功后切 `DiaryApp`。
- 测试注入：`SettingsScreen(lockStateOverride: bool)` 避免 widget 测试走真实 IO。

**笔记主页数据栏（v5.0.1）**：位于「全部/按日/按月/按年」标签栏下方（`_buildStatsBar`），样式同物品页数据栏（上绿加粗值 / 下灰标签 + 竖分隔线）。
- 三栏：**总篇数**（`_entries.length`）、**总字数**（全部 `content.length` 之和）、**连续记录 / 最长记录**。
- 统计算法在 `utils/note_stats.dart:NoteStats.compute()`（可注入 `now` 便于测试）：按 `publishDate` 归集自然日、去重；今天或昨天有记录→当前连续（标题「连续记录」+`X天`），否则断更→显示历史最长段（标题「最长记录」+`X天`）。统计全量笔记，不受筛选/搜索影响。

---

## 4. 发版标准化流程（每次改动必须完整走完）

> 固定 SOP，顺序不可跳过。APK 命名 `ArrowDiary_V.x.y.z.apk`（如 `ArrowDiary_V.5.0.7.apk`），Release tag `v5.0.7`（小写 v 前缀 + 版本数字，无大写 V，见历史 release）。
> 推送前必须先 `git fetch origin`：电脑端会独立发版，本地可能落后（如本会话 v5.0.1 → 远程已有 v5.0.2/v5.0.3），须 rebase 到远程最新之上再叠加改动，切勿强推覆盖。

1. **改代码** + 同步两处版本号（各 +1 构建号）：
   - `pubspec.yaml` → `version: x.y.z+BUILD`
   - `lib/utils/app_version.dart` → `displayVersion = 'Vx.y.z'`
2. **静态分析**：`flutter analyze`，要求 0 error / 0 warning（约 127 条 info 为历史基线，允许）。
3. **全量测试**：`flutter test`，要求全绿（当前 **652** 项）。新增改动必须配套回归测试，命名 `test/vXXYY_features_test.dart`。
   - 测试偶发：全量并行时 trash / 手势类测试偶有 1 项时序失败，重跑一遍通常即过；不要因此反复改测试。
   - 含真实文件 IO 的页面（TrashScreen 等）测试要用 `runAsync` 让 IO 完成（参考 `_settleWithIo`），否则 `_loading` 未结束、内容未渲染。
4. **构建**：
   ```bash
   export JAVA_HOME=/opt/jdk17            # 关键：默认 sdkman java 是 20，Gradle 7.4 会报 Unsupported class file major version 64
   export PATH="$JAVA_HOME/bin:$PATH"
   export ANDROID_SDK_ROOT=/opt/android-sdk
   flutter build apk --release
   ```
   Kotlin 版本冲突 warning（`incompatible version of Kotlin ... expected 1.5.1`）是历史遗留，非致命，可忽略。

   > **签名对齐（重要）**：release 构建已接入与电脑端 v4.9.50 相同的 keystore，产出包名可直接覆盖安装、不丢数据。
   > - 密钥材料：`android/app/ayodiary_debug.keystore` + `android/key.properties`（storePassword/keyPassword 均 `android`，alias `androiddebugkey`，PKCS12）。**两者被 `.gitignore` 排除，绝不提交**（本仓库为 public，外传 keystore 任何人都能签出可覆盖包）。
   > - 证书指纹：SHA-256 `75FFB3904BA166E6A8EA19B85B15D0F5B9B451DB68B38A62446D0FE2D7581C01` / SHA-1 `7898EF177C59169C0618E7025DEEA4CB84BE54B6`（`CN=Android Debug`）。
   > - `android/app/build.gradle` 中 `hasReleaseKeystore` 为 true 时用 `signingConfigs.release`，否则回退 `signingConfigs.debug`（保证无密钥环境仍可构建）。
   > - 换环境/换机器时须重新放入这两个文件，否则签名变回沙箱默认 debug key（SHA1 `fdb4c8ad…`）会再次导致覆盖安装失败。
   > - 核验产出签名：`apksigner verify --print-certs app-release.apk`，SHA-256 digest 应为上面那串。
5. **复制 + aapt 核验**：`cp build/app/outputs/flutter-apk/app-release.apk /workspace/ArrowDiary_V.x.y.z.apk`；用 aapt dump badging 核验 `versionCode` / `versionName` 与 pubspec 一致。
6. **提交推送**：
   ```bash
   git add -A
   git commit -m "feat(vx.y.z): ..."
   git -c http.version=HTTP/1.1 push origin main   # 默认 HTTP/2 常遇 GnuTLS/TLS 中断
   ```
   推送后用 `gh api repos/HarineBreeze/Arrow_Dairy_Project/commits/main --jq .sha` 复核远程 HEAD == 本地 HEAD。
7. **Release**（gh 未登录，token 从 remote URL 提取）：
   ```bash
   TOKEN=$(git remote get-url origin | sed -E 's#https://x-access-token:([^@]+)@.*#\1#')
   GH_TOKEN="$TOKEN" gh release create vX.Y.Z /workspace/ArrowDiary_V.X.Y.Z.apk \
     --repo HarineBreeze/Arrow_Dairy_Project --title "vX.Y.Z" --notes "..."
   GH_TOKEN="$TOKEN" gh release view vX.Y.Z --repo HarineBreeze/Arrow_Dairy_Project \
     --json tagName,name,assets
   ```
8. **附件核验**：确认 assets 中 APK `state=uploaded`、size 与本地一致。下载复核可能因 GitHub 网络超时中断；更可靠的是比对本地 `sha256sum` 与 release JSON 里的 `digest`（`sha256:...`）。
9. **present_files**：呈现 APK。

---

## 5. 版本历史（v4.9.33 → v5.0.0）

| 版本 | 关键变更 |
|---|---|
| v4.9.33 | 删除 mood/weather 废弃字段，导入时自动无视旧备份残留字段 |
| v4.9.34 | 新增 6 张抹茶绿 UI 插画资源（**后续 v4.9.35 已移除**） |
| v4.9.35 | 移除 6 张 UI 插画；全局文案改版（积分→灵感 / 身份牌→身份 / 个人信息→档案 / 灵感商城→灵感杂货店）；档案页新增生日轮盘；FAB 改编辑图标 |
| v4.9.36 | 单位「分」改「点」；首次新增事件/物品/资产各 +20 灵感；提醒时间加 VIP 门槛与角标；新增 `novip` 清除会员码 |
| v4.9.37 | **今日一句 100 条**（按日期确定性）+ **未来信件**（VIP 专属 / 封存 / 到期提醒 / 通知） |
| v4.9.38 | 浏览页更多图标左移放大；VIP 未解锁文案精简；未来信件预览标题 |
| v4.9.39 | 置顶数量上限（VIP 不限）；**回收站 VIP 30 天**；保存后定位；编辑页 UI 微调 |
| v4.9.40 | **6 套 VIP 信纸实装**；修复资产拖拽置顶失效 bug |
| v4.9.41 | 信纸精简（4 款全 VIP、改名抹茶横纹、去副标题图标、图文分板块、分享保留信纸） |
| v4.9.42 | 移除抹茶横纹；修复分享 logo 丢失；编辑页信纸所见即所得；星夜页面压暗 |
| v4.9.43 | 事件当天「就是今天」；**主题色自定义（VIP）**；物品/资产/事件编辑页布局调整 |
| v4.9.44 | 主题色 VIP 牌移到标题后；134 处写死主色统一走 `AppPalette.c()` |
| v4.9.45 | 7 个页面背景跟随主题色；主题色抽屉去标题/提示语 |
| v4.9.46 | 深色模式主题色适配；移除多个抽屉标题 |
| v4.9.47 | 事件 VIP 角标移到「到期提醒」后；AppToast 主题色；档案/侧栏适配；深色模式改抽屉 |
| v4.9.48 | 可使用天数标题移除；深色模式双开关（跟随系统/深色模式）；笔记时间地点 + 回收站提示语移到底部；档案身份/性别抽屉去标题 |
| v4.9.49 | **写作里程碑庆祝特效**：日记达 7/30/100/200/365/500/1000 篇各 +20 灵感 + 粒子庆祝层；`claimedWriteMilestones` 判重与跨节点补发 |
| v4.9.50 | **品牌统一 AyoDiray**（包名 `com.Ayo.diary_app`）；兑换码不限次；顶栏标题字号统一 15；暖棕/墨灰改免费；修深色抽屉刷新 BUG；未来信件日期确认；杂货店禁用态；资金参数页按钮改版 |
| **v5.0.0** | 修复非 VIP 已设提醒后点击提示语丢失；回收站提示语改「超过时间的内容将彻底删除」；**新增紫色系主题「霞紫」（VIP）**；笔记编辑页「更多」文字加粗；签名对齐电脑端 keystore（本地不入库） |
| **v5.0.1** | 笔记主页「全部/按日/按月/按年」下方新增**数据栏**（总篇数 / 总字数 / 连续记录·最长记录，样式同物品页）；设置页新增**隐私锁**（密码 + 九宫格手势，密保必填，冷启动解锁） |
| **v5.0.2**（电脑端） | 隐私锁设置拆成 4 步向导（`app_lock_setup_wizard.dart`）；关闭隐私锁需先验证；关闭验证弹窗；弹窗主题化适配深色/5 套主题；Kotlin 升级 1.8.22 |
| **v5.0.3**（电脑端） | 加密访问改 3 步向导、笔记单篇密码 2 步向导（通用组件 `pin_setup_wizard.dart`）；深色默认关闭；版本号移至列表底；回收站空态/资产空态/设置抽屉等多页 UI 优化 |
| **v5.0.4** | 深色模式下向导**未选中项**由亮灰白改为**同主题暗底纹**（`0xFFF5F8F6`→darkMap `0xFF233A2F`，随主题色变化）；**修改资产密码**验证身份后复用通用 3 步向导（设置密码→确认密码→设置密保），与「开启加密访问」样式/流程一致；`_ChangePinDialog` 简化为纯身份验证 + `v5004_features_test.dart` |
| **v5.0.5** | 笔记预览卡图片由 4:3 改为 **1:1** 方图（卡片高度 / 编辑页尺寸不变，文字区自然左移）；**暖棕**主题从免费改为「灵感杂货店」**1400 点永久兑换**「主题·暖棕」，位置移到墨灰与藕粉之间；未解锁时置灰 + 引导提示；新增 `UserProfile.ownedAccents` + `v5005_features_test.dart` |
| **v5.0.6** | 置顶卡带移除「置顶 x 篇」标题，卡片顺位上移且上/下留白相等；笔记数据栏与物品数据栏高度收窄（竖向 14→10，分隔线 28/30→24）；杂货店身份名改「身份·诞生日」；`v5006_features_test.dart` |
| **v5.0.7** | 修复：物品编辑点「完成」卡在打勾界面不返回且未保存 —— `_save` 加 try/catch + 8s IO 超时，失败提示「保存失败，请重试」并复位按钮；价格校验拦 NaN/Infinity；`ItemStorage` 增加测试注入钩子；`item_edit_save_bug_test.dart` |
| **v5.0.8** | 资产看板新增**第三张桑基图卡「资产构成」**（`asset_sankey_card.dart`）：左侧 净资产+负债 → 右侧 金融资产+固定资产，带宽按金额守恒；金融=基金/黄金/股票，固定=银行储蓄/货币基金，负债=负数类型；净资产为负时自动降级不展示。`OverviewStack` 泛化为 N 卡轮换（左滑前进/右滑回绕）+ 指示圈随卡数 + 定高纳入第三卡 + 兼容旧两卡；`v5008_sankey_test.dart`。另附上架/上云规划文档（docs/上架清单_GO_LIVE_CHECKLIST.md、docs/权威上云规划.md） |

> v4.9.32 及更早（深色模式、AppSheet、震动总开关、用户 ID 顺序号等奠基改动）见 git log，此处不再展开。

---

## 6. 商业化与激励体系现状

> 详细码表见 `docs/redeem_codes.md`。

### 6.1 基础规则
- **用户 ID**：10001 起纯数字顺序号，`user_id_seq.json` 独立发号；旧 `AYO-xxxx` 自动迁移。
- **灵感**：每日首发 +20；首次新增事件/物品/资产各 +20；兑换码发放/扣减；杂货店消费。
- **身份**：普通 / 内测版 / VIP / 终身 VIP / 诞生日；档案页可切换佩戴。
- **VIP 时效道具**：日卡（+24h，限 30）/ 周卡（+7d，限 6），共用 `vipCardExpireAt` 累加；到期自动摘牌。限时 VIP 不进 `ownedBadges`。
- 核心实现：`lib/services/reward_service.dart`、`lib/models/user_profile.dart`、`lib/widgets/identity_badge.dart`。判定入口 `RewardService.hasVipPrivilege(profile)`。

### 6.2 VIP 解锁的功能点（免费用户看到入口但点击提示充值）
| 功能 | 位置 |
|---|---|
| 事件「到期提醒」 | `countdown_edit_screen.dart` |
| 未来信件 | `edit_screen.dart` |
| VIP 信纸 3 款（手账方格/星夜来信/牛皮旧信） | `edit_screen.dart` + `utils/stationery.dart` |
| VIP 主题色 3 套（藕粉/雾蓝/霞紫；暖棕/墨灰已免费） | `settings_screen.dart:_pickAccent` |
| 回收站保留 30 天（否则 7 天） | `services/trash_storage.dart` |
| 置顶不限量（否则有上限） | 主页逻辑 |

### 6.3 回收站天数规则
- 删除时若佩戴权益身份（内测版/VIP/终身VIP）且权益生效 → 保留 **30 天**，否则 **7 天**；保留期固化在条目上（`trash_storage.dart`）。旧记录缺省 7。
- 底部提示语文案为「超过时间的内容将彻底删除」（v5.0.0 由「超过7天…」改来）；v4.9.48 起该提示语置于内容最底部（随列表滚动），非固定吸附视口。
- 到期提醒 VIP 门槛：非 VIP 点击一律弹「到期提醒是VIP专属权益，请充值后再尝试～」，含 VIP 期间曾设过提醒时间的情况（v5.0.0 修复该分支静默 return 导致提示语丢失的 bug）；已设提醒值保持不变、不可改。

---

## 7. 已定战略决策（跨会话必须延续）

### 7.1 上云方向（用户已拍板，尚未开工）
1. **目标模式**：联网化；**云服务 VIP 收费，其它用户仍存本地**。
2. **数据主权铁律**：本地为根、云为可选镜像。免费=完整功能；付费=多设备同步便利；**欠费/断网绝不锁数据**，到期可一键导出全量回本地。
3. **双轨合并 VIP**：现有灵感兑换的限时 VIP 自动赋予等时长云同步体验作为试用装；荣誉徽章独立存在。
4. **差异化定位**：数据主权 + 四模块打通；主标语"记日记、管物品、理资产、数日子——数据默认只在手机里，想上云再付费"。
5. **合规红线**：Google Play 数字商品必须走 Play Billing、iOS 必须 IAP；日记属敏感档案，上云需隐私政策/备案。
6. **架构权威划分**：内容（日记等）本地权威；契约账本（userId/points/badge/VIP 时效等）与运营开关服务端权威；禁止整份 profile 互相覆盖，按字段粒度同步。详见 `docs/CLOUD_ARCHITECTURE.md`。

### 7.2 差异化卖点（对外口径）
- 四模块打通，`@物品引用` 跨模块联动 —— 结构性护城河。
- 免费用户拿到完整产品，不是阉割版 —— 订阅制泛滥下的稀缺承诺。
- 数据主权可分叉、手工级视觉一致性。

---

## 8. 技术债与待办

| 组 | 状态 | 内容 |
|---|---|---|
| A 组死代码 | ✅ v4.9.32 已清 | design_tokens 死文件、多处死代码 |
| B 组笔误 | ✅ v4.9.32 已清 | 5 处 `;;` 双分号 |
| C 组冗余参数 | ⬜ 未动 | `UserProfile.validityLabel` 的 `owned`（兼容参数，函数体未用，改签名需连带改 10+ 调用/测试）；`_DashedRRectPainter` 的多处默认参数 |
| E 组 lint | ⬜ 未动 | 约 127 条 info：`prefer_const_*`、未用 import、`use_build_context_synchronously` 等，仅整洁度 |
| 兼容逻辑 | ⛔ 勿删 | `countdown_event.loop`、`app_settings` 旧开关/主题缺字段回落、`asset_storage` 理财→基金迁移、`trash_storage` 旧档兜底、`todo_text` 旧 `[ ]/[x]` 格式、`stationery` 已下架 id 回退经典 —— 均为老用户数据升级路径 |

### 产品待优化（灵感池，未立项）
可撤销删除（Toast+撤销）、列表左滑操作、`empty_state` 加行动按钮、滚动时顶栏渐显、长按预览气泡、编辑自动留草稿、触感分级语义化。

---

## 9. 新会话交接检查清单

- [ ] 读本文件 + `docs/redeem_codes.md`（+ 若涉及上云再读 `docs/CLOUD_ARCHITECTURE.md`）
- [ ] `git fetch origin && git rebase origin/main`，确认未落后电脑端；`git log -1` 确认版本为 v5.0.7
- [ ] `grep '^version:' pubspec.yaml` 与 `app_version.dart` 版本号一致（当前 5.0.7+165 / V5.0.7）
- [ ] 改代码：analyze 0 error → 全量测试全绿（当前 652 项）→ 构建 → commit/push → Release → present_files
- [ ] 版本号两处同步 + 构建号 +1；新增改动配 `vXXYY_features_test.dart` 回归测试
- [ ] 涉及 UI：遵守 §2 色板（尤其主题色走 `AppPalette.c()`、抽屉去标题）、§3 动效组件
- [ ] 涉及 VIP：新增强功能按 §6.2 接入 `hasVipPrivilege` 门槛与提示文案
- [ ] 涉及上云：遵守 §7 数据主权铁律与字段权威划分，先改 `CLOUD_ARCHITECTURE.md` 再改代码

### 关键命令速查
```bash
export JAVA_HOME=/opt/jdk17 && export PATH="$JAVA_HOME/bin:$PATH"  # 构建必设，否则 Java20 破坏 Gradle7.4
export ANDROID_SDK_ROOT=/opt/android-sdk
flutter analyze
flutter test
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk /workspace/ArrowDiary_V.x.y.z.apk
git -c http.version=HTTP/1.1 push origin main
TOKEN=$(git remote get-url origin | sed -E 's#https://x-access-token:([^@]+)@.*#\1#'); echo ${#TOKEN}
```
