# 简课表 v1.5.0 —— 按用户产品反馈收敛（规划稿）

> 规划：Fable（本文件）。执行与评审：Opus 5.5 代理。
> 用户原话见文末附录。一句话目标：**这是一个产品，不是一个工程**——去掉没人看的东西、去掉术语、该自动的自动。

## 0. 硬约束（每个代理都要遵守）

- 工作区：`D:\desk\claudex\12\shu_schedule`（Flutter 3.47.4 / Dart 3.13.3，仅 Android，包名 `cn.shu.schedule`）。仓库根 `D:\desk\claudex\12`。
- 工具链前缀（Bash）：`source /d/desk/claudex/12/env.sh && export TEMP=D:/desk/claudex/12/.tmpbuild TMP=D:/desk/claudex/12/.tmpbuild && mkdir -p "$TEMP"`。C 盘快满了：临时文件一律放 D:，**不要删用户的任何应用数据**。
- **不要 `git commit` / `git add` / `git stash` / `git checkout --`**。工作区里有 88 个未提交文件（1.3.1 + 1.4.0 全部在里面），只能叠加修改。不要碰 `site/` 目录和根 `README.md` 的「给朋友装」一节（另一个会话的工作）。
- 不要碰 `keys/`、`key.properties`。
- **禁止 `flutter build apk --release --split-per-abi`**（会把 versionCode 写成 2008）。打 arm64 包用 `flutter build apk --release --target-platform android-arm64`。同一时间只跑一个 Gradle 构建。
- 日期运算只用 `ScheduleUtils.addDays` / `DateTime(y, m, d + n)` / `daysBetween`，不要 `add(Duration(days:))`（开发机有夏令时，用户在 UTC+8）。
- 模拟器 `emulator-5554`（AVD shu35，API 35，Launcher3）装着 v1.4.0 正式签名包，桌面放着两个小组件。升级装包用 `adb install -r`（同签名可覆盖安装，保留数据）；**不要 `adb uninstall`，不要改系统时间**。
- 换行符：`shu_schedule/android/app/build.gradle.kts` 与 `shu_schedule/README.md` 是 CRLF，改完用 `git diff --stat` 核对行数是否只有真实改动。
- 每个任务结束前：`flutter analyze` 零问题，`flutter test` 全绿（当前 613 个），把过程写到 `D:\desk\claudex\12\.tmpbuild\plan15\handoff-<任务字母>.md`（改了哪些文件、新增/删除了哪些测试、和本计划不一致的地方、遗留）。
- 文案统一白话、面向学生：不出现 `USE_EXACT_ALARM`、`SCHEDULE_EXACT_ALARM`、`Android 13`、`API`、`SDK`、`JSON`、`SHA-256`、`WebView`、`Cookie`、`jsDelivr`、`raw.githubusercontent` 这类词（README / NOTES / 代码注释不受此限）。「闹钟和提醒」「通知」是系统设置项的名字，可以用。课次量词一律「x 节课」。
- 测试里的「今天」一律注入，不依赖机器时间。

## 1. 决策（已拍板，不再讨论）

| # | 决策 |
|---|------|
| D1 | **删掉首次启动的隐私同意框**。不再有「同意 / 不同意并退出」，不再记录同意版本。「隐私说明」页保留，但内容换成第 3 节的白话短文。联网行为本身不变（启动后自动检查更新、顺带刷新假日表）。 |
| D2 | **（2026-10-08 下午修订，用户拍板）不要底部导航栏。** 课表铺满整屏作为首页；周视图头部右上角加一个齿轮图标按钮（key `week-settings`，放在「更多 ⋮」左边）→ `Navigator.push` 打开设置页（设置页是普通 Scaffold，自动带返回键）。「今日」页整个删除。点上课提醒通知 → `popUntil(isFirst)` 回到课表并回到本周。小组件点击不变。任务 A 已按「两个 tab」做完，由任务 A2 改成这个形态。 |
| D3 | **删掉长按图标的三个快捷方式**（shortcuts.xml、三个 drawable、strings、manifest 的 meta-data 和 intent-filter、MainActivity / NativeBridge 里的 action 机制）。 |
| D4 | **「添加桌面小组件」改成一个面板**：两种小组件（4×2 当日课程列表、2×1 下一节课）各带预览图和「添加到桌面」按钮；点了之后不论原生返回什么，面板都显示「没弹出确认框？看看怎么手动添加」，展开后按手机品牌给步骤。原生 `requestPinAppWidget` 传 successCallback，成功后 Toast「小组件已添加到桌面」。 |
| D5 | **删掉课表文件分享 / 导入**：课表管理右上角「选择文件」、每张课表菜单里的「分享此课表」、设置里的「从文件导入课表」、空状态第三个按钮「打开同学分享的文件」、`timetable_share.dart` 及其测试全部删除。 |
| D6 | **备份保留，但合并为一个入口**「备份与恢复」，副标题「换手机、重装前先导出一份」，点进去一个小面板：「导出备份文件」「从备份文件恢复」。保留合并 / 覆盖确认。 |
| D7 | **上课提醒页去术语**：删「权限」分组和那段技术说明；只在有问题时显示一张提示卡（没通知权限 → 「提醒发不出来 · 去允许通知」；Android 12 上「闹钟和提醒」被关 → 「提醒可能不准时 · 去系统设置允许「闹钟和提醒」」）。其余文案照第 0 节的白话要求过一遍。 |
| D8 | **开学日期自动化（2026-10-08 下午修订：校历做默认 + 一定问一次，两个都做）**：导入时 ① 教务识别到周次 → 直接用，不弹窗；② 否则学校校历（`holidays.json` 的 `schools[id].terms` ∪ `schools.json` 的 `termPresets`）里有覆盖「今天」的学期 → 作为默认值，预览页标注「按上海大学校历 · 9月14日开学 · 现在第 4 周」并可改，**并且在用户点「确认导入」时弹一次「现在是第几周？」面板，预选校历推出的周次**，标题写「按上海大学校历，现在是第 4 周，对吗？」，一点「确定」就过；③ 都没有 → 同一个面板但不预选、标题「现在是第几周？」，不选不能导入。**不再默认今天是第一周。** 「校正当前周次」要容易找到：周视图点「第 N 周」弹出的「选择周次」面板底部加一行「本周不是第 N 周？点这里校正」→ 同一个面板 → 改开学日期并 SnackBar「已把本周设为第 x 周」；学期设置页也加「按当前周次设置」。 |
| D9 | **校历建议一键套用**：一个底部面板「按 ×× 校历」，两段内容——开学日期不一致时的「改为 x月x日开学」、本学期尚未套用的放假 / 调休条目——一个按钮「一键套用」，一个「先不用」。触发时机：导入完成回到课表后；启动时（当前课表有未套用建议，且没对这一版假日表点过「先不用」）；假日表远程更新带来新建议时（SnackBar「假日表有更新」→「查看」打开面板）。原「套用节假日安排」页保留作为手动入口。 |
| D10 | 版本 `1.5.0+10`。 |

## 2. 任务（顺序执行：A → B → C 已完成；接下来 A2 → D → E）

> 任务 D 的上一位代理被中断前已经写了 `lib/core/term_resolver.dart`、`lib/features/settings/week_number_sheet.dart`，并改了 `holiday_presets.dart`（`termCovering`）和 `app_settings.dart`（`calendarSuggestionDismissed`）。接手的代理先读这四个文件，能用就用，不要推倒重来。

### 任务 A：壳层——删今日页、删隐私同意、删快捷方式

1. `lib/app.dart`：`_pages` 只剩 `WeekViewPage` 和 `SettingsPage`；`NavigationBar` 两个目的地；删 `_privacyReady`、`_pendingActions`、`onPrivacyDeclined`、`showPrivacyConsentDialog` 调用、`acceptPrivacy`；`_startupFlow` 变成：启动提醒 → 自动检查更新（顺带刷新假日表）→（任务 D 会在这里再加校历建议）。
2. 通知点击：`ReminderService.onTap` 与冷启动 `launchPayload` 都 → 切到课表 tab 并让周视图回到本周。给 `WeekViewPage` 一个可注入的「回到本周」触发器（例如 `ValueNotifier<int> jumpToCurrentWeekSignal` 或 `GlobalKey` + 公开方法），HomeShell 持有。续排通知 payload 里的「今日」措辞同步改。
3. 删除 `lib/features/timetable/today_page.dart` 与 `test/today_resume_test.dart`；`ScheduleUtils.nextCourseAt` 等工具若还被小组件快照 / 提醒用到就保留，注释里的「今日页」字样顺手改掉（`schedule_utils.dart`、`reminder_planner.dart`、`date_override_editor.dart`、`term_settings_page.dart`、`week_view_page.dart`、`widget_sync.dart`）。`TimetableEmptyState` 的 `today-empty` 用法随之消失。
4. 隐私同意：删 `showPrivacyConsentDialog`、`PrivacyPolicy.version` 相关逻辑、`AppSettings.privacyAcceptedVersion`（`fromJson` 对多出来的旧字段要能忽略——加一条测试：带 `privacyAcceptedVersion` 的旧 settings.json 能正常读出）。`test/privacy_consistency_test.dart`、`test/privacy_and_about_test.dart` 里同意框相关用例删掉，剩下的改成「隐私说明页能打开、包含三种联网场景的关键词（教务 / 版本 / 放假）」。`privacy_page.dart` 里的简易 Markdown 渲染保留（第 3 节的短文用得上）。
5. 快捷方式：删 `android/app/src/main/res/xml/shortcuts.xml`、`res/drawable/ic_shortcut_*.xml`、`strings.xml` 六条 `shortcut_*`、manifest 里的 `android.app.shortcuts` meta-data 和那组 `SHORTCUT_*` intent-filter；`MainActivity.kt` 删 `onNewIntent` 的 action 处理、`consumeLaunchAction`、`shortcutKey`、`getLaunchAction` 分支；`native_bridge.dart` 删 `actions` 流、`launchAction`、`_handleNativeCall`（保留 `isPinWidgetSupported`、`requestPinWidget`、`deviceInfo`，任务 C 会扩展）；`test/core/native_bridge_test.dart` 同步。
6. `week_view_page.dart` 空状态文案：标题保留，正文改为「可以从教务系统一键导入，也可以手动添加。」；`TimetableEmptyState` 去掉第三个按钮（`EmptyState` 组件的 tertiary 参数若无别处使用可一并删），`test/empty_state_entries_test.dart` 同步。
7. 验收：两 tab；点通知进课表且在本周（用 Fake 网关测试 `onTap` → index 0 + 信号触发）；无「今日」字样残留在用户可见文案里（`grep -rn 今日 lib` 只允许出现在注释和「明日预告」之外的合理语境，例如「今日 · 已结束」这种小组件状态词要确认是否仍存在并合理）；`flutter analyze` / `flutter test` 绿。

### 任务 A2（2026-10-08 下午新增）：去掉底部导航，设置改为右上角齿轮

前提：任务 A、B、C 已完成（见 `.tmpbuild/plan15/handoff-A/B/C.md`），当前是两个 tab 的形态。

1. `lib/app.dart`：`HomeShell.build` 直接返回 `WeekViewPage(...)`（不再有 `IndexedStack` / `NavigationBar` / `_index`）。`_showTimetableNow()` 改为 `Navigator.of(context).popUntil((r) => r.isFirst)` + `_showCurrentWeek.value++`（设置页、导入页等都在它上面）。类注释同步。
2. `week_view_page.dart` 头部标题行：在 `PopupMenuButton`（更多 ⋮）左边加 `IconButton(key: ValueKey('week-settings'), tooltip: '设置', icon: Icons.settings_outlined)` → `Navigator.push(MaterialPageRoute(builder: (_) => const SettingsPage()))`。颜色与 ⋮ 一致（`colors.headerText`）。空课表（空状态）时头部仍要能到设置页——确认空状态布局下这个按钮仍然可见；不可见就在空状态页面也放一个。
3. `settings_page.dart`：AppBar 保持；作为被 push 的页面会自动出现返回键，确认 `ThemedBackground` 下返回键颜色可见。
4. 测试：`reminder_wiring_test.dart` 等所有断言「index 0 / 切到课表 tab」的用例改为「先 push 设置页，点通知后设置页被 pop、周视图在本周」；`settings_page_test.dart` 若通过 HomeShell 找 tab 进入设置，改成点齿轮；新增 1 个用例：周视图点齿轮 → 设置页出现 → 返回键回到周视图。`grep -rn "NavigationBar\|NavigationDestination\|_index" lib` 应无命中。
5. 交接 `handoff-A2.md`。

### 任务 B：设置页收敛、备份合并、提醒与隐私文案

1. `settings_page.dart` 重排成四组（分组标题用现有 `_group` 风格，若没有就加一个 13sp 的小标题）：
   - **课表**：课表管理 / 学期设置 / 作息时间 / 上课提醒 / 导出到日历
   - **显示**：显示非本周课程 / 格子里显示时间 / 主题
   - **桌面**：添加桌面小组件（任务 C 改其行为，这里只负责位置和文案：副标题「把课表放到桌面上，不打开 App 也能看」）
   - **其他**：记住教务登录 / 备份与恢复 / 检查更新 / 关于简课表 / 隐私说明 / 反馈
   删「导出备份」「导入备份」「从文件导入课表」三条，换成「备份与恢复」一条（D6），面板里两个按钮；现有导出 / 导入逻辑（`backup_service.dart`、合并 / 覆盖确认）原样复用。
2. `timetable_manage_page.dart`：删右上角 `import-timetable-file` 按钮、菜单里的 `share` 项、`_share`、`importTimetableFromFile` 及 `TimetableImportOutcome`；删 `timetable_share.dart`、`test/timetable_share_test.dart`；`pubspec.yaml` 里 `file_picker` 仍被备份恢复用，保留；`share_plus` 仍被备份导出 / ICS / 诊断用，保留。
3. `reminder_settings_page.dart`（D7）：删 `_group(theme, '权限')` 整组（`reminder-perm-exact`、`reminder-exact-note`、`reminder-request-exact` 等 key 随之删除）、删「允许精确闹钟？」对话框里的术语（对话框可以保留但改成「提醒想准点送达，需要在系统里允许「闹钟和提醒」。去设置 / 以后再说」）；新增一张条件提示卡 key `reminder-problem-card`，文案见 D7；「即将触发」列表里的「（没有精确闹钟权限，最多可能晚 1 小时）」改为「（系统可能让提醒晚到）」。`test/reminder_settings_page_test.dart` 相应用例改为：无通知权限 → 卡片出现且带「去允许通知」；Android 12 无精确闹钟 → 卡片出现「去系统设置」；都正常 → 没有卡片、页面不含「精确」「Android」字样。
4. `assets/privacy.md` 整篇替换为第 3 节的文本（一字不改，日期 2026-10-08）；`privacy_page.dart` 的渲染器要能正确显示其中用到的语法（标题、粗体、有序 / 无序列表、段落）。设置里「隐私说明」副标题改为「课表只存在手机里；只在导入、检查更新、更新假期表时联网」。
5. `about_page.dart`：通读一遍，把「USE_EXACT_ALARM」「WebView」「JSON」之类的词换成白话或删掉；「放假 / 调休」那条改为「导入课表后会按学校校历提示一键套用；也可以在「设置 → 学期设置」里手动改」。
6. 验收：设置页四组、条目顺序如上；备份两条路径的现有测试通过；`grep -rn "精确闹钟\|USE_EXACT\|Android 1[0-9]\|WebView\|JSON\|SHA" lib/features/settings lib/widgets assets/privacy.md` 在用户可见字符串里无命中；analyze / test 绿。

### 任务 C：小组件添加面板 + 原生成功回调

1. `MainActivity.kt`：`requestPinWidget` 增加参数 `provider`（`"day"` → `DayWidgetProvider`，`"next"` → `NextWidgetProvider`，其它值返回 false），传 `successCallback`：一个指向本应用内 `BroadcastReceiver`（可以复用 `DayWidgetProvider`/新建 `PinResultReceiver`，`exported=false`）的 `PendingIntent.getBroadcast(..., FLAG_IMMUTABLE | FLAG_UPDATE_CURRENT)`，收到后 `Toast.makeText(context, "小组件已添加到桌面", LENGTH_SHORT)`。先读官方文档 https://developer.android.com/develop/ui/views/appwidgets/configuration#pin 核对 `requestPinAppWidget(provider, extras, successCallback)` 的用法。
2. `native_bridge.dart`：`requestPinWidget({required String provider})`；`deviceInfo()` 已有 `manufacturer` / `brand`，面板用它选步骤文案。
3. `add_widget_helper.dart` 重写为 `showAddWidgetSheet(context)`：`showModalBottomSheet`，内容——标题「添加桌面小组件」；两张卡片：
   - 「当日课程 · 4×2」预览图 `assets/...`（把 `android/app/src/main/res/drawable-nodpi/widget_day_preview.png` 复制到 `assets/widgets/widget_day_preview.png`，`pubspec.yaml` 登记）+ 一句「今天 / 明天的课按时间排好，可以翻页」+ 按钮「添加到桌面」；
   - 「下一节课 · 2×1」同上（`widget_next_preview.png`）+ 一句「只显示最近的一节课，适合放在桌面第一屏」；
   - 底部一行可展开的「没弹出确认框？看看怎么手动添加」（`ExpansionTile` 或自定义），展开后按品牌给 3–4 步：小米 / 红米（HyperOS、MIUI）：长按桌面空白处 → 添加小组件 / 「小部件」→ 找到简课表；华为 / 荣耀：双指在桌面捏合 → 窗口小工具 / 服务卡片；OPPO / 一加 / realme：长按桌面空白处 → 小组件；vivo / iQOO：长按桌面空白处 → 原子组件 / 小组件；三星：长按桌面空白处 → 小组件；其它 / 原生：长按桌面空白处 → 小组件。品牌由 `manufacturer` / `brand`（小写匹配 xiaomi/redmi/huawei/honor/oppo/oneplus/realme/vivo/iqoo/samsung）决定默认展开哪一条，其它折叠可查看。
   - 点「添加到桌面」：调用原生；返回 true → 按钮下方出现一行小字「系统应该弹出了确认框 →」并把「手动添加」那行高亮；返回 false → 直接展开手动步骤并提示「这台手机的桌面不支持直接添加，按下面步骤手动加一次」。
4. `settings_page.dart` 的「添加桌面小组件」tile → `showAddWidgetSheet`。
5. 测试：`test/core/native_bridge_test.dart` 覆盖 `provider` 参数透传；新建 `test/add_widget_sheet_test.dart`：Fake bridge 返回 true / false 两种分支的界面状态；品牌匹配函数的单元测试（纯函数，放 `add_widget_helper.dart` 或拆 `widget_add_guide.dart`）。
6. **真机验证（必做）**：`flutter build apk --release`（不要 split-per-abi）→ `adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-release.apk` → 打开设置 → 添加桌面小组件 → 分别点两个「添加到桌面」，用 `adb exec-out screencap -p > D:/desk/claudex/12/shots/v150/C-pin-day.png` 等截图证明系统确认框弹出；在确认框里点「添加」后看到 Toast（截图 `C-pin-toast.png`）。桌面上多出的小组件可以留着。
7. 验收：面板两张卡片 + 手动说明；两个 provider 都能弹系统框；Toast 出现；analyze / test 绿；Kotlin 编译通过。

### 任务 D：开学日期自动化 + 校历建议一键套用

1. **数据层** `holiday_presets.dart`：确认 `SchoolTerm` 解析了 `startDate`、`totalWeeks`、`name`；新增 `SchoolTerm? termCovering(String schoolId, DateTime today)`（`[startDate, startDate + totalWeeks*7)` 包含 today）。`school_registry.dart` 的 `termPresets` 已能提供 `TermPreset`。新增一个纯函数（放 `lib/core/term_resolver.dart`）：
   `TermResolution resolveTermStart({DateTime? detectedStart, int? detectedWeek, String? schoolId, HolidayPresets presets, List<TermPreset>? schoolPresets, required DateTime today})` → `{startDate, totalWeeks?, source: detected | schoolCalendar | unknown, label}`。顺序：detected → 校历（holidays.json 优先，其次 schools.json；两边同一 startDate 视为同一条）→ unknown。
2. **导入预览页** `import_preview_page.dart`（按 2026-10-08 下午修订的 D8）：
   - 用 `resolveTermStart`。`source == schoolCalendar` 时「开学日期」行显示「按上海大学校历 · 9月14日开学 · 现在第 4 周」+「改」；`detected` 时保留现有「教务系统显示当前第 N 周」+「改」；`unknown` 时该行显示「还没确定 · 点这里选」。
   - 「改」/「点这里选」→ `showWeekNumberSheet(context, {required DateTime today, required int totalWeeks, int? initialWeek, String? title})`（`lib/features/settings/week_number_sheet.dart`，被中断的代理已经写了一版，读一遍、补 `title` 参数再用）：默认标题「现在是第几周？」，1..totalWeeks 的 ChoiceChip（key `week-number-<n>`），底下一行小字「将把 x月x日（周一）设为第一周」，按钮「确定」；另有「我知道开学日期」链接走 `showDatePicker`。返回 `DateTime`（第一周周一）。
   - **点「确认导入」时**：`source == detected` 或用户已经手动选过（`manual`）→ 直接导入；`schoolCalendar` → 先弹同一个面板，`initialWeek` = 校历推出的周次，标题「按上海大学校历，现在是第 4 周，对吗？」，用户点「确定」后才导入（关掉面板 = 取消导入，留在预览页）；`unknown` → 弹面板，不预选，标题「现在是第几周？」，不选就不能导入。确认按钮在 `unknown` 时**不禁用**（点了就弹面板），这样用户不会卡住。
   - 删掉旧的「对吗？」确认对话框（`_startDateConfirmed` / `_confirmGuessedStartDate` / `_buildStartDatePrompt`）和 `ZfsoftAdapter` 里「请在下一步选择本学期第一周的周一」那条 warning（改为不加 warning——界面会引导）。
   - **周视图「选择周次」面板**（`week_view_page.dart` 的 `_showWeekPicker`）底部加一行按钮 key `week-picker-fix`：「本周不是第 N 周？点这里校正」→ `showWeekNumberSheet(initialWeek: currentWeek)` → `appState.updateConfig(config.copyWith(startDate: picked))` → SnackBar「已把本周设为第 x 周」→ 周视图回到本周。
   - `zfsoft_adapter.dart` 的周次探测 URL 列表追加一条 `BASE + '/xtgl/index_cxshjdAreaFive.html?localeKey=zh_CN&gnmkdm=index'`（正方部分部署把「第 N 周」放在这个区块；失败照旧吞掉）。
   - `test/import/import_preview_page_test.dart`：三种 source 的界面状态；unknown 时确认按钮禁用、选周后启用；校历来源的 startDate 正确。
3. **学期设置页** `term_settings_page.dart`：「开学日期」行下面加一行「按当前周次设置」→ `showWeekNumberSheet`；「一键套用预设」改为只在当前课表 `schoolId` 有校历时显示该校的学期（来源同 D8 ②），标题「学校校历」，没有校历的课表不显示这一段（`exampleTermPresets` 不再出现在界面上；若仅剩测试用途就留在 `presets.dart`）。
4. **校历建议面板** `lib/features/settings/calendar_suggestion_sheet.dart`（D9）：
   - 纯函数 `CalendarSuggestion? buildCalendarSuggestion({required Timetable tt, required HolidayPresets presets, required DateTime today})`：若 `tt.schoolId` 有覆盖 today 的校历学期且 `startDate` 与 `tt.config.startDate` 不同 → `termFix`；`presets.planFor(config, schoolId)` 中「目标日期上没有与建议相同的 override」的条目 → `pending`；两者都空返回 null。注意：`termFix` 存在时，`pending` 要按**修正后的** config 计算。
   - 面板：标题「按上海大学校历」；第一段（有 termFix 时）「开学日期：9月14日（现在第 4 周）」；第二段「放假 / 调休 n 条」逐条列出（复用 `holiday_apply_page.dart` 的 `_row` 描述方式，有覆盖手动设置时标红「将覆盖」）；按钮「一键套用」→ `appState.updateConfig` + `applyDateOverrides`，SnackBar「已按校历设置」可撤销（复用 `day_override_sheet.dart` 的撤销模式，若复杂就不做撤销）；「先不用」→ 记 `AppSettings.calendarSuggestionDismissed[timetableId] = '<holidays.updatedAt>|<startDateKey>'`（新字段，Map<String,String>，fromJson 兼容缺失）。
   - 触发点：(a) `import_preview_page._confirm` 成功、`popUntil` 之后：通过 `AppState` 上一个 `ValueNotifier<String?> pendingCalendarPromptFor`（timetableId）或等价机制通知 HomeShell；HomeShell 在下一帧弹面板（与「已导入 n 节课」SnackBar 并存）。(b) HomeShell `_startupFlow` 里、自动检查更新之前：`buildCalendarSuggestion` 非空且 dismissed 标记不匹配 → 弹。(c) `runAutoUpdateCheck` 的假日表刷新结果为 `updated` 时重新计算，非空 → SnackBar「假日表有更新」+ 动作「查看」→ 弹面板。
   - `HolidayRepository` 的当前 presets 由 `widget.holidayRepository` 提供（HomeShell 已持有；为 null 时用内置表）。
5. 测试：`term_resolver_test.dart`（三种来源、边界：today 恰在 startDate、恰在最后一周、学期之外）；`calendar_suggestion_test.dart`（termFix / pending / 都无 / 已套用不再提示 / dismissed 标记匹配与不匹配）；`week_number_sheet_test.dart`（选第 4 周 → 返回 today 所在周周一减 21 天）；HomeShell 启动触发一次面板的 widget 测试（注入 Fake 假日仓库 + 有 schoolId 的课表 + 错误 startDate）。
6. 验收：导入 SHU 样例（`test/import/fixtures/shu_kb_envelope.json` 里 currentWeek 为空的情况）→ 开学日期自动为 2026-09-14（以 today=2026-10-08 注入）；启动时对「开学日期错设成本周」的课表弹出面板；一键套用后 9/20 调休、9/25–27、10/1–10/8 停课全部写入；analyze / test 绿。

### 任务 E（2026-10-08 下午新增）：收尾清理（任务 B/C 交接文档里列出的遗留）

1. 用户可见文案里的「假日表 / 节假日表 / 假期表 / 放假日期表」统一为**「假期表」**（`assets/privacy.md` 除外——它有逐字测试，不动）；同步相关测试断言（`privacy_consistency_test` 钉着关于页「节假日表」那句，一起改）。
2. `app.dart` 启动 SnackBar 按钮「去授权」→「去允许通知」（`reminder_wiring_test` 同步）。
3. `app_state.dart` `restoreFrom`：恢复备份后的「恢复前的旧数据已备份到 <本机路径>」不再进 `warnings`（改 `debugPrint`），避免设置页顶部红卡；`models_test.dart` 的 `contains('已备份')` 同步。
4. 用户可见术语清理：`update_dialog.dart` 的「SHA-256：」行删掉（校验值用户不需要看）；`zfsoft_adapter.dart` 里给用户看的「不是 JSON」改为「教务系统返回的内容看不懂，可能还没登录成功」；`feedback_dialog.dart` 的「GitHub Issues」改为「GitHub」；`about_page.dart` L66 附近「改开学日期，它必须是第 1 周的周一」改为「在「学期设置」里点「按当前周次设置」」。
5. 删掉已无调用方的 `ScheduleUtils.nextCourse` / `nextCourseAt` 及其 2 个测试（任务 A 交接第 5 条）。
6. analyze / test 绿；交接 `handoff-E.md`。

## 3. 新的 `assets/privacy.md`（任务 B 原文替换）

```markdown
# 隐私说明

简课表只在你的手机上运行：没有账号、没有服务器、没有广告，也不做任何数据统计。

**你的课表只存在手机里。** 课程、作息、学期设置、提醒设置都保存在这台手机上，开发者看不到。卸载 App 就全部删除；换手机前可以在「设置 → 备份与恢复」里导出一份。

**从教务导入时，账号密码直接给学校。** 你是在学校自己的教务网页里登录的，简课表只读取登录后看到的课表，不保存密码。默认导入完成后就清除登录状态，除非你打开了「记住教务登录」。

**App 只在三种情况联网：**

1. 从教务导入时，打开学校的教务网站；
2. 检查有没有新版本（每天最多一次）；
3. 更新假期表（和检查版本用同一个地址）。

后两项只是下载两个很小的文件，不会带上你的任何信息。

**上课提醒在手机本地生成**，不经过任何服务器。

**用到的权限：** 只有「通知」（发上课提醒）和「闹钟和提醒」（让提醒准点）。不读取通讯录、短信、位置、相册。

**有问题？** 在「设置 → 反馈」里联系开发者。

更新日期：2026-10-08
```

## 4. 评审视角（任务 A–D 全部完成后并行）

- **R1 产品 / 文案（扮演用户）**：逐页走一遍设置、提醒、隐私、导入预览、空状态、面板，找术语、找多余条目、找「没反应」的按钮；检查两 tab 后有没有功能变成无法到达。
- **R2 正确性 / 测试**：日期运算（周一对齐、夏令时）、校历解析边界、dismissed 标记、通知点击跳转、备份合并 / 覆盖、旧 settings.json 兼容；跑全量测试并数数。
- **R3 Android / 原生**：manifest 删干净没有残留引用、Kotlin 编译、`requestPinAppWidget` 回调的 PendingIntent flag、Toast 线程、`aapt2 dump badging` 看 versionCode / 权限没变化、R8 keep 是否受影响。

## 5. 打包（修复后）

`pubspec.yaml` → `1.5.0+10`；`NOTES.md` 加 `## v1.5.0 (2026-10-08)`；根 `README.md` 功能一节与 `shu_schedule/README.md` 同步（删今日页、快捷方式、分享课表、隐私同意；加校历一键套用、现在第几周）——**不碰「给朋友装」一节**；`flutter build apk --release` 与 `--target-platform android-arm64` 两个包复制到 `dist/简课表-v1.5.0.apk`、`dist/简课表-v1.5.0-arm64.apk`；`tool/gen_latest.py` 重新生成 `dist/latest.json`；`aapt2 dump badging` 核对 versionCode=10；模拟器覆盖安装并截图：两 tab 首页、设置页四组、添加小组件面板、校历建议面板、提醒页（无问题状态）、隐私说明页 → `shots/v150/`。

## 附录：用户原话（2026-10-08）

> 第一个是开头说的隐私协议那些，完全没什么法律效力，而且也没人有欲望看。
> 界面这边，我建议直接设"课表"和"设置"两个部分，不要搞"今日"。"今日"这一部分几乎没人会看。
> 设置里面点击添加桌面小组件，它是完全没有反应。在桌面长按软件之后弹出来的三个选项排版很奇怪，而且完全没有必要，点进去就可以做这些事情，很少有人会去长按。点击第三个"把课表小组件放到桌面"，它也是完全没有反应的。
> 1. 课表管理：点进去右上角有个"选择文件"，我不知道是什么意思，看上去没必要，可以删掉。
> 2. 学期设置：我一导入进去，直接把今天设成了第一周。既然抓取了网上的校历，不应该直接知道哪一天是第一周吗？这很不合理。还有调休之类的需要自己应用，这部分能不能在加载或导入之后弹出一个选项，直接一键应用？
> 3. 上课提醒："精确闹钟 / 安卓 13 以上"这些表述太专业了，我觉得没有必要。
> 4. 备份：导出和导入的意义是什么？没有意义的话就删掉吧。"从文件导入课表"也没必要，两个人课表完全一样的情况基本没有，其实也可以删掉。
> 5. 关于与隐私说明："关于"这边懒得细看，但好像问题不大。"隐私说明"里有好多专业术语，完全没必要，更像是给技术人员看的内容，而不是给用户看的。这是一个产品，不是一个工程
