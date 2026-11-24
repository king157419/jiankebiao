# shu_schedule

> 简课表的使用说明、安装方法（含「给朋友装：安卓、鸿蒙、iPhone」）在上一级的 [README.md](../README.md)。

## 桌面小组件（Android）

| 小组件 | 尺寸 | 内容 | 怎么加到桌面 |
| --- | --- | --- | --- |
| 简课表 | 4×2，可调 | 某一天的课程列表，◀ ▶ 翻一周内任意一天 | App 里「设置 → 添加桌面小组件」，点「当天课程 · 4×2」卡片的「添加到桌面」，系统弹确认框 |
| 下一节课（v1.4.0） | 2×1，可调 | 正在上或下一节课的课程名 / 时间 / 地点；今天没课了往后找 7 天内第一节（标「明天」/「周一」，正好一周后标「10月14日」），都没有显示「近期没有课程」 | 同一个面板里点「下一节课 · 2×1」卡片的「添加到桌面」（v1.5.0 起） |

- 有的桌面点了「添加到桌面」也不弹确认框：面板底部「没弹出确认框？看看怎么手动添加」按手机品牌（`Build.MANUFACTURER` / `BRAND`）给出步骤，从桌面的小组件列表里把「简课表」（4×2）或「下一节课」（2×1）拖出来。用户在确认框里点了添加后，`PinResultReceiver` 弹 Toast「小组件已添加到桌面」，并通过 `MainActivity.onPinned` 回传 `onWidgetPinned`，面板将对应卡片更新为「已添加到桌面 ✓」并取消手动行高亮。
- 4×2 的头部会跟着时间变：「第 4 周 · 上课中 · 至 11:50」/「第 4 周 · 51 分钟后上课」（90 分钟内）/「第 4 周 · 下一节 10:00」；
  今天的课上完了（或今天没课且过了 18:00）自动改看明天：「明天 · 第 4 周 · 3 节课」；◀ 能翻回今天（「第 4 周 · 今天 · 已结束」）。停课日的文案不变。
  翻页偏移存「距今天的天数」，`OFFSET_DEFAULT = -1` 表示默认那天（key `day_offset_<id>`，修复轮换名，老版本的 0 不再被误读成今天）。
- 两个小组件都读 App 推送的同一份快照，翻页和这些状态都在原生侧按当前时间算，不需要 App 在后台。
  刷新：App 启动 / 数据变化 / 回到前台时推送；系统 30 分钟周期；每天 00:00:30；以及每次渲染后按
  「下一节开始 / 结束、开课前 90 分钟、18:00、跨天」排的**非精确、不唤醒**闹钟（`AlarmManager.set(RTC, …)`，
  不需要精确闹钟权限，所以可能晚十几到几十分钟（系统省电策略所致）；屏幕关着时不投递，亮屏后补上）。
- 原生逻辑的 JVM 单测：`cd android && ./gradlew :app:testDebugUnitTest`（`android/app/src/test/kotlin/.../WidgetTimeLogicTest.kt`）。

## 校历与调休 / 停课

- v1.5.0 开学日期自动化（`lib/core/term_resolver.dart` + `week_number_sheet.dart`）：导入时优先用教务识别出的当前周次；否则用学校校历（覆盖今天或开学前 28 天内即将开学）并在确认导入时弹面板确认；都没有时弹「现在是第几周？」。手动新建课表或空状态首次添加课程时同样询问当前周次。用户或教务确认过的开学日期记入 `AppSettings.termStartConfirmed`，后续不再被校历建议推翻。
- v1.5.0 校历建议一键套用（`calendar_suggestion_sheet.dart`）：导入完成回首页、启动时、或假期表联网刷新使本校本学期条目指纹 `termKey` 变化时，提示一键套用放假 / 调休（已过去的条目折叠汇总）。「套用节假日安排」页保留作为手动入口。
- 「设置 → 学期设置 → 调休 / 停课」按日期设置停课、按某个星期 / 指定周次上课；**周课表里长按某一天的列头**弹出单日面板——「假期表建议」一键套用、「设为停课」（可撤销）、「调休：按某天课表上课」、「编辑…」、「清除设置」。列头角标：停课「休」（灰）、调休 / 补课「补」（主题色）；小组件同步写「停课」/「调休」。
- 隐藏周末时，某一周的周六 / 周日有课或有设置就单独显示那一天（补课的周六能看到、能长按）。
- 没有课表 / 课表里没有课时，全屏周课表给出「从教务导入 / 手动添加」两个入口，右上角齿轮进入设置页（v1.5.0 去掉底部导航栏、今日页、长按图标快捷方式、首次隐私同意弹窗与单张课表文件分享）。

## 上课提醒（v1.4.0 / v1.5.0）

- 「设置 → 上课提醒」：默认关闭，打开时才申请通知权限（拒绝就不保存）；提前 5 / 10 / 15 / 20 / 30 分钟；「明日预告」默认 21:00，说明天几节课、停课还是调休。
- `lib/core/reminders/`：纯 Dart 的 `ReminderPlanner` 按调休 / 停课展开接下来 14 天（最后一天的预告时间另发一条「提醒已排到 x月x日，打开简课表就会续上」，渠道 `evening_preview`），`ReminderService` 在启动、回到前台、课表或设置变化时重排（防抖 800 ms，计划不变不重排），
  `LocalNotificationsGateway` 用 `flutter_local_notifications` 的 `zonedSchedule` 交给系统闹钟。点击通知 `popUntil(isFirst)` 回到周课表本周。渠道 `class_reminder`（上课提醒）/ `evening_preview`（明日预告），id 发布后不能改。
- 精确闹钟：Android 13+ 声明 `USE_EXACT_ALARM`（安装即授予、不能收回；本 App 侧载、不上应用商店，课表提醒属于日历类用途），Android 12 / 12L 声明 `SCHEDULE_EXACT_ALARM`（`maxSdkVersion="32"`，可被用户收回）。拿不到精确闹钟时退回 `inexactAllowWhileIdle`，系统最多可能晚 1 小时；权限异常时页面顶部显示条件提示卡（`ReminderProblem`）。手机重启后由插件的 boot receiver 补排（关机期间错过的会在开机时一起弹出）。
- 提醒跟随当前课表：页面顶部和设置 tile 写课表名；提醒开着时当前课表换了，`ReminderService.timetableSwitches` 发事件，`HomeShell` 弹「上课提醒已切换到「xxx」」。提醒开着但没有通知权限（例如从备份恢复到新手机）时，tile 写「已开启 · 没有通知权限」，启动时弹一次带「去允许通知」的 SnackBar。
- 「发送测试提醒」立即发一条；「1 分钟后测试」和正式提醒走同一条定时链路。页面底部「接下来的提醒」列出全部计划（停课日写「停课 · 不提醒」）。
- 隐私说明（`assets/privacy.md`）白话写明用到的「通知」与「闹钟和提醒」权限；提醒不联网。

## 导出到日历（.ics，v1.4.0）

- 入口：「设置 → 导出到日历」（当前课表）或「课表管理 → 某张课表的 ⋮」（那一张）。底部弹窗显示课次总数，提醒可选「无 / 10 / 15 / 30 分钟」（上课提醒的提前量是 10 / 15 / 30 时默认用它，否则 15），「生成并分享」走系统分享（`text/calendar`，文件名 `jiankebiao-timetable-yyyyMMdd.ics`）。
- `lib/features/settings/ics_exporter.dart`（纯 Dart）按 RFC 5545：每行不超过 75 字节、只在字符之间折行；设备当前 UTC 偏移是 +08:00 时写 `TZID=Asia/Shanghai` + VTIMEZONE，否则写浮动本地时间（不带 TZID / VTIMEZONE，弹窗提示「将按手机当前时区导出」）；`PRODID` 带 `appVersion`；UID `jkb-{课表}-{课程}-{日期}-{起始节}@cn.shu.schedule` 两次导出一致；调休、停课已展开，超出总周数的不导。
- 导出的是快照：建议导入到一个单独的日历；课表或调休有变化时，先清空那个日历再重新导入，日历不会自动删除已取消的课（重新导入删不掉已经取消的课；同一 UID 是覆盖还是重复添加，各日历 App 不同，还没实测）。

## 假期表与更新源（v1.4.0 / v1.5.0）

- 发布仓库只在 `lib/core/repo_config.dart` 的 `kRepo` 一处配置；检查更新的 `latest.json`、远程假期表、「反馈」的 GitHub 链接都从它派生，读取顺序 Gitee raw（配置了才有）→ jsDelivr → GitHub raw。还是占位符时不发任何请求，设置页隐藏「检查更新」与假期表页的手动刷新按钮。
- 假期表 = 内置 `assets/holidays.json` 与联网缓存 `holidays.remote.json` 中 `updatedAt` 较新的一份（`HolidayRepository`）。检查更新成功后顺带刷新（24 小时最多一次；`latest.json` 里有 `holidays.sha256` 时校验）；「套用节假日安排」页顶部显示「假期表 · 内置 / 已更新 日期」，配置了更新源时右上角可手动刷新。
- `tool/gen_latest.py` 生成 `latest.json`（APK 与假期表的 SHA-256、版本号默认读 `pubspec.yaml`），用法见根 README「十一、发布（维护者）」。

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
