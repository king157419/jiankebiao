# PLAN-1.4 —「简课表」v1.4.0 实施规格

日期 2026-10-07。依据：`REVIEW-3-market.md` 第六节前 7 条；接入点地图见 `.tmpbuild/plan14/codemap.md`（537 行，每条都标了文件和行号，实施前必读对应小节）。

## 0. 所有执行者都要遵守的约束

- 工具链：每条 flutter / dart / adb / gradle 命令前都要 `source /d/desk/claudex/12/env.sh && export TEMP=D:/desk/claudex/12/.tmpbuild TMP=D:/desk/claudex/12/.tmpbuild && mkdir -p "$TEMP"`。C 盘没有剩余空间，临时文件一律放 D 盘。
- 同一时刻只能有一个 Gradle 构建。打包用 `flutter build apk --release`（模拟器是 x86_64，必须用通用包）；**禁止** `--split-per-abi`（会生成 versionCode 2008）。arm64 包用 `--target-platform android-arm64`。
- 模拟器 `emulator-5554`（AVD `shu35`，API 35）在线，装着 1.3.1 release 签名包（versionCode 8）。release 包可以 `adb install -r` 覆盖；debug 包装不上。返回用 `adb shell input keyevent 4`。
- 日期运算只能用 `ScheduleUtils.addDays` / `DateTime(y,m,d+n)` / `ScheduleUtils.daysBetween`，禁止 `Duration(days:)`、`.difference().inDays`（开发机时区有夏令时，NOTES.md §2.1）。
- 不提交 git，不改 `site/`，不改根 `README.md` 里「给朋友装」一节（那是另一个会话的改动），不碰 `keys/`、`key.properties`、keystore。
- 每个任务结束前：`flutter analyze` 零问题，`flutter test` 全绿（起点 411 个），新功能必须带测试。测试约定见 codemap §4（harness、key 命名 kebab-case 带前缀、IO 放 `tester.runAsync`）。
- `assets/privacy.md` 必须列出 pubspec 里的每一个运行时依赖（有测试强制），新增权限、新增联网地址也必须写进去。
- 文档：在 `NOTES.md` 末尾 `## v1.4.0 (2026-10-07)` 一节下追加本任务的小节（任务 A 创建这一节）；每个任务另外写 `.tmpbuild/plan14/handoff-<字母>.md`（≤60 行：改了哪些文件、新增测试、验证证据、遗留问题），供下一个任务和最终集成阅读。
- 优先用 Bash（cat/sed/grep）读文件；改文件用 Edit 或 heredoc 都行。遇到官方 API 不确定的地方先查官方文档（pub.dev / developer.android.com），不要凭记忆。
- 版本号、`PrivacyPolicy.version` 的修改按下文指定的任务做，其他任务不要动。

执行顺序（同一工作树，串行）：A（更新源 + 远程假日表）→ B（上课提醒）→ C（小组件）→ D（ICS 导出）→ E（周视图长按调休 + 空状态）→ F（版本、文档、打包、模拟器验证）→ G（审查）。

---

## 任务 A：更新源一处配置 + Gitee 镜像 + 假日表远程下发（第 1、6 条）

### A1 仓库配置收口
- 新建 `lib/core/repo_config.dart`：
  ```dart
  class RepoConfig {
    const RepoConfig({required this.githubOwner, required this.githubRepo, this.giteeOwner = '', this.giteeRepo = '', this.branch = 'main'});
    ...
    bool get isPlaceholder => githubOwner == 'OWNER' || githubRepo == 'REPO' || githubOwner.isEmpty || githubRepo.isEmpty;
    bool get hasGitee => giteeOwner.isNotEmpty && giteeRepo.isNotEmpty;
    String get issuesUrl => 'https://github.com/$githubOwner/$githubRepo/issues';
    /// 按「国内可达性」排序的同一文件多个地址：Gitee raw（若配置）→ jsDelivr → raw.githubusercontent
    List<Uri> rawUrls(String path);
  }
  const kRepo = RepoConfig(githubOwner: 'OWNER', githubRepo: 'REPO');
  ```
  Gitee raw 地址格式 `https://gitee.com/{owner}/{repo}/raw/{branch}/{path}`，jsDelivr `https://cdn.jsdelivr.net/gh/{owner}/{repo}@{branch}/{path}`。
- `UpdateConfig.sources` 改为 `kRepo.rawUrls('latest.json')`，`placeholder` 判断改用 `kRepo.isPlaceholder`；`FeedbackLinks.issuesUrl` / `isConfigured` 改为从 `kRepo` 派生。全仓库 `OWNER/REPO` 只剩 `repo_config.dart` 一处（文档和测试除外）。
- 保留现有 `latest.json` 协议（versionCode / versionName / changelog / downloadUrls / sha256），**不要**改用 GitHub Releases API（没有 versionCode、响应可能超 64 KiB、匿名限流）。
- 「检查更新」只提示不阻断（现状如此，确认不被破坏）。
- 重写被钉死的测试：`test/update_checker_test.dart` L85-108（源数量/顺序）、保留 `privacy_and_about_test.dart` L385-405「未配置更新源」语义（占位状态下仍然应禁用）。新增测试：配置了 Gitee 时源为 3 个且 Gitee 在前；未配置 Gitee 时 2 个。

### A2 假日表远程下发
- `assets/holidays.json` 顶层加 `"updatedAt": "2026-10-06"`（已有 `version: 1`）。`HolidayPresets.fromJson` 解析顶层 `version`（≠1 视为无效）与 `updatedAt`；加字段 `HolidayPresets.updatedAt`、`HolidayPresets.source`（`bundled` / `remote`）。
- 新建 `lib/core/holiday_repository.dart`：
  - `HolidayRepository({UpdateFetch? fetch, RepoConfig repo = kRepo, Directory Function()? dirProvider})`。
  - `Future<HolidayPresets> load()`：读内置；若缓存文件 `holidays.remote.json`（放在 `Storage` 的数据目录，给 `Storage` 加一个公开的 `Future<Directory> dataDirectory()`，尊重 `Storage.overrideDirectory`）存在且解析有效且 `updatedAt` 更新于内置，则用缓存**整体替换**（不做逐条合并）。
  - `Future<HolidayRefreshResult> refresh({bool force = false, required bool privacyAccepted, DateTime? now})`：未配置仓库 → `notConfigured`；未同意隐私 → `skipped`；24 小时内已刷新且非 force → `throttled`（上次刷新时间存在 `AppSettings.lastHolidayRefresh`，新增字段，按 app_settings.dart L15-27 的约定给默认值，`restoreFrom` 时保留设备上的值，同 `lastUpdateCheck`）；否则依次尝试 `kRepo.rawUrls('shu_schedule/assets/holidays.json')`，用 `UpdateChecker.httpFetch`（把 64 KiB 上限改成参数，假日表允许 256 KiB；错误文案不要再写死 `latest.json`），解析成功、`version == 1`、`updatedAt` 更新于当前 → 原子写缓存（复用 `_writeAtomic` 思路）→ `updated`；相同 → `unchanged`；全部失败 → `failed`。
  - 可选完整性校验：若 `latest.json` 含 `"holidays": {"sha256": "..."}` 则校验 sha256（`package:crypto` 要加为直接依赖并写进 privacy.md）；没有则只依赖 TLS。
- `HolidayApplyPage` 改为接收 `HolidayRepository? repository`（保留 `presets` 注入供旧测试），`initState` 用 `repository.load()`；页面头部显示「假日表 · 内置 2026-10-06」或「已更新 2026-11-xx」；AppBar 加刷新按钮（key `holiday-refresh`）调用 `refresh(force: true)` 并用 SnackBar 反馈四种结果；进入页面时静默调用一次非 force 的 refresh（成功则重新 load）。仓库未配置时刷新按钮显示但点击提示「更新源未配置」。
- `runAutoUpdateCheck` 成功后顺带 `refresh()`（受 24h 节流），失败静默。
- 写一个发版辅助脚本 `tool/gen_latest.py`（Python 3，`D:/conda/miniconda3/python.exe`）：输入版本号、APK 路径、changelog，输出 `latest.json`（含两个 APK 的 sha256 和 `holidays.sha256`）。README「发布」一节说明用法。

### A3 隐私与文案
- `PrivacyPolicy.version` 1 → 2，`updatedAt` → `2026-10-07`（这会让老用户重新看一次同意对话框，是有意为之）。
- `assets/privacy.md`：联网清单加 Gitee；L25「学校列表不会下载」的承诺改写为：学校列表仍内置；假日表会在用户同意后、仅从配置的仓库镜像下载并缓存在本地，内容只有日期；加 `crypto` 到第三方列表；更新日志加 v2 条目。同步 `privacy_page.dart` L353-354、`settings_page.dart` L201、`about_page.dart` 中重复的联网描述。所有被测试要求的字符串保留。
- `NOTES.md` 创建 `## v1.4.0 (2026-10-07)` 一节并写 A 小节；根 `README.md` 加「发布前替换清单：只改 `lib/core/repo_config.dart` 一处」。

### A4 测试
- `HolidayRepository`：内置回退、缓存更新于内置时替换、缓存旧于内置时忽略、损坏缓存忽略、refresh 的 notConfigured / throttled / updated / unchanged / failed、sha256 不匹配拒绝。
- 页面：刷新按钮存在；注入 fake repository 时头部显示数据版本。

---

## 任务 B：本地课前提醒（第 2 条）

### B1 依赖与 Android 配置（先查 pub.dev 确认版本仍是最新稳定版）
- pubspec：`flutter_local_notifications: ^22.3.1`、`timezone: ^0.11.1`（直接依赖，因为要 import `TZDateTime`）。**不要**加 `flutter_timezone`：所有提醒都是一次性绝对时刻，用 `tz.TZDateTime.from(localDateTime, tz.UTC)` 即可，不需要 IANA 数据库和设备时区名。
- `android/app/build.gradle.kts`：`compileOptions { isCoreLibraryDesugaringEnabled = true }`，新增 `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }`（minSdk 24 不需要 multidex）。
- `AndroidManifest.xml`：`POST_NOTIFICATIONS`、`SCHEDULE_EXACT_ALARM`、`RECEIVE_BOOT_COMPLETED`、`VIBRATE`；`ScheduledNotificationReceiver` 与 `ScheduledNotificationBootReceiver`（intent-filter 按插件 README）。不用 `USE_EXACT_ALARM`。
- 状态栏小图标：`res/drawable/ic_stat_notify.xml`（单色白色矢量，可用现有 shortcut 图标简化）；`res/raw/keep.xml` 保住它不被 shrinkResources 删掉。
- 渠道：`class_reminder`「上课提醒」IMPORTANCE_HIGH；`evening_preview`「明日预告」IMPORTANCE_DEFAULT。

### B2 纯 Dart 规划器（可测试，不依赖插件）
- `lib/core/reminders/reminder_planner.dart`：
  ```dart
  class ReminderSettings { bool enabled=false; int leadMinutes=15; bool eveningPreview=true; int previewHour=21; int previewMinute=0; } // 放进 AppSettings，带默认值与 copyWith/json
  class PlannedReminder { int id; DateTime fireAt; String title; String body; String channel; String payload; }
  class ReminderPlanner { static List<PlannedReminder> plan({required Timetable? timetable, required ReminderSettings settings, required DateTime now, int horizonDays = 10}); }
  ```
  规则：对 `now` 起 `horizonDays` 天内每一天，用 `ScheduleUtils.coursesOn(date, timetable)`（已含停课/调休）；每门课在 `periodRange(...).start − leadMinutes` 触发，`fireAt <= now` 的跳过；标题「{课程名} · {HH:mm} 上课」，正文「{地点}{ · 教师}· 第 s-e 节」，调休日追加「（调休：按第 N 周周X上课）」。
  明日预告：每天 `previewHour:previewMinute` 对「明天」生成一条，仅当明天在学期内且（有课 或 有覆盖）：停课 →「明天停课{（备注）}」；调休 →「明天按第 N 周周X上课，共 k 节，{首节时间} 开始」；普通 →「明天 k 节课，{首节时间} {首节课名}」。明天既无课也无覆盖 → 不生成。
  id：FNV-1a 32 位正整数，输入 `kind|date|courseId|startPeriod`；重排时先 `cancelAllPendingNotifications()` 再整批调度。

### B3 网关与服务
- `lib/core/reminders/reminder_gateway.dart`：抽象 `ReminderGateway { Future<void> init(onTap); Future<bool> requestNotificationPermission(); Future<ReminderPermission> permissions(); Future<bool> requestExactAlarm(); Future<void> openSettings(); Future<void> scheduleAll(List<PlannedReminder>, {required bool exact}); Future<void> cancelAll(); Future<void> showTest(); Future<void> scheduleTestIn(Duration); Future<List<PendingReminder>> pending(); Future<String?> launchPayload(); }`。
  真实实现 `LocalNotificationsGateway` 用插件（Android 分支通过 `resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()`；能精确则 `exactAllowWhileIdle`，否则 `inexactAllowWhileIdle`）。测试用 `FakeReminderGateway`（放 `test/helpers/`）。
- `lib/core/reminders/reminder_service.dart`（ChangeNotifier）：`replan(AppState)`（800 ms 防抖，只有 `settings.enabled && privacyAccepted` 才调度，否则 `cancelAll`）；暴露 `lastPlan`、`permissions`。
- 接线（app.dart）：`ShuScheduleApp` 构造函数加 `ReminderGateway? reminderGateway`（默认真实实现）；给 `_ShuScheduleAppState` 加 `WidgetsBindingObserver`，`resumed` 时：刷新权限状态、`replan`、`_scheduleWidgetPush()`（小组件也缺这个钩子）；AppState 变化监听里同时触发 replan；`HomeShell._startupFlow` 在隐私同意后调用 `init` 并处理冷启动 payload → `_handleAction('today')`。
- `restoreFrom`：提醒偏好随备份恢复（它是用户偏好）；权限状态不存。

### B4 设置页
- settings_page.dart 新分组「上课提醒」→ tile（key `settings-reminders`，副标题「已开启 · 提前 15 分钟」/「未开启」）→ `ReminderSettingsPage`：
  - 总开关（key `reminder-enabled`）：打开时先请求通知权限，拒绝则回弹并提示去设置。
  - 提前分钟 ChoiceChip 5/10/15/20/30（key `reminder-lead-<n>`）。
  - 明日预告开关 + 时间（TimePicker，key `reminder-preview`、`reminder-preview-time`）。
  - 权限状态卡：通知（已允许/未允许 + 「去设置」）、精确闹钟（已允许/未允许 + 「去授权」，Android 14 新装默认关闭的说明；未允许时写明「提醒可能晚几分钟」）。
  - 「发送测试提醒」（立即）与「1 分钟后测试」（走 zonedSchedule 路径，验证真正的调度链）。
  - 「即将触发」列表：`ReminderPlanner.plan` 的结果按日期分组（最多 10 天），停课日显示一行「x月x日 停课 · 不提醒」。
- 页面不改 `PrivacyPolicy.version`（A 已改到 2），但要把三个新权限（POST_NOTIFICATIONS、SCHEDULE_EXACT_ALARM、VIBRATE）和两个新依赖写进 `assets/privacy.md`，并说明「提醒完全在本机生成，不联网」。

### B5 验证
- 单测：规划器（普通日、停课日无提醒、调休日按目标星期出课、预告三种文案、`fireAt<=now` 跳过、id 稳定）；设置页用 Fake 网关测开关/权限行/列表；`settings-reminders` tile 存在。
- 真机链路（模拟器）：`flutter build apk --release` → `adb install -r`；`adb shell pm grant cn.shu.schedule android.permission.POST_NOTIFICATIONS`；打开 1.3.1 已导入的示例课表 → 设置 → 上课提醒 → 开启 → 「1 分钟后测试」→ 60 秒后 `adb shell dumpsys notification --noredact | grep -A3 cn.shu.schedule` 看到通知；`adb shell dumpsys alarm | grep -c cn.shu.schedule` 看到已排程闹钟；截图保存到 `shots/v140/B-*.png`（`adb exec-out screencap -p > 文件`）。把证据写进 handoff。

---

## 任务 C：小组件自动切到明天 + 状态头部 + 2×1「下一节」（第 3 条）

- 在 `ShuWidgetProvider.kt` 加共享解析：`fun resolveDisplay(snapshot, now: Calendar, offset: Int): DisplayDay(dayIndex, daysFromToday, autoTomorrow)`。规则：`offset == 0` 且（今天有课且最后一节 `endMinutes <= nowMinutes`，或 今天无课且 `now >= 18:00`）→ 显示明天，`autoTomorrow = true`。`DayWidgetProvider.render` L172-173 与 `DayRemoteViewsFactory.onDataSetChanged` L76-77 都改用它，消灭重复逻辑。`relativeDayLabel` 改为按实际日期差计算。
- 头部副标题（`day_header_sub`）：显示今天时按当前时间给状态：上课中 →「第 N 周 · 上课中 · 至 11:50」；下一节 ≤ 90 分钟 →「第 N 周 · 51 分钟后上课」；更远 →「第 N 周 · 下一节 10:00」；自动切到明天 →「明天 · 第 N 周 · 3 节课」；停课日沿用现有文案。保持单行。
- 边界刷新：每次 render 后用 `AlarmManager.set(RTC, nextBoundary, pendingIntent)`（非精确、不唤醒、独立 requestCode）在下一个课程开始/结束、18:00、次日 00:00:30 中最近的一个时刻重绘。不申请精确闹钟权限。
- 2×1「下一节」：`NextWidgetProvider.kt` + `res/layout/widget_next.xml`（课程名 / 时间 / 地点 三行，无列表）+ `res/xml/next_widget_info.xml`（minWidth 110dp，minHeight 40dp，可调）+ manifest receiver + 预览图 + strings（不要出现「上大」）。内容：下一节或上课中那一节；今天没了就显示明天第一节并标「明天」；全无则「近期没有课程」。独立的每日闹钟 requestCode。更新 `WidgetSync.refreshTargets` 并修 `widget_sync_test.dart` L222-230。`MainActivity.requestPinWidget` 保持钉 4×2 不变，2×1 通过桌面小组件列表添加（README 说明）。
- Dart 侧：快照已含 start/end 时间，无需改字段；只确认 B 加的 resume 推送已生效。
- 验证：`flutter build apk --release` 安装 → 把小组件放到桌面（用 App 内现有「添加小组件」入口）→ **不要**用 `adb shell date` 改系统时间（会打乱提醒验证）；改为临时在示例课表里加一门「现在正在上」的课来观察「上课中」文案，然后删掉；截图 `shots/v140/C-*.png`。

---

## 任务 D：ICS 导出（第 4 条）

- `lib/features/settings/ics_exporter.dart`（纯 Dart）：`IcsExporter.build({required Timetable timetable, int? alarmMinutes, required DateTime now})` → String。
  - 范围 `[startDate, addDays(startDate, totalWeeks*7-1)]`，逐日 `effectiveDayOf` + `coursesOnEffective`，`week > totalWeeks` 跳过，停课日自然为空，调休日按目标星期出课。
  - 头：`BEGIN:VCALENDAR / VERSION:2.0 / PRODID:-//简课表//1.4//CN / CALSCALE:GREGORIAN / METHOD:PUBLISH / X-WR-CALNAME:{课表名} / X-WR-TIMEZONE:Asia/Shanghai`，附 `VTIMEZONE`（Asia/Shanghai，单 STANDARD 段，TZOFFSETFROM/TO +0800，DTSTART 19700101T000000）。
  - 事件：`UID:jkb-{timetableId}-{courseId}-{yyyyMMdd}-{startPeriod}@cn.shu.schedule`、`DTSTAMP`（UTC，Z 结尾）、`DTSTART;TZID=Asia/Shanghai:yyyyMMddTHHmmss`、`DTEND`、`SUMMARY`、`LOCATION`、`DESCRIPTION`（教师 / 第 s-e 节 / 第 N 周 周X / 调休说明）、`CATEGORIES:课程`；`alarmMinutes != null` 时附 `VALARM`（`ACTION:DISPLAY`、`TRIGGER:-PT{n}M`）。
  - 文本转义反斜杠、分号、逗号、换行；CRLF；75 字节折行且不切断 UTF-8 多字节字符（先查 RFC 5545 §3.1 确认）。
- 分享：复用 `timetable_share.dart` 的 `_shareWithSystemSheet` 模式（抽成可共用函数），mime `text/calendar`，文件名 `jiankebiao-timetable-yyyyMMdd.ics`（ASCII）。
- 入口：settings_page「课表」分组加 tile「导出到日历（.ics）」（key `settings-export-ics`）→ 底部弹窗（key `ics-sheet`）：一句说明（「iPhone：微信/AirDrop 打开后选“添加全部”；电脑：Outlook / Google 日历导入」）、提醒选项 ChoiceChip 无/10/15/30（key `ics-alarm-<n>`，默认取 B 的 leadMinutes）、「生成并分享」（key `ics-share`）；`TimetableManagePage` 菜单加 `ics` 项。
- 文档：根 `README.md` L57-61、L251 关于「App 里没有 ICS 导出」的说法改为已内置（不要动「给朋友装」一节）。
- 测试：事件数等于学期内有效课次；停课日期无事件；调休日事件为目标星期的课；UID 稳定；CRLF 与折行（含长中文行）；转义；VALARM 可选；底部弹窗与 share 钩子（`TimetableShare.shareFile` 式注入）。

---

## 任务 E：周视图长按列头设调休 + 空状态三入口（第 5、7 条）

### E1 抽出共用流程
- 把 `TermSettingsPage._editOverride`（term_settings_page.dart L188-242）抽到 `lib/features/settings/date_override_flow.dart` 的顶层函数 `Future<void> editDateOverride(BuildContext, AppState, {DateTime? date, OverrideMode? initialMode})`，行为与现有 `override-*` 测试键全部保留。

### E2 长按列头
- `week_view_page.dart` `_weekdayCell`：外层 `InkWell(key: 'weekday-<yyyy-MM-dd>', onLongPress: ...)` 弹底部面板 `DayOverrideSheet`（key `override-sheet`）：标题「10月8日 周四 · 第 4 周」+ 当前状态描述；选项：
  1. 若 `HolidayRepository.load()` 的数据对该日期有建议（学校条目或国家补班日），最上方一行「假日表建议：按 10/6（周二）课表上课 / 停课（国庆）」一键套用（key `override-sheet-suggest`）；
  2. 「设为停课」（key `override-sheet-cancel`，一键，SnackBar 可撤销）；
  3. 「调休：按某天课表上课」（key `override-sheet-actas`，打开编辑器并预置 weekday 模式）；
  4. 「编辑…」（完整编辑器）；
  5. 已有覆盖时「清除」（key `override-sheet-clear`）。
- 列头角标：新增 `EffectiveDay.badge`（停课 → 「休」，调休 → 「补」），列头以小圆角 chip 显示（休：灰，补：主题色），key 仍为 `override-<yyyy-MM-dd>`；更新 `week_view_override_test.dart` L111-140 的断言；`DateOverride.shortLabel` 不改（今日页、小组件继续用「停课」「调休」）。
- 周末列：`_visibleDays` 改为按周计算：`showWeekend == false` 时，若该周周六/周日有有效课程或有覆盖，则把该天也显示出来（这样 10/10 周六补课能看到、能长按）。加测试。

### E3 空状态
- `EmptyState` 增加 `tertiaryLabel/onTertiary` 和 `keyPrefix`（按钮 key `<prefix>-primary/secondary/tertiary`）。
- 周视图空状态：「从教务导入」「手动添加」「打开同学分享的文件」（后者调 `importTimetableFromFile`；若当前课表为空表则 `applyImport(overwriteId: current.id)` 覆盖它，避免留下空的「我的课表」—— 给 `importTimetableFromFile` 加参数实现）。
- 今日页：`timetable == null` 时同样三个入口；有课表但课程数为 0 时也显示这组入口；今天停课/无课且下一个上课日距今 ≥ 2 天时副标题显示「10月8日（周四）复课」，`ScheduleUtils.nextCourse` 调用时 `lookaheadDays` 用学期剩余天数。
- 测试：三按钮存在且可点；空表覆盖导入；复课日期文案（含跨长假）。

---

## 任务 F：集成、打包、模拟器验证

- `pubspec.yaml` → `1.4.0+9`；`app_brand.dart` appVersion `1.4.0`。
- `NOTES.md` v1.4.0 一节整理成统一格式（各任务已追加）；根 `README.md`：功能列表、调休一节加「长按列头」、提醒、ICS、小组件、版本历史 1.4.0 一行；`shu_schedule/README.md` 同步。
- `flutter analyze`、`flutter test` 全绿并记录总数。
- 打包：先 `flutter build apk --release` → `dist/简课表-v1.4.0.apk`；再 `--target-platform android-arm64` → `dist/简课表-v1.4.0-arm64.apk`；用 aapt2（`/d/desk/sdk/android/build-tools/36.0.0/aapt2.exe dump badging`）确认两个包 versionCode=9、versionName=1.4.0；记录字节数与 sha256。
- 模拟器：`adb install -r` 通用包（从 1.3.1 升级，确认课表与调休数据保留）；逐项截图到 `shots/v140/`：隐私重新同意、设置页新分组、上课提醒页（权限卡 + 即将触发）、测试通知到达、小组件状态头部、2×1 小组件、ICS 底部弹窗与系统分享面板、周视图长按面板与「休」「补」角标、周六补课列、空状态三入口（新建一个空课表看）、假日页数据版本与刷新。
- 用 `tool/gen_latest.py` 生成 `dist/latest.json`（下载地址留占位）。
- handoff-F 写清：测试总数、包大小、哪些项只在测试里验证、遗留问题。

## 任务 G：审查（只读）
- 对 `git diff HEAD` + 未跟踪文件（排除 `site/`、根 README「给朋友装」）做审查：正确性（尤其日期/时区、提醒 id、ICS 规范）、Android 配置（权限、receiver、desugaring、keep.xml）、测试覆盖缺口、隐私文本是否与实现一致。输出按严重度排序的清单（文件:行号 + 失败场景），不改代码。
