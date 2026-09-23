# 上大课表（SHU Schedule）— 项目总规划

> 目标：复刻 WakeUp 课程表的核心体验（一键从教务导入、好看的周课表、桌面小组件、可自定义作息），无广告，首发上海大学，Android 先行（打包 APK 给用户自己手机安装）。
> 规划：Fable；执行：Opus 子代理；主题视觉：Codex（产出在 design/）。

## 0. 已核实的事实（不要再猜，直接用）

### 0.1 上海大学教务系统（2025 年 5 月起启用的新系统 = 正方教务 zfsoft "jwglxt"）
- 学生课表所在系统：**本科教学管理信息服务平台** `https://jwxt.shu.edu.cn/jwglxt/`（正方新版）。选课系统 `jwxk.shu.edu.cn` 是另一实例，只管选课，课表以 jwxt 为准。
- 登录：访问 `https://jwxt.shu.edu.cn/` 会跳转到统一身份认证 `https://newsso.shu.edu.cn/...`（可能有手机/企业微信二次验证），登录后回到 `https://jwxt.shu.edu.cn/jwglxt/xtgl/index_initMenu.html`。**登录动作由用户在 WebView 里自己完成，App 只负责在登录后注入脚本抓课表。**
- 个人课表接口（正方通用，SHU 已被开源项目验证）：
  - `POST https://jwxt.shu.edu.cn/jwglxt/kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N2151`
  - 表单：`xnm=2026&xqm=3&kzlx=ck&xsdm=` （xnm=学年起始年；xqm：3=第1学期/秋，12=第2学期/春，16=第3学期）
  - 返回 JSON：`kbList[]`（有节次的课）、`sjkList[]`（无固定时间的课，如实践/线上）、`xsxx`（学生与学期信息，含 `XNMC`/`XQMC`/`KCMS` 等）
  - `kbList` 元素常用字段：`kcmc` 课程名、`xm` 教师、`cdmc` 教室、`xqj` 星期(1-7)、`jcs` "1-2"（节次起-止）、`jc` "1-2节"、`zcd` 周次文本（如 `1-16周`、`1-15周(单)`、`2-16周(双)`、`1-8周,10-16周`、`3周`）、`kch` 课程号、`jxbmc` 教学班、`xqmc` 校区、`kcxszc`、`sksj`。
  - 学期默认值：课表页 `GET /jwglxt/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default` 里 `<select id="xnm">`/`<select id="xqm">` 的 selected 项即当前学期；拿不到时默认 xnm=2026、xqm=3。
  - 当前周次：正方首页/顶部区域通常含 "第N周" 字样（如 `index_initMenu.html` 或 `xtgl/index_cxAreaSix.html`）；用正则 `第\s*(\d+)\s*周` 尝试解析，解析成功则 `开学日期 = 本周周一 - (N-1)*7 天`；失败则退回默认开学日期，并在导入预览页让用户确认/修改。
- 从这台电脑 curl 学校域名会 SSL 握手失败（校内/网络限制），**不要在本机做联网测试**，用 fixtures 做单元测试；真机由用户验证。
- 旧系统 `cj.shu.edu.cn`（2020 年小爱课程表适配 ZKLlab/ai-schedule-shu）已废弃，不用适配。

### 0.2 上海大学作息（2021-2022 学年起，每天 12 节，官方校历确认）
| 节 | 时间 | 节 | 时间 | 节 | 时间 |
|---|---|---|---|---|---|
| 1 | 08:00–08:45 | 5 | 13:00–13:45 | 9 | 18:00–18:45 |
| 2 | 08:55–09:40 | 6 | 13:55–14:40 | 10 | 18:55–19:40 |
| 3 | 10:00–10:45 | 7 | 15:00–15:45 | 11 | 20:00–20:45 |
| 4 | 10:55–11:40 | 8 | 15:55–16:40 | 12 | 20:55–21:40 |

（1-4 上午，5-8 下午，9-12 晚上；2/4/6/8/10 节后有大课间。）作息必须可在设置里逐节修改、可增减节数、可一键恢复"上海大学默认"。

### 0.3 校历（2025-2026 学年起上大改为两学期制，每学期 18 周 = 16 教学周 + 2 考试周）
- 2026-2027 秋季学期：**2026-09-14（周一）开学**，2027-01-17 结束，共 18 周。
- 2026-2027 春季学期：2027-02-22 开学，2027-06-27 结束，18 周。夏季实践学期 2027-06-28～07-25。
- 内置预设：`SHU 2026 秋 = 2026-09-14 / 18 周`、`SHU 2027 春 = 2027-02-22 / 18 周`；开学日期与总周数都必须允许用户手动改。

### 0.4 本机环境
- Windows 11，Node 22，JDK 17 (Temurin, `D:\MCLDownload\ext\jre-v64-220420\jdk17`)，**无 Flutter、无 Android SDK、无 adb**。代理 `http://127.0.0.1:7897` 可用（HTTP_PROXY/HTTPS_PROXY 已在环境变量中），storage.googleapis.com / dl.google.com / pub.dev / gradle 均可达。
- **C 盘只剩 ~4 GB，D 盘 ~28 GB**：Flutter SDK、Android SDK、Gradle 缓存、Pub 缓存全部放 D 盘（`D:\sdk\flutter`、`D:\sdk\android`、`GRADLE_USER_HOME=D:\sdk\gradle`、`PUB_CACHE=D:\sdk\pub_cache`、`ANDROID_USER_HOME=D:\sdk\android_user`）。
- 有 Hyper-V/虚拟化 → Android 模拟器（WHPX）大概率可用，可用于真实安装 APK 与截图。

## 1. 技术选型（已定）
- **Flutter 3.x（stable）+ Dart**，Android 优先（minSdk 24，targetSdk 35）。理由：单语言、UI 一致可爱、`home_widget` 生态成熟、`flutter build apk` 一条命令出包。
- 依赖：`webview_flutter`（登录+注入 JS）、`home_widget`（桌面小组件）、`shared_preferences` + JSON 文件（path_provider）持久化、`provider` 状态管理、`intl`、`uuid`、`file_picker`/`share_plus`（备份导入导出）、`flutter_launcher_icons`。不要引入需要后端的东西。
- 项目目录：`D:\desk\claudex\12\shu_schedule`（Flutter 工程），包名 `cn.shu.schedule`，应用名「上大课表」。

## 2. 数据模型（所有代理必须遵守的契约，放在 lib/models/）
```dart
class PeriodTime { final int index; final String start; final String end; }          // "08:00"
class ScheduleConfig {
  String name;                 // "2026-2027 秋"
  DateTime startDate;          // 第 1 周周一
  int totalWeeks;              // 18
  List<PeriodTime> periods;    // SHU 默认 12 节
  bool showWeekend;            // 默认 true（周六/周日显示）
}
class Course {
  String id; String name; String? teacher; String? location;
  int day;                     // 1..7，1=周一
  int startPeriod; int endPeriod;   // 含首尾
  List<int> weeks;             // 具体周数列表，如 [1,2,...,16]
  int colorIndex;              // 0..9 → theme.courseColors
  String? note; String source; // 'zfsoft-shu' | 'manual' | 'backup'
}
class Timetable { String id; String name; ScheduleConfig config; List<Course> courses; }
class AppSettings { String currentTimetableId; String themeId; bool showNonCurrentWeekCourses; bool showTimeInGrid; }
```
- 所有模型有 `toJson/fromJson`；持久化为 `timetables.json` + `settings.json`（应用文档目录）；写入后同步刷新小组件数据（见 §4）。
- 工具函数（lib/core/schedule_utils.dart）：`weekOf(DateTime now, config)`、`coursesOn(date)`、`nextCourse(now)`、`periodRange(config, start, end) -> (startTime,endTime)`、周次文本解析 `parseWeeksText("1-16周(单)") -> List<int>`。

## 3. 功能范围（v1 必做）
1. **周课表页**：顶部学期/周次（可左右滑动切换周、点击跳周）、左侧节次+时间列、7 列（可隐藏周末）、课程块（课程名/地点/教师层级、圆角、主题色）、今天列高亮、当前时刻横线、非本周课程半透明可开关、点击课程块弹详情（编辑/删除）。
2. **今日页 / 下节课卡片**：今天课程列表、距离下一节课倒计时。
3. **导入**：`导入 → 选择学校（v1 只有"上海大学"，列表结构预留其他学校）→ WebView 打开 jwxt.shu.edu.cn 登录 → 登录后底部浮出「一键导入」按钮 → 注入 JS 抓取 → 解析 → 预览页（课程列表、检测到的学期/周次、开学日期可改）→ 确认（覆盖当前课表 / 新建课表）`。失败要有清楚的提示（未登录、接口变化、解析为空）。
4. **手动添加/编辑课程**：课程名、教师、地点、星期、节次范围、周次（全周/单/双/自定义多选）、颜色。
5. **设置**：作息表编辑（逐节改时间、增删节、恢复 SHU 默认）、开学日期、总周数、是否显示周末、主题选择、多课表管理（新建/切换/重命名/删除）、备份导出/导入（JSON 文件）、关于页。
6. **主题**：读取 `design/themes.json`（复制到 assets），6 套主题（含深色），课程块 10 色轮换，可选背景插画；主题切换即时生效，小组件跟随主题色。
7. **桌面小组件（Android AppWidget，home_widget）**：
   - 「今日课程」4x2（可拉伸）：原生 RemoteViews 渲染（不依赖 Flutter 运行），显示日期/周次 + 今日课程行（时间、名称、地点），下一节高亮，无课显示可爱空状态文案；每天 0 点及每 30 分钟刷新（AlarmManager/updatePeriodMillis）。
   - 「本周课表」4x4：Flutter 端 `renderFlutterWidget` 渲染成 PNG 交给原生 ImageView；在 App 打开、数据/主题变化时重绘。
   - 点击小组件打开 App。
8. **打包**：`flutter build apk --release`（先 debug 验证），产出 `build/app/outputs/flutter-apk/app-release.apk`，同时复制到 `D:\desk\claudex\12\dist\上大课表-vX.Y.Z.apk`。

v2 预留（不做但结构上留口）：iOS、其他学校适配（正方通用适配器已参数化：base URL 不同即可）、ICS 导出、课前提醒、WebDAV 同步。

## 4. 模块与接口约定
- `lib/models/`：§2 模型（Agent T 建骨架，B1 完善）。
- `lib/core/`：存储 `Storage`、`ScheduleUtils`、`ThemeRegistry`（从 assets/themes.json 加载 → `AppTheme` → `ThemeData`）。
- `lib/features/timetable/`（B1）：周视图、今日视图、课程详情/编辑。
- `lib/features/settings/`（B1）：设置页、作息编辑、主题选择、课表管理、备份。
- `lib/features/import/`（B2）：
  ```dart
  abstract class SchoolAdapter { String get id; String get name; String get loginUrl; bool isLoggedIn(String currentUrl); String get scrapeScript; ImportResult parse(String rawJsonFromPage, {DateTime? now}); }
  class ImportResult { List<Course> courses; List<Course> unscheduled; String? termName; DateTime? detectedStartDate; int? detectedCurrentWeek; List<String> warnings; }
  class ZfsoftAdapter implements SchoolAdapter { ZfsoftAdapter({required id, name, baseUrl}); }  // SHU = ZfsoftAdapter(id:'shu', name:'上海大学', baseUrl:'https://jwxt.shu.edu.cn/jwglxt')
  class ImportFlowPage extends StatefulWidget { /* 学校选择→WebView→导入→预览→回调 onImported(ImportResult, mode) */ }
  ```
  对外只暴露 `ImportFlowPage` 与 `SchoolRegistry.all`。解析器必须有基于 fixtures 的单元测试（构造 5+ 条真实格式的 kbList 样例，覆盖单双周、多段周次、跨节次、周末课、无 cdmc）。
- `lib/features/widgets/`（B3）：`WidgetSync.push(Timetable, AppTheme)`：写入 home_widget 共享数据（JSON 快照：今后 14 天每天的课程列表+主题色）并触发更新、渲染周表 PNG；Android 原生代码在 `android/app/src/main/kotlin/cn/shu/schedule/widgets/`（`TodayWidgetProvider.kt`、`WeekWidgetProvider.kt`、layouts、`res/xml/*_info.xml`）；`AndroidManifest.xml` 的 receiver 声明只由 B3 改。
- `lib/main.dart`、路由、导航壳（B1 拥有）；B2/B3 只提供入口 Widget/函数，不改 main.dart（集成由 Phase 3 代理做）。
- `pubspec.yaml`：Agent T 一次性声明全部依赖；后续如需新增依赖，在 `NOTES.md` 记录再加。

## 5. 执行阶段
- **Phase 1（并行）**：Agent T 安装工具链 + 脚手架 + 模型/存储骨架 + `flutter build apk --debug` 通过；Codex 出主题（design/）。
- **Phase 2（并行，各自只碰自己的目录）**：B1 UI + 设置 + 主题；B2 导入；B3 小组件。
- **Phase 3**：集成代理接线（main.dart、导入回调、WidgetSync 调用点）、`flutter analyze` 零错误、`flutter test` 通过、release APK、（若模拟器可用）安装并截图、写 README（用户使用说明 + 已知限制）。
- **Phase 4**：code-review 代理审查关键风险（解析健壮性、存储损坏恢复、WebView 安全），修复后重新出包。

## 6. 验收标准
- 冷启动无课表时有引导（导入 / 手动添加）。
- 解析单元测试覆盖 §0.1 列出的所有 zcd 格式；周次/节次/星期越界不崩溃。
- 设置里改作息后周表与小组件同步变化。
- `flutter analyze` 无 error；release APK 可生成；APK ≤ 40 MB。
- 输出：`dist/*.apk`、`README.md`（安装方法、导入步骤、常见问题）、截图若干。
