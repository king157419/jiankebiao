# NOTES —— Agent T（Phase 1：工具链 + 脚手架）

记录本阶段做的决定、与 PLAN 的偏差、以及留给 Phase 2/3 的已知问题。

---

## 1. 与 PLAN 的偏差（都是被环境逼的，不是随手改的）

### 1.1 SDK 根目录 `D:\sdk` → `D:\desk\sdk`
`D:\` 盘根的 ACL 只给 `Everyone = ReadAndExecute`，非管理员建不了 `D:\sdk`
（PowerShell 与 Git Bash 都是 Access denied）。整套 SDK 改放可写的 `D:\desk\sdk\`。
同样落在 D 盘，C 盘一个字节都没占。
要改回去需要管理员权限，改完同步改 `env.sh` 的 `SDK_ROOT` + `_SDK_POSIX` 和 `env.ps1` 的 `SDK_ROOT`。

### 1.2 `compileSdk` 35 → **36**（targetSdk / minSdk 不变）
两件事叠在一起：
1. Flutter 3.47.4 的 `flutter doctor` 硬要求 Android SDK 36，只装 35 就是黄叹号。
   于是额外装了 `platforms;android-36` + `build-tools;36.1.0`。
2. 更硬的约束：**第一次 `flutter build apk --debug` 直接 BUILD FAILED**，原因是
   `:webview_flutter_android`、`androidx.core:core:1.18.0`、`androidx.core:core-ktx:1.18.0`
   都要求依赖方 `compile against version 36 or later of the Android APIs`，
   而 `:app is currently compiled against android-35`。

所以 `android/app/build.gradle.kts` 里 `compileSdk = 36`。
**`targetSdk = 35` 和 `minSdk = 24` 仍然是 PLAN §1 要求的值**（写死数字，
不用 `flutter.compileSdkVersion` / `flutter.targetSdkVersion`）。
compileSdk 只决定「能用哪些 API 编译」，targetSdk 才决定运行时行为，
所以这个偏差不改变 PLAN 承诺的兼容性范围。

### 1.3 Flutter 版本
PLAN 说「Flutter 3.x stable」。当前 stable 是 **3.47.4（Dart 3.13.3）**，已按此安装。

---

## 2. 设计决定

### 2.1 日期运算一律不用 `Duration(days:)`
本机时区是 **Mountain Standard Time（有夏令时）**，不是 Asia/Shanghai。
写完第一版后 `flutter test` 立刻炸出来：
`mondayOfWeek(config, 18)` 期望 `2027-01-11 00:00`，实际得到 `2027-01-10 23:00`。
原因是 `DateTime.add(Duration(days: 119))` 加的是绝对时长，跨夏令时会错位一小时。

**契约（Phase 2/3 请遵守）**：
- 加减天数用 `ScheduleUtils.addDays(date, n)`（内部是 `DateTime(y, m, d + n)`）。
- 算天数差用 `ScheduleUtils.daysBetween(from, to)`（内部 UTC 归一化）。
- 不要写 `.add(Duration(days: n))`、`.subtract(Duration(days: n))`、`.difference(x).inDays`。

`test/schedule_utils_test.dart` 有一条「跨夏令时也不会错位（回归测试）」在盯着，
遍历 18 周 × 7 天检查 `hour == 0` 且 `weekday` 正确。

### 2.2 `weekOf` vs `rawWeekOf`
PLAN §2 只列了 `weekOf`。实现拆成两个，因为 UI 和逻辑要的语义不一样：
- `rawWeekOf(date, config)`：不裁剪。开学当周 = 1，开学前是 0 / 负数，学期后可以 > totalWeeks。
  **课程过滤必须用这个**（否则开学前会错误地显示第 1 周的课）。
- `weekOf(date, config)`：裁剪到 `[1, totalWeeks]`，直接喂给「当前第 N 周」这类 UI。
另有 `isDuringTerm(date, config)` 判断是否在学期内 —— 冷启动引导页可以用。

### 2.3 `ScheduleConfig.startDate` 自动对齐到周一
构造器里做了 `_mondayFloor`：用户/导入给的任何日期都会向前对齐到当周周一，并清掉时分秒。
这样 `dateOf(config, 1, 1) == config.startDate` 永远成立，周次计算不会因为
「用户填了周三」而整体偏移。
**副作用**：设置页里显示开学日期时，显示的是对齐后的周一，不是用户原样输入的那天。
如果 Phase 2 觉得这会让用户困惑，改成在 UI 层提示「已对齐到本周周一」，
不要去掉构造器里的对齐。

### 2.4 `parseWeeksText` 的单双周语义：**按段生效，不是全局**
`1-4周,6-8周(双)` → `[1,2,3,4,6,8]`（`(双)` 只作用于 `6-8` 这一段）。
这是正方 `zcd` 字段的实际语义。解析器还做了这些归一化：
全角 `，（）`、`~`/`～`/`—`/`–`/`至`/`到` 当连字符、去掉 `第`/`周`/空白、
`1-5周单` 这种不带括号的写法、`8-5周` 反序自动交换、
`1-9999周` 裁剪到 `ScheduleUtils.maxWeek = 60`、非法文本返回空列表。

配套还有 `formatWeeksText(List<int>)` 做反向压缩（`[1,2,3,5]` → `1-3,5周`），
供课程编辑页 / 详情页显示，和 `parseWeeksText` 互逆（有测试）。

### 2.5 `Storage` 的损坏恢复策略
PLAN 要求「损坏文件要能回退到默认而不是崩溃」。具体做法：
- 读：任何异常（文件不存在 / 空文件 / 非法 JSON / 顶层类型不对）都返回默认值，
  并把问题塞进 `StorageSnapshot.warnings`（`AppState.warnings` 暴露给 UI）。
- 损坏的文件**不会被直接覆盖**，而是改名成 `timetables.json.corrupt-<毫秒时间戳>` 保留现场。
- 单条课表解析失败只跳过那一条，不整个丢弃。
- 写：先写 `*.tmp` 再 `rename`，避免断电/闪退留下半截 JSON。
- `currentTimetableId` 指向不存在的课表时，load 时自动修正成第一张。

测试可以通过 `Storage.overrideDirectory = <临时目录>` 绕开 `path_provider`
（单测环境里没有平台通道，`getApplicationDocumentsDirectory()` 会抛）。

另外提供了 `Storage.exportJson` / `Storage.importJson` 给备份功能用
（格式：`{version, exportedAt, timetables, settings}`，非法输入抛 `FormatException`）。

### 2.6 模型的「脏数据不崩溃」约定
所有 `fromJson` 都做了类型防御：字段缺失/类型不对时回退默认值，
`day` 裁剪到 1..7，`colorIndex` 裁剪到 0..9，`endPeriod < startPeriod` 时修正为等于 `startPeriod`，
`weeks` 自动去重升序并丢掉非正数。
导入解析器（B2）可以放心把脏数据丢进 `Course.fromJson`。

### 2.7 `AppState` 每次变更后自动 save
所有写方法内部走 `_commit()` = `notifyListeners()` + `await save()`。
调用方不需要手动 save。
**Phase 3 接线 `WidgetSync.push` 时，挂在 `_commit()` 里最省事** —— 但注意那会让每次
改颜色都触发小组件重绘，可能需要防抖。

---

## 3. 已知问题 / 留给后续阶段

1. **`lib/main.dart` 是占位页**，只显示课表名 / 第 N 周 / 课程数 / 节数 + 一个「新建课表」按钮。
   PLAN §4 说 main.dart 归 B1 所有，Phase 2 会整体替换。
2. **`assets/themes/`、`assets/images/` 目前是空目录 + `.gitkeep`**，
   已在 `pubspec.yaml` 的 `flutter.assets` 里声明。
   Codex 的 `design/themes.json` 还没复制进来 —— Phase 2 (B1) 负责复制并写 `ThemeRegistry`。
   注意：Flutter 的目录型 asset 声明不会递归，只收该目录下一层的文件。
3. **`flutter_launcher_icons` 已装但没配置**，`pubspec.yaml` 里还没有 `flutter_launcher_icons:` 段，
   图标还是 Flutter 默认的。等 Codex 出了图标再配 + 跑 `dart run flutter_launcher_icons`。
4. **`lib/features/{timetable,settings,import,widgets}` 是空目录**，按 PLAN §4 预留。
5. **模拟器没有实际启动验证过**，只装好了 `emulator` + `system-images;android-35;google_apis;x86_64`。
   首次启动若报 WHPX 错误，见 `TOOLCHAIN.md` §3。
6. **release 签名还是 debug key**（`flutter create` 的默认 TODO 没动）。
   PLAN §3.8 只要求出 APK 给用户自己装，debug key 够用；
   若以后要上架再补 keystore。
7. **依赖版本**（pub.dev 当前最新稳定版，`flutter pub add` 解析结果）：
   ```
   webview_flutter ^4.14.1   home_widget ^0.9.4       shared_preferences ^2.5.5
   path_provider ^2.1.6      provider ^6.1.5+1        intl ^0.20.3
   uuid ^4.6.0               file_picker ^13.1.0      share_plus ^13.3.0
   dev: flutter_lints ^6.0.0  flutter_launcher_icons ^0.14.4
   ```
   `flutter pub outdated` 报 9 个包有更新但被约束挡住 —— 都是 Flutter SDK 自己钉死的
   传递依赖（meta / test_api / vector_math 等），不用管。
   **按 PLAN §4：后续要加依赖，先在本文件记一笔再加。**
8. **`file_picker` 在 Windows 桌面端拉了 `windows_file_picker`**，Android 打包不受影响。
9. **`home_widget` 会触发 KGP 弃用警告**（不影响构建）：
   ```
   WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): home_widget
   Future versions of Flutter will fail to build if your app uses plugins that apply KGP.
   ```
   现在只是 warning，将来 Flutter 版本会变成 error。B3 做小组件时留意 `home_widget`
   有没有出「Built-in Kotlin」版本；真被卡住时的兜底是自己写 AppWidget + MethodChannel。
10. **debug APK 有 164 MB**（含 arm64-v8a / armeabi-v7a / x86_64 三套 native code + 调试符号）。
    PLAN §6 要求 release APK ≤ 40 MB —— release 会 strip 掉调试信息，应该没问题，
    实在超了就用 `flutter build apk --release --split-per-abi`。**release 包尚未构建验证。**
11. **D 盘空间告急**：装完整套工具链后从 27 GB 掉到约 14 GB。
   安装包 zip 已删。真的不够用时可以删 `D:\desk\sdk\android\system-images`
   （3.5 GB，放弃模拟器改用真机）或 `D:\desk\sdk\gradle\caches`（会重新下载）。

---

## 4. 验收状态（真实跑过的结果，2026-09-16）

| 项 | 命令 | 结果 |
|---|---|---|
| doctor | `flutter doctor` | **全绿，No issues found!**（8 项全 √） |
| 静态检查 | `flutter analyze` | **No issues found!**（零 error 零 warning） |
| 单元测试 | `flutter test` | **49 passed, 0 failed** |
| debug 包 | `flutter build apk --debug` | **成功**，`build/app/outputs/flutter-apk/app-debug.apk` 164 MB |
| release 包 | `flutter build apk --release` | **未跑过**，Phase 3 验证 |
| 模拟器 | `emulator -avd ...` | **未跑过**，镜像已装 |

APK 元信息（`aapt2 dump badging` 实测）：
```
package: name='cn.shu.schedule' versionCode='1' versionName='1.0.0' compileSdkVersion='36'
minSdkVersion=24   targetSdkVersion=35
application-label:'上大课表'
uses-permission: android.permission.INTERNET
native-code: 'arm64-v8a' 'armeabi-v7a' 'x86_64'
```
（WAKE_LOCK / ACCESS_NETWORK_STATE / RECEIVE_BOOT_COMPLETED / FOREGROUND_SERVICE
是 `home_widget` 等插件自己 merge 进来的，不是我们声明的。）

第一次 Gradle 构建（含下载 Gradle 9.3.1 + 全部 Maven 依赖，走代理）约 **19 分钟**；
缓存热起来之后重新构建约 **3.3 分钟**。

---

## 5. 本阶段产出文件

```
D:\desk\claudex\12\
├── env.sh                      # Bash 环境变量
├── env.ps1                     # PowerShell 环境变量
├── TOOLCHAIN.md                # 工具链手册
├── NOTES.md                    # 本文件
└── shu_schedule\               # Flutter 工程
    ├── pubspec.yaml            # 依赖 + assets 声明
    ├── lib\
    │   ├── main.dart           # 占位最小页（B1 会替换）
    │   ├── models\             # period_time / schedule_config / course / timetable / app_settings
    │   ├── core\               # presets / schedule_utils / storage / app_state
    │   └── features\           # timetable / settings / import / widgets（空目录，Phase 2 填）
    ├── test\
    │   ├── schedule_utils_test.dart    # parseWeeksText / weekOf / periodRange / coursesOn / nextCourse
    │   └── models_test.dart            # 模型往返 + 脏 JSON + Storage 损坏恢复
    ├── assets\themes\.gitkeep
    ├── assets\images\.gitkeep
    └── android\                # applicationId cn.shu.schedule，label「上大课表」，INTERNET 权限
```

---

# B3 记录（Phase 2：Android 桌面小组件）

## 1. 产出文件

```
lib/features/widgets/
├── widget_palette.dart     # WidgetPalette（小组件自己的调色板，含 fallback()）
├── widget_sync.dart        # WidgetSync.push / buildSnapshot（导出 WidgetPalette、WeekGridImage）
├── week_grid_image.dart    # WeekGridImage：离屏渲染成 PNG 的紧凑周网格
└── demo_timetable.dart     # 6 门课的示例课表，只给自测按钮用（Phase 3 可删）

android/app/src/main/
├── kotlin/cn/shu/schedule/widgets/
│   ├── WidgetSnapshot.kt        # 快照 JSON 解析 + WidgetPalette（Kotlin 侧）
│   ├── ShuWidgetProvider.kt     # 公共基类 + RemoteViews 工具函数
│   ├── TodayWidgetProvider.kt   # 4x2「今日课程」
│   └── WeekWidgetProvider.kt    # 4x4「本周课表」
├── res/layout/widget_today.xml / widget_today_preview.xml
├── res/layout/widget_week.xml  / widget_week_preview.xml
├── res/drawable/widget_bg_rounded.xml
├── res/xml/today_widget_info.xml / week_widget_info.xml
├── res/values/strings.xml       # 小组件 label / description / 空状态文案
└── AndroidManifest.xml          # 两个 receiver + MainActivity 的 LAUNCH intent-filter

test/widgets/widget_sync_test.dart  # 15 条
```

**没有加新依赖**，`pubspec.yaml` 未改动（`home_widget ^0.9.4` Agent T 已装好）。

## 2. 数据契约

Flutter 把两份数据写进 home_widget 的 `HomeWidgetPreferences`：

| key | 内容 |
|---|---|
| `snapshot` | JSON 字符串：`{version, generatedAt, timetableName, termName, totalWeeks, palette{…#RRGGBB}, periods[], days[14]}`。`days[i] = {date:"2026-09-16", weekday:1..7, week:N 或 null(假期), courses:[{name,location,teacher,startPeriod,endPeriod,start:"08:00",end:"09:40",color:"#RRGGBB"}]}`，课按开始节次升序。 |
| `week_image` | 本周课表 PNG 的绝对路径（`renderFlutterWidget` 自己写的，360×360 逻辑尺寸 / pixelRatio 2 → 720×720）。 |

原生端只读这两个 key，**不认识任何 Dart 类型**；改快照结构时同步改 `WidgetSnapshot.kt`，并把 `WidgetSync.snapshotVersion` +1。

## 3. Phase 3 接线（必读）

### 3.1 AppTheme → WidgetPalette
`WidgetPalette` 是小组件自己的小类，故意不依赖 B1 的 `AppTheme`。接线时写一个映射函数，字段一一对应 `design/themes.json`：

```dart
WidgetPalette paletteFromTheme(AppTheme t) => WidgetPalette(
  background: t.colors.background,
  surface: t.colors.surface,          // 必须不透明！小组件面对任意壁纸
  text: t.colors.onSurface,
  mutedText: t.colors.onSurfaceMuted,
  accent: t.colors.accent,
  todayHighlight: t.colors.todayHighlight,
  isDark: t.isDark,
  courseColors: WidgetPalette.normalizeCourseColors(t.courseColors), // 补齐到 10 个
  courseTextOnBlock: t.courseTextOnBlock,
);
```
拿不到主题时用 `WidgetPalette.fallback()`（= themes.json 的「樱花粉」），小组件永远有可读配色。

### 3.2 调用时机
`WidgetSync.push(timetable, palette)` 建议在这些点调用：
- **App 启动后**（`main()` 里 `state.load()` 之后，await 不阻塞首帧就行）；
- **课表数据变更后**（导入完成、增删改课程、切换当前课表）；
- **作息 / 开学日期 / 总周数变更后**（小组件里的时间文本由快照里的 `start`/`end` 决定）；
- **主题切换后**（整份 palette 都要重推）。

NOTES §2.7 提到 `AppState._commit()` 是最省事的挂点，但**必须防抖**：改颜色、拖拽这类操作会连续触发，而 `renderFlutterWidget` 每次都要离屏渲染 + 写 PNG（实测 720×720 约 50 KB）。建议：

```dart
Timer? _widgetDebounce;
void _scheduleWidgetPush() {
  _widgetDebounce?.cancel();
  _widgetDebounce = Timer(const Duration(milliseconds: 800), () {
    WidgetSync.push(currentTimetable!, paletteFromTheme(currentTheme));
  });
}
```
`push` 自己吞掉所有异常并返回 bool，**不需要在调用点再 try/catch**，也不会让 App 崩。没有课表时不要调用（传 null 会 NPE，调用方自己判空）。

### 3.3 main.dart 里的临时按钮
占位 main.dart 里加了三个自测按钮：「推送示例数据到小组件」「把「今日课程」钉到桌面」「把「本周课表」钉到桌面」（后两个走 `HomeWidget.requestPinWidget`）。Phase 3 重写 main.dart 时删掉；如果想保留调试入口，挪到设置页的「关于/调试」里即可。

## 4. 模拟器验证结果（真的跑过，2026-09-16）

AVD `shu35`（pixel_6 / android-35 google_apis x86_64），`-gpu swiftshader_indirect`，全程 adb 自动化：

| 验证项 | 结果 | 截图 |
|---|---|---|
| APK 安装 + 两个 receiver 注册 | 通过（`dumpsys package` 能看到两个 provider） | — |
| 点「推送示例数据」→ 写入 snapshot + week_image.png | 通过（`run-as cat shared_prefs/HomeWidgetPreferences.xml` 验证） | — |
| 周表 PNG 内容 | 720×720，周次胶囊/日期范围/今天列高亮/课程块配色/周末自动隐藏都正确 | `shots/b3/week_image.png` |
| 「今日课程」真实贴在桌面 | 通过：头部「9月16日 周三 / 第 1 周」，两行课，**下一节「数据结构」accent 高亮** | `shots/b3/shot_widget_today.png` |
| 「本周课表」真实贴在桌面 | 通过：整张 PNG 正常显示，圆角 + 白底 | `shots/b3/shot_widget_week.png` |
| 点击小组件打开 App | 通过（logcat 有 `START … act=es.antonborri.home_widget.action.LAUNCH`，焦点窗口变成 MainActivity） | — |
| 无课空状态 | 通过：把设备日期改到 2026-09-20（周日）再触发刷新 → 「今天没有课，去玩吧 ✨」 | `shots/b3/shot_empty.png` |
| 快照缺失 | 通过：`pm clear` 后 → 「打开 App 刷新课表」 | `shots/b3/shot_norefresh_crop.png` |
| 小组件选择器预览 + 中文 label/description | 通过 | `shots/b3/shot_preview.png` |

> 跨天刷新那条路径是**真的验证过**的：用 `am broadcast -a cn.shu.schedule.action.DAILY_REFRESH -n cn.shu.schedule/.widgets.TodayWidgetProvider` 走的就是 AlarmManager 会发的那个 Intent。

模拟器结束后已 `adb emu kill`，AVD 保留（删掉了 `snapshots/` 目录回收 2.6 GB，下次是冷启动，约 1 分钟开机）。

## 5. 踩过的坑 / 已知限制

1. **`am broadcast -a android.appwidget.action.APPWIDGET_UPDATE` 发不出去**：它是 protected broadcast，shell 会 `SecurityException: not allowed to send broadcast … from unknown caller`。所以自己定义了 `cn.shu.schedule.action.DAILY_REFRESH`（非 protected，shell 可发）。
2. **`AppWidgetProvider.onReceive` 不带 `EXTRA_APPWIDGET_IDS` 就不会调 `onUpdate`**。AlarmManager 广播和 adb 广播都带不了 id，于是 `ShuWidgetProvider.onReceive` 自己 `getAppWidgetIds(ComponentName)` 补上再转发。没有这段的话定时刷新完全不生效，而且**一点报错都不会有**。
3. **RemoteViews 不支持 `<View>`**（只允许 `@RemoteView` 注解过的类：LinearLayout / FrameLayout / RelativeLayout / GridLayout / TextView / ImageView / Button / ProgressBar / …）。课程色条改用宽 4dp 的空 `TextView`。
4. **`<include>` 复用行布局会导致子 View id 冲突**（6 个 include 里都是 `row_time`，`setTextViewText` 分不清）。所以 6 行是展开写死的 `row_0..row_5`，id 各自独立。
5. **圆角 + 主题色不能兼得（低版本）**：底板是 `widget_bg_rounded.xml`（纯色 shape + 24dp 圆角），运行时着色在 API 31+ 用 `RemoteViews.setColorStateList(id,"setBackgroundTintList",…)` 保留圆角；API < 31 没这个方法，回退成 `setInt("setBackgroundColor")`，**圆角会丢**（Android 11 及以下的启动器本来也不做圆角裁切，影响很小）。
6. **`previewLayout` 直接指真实布局会是一片空白**：真实布局默认把 6 行课程都设成 `gone`（等 Kotlin 填）。单独写了 `widget_today_preview.xml` / `widget_week_preview.xml` 放静态示例内容。
7. **不申请精确闹钟权限**：跨天刷新用 `setInexactRepeating(RTC, 次日00:00:30, INTERVAL_DAY)`。课表晚几分钟换天无所谓，不值得为 `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` 增加权限和上架风险。`updatePeriodMillis` 也已经是系统最小值 30 分钟。
8. **周表图片只在 App 打开 / 数据变更时重绘**（`renderFlutterWidget` 必须有 Flutter 引擎）。后果：跨天之后「本周课表」里的今天高亮列要等下一次 `WidgetSync.push` 才会移动；跨周之后显示的还是上周。可接受，但 Phase 3 记得在 App 启动时无条件 push 一次。
9. **`Color.value` 已废弃**，用 `toARGB32()`；`withOpacity` 已废弃，用 `withValues(alpha:)`。
10. **模拟器磁盘**：`avdmanager create` 默认 `disk.dataPartition.size=10G`，D 盘只剩 9 GB 时直接 `FATAL | Not enough space to create userdata partition`。改 `shu35.avd/config.ini` 的 `disk.dataPartition.size=2048M` 才能启动（命令行 `-partition-size` 上限是 2047，给 2048 会报错）。另外 `avdmanager` 在 Git Bash 里要写全名 `avdmanager.bat`，路径参数要 `MSYS_NO_PATHCONV=1` 否则 `/data/...` 会被翻译成 `D:/Git/data/...`。
11. **日期一律走 `ScheduleUtils.addDays` / `rawWeekOf`**（NOTES §2.1）。快照里的 14 天就是这么生成的，测试里有一条开学前（week=null）的用例盯着。

## 6. 待加依赖

无。

---

# B2 记录（Phase 2：从上海大学教务系统一键导入）

产出目录：`lib/features/import/`（adapters + pages）与 `test/import/`。
**没有改动** `main.dart`、`pubspec.yaml`、`android/`、`lib/models/`、`lib/core/`。

## B2.1 公开入口（Phase 3 只需要认这两个）

```dart
import 'package:shu_schedule/features/import/pages/import_flow_page.dart';
import 'package:shu_schedule/features/import/adapters/school_registry.dart';

ImportFlowPage()            // 整条导入流程的入口页（StatelessWidget）
ImportFlowPage.routeName    // '/import'
SchoolRegistry.all          // List<SchoolAdapter>，目前只有上海大学
```

其余类型（`SchoolAdapter` / `ImportResult` / `ImportException` / `ZfsoftAdapter`）
在 `adapters/school_adapter.dart`、`adapters/zfsoft_adapter.dart`，UI 层不需要直接用。

内部结构：

```
lib/features/import/
├── adapters/
│   ├── school_adapter.dart      # SchoolAdapter / ImportResult / ImportException / ImportStage
│   ├── zfsoft_adapter.dart      # 正方通用适配器 + 注入脚本模板 + 解析器
│   └── school_registry.dart     # SchoolRegistry.all / byId / search
└── pages/
    ├── import_flow_page.dart    # 入口（= SchoolSelectPage）
    ├── school_select_page.dart  # 学校列表 + 搜索框 + 说明文案
    ├── web_login_page.dart      # WebView 登录 + 一键导入 + 进度/错误
    └── import_preview_page.dart # 预览、勾选、改开学日期/总周数、覆盖 or 新建
```

## B2.2 Phase 3 接线说明

1. **路由注册**（`lib/app.dart` 或 `main.dart`，B1 的文件）：
   ```dart
   routes: {
     ImportFlowPage.routeName: (_) => const ImportFlowPage(),
   }
   ```
   然后从空状态引导页 / 设置页 `Navigator.pushNamed(context, ImportFlowPage.routeName)`。
   直接 `Navigator.push(MaterialPageRoute(builder: (_) => const ImportFlowPage()))` 也行。

2. **必须有 `ChangeNotifierProvider<AppState>` 在上层**。
   预览页确认时用 `context.read<AppState>()` 写数据，没有 Provider 会直接抛
   `ProviderNotFoundException`。

3. **导航栈约定**：确认导入后调用 `Navigator.popUntil((r) => r.isFirst)` 回到首页，
   再弹 SnackBar「已导入 N 门课程」。所以 `ImportFlowPage` 必须是从首页 push 出去的，
   不要把它塞进 BottomNavigationBar 的某个 tab 里当常驻页面。

4. **写入语义**（与 `AppState` 的契约）：
   - 覆盖：`replaceCourses(tt.id, courses)` + `updateConfig(tt.config.copyWith(name, startDate, totalWeeks))`。
     **只改这三项**，作息表 `periods`、`showWeekend`、主题、课表 `Timetable.name` 都不动。
   - 新建：`createTimetable(name, config: ScheduleConfig(..., periods: shuDefaultPeriods))`
     （createTimetable 内部已经 add + 切换）再 `replaceCourses`。
   - 当前一张课表都没有时，「覆盖」选项自动禁用并强制走「新建」。
   - `AppState._commit()` 自己会 save，导入流程不额外调 `save()`。
   - 如果 Phase 3 把 `WidgetSync.push` 挂在 `_commit()` 上，注意一次导入会触发 3~4 次
     commit（createTimetable / replaceCourses / updateConfig），需要防抖。

5. **不需要新依赖**。只用了已有的 `webview_flutter ^4.14.1` 和 `provider`。

## B2.3 技术要点（改代码前先看这段）

- **必须用 JavaScriptChannel 回传，不能用 `runJavaScriptReturningResult`**：
  注入脚本里的 `fetch` 是异步的，`runJavaScriptReturningResult` 只会拿到 `undefined`。
  脚本通过 `ShuImport.postMessage(JSON.stringify({...}))` 回传，
  通道名常量是 `importChannelName`（`ShuImport`），Dart 侧 `addJavaScriptChannel` 注册。
- **脚本用 Promise 链，不用 async/await**：minSdk 24 对应的老 Android System WebView
  （Chrome 51）不支持 async/await。同理脚本里的中文全部写成 `\uXXXX` 转义，
  避免经过 `runJavaScript` 时的编码问题。
- **脚本回传两种消息**：
  - 进度：`{"progress":true,"stage":"index|week|kb"}` → 只更新底部文案；
  - 终态：`{"ok":true,"stage":"done","data":{...}}` 或 `{"ok":false,"stage":"...","error":"..."}`。
  错误里用哨兵字符串 `__LOGIN__` / `__NOTJSON__`，Dart 侧翻译成中文提示 + 处理建议。
- **抓取顺序**（对应 PLAN §0.1）：
  1. `GET /kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default`
     → 读 `<select id="xnm">`/`<select id="xqm">` 的 `option[selected]`；
     顺便当登录检测（返回登录页 HTML 就直接失败）。读不到就按日期推断
     （9 月及以后取今年，否则去年；xqm 默认 3）。
  2. `GET /xtgl/index_initMenu.html`、`GET /xtgl/index_cxAreaSix.html?localeKey=zh_CN&gnmkdm=index`
     → 正则 `第\s*(\d+)\s*周`。失败不致命。
  3. `POST /kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N2151`，表单 `xnm&xqm&kzlx=ck&xsdm=`，
     `credentials:'include'`，`Content-Type: application/x-www-form-urlencoded;charset=UTF-8`。
     返回不是 JSON 就识别登录页并报「未登录/会话失效」。
  脚本内 30 秒超时，Dart 侧再兜底 40 秒。
- **开学日期推断**：拿到第 N 周 → `detectedStartDate = 本周周一 - (N-1)*7 天`，
  全程用 `ScheduleUtils.addDays`（遵守 NOTES §2.1 的「不用 Duration(days:)」契约）。
  拿不到 → 用 `shuTermPresets` 里离今天最近的预设，并写一条 warning。
- **颜色索引**：`ZfsoftAdapter.colorIndexFor(课程名)`，FNV-1a 32 位哈希 % 10。
  与平台/运行次数无关，重装 App、重新导入颜色都一样。
- **登录判定**：`host == jwxt.shu.edu.cn` 且 `path` 含 `/jwglxt/` 且不含 `login`。
  `newsso.shu.edu.cn` 一律视为未登录（用户自己在 WebView 里过二次验证）。
  判定失败也有兜底：底部永远有「我已登录，直接导入」次级按钮。
- **合并规则**：`课程名|教师|地点|星期|起节|止节` 完全相同的多条 `kbList` 记录合并周次
  （正方会把 `1-8周` 和 `10-16周` 拆成两条）。
- **脏数据一律跳过 + 写 warning**，不抛异常：缺 `kcmc`、`xqj` 不在 1..7、
  `jcs`/`jc` 都解析不出数字、`zcd` 解析出空周次列表。

## B2.4 真机验证清单（第一次导入时请按顺序看）

1. 首页 →「导入课表」→ 选「上海大学」→ WebView 打开 `jwxt.shu.edu.cn`，
   应当自动跳到 `newsso.shu.edu.cn` 的统一身份认证页。
2. 登录（含手机/企业微信二次验证）。**登录成功的标志**：AppBar 副标题的域名
   从 `newsso.shu.edu.cn` 变回 `jwxt.shu.edu.cn`，底部按钮从灰色提示变成
   蓝色的「一键导入课表」。若域名对了但按钮没变，直接点「我已登录，直接导入」。
3. 点导入后底部依次显示：正在打开课表查询页 → 正在识别当前周次 → 正在请求个人课表
   → 正在解析课程数据。**任何一步卡住超过 40 秒会弹「抓取超时」对话框。**
4. 预览页要逐项核对：
   - 顶部学生姓名是不是你本人（不是就说明登的是别人的号）；
   - 学期名（如「2026-2027 秋」）与教务系统显示的一致；
   - 「教务系统显示当前第 N 周」与实际一致；如果显示「未自动识别到周次」，
     **一定要手动改开学日期**（点那一行开 DatePicker，选任意一天会自动对齐到周一）；
   - 总周数默认 18，上大两学期制正常就是 18；
   - 课程数量与教务网页上的一致；抽查 2~3 门的星期/节次/周次/教室/教师；
   - 展开「N 条提醒」看有没有课被跳过 —— **被跳过的课需要手动补录**；
   - 展开「N 门没有固定时间的课」（实践/线上课），这些不会进网格。
5. 选「覆盖当前课表」还是「新建课表」→ 确认 → 应当回到首页并提示「已导入 N 门课程」。
6. 回周课表页核对：本周显示的课、单双周课是否只在对应周出现（左右滑动切几周看看）。

**失败时怎么取日志**：
- 对话框里的错误文案本身已经包含 stage（在哪一步挂的）与原始错误。
- 需要更细的日志：电脑上接 USB，`adb logcat -s flutter chromium`，
  再复现一次；WebView 里 JS 的报错会走 chromium tag。
- 实在定位不了：在 WebView 里手动打开
  `https://jwxt.shu.edu.cn/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default`
  看能不能正常显示课表页；能显示说明是解析问题，不能显示说明是登录/网络问题
  （校外访问 jwxt 需要学校 VPN）。

## B2.5 已知风险 / 未验证

1. **完全没有联网验证过**。本机 curl `jwxt.shu.edu.cn` SSL 握手失败（PLAN §0.1 已确认），
   所有测试都是基于 `test/import/fixtures/` 的仿真数据。
   **真实接口的字段名、返回结构、登录跳转链路都需要用户在真机上首验。**
2. **正方接口字段可能变化**：`kbList` 的 `kcmc/xm/cdmc/xqj/jcs/jc/zcd` 是正方通用字段，
   但学校可以定制。解析器对缺字段是「跳过 + warning」而不是崩溃，
   所以最坏情况是「导入了 0 门课 + 一堆提醒」，不会白屏。
   真变了只需要改 `ZfsoftAdapter._parseKbList` 里的字段名。
3. **SSO 二次验证**：`newsso.shu.edu.cn` 可能要短信/企业微信确认，甚至跳到外部 App。
   WebView 里跳外部 App 的 scheme（如 `wxwork://`）**不会被处理**，
   `NavigationDelegate` 没有拦截非 http(s) scheme。如果用户反馈卡在企业微信验证，
   需要在 `web_login_page.dart` 的 `onNavigationRequest` 里加外跳
   （**需要新依赖 `url_launcher`**，见 B2.6）。
4. **没有设置混合内容 / 自定义 UA**。`setJavaScriptMode` 与 cookie 是 Android WebView
   默认行为（默认接受 cookie），够用。要开混合内容得 import `webview_flutter_android`
   并用 `AndroidWebViewController`，那是间接依赖，直接 import 会触发
   `depend_on_referenced_packages` lint（本项目要求零 warning）。真机上如果发现
   教务页有 http 子资源被拦，再按 B2.6 补 `webview_flutter_android`。
5. **`sjkList`（无固定时间的课）只展示、不写入课表**。
   原因：`Course.fromJson` 会把 `day` 裁剪到 1..7、`startPeriod` 裁剪到 >= 1，
   所以 `day=0` 的占位课程一旦存盘再读回来，会变成「周一第 1 节」的幽灵课。
   与其造脏数据，不如在预览页明确告诉用户「这些不会写入网格，需要时手动添加」。
   v2 如果要支持，得先在模型层给 `day == 0` 一个合法语义。
   （这是对任务描述里「可选择作为备注课程忽略」的一处有意收敛。）
6. **`test/import/import_preview_page_test.dart` 有时序依赖**：
   `testWidgets` 跑在 fake async 区里，而 `Storage` 写的是真实文件，
   所以点确认后用了 `runAsync(delay) + pump()` 循环 40 次放行真实 IO。
   如果 `AppState._commit()` 以后加了更多 await 跳数（比如 Phase 3 挂上 `WidgetSync.push`），
   这个循环次数可能需要调大，否则这几条测试会 flaky。
   `zfsoft_adapter_test.dart`（纯解析，46 条）没有这个问题。

## B2.6 待加依赖（按 PLAN §4 先记后加）

目前 **不需要** 新依赖。以下是「真机验证撞上对应问题才加」的候选：
- `url_launcher`：SSO 需要跳企业微信/支付宝等外部 App 时（风险 3）。
- `webview_flutter_android`：需要显式配置混合内容 / UA / cookie 时（风险 4）。
  它已经是 `webview_flutter` 的传递依赖，只是要写进 `pubspec.yaml` 才能合法 import。

## B2.7 B2 验收状态（真实跑过的结果）

| 项 | 命令 | 结果 |
|---|---|---|
| 静态检查 | `flutter analyze lib/features/import test/import` | **No issues found!**（零 error 零 warning） |
| 解析单测 | `flutter test test/import/zfsoft_adapter_test.dart` | **46 passed** |
| 预览页接线测试 | `flutter test test/import/import_preview_page_test.dart` | **4 passed** |
| 真机导入 | —— | **未验证**（本机无法访问 shu.edu.cn） |

fixtures：
- `test/import/fixtures/shu_kb_envelope.json`：13 条 `kbList`（覆盖 `1-16周`、`1-15周(单)`、
  `2-16周(双)`、`1-8周,10-16周`、`3周`、跨节 `3-4`、周六 `xqj=6`、缺 `cdmc`、
  只有 `jc` 没有 `jcs`、同课程拆两条需合并、4 条脏数据）+ 1 条 `sjkList` + `xsxx`。
  解析结果：8 门课、1 门无固定时间、4 条 warning。
- `test/import/fixtures/shu_login_redirect.html`：被踢回统一身份认证登录页的 HTML。

---

# B1 记录（Phase 2：UI + 设置 + 主题）

## B1.1 新增的公共类与 Phase 3 接线方式

### 接线：`lib/main.dart` 只需要这样写
```dart
import 'package:flutter/material.dart';
import 'app.dart';
import 'features/import/pages/import_flow_page.dart';
import 'features/timetable/week_view_page.dart' show importRouteName;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ShuScheduleApp(
    extraRoutes: <String, WidgetBuilder>{
      importRouteName: (_) => const ImportFlowPage(),   // B2 提供
    },
  ));
}
```
- `ShuScheduleApp`（`lib/app.dart`）**自己创建并 `load()` `AppState` 与 `ThemeController`**，
  自己套 `MultiProvider` + `MaterialApp`。main.dart 不需要再建 Provider。
- 可选参数 `appState` / `themeController` 只给测试注入用；`extraRoutes` 给 Phase 3 注册路由。
- 导入入口在两个地方调用 `Navigator.pushNamed(context, importRouteName)`（常量值 `'/import'`，
  定义在 `lib/features/timetable/week_view_page.dart`）：周视图右上角菜单「从教务导入」、
  空状态引导的主按钮。**没注册时不会崩**，会落到 `onUnknownRoute` 的「尚未接入」页。
- 底部导航壳是 `HomeShell`（课表 / 今日 / 设置），已 export，可单独复用。

### 主题系统 `lib/core/theme/`
| 类 | 说明 |
|---|---|
| `AppTheme` | 与 themes.json 一一对应：`id/name/description/isDark/colors/courseColors[10]/courseTextOnBlock/cornerRadius/blockOpacity/fontHint/decor`。另有 `courseColor(i)`（取模，越界不崩）、`courseBlockColor(i)`（已乘 blockOpacity）、`backgroundAssetPath`、`titleFontFamily`、`toThemeData()`、`toJson()`。 |
| `ThemeColors` | 15 个颜色 token，字段名与 JSON 完全一致。 |
| `ThemeDecor` | `backgroundAsset` / `emoji` / `widgetStyle`（`glass|paper|flat`，**B3 的小组件底板样式读这个**）。 |
| `ThemeRegistry` | `load({bundle})` 从 `assets/themes/themes.json` 读；任何失败回退到 `[builtinShuTheme]`。`parse(text)`（顶层非数组抛 FormatException，单条坏只跳过那条）、`resolve(themes, id)`（找不到 → `shu` → 第一套 → 内置）。 |
| `builtinShuTheme` | 内置兜底「上大蓝」，与 JSON 里 id=`shu` 的内容一致。 |
| `ThemeController` | `ChangeNotifier`，`load()` / `current` / `themes` / `select(id)`。`select` 直接写 `AppState.settings.themeId`（AppState 自动持久化）。 |

**B3 需要主题色时**：`context.read<ThemeController>().current`，或把 `AppTheme.toJson()` 直接塞给
`WidgetSync.push`（`toJson` 输出的就是 themes.json 同构的 map，颜色是 `#RRGGBB`）。

### 其它可复用件
- `WeekLayout`（`lib/features/timetable/week_layout.dart`）：周表网格几何纯函数
  —— `topOf/totalHeight/segmentsOf/heightOfSpan/currentTimeOffset/positionOfIndex`，
  第 4/8 节后的午间/晚间带都在这里。**B3 画 4×4 周表 PNG 可以直接复用。**
- `CourseForm`（课程校验 + 周次快捷方案 + `defaultColorIndex(name)` 按名字哈希配色）。
- `PeriodForm`（作息校验：end>start、不与前后节重叠；增删节次 + renumber）。
- `EmptyState`、`ThemedBackground`（`lib/widgets/`）。
- `BackupService`（导出走 share_plus，导入走 file_picker + `Storage.importJson`，支持覆盖/合并）。
- `AboutPage` 里的 `appVersion = '1.0.0'` 常量，发版时要和 pubspec 的 version 一起改。

## B1.2 资源
- `design/themes.json` → `assets/themes/themes.json`（原样复制，没改内容）。
- `design/assets_app/{sakura,mint,galaxy}_bg.webp` → `assets/images/`（共 128 KB）。
- **themes.json 里 `backgroundAsset` 写的是 `*.png`（设计稿原图），工程里打包的是压缩过的
  `*.webp`**。`AppTheme.backgroundAssetPath` 负责把扩展名换成 `.webp`，所以没有改 JSON。
  以后要是换了图片格式，改 `backgroundAssetPath` 一处即可。
- `pubspec.yaml` 的 `flutter.assets` 早就声明了这两个目录，**没有动 pubspec**。

## B1.3 待加依赖
无。B1 只用了已有依赖（provider / share_plus / file_picker / path_provider）。
`intl` 没用上（日期格式简单，自己拼的 `M/d`，避免多一层本地化初始化）。

## B1.4 已知问题 / 给后续阶段
1. **`testWidgets` 里不能直接 `await` 真实 I/O**。`AppState.load()/save()`、`rootBundle` 在
   fakeAsync 下永远不返回，测试会卡死（我踩过，卡满 400s）。必须包在
   `await tester.runAsync(() async { ... })` 里。`test/week_view_test.dart` 是现成范例。
2. **周表里不要用固定高度 + 多行小字**。时间列一开始直接溢出 17px（测试字体每个字符都是正方形，
   `08:00` 在 10sp 下就有 50px 宽）。现在三行都套了 `FittedBox(scaleDown)`，
   系统字体放大时会缩放而不是溢出。其它自定义固定尺寸的地方（课程块）用的是 `Flexible` + `ellipsis`。
3. **当前时刻线**只画在「今天」那一列，且只在查看的周 == 本周、且在学期内时出现；
   第一节课前和最后一节课后不画（`WeekLayout.currentTimeOffset` 返回 null）。时间标签放在左侧
   时间列，不遮课名。每分钟一个 `Timer.periodic` 刷新（周视图和今日页各一个）。
4. **跨午间/晚间休息的课程会拆成两块画**，第二块标题带「（续）」，色槽相同（DESIGN §4 要求）。
5. **冲突课程**：同一天节次区间重叠的课归成一组，只画第一门 + 右上角 `+N` 角标，
   点开详情 sheet 会列出全部。不做并排显示（窄屏放不下）。
6. **非本周课程**用 `Opacity(0.38)` 整体降透明度 —— 这是 PLAN 明确要求的「半透明」，
   与 DESIGN「不要给整个组件降透明度」的规则冲突，这里以 PLAN 为准（它是被刻意弱化的内容）。
7. `ScheduleConfig` 构造器会把开学日期对齐到周一（Agent T 的 §2.3）。学期设置页在用户选了
   非周一的日期时会弹 SnackBar 提示「已自动对齐到当周周一」，没有去掉构造器里的对齐。
8. **`AppState._commit()` 里还没挂 `WidgetSync.push`**。Phase 3 接线时注意：改主题走的是
   `AppState.setThemeId`，也会触发 `_commit()`，小组件重绘可能需要防抖（Agent T §2.7 已提醒）。
9. 备份导出用的是系统分享面板（share_plus），**没在真机验证过**；桌面端 file_picker 走的是
   Windows 实现，Android 上是 SAF。真机由用户验证。
10. `flutter build apk` 没跑过（B3 在用 Gradle，按分工避让），只跑了 `analyze` + `test`。

## B1.5 B1 的验收结果（真实跑过，2026-09-16）
| 项 | 命令 | 结果 |
|---|---|---|
| 静态检查 | `flutter analyze` | **No issues found!**（零 error 零 warning） |
| 全量测试 | `flutter test` | **150 passed, 0 failed**（含 B2 的导入测试） |
| B1 新增测试 | `theme_registry_test` / `week_view_test` / `course_form_test` / `period_form_test` | 9 + 4 + 8 + 15 = 36 条全绿 |

B1 新增的测试覆盖：themes.json 解析出 6 套主题（含 10 色不重复、深色 brightness、背景图真实存在）、
读取失败回退内置主题、周视图渲染课程名/地点/教师/周次/休息带、非本周开关、空状态引导、今日页、
课程编辑校验、作息编辑校验、`WeekLayout` 几何与当前时刻线。

---

# Phase 3 记录（集成 + REVIEW-1 修复 + 出包 + 模拟器冒烟）

日期 2026-09-16。本阶段只有一个代理在改工程，可以自由跑 build / test / 模拟器。

## P3.1 接线做了什么

### `lib/main.dart`（整体重写，17 行）
```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ShuScheduleApp(
    extraRoutes: <String, WidgetBuilder>{
      importRouteName: (_) => const ImportFlowPage(),
    },
  ));
}
```
B3 留下的三个自测按钮（推送示例数据 / 两个 requestPinWidget）全部删掉。
`lib/features/widgets/demo_timetable.dart` **保留**，`test/widgets/widget_sync_test.dart` 还在用它。

### `lib/features/widgets/palette_mapper.dart`（新增）
`paletteFromTheme(AppTheme) → WidgetPalette`，字段按 B3 记录 §3.1 一一对应。
themes.json 里 6 套主题的 `todayHighlight` 全是不透明 `#RRGGBB`，
所以 `WidgetPalette.hex` 丢 alpha 不会出问题（有 alpha 的话小组件会显示成一块死色）。

### `lib/app.dart`（`_ShuScheduleAppState` 里挂推送）
- `initState` 给 `AppState` 和 `ThemeController` 各加一个 listener → `_scheduleWidgetPush()`；
- `_scheduleWidgetPush` = 取消旧 Timer + 新建 **800ms** 防抖 Timer；
- `_bootstrap()` 里 `load()` 完成后**无条件 push 一次**（跨天/跨周之后「今天高亮」靠这次拉回来）；
- `dispose` 里 cancel Timer + removeListener。

挂在 `app.dart` 而不是 `AppState._commit()` 里，原因：
`_commit()` 在 `lib/core/` 里，不应该反向依赖 `features/widgets/` 和主题；
而 `_ShuScheduleAppState` 天然同时持有 `AppState` 和 `ThemeController`，是唯一能拿全两份数据的地方。
副作用：单测里的 `AppState` 不会触发小组件推送（正是我们想要的，
`test/week_view_test.dart` 这类 `testWidgets` 不会因为 pending Timer 而报错）。

导入路由验证：周视图右上角 ⋮ →「从教务导入」、空状态主按钮，两条路都能进 `/import`；
确认导入后 `popUntil(isFirst)` 正常回首页。

## P3.2 周表小组件外观（B3 记录 §4 那张 `shot_widget_week.png` 的白边问题）

三处一起改才有效：
1. `WidgetSync.weekImageHeight` 360 → **460**（宽仍 360，比例 0.78 ≈ 4×4 桌面格子的实际形状）。
   `WeekGridImage` 的默认 `height` 同步改，doc 注释也改成「按 360×460 设计」。
2. `res/layout/widget_week.xml`：去掉根布局的 `android:padding="8dp"` 与 ImageView 的
   `adjustViewBounds`（match_parent 下它本来就没用），`scaleType` 保持 `fitCenter`。
3. `WeekWidgetProvider.kt`：`applySurface(R.id.week_root, palette.surface)` → **`palette.background`**。
   PNG 自己的底色就是 `palette.background`，两者一致时 fitCenter 剩下的那点留白看不见；
   用 surface（白）就会在彩色 PNG 周围露出一圈白框。

实测（`shots/final/15_widget_week_pinned.png`）：小组件卡片 946×1218 px，图片铺满，无白边。

## P3.3 App 图标

用了 Codex 出的 `design/assets/app_icon.png`（1024×1024，樱花粉→奶白渐变 + 白色圆角课表卡 +
3×3 网格 + 3 个彩色格子 + 樱花）。复制到 `shu_schedule/assets/icon/app_icon.png`
—— **故意不写进 `flutter.assets`**，它只在生成图标时被读，不需要打进包（省 850 KB）。

`pubspec.yaml` 的 `flutter_launcher_icons` 段：
```yaml
android: "ic_launcher"      ios: false
image_path: "assets/icon/app_icon.png"
min_sdk_android: 24
adaptive_icon_background: "#FBE4EA"
adaptive_icon_foreground: "assets/icon/app_icon.png"
adaptive_icon_foreground_inset: 15
```

**`inset` 这个值是踩出来的**：默认 16 / 手写 0 都不对。
- inset **0**：源图里课表卡片占画布约 71%，而自适应图标的安全区只有 66%（108dp 画布里可见的是中间 72dp），
  圆形遮罩会把卡片右下角那个蓝格子切掉 —— 真机上肉眼可见。
- inset **15**：图缩到 85%，卡片落进安全区；而 85% 仍然 > 66% 的可见圆，
  所以粉色渐变照样铺满整个圆，`adaptive_icon_background` 其实看不见，不会出现背景色接缝。

验证方式（不必每次重打包）：
```bash
magick res/drawable-xxxhdpi/ic_launcher_foreground.png -resize 302x302 fg_small.png   # 432*0.70
magick -size 432x432 xc:"#FBE4EA" fg_small.png -gravity center -composite comp.png
magick -size 432x432 xc:none -fill white -draw "circle 216,216 216,72" mask.png
magick comp.png mask.png -alpha off -compose CopyOpacity -composite -crop 288x288+72+72 sim.png
```
真机结果见 `shots/final/17_app_icon_drawer.png`。应用名仍是「上大课表」（manifest 没动）。

`flutter_launcher_icons` 顺手新建了 `res/values/colors.xml`（只有 `ic_launcher_background`）。

## P3.4 签名与版本

- keystore：`D:\desk\claudex\12\keys\shu_schedule.jks`，**PKCS12**（`keytool` 不加 `-storetype`
  默认就是 PKCS12；显式写 `-storetype JKS` 会有一条「建议迁移到 PKCS12」的警告），
  alias `shu`，DN `CN=SHU Schedule`，RSA 2048 / SHA256withRSA，10000 天。
  口令写在 `keys/README.txt`（`shuschedule2026`）。
- `android/key.properties`（storePassword / keyPassword / keyAlias / storeFile 绝对路径）。
- `android/app/build.gradle.kts`：按 Flutter 官方文档加 `signingConfigs.release`，
  并且 **`key.properties` 不存在时自动回退 debug 签名**，别人 clone 下来也能构建。
- `.gitignore`：工程内加了 `/android/key.properties`、`*.jks`、`*.keystore`；
  仓库根 `D:\desk\claudex\12\.gitignore` 也加了 `keys/`、`dist/`、`shu_schedule/build/`。
- 版本 `1.0.0+1`（pubspec 里本来就是），`about_page.dart` 的 `appVersion = '1.0.0'` 一致。
- 验证：`apksigner verify --print-certs` → `Signer #1 certificate DN: CN=SHU Schedule`。

## P3.5 REVIEW-1 的修复要点（详见 REVIEW-1.md，17 条全做）

### C1 `Storage` 原子写 + 串行化 —— 这条改出了三个坑

1. **`rename` 之前不要 `delete`**。`File.rename` 在 POSIX/Windows 上都是原子覆盖；
   先删再改名会造出「旧文件没了、新文件没就位」的窗口。
2. **`.tmp` 要带自增序号**，否则两次并发写互踩。
3. **写队列（`_serialized`）必须整段跑在 `Zone.root` 里**。这是最坑的一条：
   > Future 完成时，唤醒监听者的那个微任务是用 **future 自己创建时所在的 zone** 调度的。
   >
   > 队列的 `Completer` 如果建在调用方的 zone 里（比如 `testWidgets` 的 fakeAsync），
   > 那个测试一结束就再也不会被 pump，队列下一环永远不会被唤醒 ——
   > **`test/import/import_preview_page_test.dart` 的后两条用例直接挂死 90 秒**，
   > 而且第一次只把 `.then` 放进 `Zone.root.run` 是不够的，`Completer()` 本身也得在里面建。
4. 顺带：`saveTimetables/saveSettings` 里 `jsonEncode` 和 `await _file(...)` 都要在**进队列之前**做完。
   前者是因为排队期间数据还会被改；后者是因为 `_file()` 会调 `getApplicationDocumentsDirectory()`
   （平台通道），把它留在队列里跑，通道一不可用整条队列就永久卡住。
5. `_loadTimetables/_loadSettings` 开头 `_recoverFromTmp`：主文件不在但有 `<name>.<n>.tmp` 时
   取 mtime 最新的一个 rename 回来 + 写 warning；主文件存在时绝不覆盖。
6. 5 处未 await 的调用点补 `await`：`periods_editor_page.dart:62,74`、
   `term_settings_page.dart:61,84`、`timetable_manage_page.dart:54`。

### H1/H2/H3
- **H1**：`_startImport()` 开头比较 `Uri(_currentUrl).host` 与 `adapter.homeUrl` 的 host，
  不等直接给「当前页面还在 xxx，无法直接抓取教务数据」+ 建议，不再让用户看莫名其妙的 `Failed to fetch`。
- **H2**：脚本加 `checkLogin(r)`（401/403、或 `r.redirected` 且 `r.url` 不以 BASE 开头 → `__LOGIN__`），
  最外层 catch 区分 `TypeError`/`Failed to fetch` → 新哨兵 `__NETWORK__`，
  Dart 侧翻译成「请求教务接口失败，可能是登录已失效或网络不通（校外需要 VPN）」。
  **这条在模拟器上真的跑到了**（模拟器访问不了 shu.edu.cn），见 `shots/final/04_import_error_dialog.png`。
- **H3**：`raw.contains('"progress"')` 换成真正的 `jsonDecode`。逻辑抽成纯函数
  `parseChannelMessage(String) → ChannelMessage{kind, stage}`（放在 `school_adapter.dart`），
  因为原来在 `_WebLoginPageState` 的私有方法里根本没法单测（构造 WebView 需要平台）。
  `ChannelMessageKind.ignore / progress / result`；非 JSON、非对象、无 `ok` 键一律 ignore。

### M1-M8 / L1-L5
| 条目 | 做法 |
|---|---|
| M1 | `_errorShowing` 标志 + `showDialog(...).whenComplete(复位)`，SSO 链路不再叠弹窗 |
| M2 | 脚本里 `matchWeek()`：`当前…第 N 周` > `本周…第 N 周` > 宽松 `第 N 周` |
| M3 | `decodeBody(r)`：content-type 含 `gb` 时走 `TextDecoder('gbk')`（失败退 `gb18030`），否则 `r.text()` |
| M4 | 脚本里**字符串与正则**的中文全改 `\uXXXX`；**注释里的中文保留**（不参与运行，留着更好读），doc 注释同步改口径 |
| M5 | 预览页摘要卡下方加「最大周次 N > 总周数」提示条 + 一键「改为 N 周」 |
| M6 | `importJson` 逐条 try/catch + warnings，一条都解析不出来才抛 FormatException |
| M7 | `restoreFrom`：先 `Storage.backupBeforeRestore()`（`timetables.json.before-restore-<ts>`）、`normalizeIds`、空列表时 `currentTimetableId=''` |
| M8 | `WidgetSync.push` 用 `isDuringTerm ? rawWeekOf : null`；`WeekGridImage.week` 改成 `int?`，null 时画「假期中 ☕」空态 |
| L1 | 预览页 build() 里不再给 `_mode` 赋值，改成局部 `shown = hasCurrent ? _mode : createNew` |
| L2 | `parsePeriodSpan(jcs, jc, {warnings, courseName})`：两者都解析，不一致时取跨度更大的 + warning |
| L3 | kbList 合并 key 加上 `jxbmc`（教学班），不同教学班不再被合成一门 |
| L4 | `Storage.normalizeIds()`：课表/课程 id 为空或重复时重新分配 uuid，`importJson` 与 `restoreFrom` 都调 |
| L5 | `isLoggedIn`：`path == '/jwglxt'`（无尾斜杠）也算，不再让「一键导入」按钮莫名其妙灰着 |

### 顺带修的一个 P0（REVIEW-1 里没有，是模拟器冒烟测出来的）
**冷启动空状态点「手动添加」→ 填完保存 → 什么都没发生。**
`AppState.addCourse` 在一张课表都没有时 `tt == null` 直接 `return null`，课程被静默丢弃。
修法：`tt ??= await createTimetable();`（自动建一张「我的课表」再放进去）。
`test/models_test.dart` 加了回归用例。这个 bug 只有真机点一遍才会暴露，单测和 analyze 都发现不了。

## P3.6 质量门（真实结果）

| 项 | 命令 | 结果 |
|---|---|---|
| 静态检查 | `flutter analyze` | **No issues found!**（零 error 零 warning） |
| 单元测试 | `flutter test` | **180 passed, 0 failed**（Phase 2 结束时是 150，本阶段新增 30 条） |
| release 通用包 | `flutter build apk --release` | 成功，**53.7 MB**（56,290,687 B） |
| release arm64 | `--split-per-abi` | **19.2 MB**（20,137,757 B） |
| release armeabi-v7a | 同上 | 16.8 MB |
| release x86_64 | 同上 | 20.7 MB |

新增测试 30 条分布：
- `test/models_test.dart` +18：并发 20 次 save 不丢数据 / 并发后能读回 / `.tmp` 恢复 /
  主文件在时不被 `.tmp` 覆盖 / importJson 单条坏数据 / normalizeIds / backupBeforeRestore /
  `addCourse` 自动建表 / `restoreFrom` 的三条。
- `test/import/zfsoft_adapter_test.dart` +12：`__NETWORK__` 分支、脚本里有 checkLogin/decodeBody/
  matchWeek、周次正则顺序、脚本代码部分无裸中文（剥掉注释后查 CJK）、jcs/jc 不一致、
  jxbmc 合并规则、无尾斜杠登录判定、`parseChannelMessage` 5 条。

**`dist/` 产物**
```
dist/上大课表-v1.0.0.apk         53.7 MB  通用（arm64 + armeabi-v7a + x86_64）
dist/上大课表-v1.0.0-arm64.apk   19.2 MB  arm64 单独包
```
> PLAN §6 写的是「APK ≤ 40 MB」。**arm64 包 19.2 MB 达标，通用包 53.7 MB 不达标** ——
> 三套 native code 打在一起就是这个体积，没法再压。给用户优先推 arm64 包，通用包只作兜底。

## P3.7 模拟器冒烟测试（AVD `shu35`，真实安装 release 包）

`emulator -avd shu35 -no-snapshot-save -no-snapshot-load -gpu swiftshader_indirect -no-boot-anim`，
约 20 秒开机。**装 release 包前必须先 `adb uninstall cn.shu.schedule`** ——
B3 留下的 debug 签名包还在，直接 `install -r` 会 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。

截图都在 `shots/final/`：

| # | 项 | 结果 | 截图 |
|---|---|---|---|
| a | 冷启动空状态 | 通过。第 1 周 / 9-14~9-20 / 今天 9/16 周三高亮 / 引导按钮 | `01_cold_start_empty.png` |
| b | 导入：学校列表 | 通过，只有上海大学 + 说明文案 | `02_school_select.png` |
| b | 导入：WebView | 通过。模拟器访问不了 shu.edu.cn → **一个**「网页加载失败 net::ERR_CONNECTION_CLOSED」对话框（M1 去重生效，没有叠弹窗），不崩溃 | `03_webview_login.png` / `03_webview_login_error.png` |
| b | 导入：点「我已登录，直接导入」 | 通过。走到 H2 的新分支：「请求教务接口失败，可能是登录已失效或网络不通」+ VPN 建议 | `04_import_error_dialog.png` |
| c | 手动新建 2 门课 | 通过（**先修了 P3.5 末尾那个 P0**）。周一 1-2 节 + 周三 5-6 节，今天整列高亮、11:28 当前时刻线、午间/晚间休息带都对 | `05_week_view_2courses.png` |
| d | 「今日」tab | 通过。「9 月 16 日 · 周三 / 2026-2027 秋 · 第 1 周」+ 今天那门课 | `06_today_tab.png` |
| e | 主题：星空紫 | 通过，深色 + 星空背景插画，即时生效 | `07_theme_picker.png` / `08_theme_galaxy_week.png` |
| e | 主题：薄荷奶绿 | 通过 | `09_theme_mint_week.png` |
| e | 作息：第 1 节 08:00→07:30 | 通过，回周课表时间列变成 07:30 | `10_period_editor_dialog.png` / `11_periods_editor_0730.png` / `12_week_after_period_change.png` |
| f | 两个小组件钉到桌面 | 通过。数据与 App 完全一致（第 1 周 / 9-14~9-20 / 我的课表 / 周一周三两门课 / 周三整列高亮），**配色跟着薄荷奶绿走**，周表图片铺满卡片无白边 | `13_widget_picker.png` / `14_widget_today_pinned_page1.png` / `15_widget_week_pinned.png` / `16_widget_today_pinned_mint.png` |
| f | 点小组件打开 App | 通过，logcat 有 `START … act=es.antonborri.home_widget.action.LAUNCH`，`topResumedActivity` 变成 MainActivity | — |
| — | App 图标 | 通过，圆形遮罩下课表卡完整不被切 | `17_app_icon_drawer.png` |
| g | logcat | **全程无 FATAL、无 AndroidRuntime 异常、无 ANR**；`-s flutter` 只有一行 Impeller 后端信息 | — |

结束后 `adb emu kill`。

### 自动化踩的坑
1. **`adb shell input text` 不支持中文**，会抛 `NullPointerException: Attempt to get length of null array`。
   所以冒烟测试里手动建的两门课用的是 ASCII 名（`Advanced Math A` / `Data Structure`）。
   要中文得装 ADBKeyboard 之类的输入法 APK，本次没装（D 盘紧张）。
2. **Git Bash 会把 `/sdcard/ui.xml` 翻译成 `D:/Git/sdcard/ui.xml`**，
   `adb shell uiautomator dump` 和 `adb pull` 都要加 `MSYS_NO_PATHCONV=1`（B3 记录 §5.10 也提过）。
3. **找控件不能用「子串命中第一个」**。第一次点「手动添加」点到了空状态那行说明文字
   「可以从教务系统一键导入，也可以**手动添加**。」上。排序规则要按
   「完全相等 > 首行相等 > 开头匹配 > 子串」，并且给 `clickable="true"` 加权。
4. **Material 时间选择器要切到文本输入模式**（"Switch to text input mode"），
   而且键盘弹出/收起会让整个对话框的 bounds 上下平移 100~350 px，
   **每一步都得重新 dump 再点**，照着上一次的坐标点必然点歪。
5. **拖小组件到桌面要用 `input motionevent DOWN/MOVE/UP` 分步发**，中间 sleep 让长按判定生效；
   `input swipe` 时长再长也只是滑动，不会触发拖拽。
6. 模拟器时区是 GMT，日期 2026-09-16 —— 正好是 SHU 2026 秋第 1 周周三，省事。

## P3.8 遗留问题 / 交给后续

1. **导入全链路仍未在真实校园网验证过**（本机 + 模拟器都访问不了 `shu.edu.cn`）。
   错误分支（未登录 / 网络不通 / 超时 / 非 JSON）都验过了，**成功分支只有 fixtures 单测覆盖**。
2. **SSO 跳外部 App（企业微信 `wxwork://`）仍不支持**（B2.5 风险 3 未动）。
   要修得加 `url_launcher` 依赖并在 `onNavigationRequest` 里拦非 http(s) scheme。
3. **通用 APK 53.7 MB > PLAN 的 40 MB 上限**，见 P3.6。
4. **「本周课表」小组件跨天/跨周仍要打开 App 才刷新**（B3 §5.8 的老限制，没改）。
   彻底修需要原生端自己画周表，或者用 WorkManager 唤起 Flutter engine 重绘。
5. **课程块文字裁切**：课程名是长英文单词（`Advanced Math A`）时，第 3 行会被容器裁掉半行
   （见 `05_week_view_2courses.png` 周一那块）。中文课名 4~8 字不会触发。
   属于 `Flexible + maxLines` 的边界情况，没改。
6. **备份导出/导入仍未真机验证**（B1.4 第 9 条）：share_plus 的系统分享面板、
   file_picker 的 SAF 选择器都没在模拟器上点过。
7. `home_widget` 的 KGP 弃用警告还在（Agent T §3.9），将来 Flutter 版本会变成 error。
8. `keys/README.txt` 里是明文口令，只适合自用分发。要上架请换强口令重新生成 keystore
   —— 但注意 **keystore 换了之后老用户必须卸载重装**。

## P3.9 本阶段产出/改动文件

```
新增
  shu_schedule/lib/features/widgets/palette_mapper.dart
  shu_schedule/assets/icon/app_icon.png              (Codex 出的图，不打进包)
  shu_schedule/android/key.properties                (.gitignore)
  shu_schedule/android/app/src/main/res/values/colors.xml
  shu_schedule/android/app/src/main/res/mipmap-*/ic_launcher.png
  shu_schedule/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  shu_schedule/android/app/src/main/res/drawable-*/ic_launcher_foreground.png
  keys/shu_schedule.jks + keys/README.txt            (.gitignore)
  dist/上大课表-v1.0.0.apk + dist/上大课表-v1.0.0-arm64.apk
  README.md                                          (面向用户的中文说明)
  .gitignore                                         (仓库根)
  shots/final/*.png                                  (18 张冒烟测试截图)

重写
  shu_schedule/lib/main.dart

改动
  shu_schedule/lib/app.dart                          (防抖推送小组件)
  shu_schedule/lib/core/storage.dart                 (C1 / M6 / L4)
  shu_schedule/lib/core/app_state.dart               (M7 + addCourse 自动建表)
  shu_schedule/lib/features/import/adapters/school_adapter.dart   (H3 parseChannelMessage)
  shu_schedule/lib/features/import/adapters/zfsoft_adapter.dart   (H2/M2/M3/M4/L2/L3/L5)
  shu_schedule/lib/features/import/pages/web_login_page.dart      (H1/H3/M1)
  shu_schedule/lib/features/import/pages/import_preview_page.dart (M5/L1)
  shu_schedule/lib/features/settings/{periods_editor,term_settings,timetable_manage}_page.dart (C1 await)
  shu_schedule/lib/features/widgets/widget_sync.dart              (M8 + 图片尺寸 360x460)
  shu_schedule/lib/features/widgets/week_grid_image.dart          (M8 空态 + 尺寸)
  shu_schedule/android/app/build.gradle.kts          (signingConfigs.release)
  shu_schedule/android/app/src/main/res/layout/widget_week.xml    (去 padding)
  shu_schedule/android/app/src/main/kotlin/.../WeekWidgetProvider.kt (底板用 background)
  shu_schedule/pubspec.yaml                          (flutter_launcher_icons 段)
  shu_schedule/.gitignore                            (key.properties / *.jks)
  test/models_test.dart, test/import/zfsoft_adapter_test.dart     (+30 条)
```

---

## v1.0.1 (2026-09-16) 真机反馈修复

真机（Android 13）上点「一键导入」，WebView 打开 `https://jwxt.shu.edu.cn/` 之后
被上大统一身份认证 302 到 **`http://jwxt.shu.edu.cn/sso/shulogin`（明文 http）**，
Android 9+ 默认禁止明文流量，WebView 直接报 `net::ERR_CLEARTEXT_NOT_PERMITTED`，
弹出我们的「网页加载失败」。更糟的是对话框左键「回教务首页」重新 load 的还是
`https://jwxt.shu.edu.cn/`，又走一遍同样的跳转，看上去像「按了没反应」。

三处修复：

1. 新增 `android/app/src/main/res/xml/network_security_config.xml`，
   只对 `shu.edu.cn`（含子域）放行明文流量，并在 `AndroidManifest.xml` 的
   `<application>` 上挂 `android:networkSecurityConfig`。不是全局 `usesCleartextTraffic`，
   其他域名照旧禁止明文。
2. `zfsoft_adapter.dart` 的注入脚本：`var BASE = '__BASE__';` 之后加一段 ES5 代码，
   当 BASE 的域名和 `location.hostname` 相同时，把 BASE 改写成
   `location.protocol + '//' + location.host + <原路径>`。
   否则 SSO 之后页面落在 `http://jwxt.shu.edu.cn/jwglxt/...`，
   从 http 源 fetch https 的 BASE 是跨源请求，会被 CORS 打掉，
   用户只看到一句 `Failed to fetch`。`checkLogin` 里的 `r.redirected` 前缀判定用的也是
   同一个 BASE，改写后仍然成立。
3. `web_login_page.dart`：`onWebResourceError` 里如果 `description` 含 `CLEARTEXT`，
   建议文案改成「教务系统跳转到了明文 http 地址，请把 App 升级到 1.0.1 以上」
   （修完之后不该再出现，留着是为了以后诊断一眼能认出旧包）；
   对话框左键从「回教务首页」改名为「重新打开教务」，行为不变（pop + loadRequest(homeUrl)）。

版本号 `1.0.0+1` → `1.0.1+2`，同时把 `lib/features/settings/about_page.dart` 的
`appVersion` 常量从 `1.0.0` 改成 `1.0.1`（它是手写的，注释里就写着「发版时和 pubspec 同步」）。
不改的话「关于」页和设置页副标题还写着 v1.0.0，而新的错误提示恰恰叫用户
「升级到 1.0.1 以上」，用户没法自查装没装对包。

> 注意：本机访问不到 `shu.edu.cn`，真实 SSO 链路无法在开发机上验证，
> 只能靠单测 + APK 清单确认改动确实打进了包里。

---

## v1.0.2 (2026-09-16) 课程名截断

真机反馈：周课表里的课程名被截断。根因不是 `maxLines` 给少了，而是
**给死了**——`_CourseBlock` 的 Column 里名字 / 地点 / 教师三个 `Text` 都包在
`Flexible` 里（默认 flex = 1），一节高的块只有 ~47px 可用，三份 flex 平分下来
名字实际只剩一行多，`maxLines: 3` 根本排不下，于是第一行就 `…` 了。
块越矮、附加信息越多，名字被挤得越狠。

改成「按块的实际高度分配行数」，三处都用同一条规则：

1. `lib/features/timetable/week_view_page.dart`
   - 新增 `_blockLines(...)`：行高直接取 `fontSize * height`
     （几个 TextStyle 都写死了 `height`，这就是 Flutter 排出来的行高），
     课程名要几行则用 `TextPainter` 按块的实际宽度量一次
     （`_measureNameLines`，`computeLineMetrics().length`）。
     规则是「**只有课程名仍能完整排下，附加行才拿得到那一行**」——
     教师和上课时间在详情里都看得到，名字被切掉才是真的看不懂。
     名字本来就排不下（窄格子里的超长名）时至少把地点留住；
     块矮到只够两行时只画课程名。剩下的高度整除行高就是名字的行数，下限 1 行。
   - 块内容包进 `LayoutBuilder` 拿 `constraints.maxHeight`；
     Column 改 `mainAxisSize: min`，只有课程名留 `Flexible`（loose），
     附加行改成普通 `Text`——这样溢出不可能发生，也不会再有人抢名字的高度。
   - 排版微调：块内 padding 4/5 → 3/4，所有文字 `letterSpacing: 0`，
     地点 10 → 10.5、教师 9 → 9.5（7 列窄格子里每行能多塞一个字）。
     课程名仍是 12，没有再缩小。
   - 地点这里本来就是直接画 `course.location`，没有 `@` 前缀，不用动。
2. `lib/features/widgets/week_grid_image.dart`
   - `_buildBlock` 的第二个参数从 `span` 改成块的真实高度
     `span * cellH - _blockInset * 2`（PNG 是 360×460，`cellH ≈ 33.5`，
     光看 span 猜不准）。同一条规则：1 节高 → 名字 2 行、不画地点；
     2 节高 → 地点 1 行 + 名字 5 行。
3. `android/app/src/main/res/layout/widget_today.xml`
   - 6 行 `row_N_name` 的 `maxLines` 1 → 2、`textSize` 13sp → 12sp，
     行的上下 padding 4dp → 3dp，抵掉多出来的那一行，4×2 里能显示的行数不变。
   - `TodayWidgetProvider.kt` 只有 `take(MAX_ROWS)`（限行数，不是截字符串），
     `WidgetSnapshot.kt` 没有任何截断，不用动。

`README.md` 已知问题第 8 条改成「v1.0.2 已修」。
版本 `1.0.1+2` → `1.0.2+3`，`about_page.dart` 的 `appVersion` 同步到 `1.0.2`。

## v1.0.3 (2026-09-16) 课程块改成「名字靠上、教室靠下」

用户反馈 v1.0.2 的课程名仍会被截断，且「文字的下线被框死」。复查发现 v1.0.2 的做法
（先按预算切出附加行、剩下的高度用 `floor()` 换算成 `maxLines`）有两个问题：

1. `floor()` 会白白丢掉不足一行的零头（最多接近一整行的高度），块底部明明还空着，
   名字却已经吃到省略号；
2. 名字外面是 `Flexible`，附加行紧跟其后，名字的可用高度被结构框死。

改法（`week_view_page.dart` `_blockLines` / `_CourseBlock`，`week_grid_image.dart`
`_buildBlock` 同步）：

- 布局改成 `Column(max) + Expanded(Align.topLeft(名字)) + 底部附加行`：
  名字靠上、教室靠下，中间的空隙全部归名字；
- 行数分配改成「名字优先」的退让循环：先用最大字号配尽量多的附加行，排不完就依次
  砍掉时间 → 教师 → 教室，全砍完还排不完就把字号缩一档（App 12→11→10，
  小组件 PNG 8.5→8→7.5），最后兜底用最小字号把整块高度都给名字；
- 名称行高 1.15 → 1.1，同样宽度下多挤出约一行。

测试 `test/week_view_test.dart` 里那条超长课程名用例加了真正的判据：用 `TextPainter`
按渲染出来的宽度和样式量一遍，要求「实际需要的行数 ≤ maxLines」，即不能出现省略号。

补充（同版本，emulator 实测后追加两处）：

- **冲突角标压住课程名**：右上角的 `+N` 是 `Stack` 里的 `Positioned`，和课程名同层，
  首行文字正好被盖住（截图里「线性代数」显示成「线性⬤数」）。改成有角标时课程名
  整体让出 `_kBadgeWidth = 18` 的宽度（测量与 `Padding` 同步扣掉）。
- **1 节高的格子再补一轮**：字号阶梯加到 `[12, 11, 10, 9]`；并且当最小字号仍排不下时
  （`_BlockLines.fitted == false`），把上下留白从 4 收到 1 再算一遍，
  常常正好多出一行。实测「大学英语综合课程与跨文化交际（三）」17 字在 1 节高、
  7 列宽的格子里已经能完整显示。小组件 PNG 的字号阶梯同步加到 `[8.5, 8, 7.5, 7]`。

验证：`flutter analyze` 零问题，`flutter test` 182 passed，release APK 装到 shu35
模拟器上截图确认（`shots/v103/03-week-grid-tight.png`、`04-home-widgets.png`、
`05-week-widget.png`）：周课表、今日小组件、本周课表小组件里所有长名都完整显示。

## v1.1.0 (2026-09-17) 课表视觉重做 + 两个新小组件

用户反馈：「排版好丑」「那条表示当前时刻的横线有点丑，想个创意代替」。
设计方案让 Codex（gpt-5.6-sol）出了一版规格稿，产物在
`design/.omc/artifacts/ask/codex-ui-flutter-app-...2026-09-17T02-31-19-419Z.md`，
Codex 推荐「课程块侧边进度」而不是继续画线。实现按它的规格走：

### 课程块排版（`week_view_page.dart`）
- **信息组连续、整组靠上**：课程名 →（间距 4）→ 教室 → 教师。
  v1.0.3 的「名字靠上、教室贴底」会在两节课高的块中间留一个洞，
  居中又会让相邻格子的首行对不齐；现在多余留白统一落在信息组下方，
  所有格子的第一行起点一致。
- **整周统一字号**：这一周里只要有一门课在 11.5 下放不下，整周一起降到
  紧凑档 10.5（`_weekNeedsCompact`，按「课表 id + 周 + 列宽 + 文字缩放」缓存）。
  避免相邻格子忽大忽小。只有 1 节高 + 超长名才会单独再降到 9.5。
- 字号按 Codex 规格：课程名 11.5/600 行高 1.22，教室 9.5/500，教师 9.5/400；
  教室 82% 不透明度、教师 66%，和课程名拉开层级。
- 「格子里显示时间」默认关掉——左侧时间列已经有时刻，格子里再写一遍是噪音。

### 「此刻」的表达（取消横线）
- 删掉横贯当天列的 2px 实线 + 圆点。
- 时间列里原本就有的「现在 14:23」胶囊保留，负责精确时刻。
- **正在上的那节课**：1.5px accent 70% 描边 + 右边缘一条 2.5px 进度槽，
  已上部分 accent 85%，槽底 16%。进度槽画在内边距里，
  所以上课那一刻课程名不会重新换行。

收尾（同版本，真机/模拟器实测后追加）：

- **字号阶梯末档加回 9pt，并且 ≤9.5 的档位行高收到 1.08**（`_nameLineHeight`）。
  行高从 1.1 提到 1.22 之后，1 节高的格子又装不下 17 字的长名了；
  测量和渲染都要用同一个行高，否则 `TextPainter` 量出来的行数和实际排版对不上。
- **`showTimeInGrid` 默认值改成 false 只对全新安装生效**，老用户的 settings.json
  里存的还是 true。加了 `AppSettings.settingsVersion`（当前 2）：
  读到没有这个字段的 v1 存档就把 `showTimeInGrid` 迁移成 false 一次，
  之后用户自己开关的选择一直保留。有单测覆盖「迁移一次」和「迁移后不再覆盖用户选择」。
- **磁盘**：C: 已经 0 字节可用，`flutter test` 会静默卡住（往 %TEMP% 写 output.dill
  失败，errno 112）。构建/测试前 `export TEMP='D:\desk\claudex\12\.tmpbuild'`
  和同名 TMP 可以绕开，但 C: 需要用户自己清理。
  占大头的是 AppData\Local（Packages 14.6G、Claude-3p 10.3G、Docker 7.6G、
  wsl 5.3G、Google 5.8G）和 AppData\Roaming 33G，都是用户自己的程序数据，不要动。

---

## v1.2.0 (2026-09-17) 只留一个可滑动的小组件 + 应用快捷方式

用户（vivo 手机）反馈：桌面上根本找不到这个 App 的小组件，能找到的那个预览还是个应用图标。
三件事一起做了：小组件砍到一个并且让课程列表能滑、App 里做一个「一键添加」、
长按 App 图标加三个快捷方式。

### 为什么砍到一个

v1.1.0 有四个 Provider（今日 / 某日可翻页 / 两日 / 本周）。真机上暴露出两个问题：

1. **vivo 启动器会按「每个 App 的小组件数量」分层**：只有一个时长按桌面 →「小组件」
   一眼就能看到；有四个之后被折进「应用挂件」的二级菜单，还要先找 App 再找组件。
2. **选择器里的预览图全是应用图标**。`previewLayout`（真正能画出组件长什么样的那个）
   是 **API 31+** 才生效的字段，API 30- 和一部分只认老字段的国产启动器只看
   `previewImage`，而当时四个 info 里的 `previewImage` 全都写的 `@mipmap/ic_launcher`。
   现在 `day_widget_info.xml` 改成指向 `@drawable/widget_day_preview`（nodpi PNG，
   后面用真机截图替换），`previewLayout` 保留给 API 31+。

「某日课程（可翻页）」本来就是另外三个的超集（翻到明天 = 两日，翻一圈 = 本周），
所以留它，label 改成就叫「上大课表」（在启动器列表里最好认），另外三个连同
`week_grid_image.dart`（离屏渲染周表 PNG）、`WidgetSync.weekImageKey`、
`WidgetSnapshot.KEY_WEEK_IMAGE`、`CourseRows.kt` 一起删掉。
**快照格式没动**，所以老版本装上来也不会读挂。

### RemoteViews 的 ListView 必须配一个 RemoteViewsService

原来是布局里写死 6 行（`day_row_0..5`），放不下就显示「还有 N 门」——课多的那天纯属摆设。
改成真的能滚的列表，要点：

- RemoteViews 不能直接塞 View，`ListView` 的数据要由一个
  `RemoteViewsService.RemoteViewsFactory` **跨进程**提供
  （新文件 `widgets/DayWidgetService.kt`）。manifest 里这个 service 必须声明
  `android:permission="android.permission.BIND_REMOTEVIEWS"`，否则系统拒绝绑定，
  列表永远空白。`exported="false"` 不影响系统绑定（系统是以 BIND 权限来的）。
- **适配器 Intent 的 `data` 必须逐 widget 唯一**（`shuwidget://list/<widgetId>`）。
  和 PendingIntent 一样，系统判重时不看 extras；两个小组件共用一个 data 的话，
  第二个会复用第一个的工厂，翻页会互相串。
- **`updateAppWidget` 之后必须再调
  `appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.day_list)`**。
  列表内容不在 RemoteViews 里，光 update 只换了壳，`onDataSetChanged` 不会跑，
  翻页和推数据都看不到变化。
- 列表项自己**不能**带 PendingIntent：Provider 用
  `setPendingIntentTemplate(R.id.day_list, <打开 App 的 PendingIntent>)`，
  每一项 `setOnClickFillInIntent(R.id.item_root, Intent())`。
  （模板用的是 `HomeWidgetLaunchIntent.getActivity`，它是 `FLAG_IMMUTABLE` 的，
  fill-in 的内容会被忽略——这里 fill-in 本来就是空的，只要能拉起 App 就行。）
- 空态改成 `setEmptyView(R.id.day_list, R.id.day_empty)`，
  文案（「这天没有课」/「打开 App 刷新课表」）要在 `updateAppWidget` **之前**设好。
  两者必须在同一个父容器里叠着（布局里包了一层 `FrameLayout`）。
- 翻页偏移的读写现在跨了两个类（Provider 写、Factory 读），
  所以 `PREFS_PAGE` / `keyOffset` / `keyDate` / `pageStore` / `readOffset`
  从 `DayWidgetProvider` 的 companion 提到了 `ShuWidgetProvider.kt` 的包级函数。
  Factory 读快照走 `HomeWidgetPlugin.getData(context)`——和 `HomeWidgetProvider`
  给 `onUpdate` 的是同一份 SharedPreferences（`HomeWidgetPreferences`）。

### 「绝对不会找不到」的添加方式：requestPinAppWidget

`AppWidgetManager.requestPinAppWidget(ComponentName, null, null)`（**API 26+**）
会让系统直接弹一个「添加到桌面」的确认框，用户点一下就完事，不用进桌面翻菜单。
API 25 及以下、或者启动器 `isRequestPinAppWidgetSupported == false` 时返回 false，
这时才退回去显示手动步骤。

接线：`MainActivity` 不再是裸的 `FlutterActivity`，`configureFlutterEngine` 里注册
MethodChannel `cn.shu.schedule/native`，三个方法 `isPinWidgetSupported` /
`requestPinWidget` / `getLaunchAction`。Dart 侧是 `lib/core/native_bridge.dart`，
**所有方法都吞掉 `PlatformException` / `MissingPluginException` 返回 false/null**，
免得在没有原生实现的环境（单测、以后可能的 iOS）里炸。
弹窗和手动步骤的流程抽在 `lib/features/widgets/add_widget_helper.dart`，
设置页的「添加桌面小组件」和快捷方式的 `add_widget` 共用同一个函数。

### 长按 App 图标的快捷方式（静态）

`res/xml/shortcuts.xml` 三条：`today` / `import` / `add_widget`，各配一个 24dp 的
矢量图标（`ic_shortcut_*.xml`），在 manifest 的 **MainActivity 元素里面**用
`<meta-data android:name="android.app.shortcuts" android:resource="@xml/shortcuts"/>` 注册。
静态快捷方式不需要权限、不需要 App 在跑，系统装包时就读这个文件。
Intent 都是显式的（targetPackage + targetClass），另外给这三个 action 加了一条带
`category.DEFAULT` 的 intent-filter（显式 Intent 其实用不上，留着不亏）。

两条到达路径都要处理：

- **冷启动**：Flutter 那边 `getLaunchAction` 主动来取。原生**取完就把
  `intent.action` 清掉**——`getIntent()` 在配置变更（旋转、切深色模式）后会原样重放，
  不清的话每转一次屏就重新跳一次。
- **App 已经在跑**（`launchMode="singleTop"`，快捷方式不会新建 Activity）：
  `onNewIntent` 里 `setIntent` + 反向 `invokeMethod("onAction", key)`。

Dart 侧在 `HomeShell` 里落地：`initState` 订阅 `NativeBridge.actions`，
`build` 里等 `AppState.isLoaded` 之后用一次 `addPostFrameCallback` 取冷启动动作
（build 里不能 push 路由也不能弹 dialog）。`today` → 切到底部第 1 个 tab，
`import` → `pushNamed(importRouteName)`，`add_widget` → `requestAddWidget`。

### 质量门（真实跑过）

- `dart format lib test`：干净。
- `flutter analyze`：No issues found!
- `flutter test`：191 passed（删掉 3 个 `WeekGridImage` 的 widget 测试，
  把「refreshTargets 覆盖全部四个 Provider」改成「只有唯一那个 Provider」，
  新增 `test/core/native_bridge_test.dart` 9 个：成功 / 返回 null / 返回 false /
  `PlatformException` / `MissingPluginException` / `onAction` 流）。
- `flutter build apk --debug`：成功。

### 模拟器验证（AVD `shu35`，Android 15，release 包覆盖安装 v1.1.0）

截图在 `shots/v120/`。

- **覆盖安装不丢数据**：v1.1.0 → v1.2.0 直接 `adb install -r`，课表和主题都在；
  桌面上原来的「两日课程」实例随 Provider 一起消失，「某日课程」实例原地变成新的
  ListView 版本（`01-home-after-upgrade.png`）。
- **翻页**：▶ 六次到 +6 后箭头变灰，「回到今天」出现；空的那天显示「这天没课」；
  点日期块回到今天（`sheet-paging.png`）。
- **上下滑动**：桌面的拖拽改大小不认 adb 手势（`input swipe` / `motionevent` 都没用），
  改用 `settings put system font_scale 1.6` 把 3 门课撑出 4×2，
  在列表里上滑之后第 3 门课露出来（`sheet-scroll.png`）。顺带证明大字号用户也能用。
- **长按图标**：Pixel 启动器显示三条（用的是 longLabel）：看今天上什么课 /
  从教务系统导入课表 / 把课表小组件放到桌面，图标正常（`10-icon-longpress.png`）。
  三条分别验证：今日 tab、导入页、系统「Add to home screen」弹窗（`sheet-shortcuts.png`）。
- **设置页「添加桌面小组件」**：同样弹出系统确认框（`15-settings-pin.png`）。
- **选择器预览图**：`widget_day_preview.png` 换成了真实截图裁剪（720×448，圆角透明），
  API 31+ 的启动器仍然走 previewLayout，所以这张图只有 vivo 这类只认 previewImage 的启动器
  才看得到，**在模拟器上没法验证**。
- logcat 里 `ShuWidget` / `ShuNative` 没有 warning，没有崩溃。

### 已知/没验证的

- `requestPinAppWidget` 在 vivo OriginOS 上弹不弹只能真机试；弹不出来会退回图文步骤对话框。
- 长按菜单里显示短标签还是长标签由启动器决定（Pixel 显示长标签）。
- 大字号下高亮那一行课名超过两行会省略号（`maxLines=2`），不影响滑动。


---

## v1.3.0 (2026-09-23) 去上大化 + 地基

计划见 `PLAN-1.3.md`，依据 `REVIEW-2-product.md` §2.2 / §5 / §9。本节按 Phase 追加。

### Phase A：数据模型与规则（opus55）

**质量门（真实跑过）**：`flutter analyze` → `No issues found!`；`flutter test` → `00:06 +251: All tests passed!`。
基线（改动前）是 191 个，**新增 60 个**，另外改了 `widget_sync_test` 里 3 处「14 天」的断言（现在是 133 天）。

新增测试文件：`date_override_test.dart`（14）、`week_layout_test.dart`（18）、`migration_test.dart`（13）、
`app_state_group_test.dart`（3）、`week_view_override_test.dart`（5，widget 测试）、
`widgets/widget_snapshot_term_test.dart`（7）。新增 fixture：`test/fixtures/v1_2_0/`
（`backup_v1.json` = 1.2.0 导出的备份；`timetables.json` / `settings.json` = 1.2.0 的本地存档，按 1.2.0 的 `toJson` 手写）。

#### 1. 调休 / 停课 `DateOverride`
- 新模型 `lib/models/date_override.dart`：`DateOverride { bool cancelled; int? actAsWeek; int? actAsWeekday; String? note }`，
  `ScheduleConfig.overrides: Map<'yyyy-MM-dd', DateOverride>`（旧 JSON 缺字段 → 空表；key 容错归一化，坏条目丢掉）。
- 语义：`cancelled` = 停课；只给 `actAsWeekday` → 周次沿用这一天本身所在的周（「国庆后周六上周一」）；
  只给 `actAsWeek` → 星期沿用这一天本身；两个都给 → 按指定周的指定星期。只写 note 不改课程。
- **唯一入口** `ScheduleUtils.effectiveDayOf(date, config) → EffectiveDay`，`coursesOn` / `coursesOnEffective` 都走它：
  - 今日页：`coursesOn`（已改），副标题追加「· 停课（备注）」/「· 调休，按第 N 周周一上课」，停课日空态标题「今天停课。」；
  - 周视图：`_dayColumn` 用 `effectiveDayOf` + `coursesOnEffective`，停课那天整列不画（非本周幽灵块也不画）；
    日期头在日期数字下面加一行小字「停课」（danger 色）/「调休」（accent 色），读屏标签带完整说明；
    整周紧凑字号的测量也按调休后的课算，缓存 key 带上 overrides 指纹；
  - 小组件快照：同一个入口；`nextCourse` 自动跳过停课日。
  - 「快照与 coursesOn 逐日一致」有专门的对拍测试。

#### 2. 休息带从作息推导
- `WeekLayout` 不再有写死的 `[3, 7]`。规则在 `ScheduleUtils.breakAfterIndices(config)`：
  `ScheduleConfig.breakAfter`（`List<int>?`，元素是 `PeriodTime.index`）非 null 用手动值（过滤掉不存在的节和最后一节；`[]` = 不画）；
  null 自动：相邻两节 `start(i+1) - end(i) >= 40` 分钟画一条。上大 12 节推导出 `[4, 8]`，和旧行为一致（旧测试全过）。
- 带的种类按间隔中点：11:00~15:00 午间（28dp，「午间休息」）、>= 15:00 晚间（24dp，「晚间休息」）、其他（24dp，「休息」）。
- `segmentsOf` 用推导出的位置拆块。「上午 5 节」fixture（午休在第 5 节后、晚休在第 9 节后）的拆分、topOf、
  时刻线、周视图里两条带的实际纵向位置都有测试。

#### 3. `Course.groupId` / `externalKey`
- 两个可空字段，JSON 往返，旧 JSON → null。`AppState.updateCourse(course, {syncGroupColor = true})`：
  颜色变了且有 groupId 时同组其余课程一起改色。编辑器保存时原样保留这两个字段（之前是 `Course(...)` 新建，会丢）。
- **目前没有任何地方会生成 groupId**：导入（Phase B，按 kch 分组）和「复制到其他星期」（Phase C）来填。

#### 4. `Timetable` 导入元数据
- `schoolId` / `systemType` / `termCode` / `importedAt`（均可空）+ `sourceTag` getter（`'$systemType-$schoolId'`）。
- `Timetable.migrateLegacyJson`：**只在两个 key 都不存在时**（= 1.2.0 及以前的 JSON）从课程的旧来源标记
  `zfsoft-shu` 推断出 `zfsoft` / `shu`；新版本写出的 JSON 总带这两个 key，所以幂等，不会把后来的手动课表误标。
  本地存档（`Timetable.fromJson`）和备份都会走到。

#### 5. 备份 v2
- `exportJson` 写 `version: 2`（`Storage.backupVersion`）。`importJson` → `Storage.migrateBackup`：缺 / 坏 version 当 1；
  v1 走 `migrateBackupV1ToV2`（纯函数：课表补 schoolId/systemType；设置缺 `settingsVersion` 时标 1）；
  比 2 新的不拒收，尽量读 + warning。
- `AppSettings.fromJson` 改成按 `versionOf(json)` 逐级迁移（`< 2` 才把 `showTimeInGrid` 重置为 false）。
  行为差异：以前「settingsVersion 是任意 int 就保留」，现在显式写 1 也会迁移——这才是对的，备份迁移依赖这一点。
  `AppSettings.currentVersion` 仍是 2（这一版设置结构没变，不空升版本号）。

#### 6. 小组件快照覆盖整学期
- `WidgetSync.snapshotDaysFor(config) = min(totalWeeks * 7 + 7, 150)`（`maxSnapshotDays = 150`），18 周 → 133 天；
  测试确认学期中任意一周打开 App，快照都覆盖到「学期最后一天 + 6 天翻页」。
- `snapshotVersion` 1 → 2；调休 / 停课的日子多两个字段 `label`（「停课」/「调休」）和 `note`（备注，没有备注时是完整说明）。
  其余字段不变。
- **体积实测**：150 天 × 每天 12 节全满（7×12 = 84 条 / 周，长课程名 / 教室 / 教师）= **412,056 字节（402.4 KB）JSON**，< 500KB。
  另估了 Android SharedPreferences XML 落盘时 `"` → `&quot;` 的膨胀：约 **672,526 字节（656.8 KB）**（估算，没在真机上量文件）。
  真实课表一般每周 20~30 块，体积约为这个极端值的 1/3。
- Kotlin 端没改，只读确认：`DayWidgetProvider` / `DayWidgetService` 用 `date == today` 找到今天的下标再按 offset（≤ 6）取，
  天数变多不影响；多出来的 `label` / `note` 被 `optXxx` 忽略；快照里找不到今天时的「打开 App 刷新」兜底仍在。

#### 7. 上大专属内容改成通用示例
- `shuDefaultPeriods` → `defaultPeriods`，`shuTermPresets` → `exampleTermPresets`，`ScheduleConfig.shuDefault()` → `ScheduleConfig.defaults()`，
  `AppState.resetPeriodsToShuDefault()` → `resetPeriodsToDefault()`；注释改成「通用示例，数据取自上海大学」。
- **保留了两个兼容别名** `shuDefaultPeriods` / `shuTermPresets`（`presets.dart` 末尾），因为 `zfsoft_adapter.dart`、
  `import_preview_page.dart` 和 `zfsoft_adapter_test.dart` 还在用，按约定 Phase A 不动导入。**Phase B 改完导入后删掉这两行。**
- 界面文案、品牌没动（Phase C）。

#### 没做 / 有疑虑
- 没在模拟器上看过周视图日期头的「停课 / 调休」小字的实际效果，只有 widget 测试（不抛 overflow、位置在对应列）。
  日期头外面加了 `FittedBox(scaleDown)` 防大字号溢出。
- 停课那天的课直接不画；要不要以淡色幽灵块显示「本来有什么课」留给 Phase C 的调休 UI 一起定。
- 调休日在周视图里画的是「被换过来那天」的课，课程块读屏标签里的星期仍是课程本身的星期（例如周六列里读「周一」）。
- 新增的几句文案（「停课」「调休」「调休，按第 N 周周一上课」「今天停课。」「休息」）是功能必需的最少文字，Phase C 可以改。
- REVIEW-2 §5 提到的「多套作息 `PeriodProfile` 预留字段」不在 PLAN 的 Phase A 清单里，没做。
- REVIEW-2 建议的「快照改推周模板 + 覆盖项，Kotlin 自己算」没做（PLAN 定的是展开 150 天）；150 天封顶意味着 21 周以上的学期
  在开学头几天打开 App 时，快照覆盖不到学期末，直到下次打开 App 刷新。
- 调休日落在学期外、但 `actAsWeek` 指向学期内时：课程照常列出，但快照里这一天的 `week` 仍按日历写 null（小组件头部显示「假期」）。
- 对整个 `lib/` `test/` 跑过一次 `dart format`，原有文件应当本来就是格式化过的（第二次运行只报了新文件有变化），但没有 git 无法逐文件确认。

#### Phase A 改动文件
- 新增：`lib/models/date_override.dart`；测试见上；`test/fixtures/v1_2_0/*`。
- 修改：`lib/models/{schedule_config,course,timetable,app_settings}.dart`、`lib/core/{schedule_utils,app_state,storage,presets}.dart`、
  `lib/features/timetable/{week_layout,week_view_page,today_page,course_editor_page}.dart`、
  `lib/features/widgets/{widget_sync,demo_timetable}.dart`、`lib/features/settings/{periods_editor_page,term_settings_page}.dart`（只改引用名）、
  `test/{widgets/widget_sync_test,schedule_utils_test,period_form_test}.dart`（改引用名 / 14→133 天）。

### Phase B：导入引擎泛化（opus55）

**质量门（真实跑过）**：`flutter analyze` → `No issues found!`；`flutter test` → `00:13 +323: All tests passed!`
（Phase A 结束时 251 个，净增 72 个；删了 3 个不再成立的旧测试：`nearestPreset` 一个、旧 `SchoolRegistry.all` 两个）；
`flutter build apk --debug --target-platform android-arm64` → `√ Built build\app\outputs\flutter-apk\app-debug.apk`（Gradle 118s，EXIT=0）。
合并后的 Manifest 里确认有 `wxwork / weixin / mqqapi` 三条 `<queries>` 和 `networkSecurityConfig`。

新增测试文件：`test/import/school_registry_test.dart`（22）、`test/import/diagnostics_test.dart`（19）、
`test/import/edu_session_test.dart`（13，含 AppSettings 迁移与跳转分流）、`test/course_source_label_test.dart`（4）；
`zfsoft_adapter_test.dart` 新增 8 个（其中「v1.3.0 泛化」组 6 个），改写「拿不到周次」一个，`import_preview_page_test.dart` 新增 5 个 widget 测试 + 3 个纯函数测试。

#### 1. 明文放行改成 `edu.cn`
`network_security_config.xml`：`<domain includeSubdomains="true">edu.cn</domain>`，删掉 shu.edu.cn 专项。IP 直连 / 非 edu.cn 的教务仍不放行
（`SchoolUrlGuess` 对这种网址会提醒；WebView 报 CLEARTEXT 时的提示文案也改成说明这条规则，不再叫人「升级到 1.0.1」）。

#### 2. 非 http(s) scheme 外跳
- 依赖：`flutter pub add url_launcher` → `url_launcher: ^6.3.2`（url_launcher_android 6.3.33）。
- `web/external_navigation.dart` 的纯函数 `planNavigation(url)`：http/https/about/data/blob/javascript/相对地址 → WebView；
  `file:` / `content:` / 空 → 拦下；其他 scheme → 外部 App；`intent://…#Intent;scheme=x;S.browser_fallback_url=…;end`
  → 换成 `x://…`，并带上 http(s) fallback（外部 App 打不开时 WebView 加载 fallback）。
- `NavigationDelegate(onNavigationRequest:)` 用它分流；外跳走 `launchUrl(..., mode: LaunchMode.externalNonBrowserApplication)`，
  失败 / 没装 App → SnackBar「没有找到能打开这个登录方式的 App（scheme），请改用账号密码登录…」。
- **查过 url_launcher README 与 url_launcher_android 源码**：`<queries>` 只影响 `canLaunchUrl`；`launchUrl` 是 `startActivity`，
  不受包可见性限制，找不到 Activity 时抛 `PlatformException(ACTIVITY_NOT_FOUND)`（已 catch）。仍在 Manifest 声明了 wxwork/weixin/mqqapi，
  注释写明了原因。
- ⚠️ **回归风险（未在真机验证）**：看了 webview_flutter_android 4.14.1 源码，一旦设置 `onNavigationRequest`，Android 端
  `shouldOverrideUrlLoading` 恒返回 true，放行的主框架跳转由插件用 `loadUrl(url, headers)` 重新发起（只对 GET；POST 不经过这里）。
  这对 302 链路一般等价，但 Referer / 历史栈可能和以前不同。**Phase D 必须在模拟器上把上大统一身份认证登录 → 一键导入完整走一遍。**

#### 3. `SchoolAdapter` / `ImportResult` 扩展
- `SchoolAdapter` 改成可被 `extends` 的抽象类，新增：`systemType`、`sourceTag`（= `Timetable.sourceTagOf(systemType, id)`）、
  `allowedHosts`、`isAllowedHost(url)`、`userAgent`、`presets`（`List<TermPreset>?`）、`periodProfileId`、`captureMode`
  （`CaptureMode { fetch, currentPage }`，只实现了 fetch）。
- `ZfsoftAdapter`：构造参数加 `entryUrl / allowedHosts / userAgent / presets / periodProfileId`；`static const type = 'zfsoft'`；
  登录判定与「注入前 host 检查」都改成认 `allowedHosts`（不给时 = baseUrl 的 host，与 1.2.0 一致）；
  WebView 有 `userAgent` 时 `setUserAgent`。
- `ImportResult` 新增 `termCode`（`ZfsoftAdapter.termCodeOf`：`2026`+`3` → `2026-2027-1`，12→2，16→3）、`detectedPeriods`
  （正方接口不带时刻，恒为 null）、`schoolId`、`systemType`、`sourceTag`。
- `detectedStartDate` 识别不到周次时为 **null**（删掉了 `nearestPreset`），warning 改为「请在下一步选择本学期第一周的周一」。
- 导入时生成 `Course.groupId`（`<sourceTag>-g-<hash(kch|jxbmc)>`，没有 kch 用课程名）与 `externalKey`
  （`kch|jxbmc|星期|起-止`，同一时段因换教室拆成多条时加 `#2`…保证唯一；无固定时间的课 `sjk|kch|jxbmc`）。
- 抓取脚本 `fail()` 在 `__NOTJSON__` / `__LOGIN__` 时带回 `sample`（原始响应前 204800 字符），只给诊断样本用。
- 通道消息多了一种 `ChannelMessageKind.diagnostic`（`{diag:true, url, html}`，我们自己注入的「页面快照」脚本发的）。

#### 4. 预览页
- 作息：`ImportPreviewDefaults.periods(detected, current, periodProfileId)` = 识别出的 ?? 当前课表作息 ?? 模板
  （`presets.dart` 新增 `PeriodTemplate` / `periodTemplates` / `periodTemplateById`，目前只有 `default-12`「通用 12 节」，
  界面按列表写）。预览页新增「作息时间」一行，可以在 识别 / 沿用当前 / 各模板 之间改选；课程用到的节次超过所选作息时给提示。
  新建课表现在也沿用当前课表作息（以前固定上大 12 节）；覆盖时作息跟着所选项走（默认就是当前作息，行为不变）。
- 开学日期：识别到周次 → 推断值；识别不到 → 默认 `ScheduleUtils.nearestMonday(today)`（周一~周四取本周一，周五~周日取下周一，
  日历加减），卡片下方高亮提示 + 「选择日期」按钮；学校有 `presets` 时显示成快捷 chip（点了自动带上总周数）。
  没确认就点「确认导入」会先弹「确认开学日期」对话框（「对，导入」/「重新选择」）。**不再出现任何学校的校历日期作为默认值。**
- 写入改走新的 `AppState.applyImport(...)`：一次保存，覆盖时保留 `Timetable.name`；同时写 `schoolId / systemType / termCode / importedAt`。
- 右上角「导出诊断样本」（有 `diagnostics` 时）；写入成功、退回首页之前调 `onImported`（清登录态，失败不影响导入）。
- `ScheduleUtils` 新增 `mondayOf(date)` / `nearestMonday(date)`（都用 `addDays`）。

#### 5. Cookie / 网页存储清理 +「记住教务登录」
- `web/edu_session.dart`：纯策略 `shouldClearEduSession(rememberLogin, event)`——关掉开关时无条件清；其余（导入成功 / 离开登录页）
  不记住就清。`clearEduSessionIfNeeded(...)` 两步（`WebViewCookieManager().clearCookies()`、`WebViewController.clearLocalStorage()`，
  Android 上都是全局的）各自 3 秒超时、互不阻塞、不抛异常。`EduSessionStore` 接口方便测试替换。
- 时机：预览页写入成功后（awaited）；登录页 `dispose` 时如果还没清过（没导入就离开 / 失败后返回）也清一次（不 await）。
  **「离开登录页也清」是我加的**，PLAN 只写了导入成功后清；理由是导入失败的用户同样会把登录态留在 App 里（REVIEW-2 §7.3 的风险）。
- `AppSettings.rememberEduLogin`（默认 false，旧 JSON 缺字段 → false，没升 `settingsVersion`）+ `AppState.setRememberEduLogin`；
  设置页新增「教务导入」分组的开关，关掉时立刻清一次并 SnackBar 提示结果。

#### 6. 学校清单 `assets/schools.json`
- 结构按 PLAN：`{id,name,pinyin,aliases,type,entryUrl,baseUrl,allowedHosts,overrides:{},periodProfileId,status}`；
  `overrides` 认 `homeUrl / description / userAgent / termPresets`。上大是唯一条目、唯一 `verified`，上大校历预设从代码挪进了这里。
- `SchoolRegistry`：`ensureLoaded({bundle})` 异步读 asset 并缓存（并发调用只读一次），读不到 / 坏 JSON / 空清单 → 代码里的
  `fallbackJson`（只有上大，有测试盯着它和 asset 的关键字段一致）；之后 `byId` / `adapterFor` / `search` 同步可用；未加载时返回空不崩。
  `loadFromJson` 丢掉缺字段 / 重复 id 的条目并记 `lastLoadWarnings`；`search` 认名称 / id / 别名 / 拼音连写 / 拼音首字母，
  排序 已验证 > 社区 > 实验。`main.dart` 启动后后台预读一次（课程详情里要显示校名）。
- 学校选择页：FutureBuilder 等加载；每行显示状态标签（`SchoolStatusChip`：已验证 / 社区 / 实验）；列表末尾「我的学校不在列表」→
  输入网址 → `SchoolUrlGuess.fromUrl`：路径里有完整的 `/jwglxt` 段就生成临时 experimental 正方条目（`baseUrl` 截到 `/jwglxt`，
  `homeUrl` = 源 + `/`，`entryUrl` = 用户给的地址去掉 fragment，`allowedHosts` = 该 host，id `custom-<host>`，没写 scheme 补 https），
  确认后打开；认不出 → 「暂不支持」+ `FeedbackLinks.unsupportedSchoolHint`。
- `lib/core/feedback_links.dart`：`FeedbackLinks.issuesUrl`（`OWNER/REPO` 占位）、`email`（空）、`isConfigured`、两段提示文案。**入口留给 Phase C。**

#### 7. 诊断样本
- `diagnostics/redact.dart`：`redactSensitive(text, extraSecrets)` 纯函数——已知字面量（学生姓名）→ `xm/xsxm/姓名` 字段
  （JSON、再转义一层的 JSON、`xm=` 查询串、`姓名：` 文本）→ 手机号（可带 +86 / 空格 / 短横线）→ 独立的 8~12 位数字，全部换成 `***`；
  `truncateUtf8` 按字节截断不切坏汉字。
- `diagnostics/diagnostic_sample.dart`：`DiagnosticSample.build`（纯函数，先脱敏再截断，每段 ≤ 200KB）写头部元信息
  （app 版本、时间、学校、系统、状态、URL、阶段、错误）+ `response`（通道原始消息）+ `page`（页面 HTML 快照）；
  `exportAndShare` 写到 `getTemporaryDirectory()/import-diagnostic-yyyyMMdd-HHmmss.txt` 并 `SharePlus.instance.share`。
- 入口：登录页的错误对话框（抓取超时 / 解析失败 / 没解析到课程时多一个「导出诊断样本」按钮 + 说明）、登录页右上角「更多」菜单、预览页右上角。
- 已知取舍：8 位课程号、`20260914` 这种日期也会被当学号抹掉；`kbList` 里的 `xm` 是教师名，也会被抹掉（样本仍是合法 JSON，测试确认）。

#### 8. 来源标记
- 课程 `source` = `ImportResult.sourceTag` = `Timetable.sourceTagOf(systemType, schoolId)`，上大仍是 `zfsoft-shu`（课程 id 前缀也不变，
  覆盖导入不会换 id）。`Timetable.sourceTag` getter 改用同一个函数。
- 课程详情 `courseSourceLabel(source, schoolNameOf:)`（纯函数）：manual / backup / 任意 `<type>-<schoolId>`（含旧值 `zfsoft-shu`）
  → 「来自教务系统导入（校名）」，查不到校名时不带括号。

#### 删除 / 改名
- 删掉 `presets.dart` 的兼容别名 `shuDefaultPeriods` / `shuTermPresets`，删掉 `ZfsoftAdapter.nearestPreset` 与 `static const sourceTag`。
  全仓库 grep 已无引用。`SchoolRegistry.all` 不再存在（改为 `entries`，元素是 `SchoolEntry`，要适配器用 `buildAdapter()` / `adapterFor(id)`）。

#### Phase C 可以直接用的公共 API
- `FeedbackLinks.{issuesUrl, email, isConfigured, unsupportedSchoolHint, diagnosticHint}`（`lib/core/feedback_links.dart`）。
- `DiagnosticSample.exportAndShare(DiagnosticInput)` / `build(...)`；`redactSensitive` / `truncateUtf8`。
- `AppState.applyImport({overwriteId, name, courses, config, schoolId, systemType, termCode, importedAt})`
  ——「从文件导入课表」新建单表时也可以复用（`overwriteId: null`）。
- `AppState.setRememberEduLogin`、`AppSettings.rememberEduLogin`；`clearEduSessionIfNeeded` / `EduSessionEvent` / `WebViewEduSessionStore`。
- `SchoolRegistry.{ensureLoaded, byId, adapterFor, search, entries}`、`SchoolEntry`、`SchoolStatus.label`、`SchoolStatusChip`、`systemTypeLabel`。
- `periodTemplates` / `periodTemplateById`；`ScheduleUtils.mondayOf` / `nearestMonday`；`Timetable.sourceTagOf`；`courseSourceLabel`。
- `url_launcher` 已在依赖里（Phase C 检查更新 / 反馈跳转直接用，`LaunchMode.externalApplication`）。

#### 没做 / 已知问题
- **没有真机 / 模拟器验证**：外跳、Cookie 清理、诊断样本分享、`onNavigationRequest` 对 SSO 链路的影响都只有单测 / 源码阅读；Phase D 要走一遍。
- 设置页关掉开关时用 `WebViewController()` 临时建一个 controller 清网页存储（Android 上会建一个原生 WebView 对象），没实测开销。
- 离开登录页时的清理是异步的：用户退出后马上重新进入登录页，理论上可能清掉新会话刚写的 Cookie（窗口期很短，没复现）。
- `CaptureMode.currentPage` 只是枚举，没有任何实现；`detectedPeriods` 对正方恒为 null。
- 实验学校在登录页没有额外的「未验证」横幅（只在打开前的对话框里提示）。
- 设置页 / 关于页 / 作息编辑页里仍有「恢复上海大学默认」之类文案，属于 Phase C 的去上大化文案，本阶段没动；Manifest label 等品牌也没动。
- `schools.json` 没有签名、没有远程更新（REVIEW-2 L2 的远程清单在 1.4）。

#### Phase B 改动文件
- 新增：`assets/schools.json`；`lib/core/feedback_links.dart`；`lib/features/import/diagnostics/{redact,diagnostic_sample}.dart`；
  `lib/features/import/web/{edu_session,external_navigation}.dart`；
  `test/import/{school_registry_test,diagnostics_test,edu_session_test}.dart`、`test/course_source_label_test.dart`。
- 修改：`pubspec.yaml`（url_launcher、assets/schools.json）/ `pubspec.lock`；`android/app/src/main/AndroidManifest.xml`（queries）、
  `android/app/src/main/res/xml/network_security_config.xml`；`lib/main.dart`；`lib/core/{presets,schedule_utils,app_state}.dart`；
  `lib/models/{app_settings,timetable,course}.dart`；`lib/features/import/adapters/{school_adapter,school_registry,zfsoft_adapter}.dart`；
  `lib/features/import/pages/{school_select_page,web_login_page,import_preview_page}.dart`；
  `lib/features/settings/settings_page.dart`；`lib/features/timetable/course_detail_sheet.dart`；
  `test/import/{zfsoft_adapter_test,import_preview_page_test}.dart`。

### Phase C：产品层（opus55）

**质量门（真实跑过）**：`flutter analyze` → `No issues found!`；`flutter test` → `+388: All tests passed!`
（Phase B 结束时 323 个，**新增 65 个**，旧测试只改了 `theme_registry_test` 里「上大蓝」→「经典蓝」两处）；
`flutter build apk --debug --target-platform android-arm64` → `√ Built build\app\outputs\flutter-apk\app-debug.apk`（EXIT=0，增量 19s，MainActivity.kt 重新编译过）；
`aapt2 dump badging` → `application-label:'简课表'`（所有 locale 同名），`package: name='cn.shu.schedule' versionCode='6' versionName='1.2.0'`（版本号留给 Phase D）。
`aapt2 dump permissions` 与 Phase B 的包一致：INTERNET + WAKE_LOCK / ACCESS_NETWORK_STATE / RECEIVE_BOOT_COMPLETED / FOREGROUND_SERVICE
（manifest-merger-blame 报告确认四个都来自 `androidx.work:work-runtime:2.11.2`，由 home_widget 引入）+ androidx.core 的
`cn.shu.schedule.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`。package_info_plus 没有带进新权限。

新增测试文件（都在 `test/`）：`course_entry_test.dart`（9）、`timetable_share_test.dart`（11）、`date_override_editor_test.dart`（9）、
`update_checker_test.dart`（16）、`privacy_and_about_test.dart`（20）；共用工具 `helpers/harness.dart`（`settleWithRealIo` / `TempStorage` / `loadState` / `pumpApp`）。

#### 1. 品牌「简课表」
- `lib/core/app_brand.dart`：`AppBrand.name = '简课表'`、`AppBrand.slug = 'jiankebiao'`、`AppBrand.tagline`；
  `appVersion` 常量也从 about_page 挪到这里（about_page `export` 它，老 import 不用改）。**Phase D 发版时改这里的 `appVersion`**。
- Android：`strings.xml` 新增 `app_name`（= 简课表），`widget_day_label` 改成 `@string/app_name`，Manifest `android:label="@string/app_name"`；
  资源 / Manifest 注释里的「上大课表」一并改掉。shortcuts 的长短标签本来就不含品牌名（「今日课程」等），没改。
  `DayWidgetProvider.kt` / `DayWidgetService.kt` 只有注释里写「上大课表」，**没有硬编码文案**（运行时文字都来自 strings.xml），没动。
- Dart：MaterialApp title、周视图无课表时的标题、设置页「关于简课表」、关于页（重写：去掉上大统一身份认证等说法，补了分享 / 调休 / 隐私入口）、
  `add_widget_helper` 手动步骤、`periods_editor_page`「恢复默认作息」（弹窗内容改成「内置的每天 12 节示例作息」）。
- 备份文件名 `jiankebiao-backup-<时间戳>.json`（`BackupService.backupFileName`），分享标题 / 文案用 `AppBrand.name`。
- 主题「上大蓝」改名「经典蓝」（themes.json 与内置兜底主题；**id 仍是 `shu`**，存档里的 themeId 不受影响）。
- `pubspec.yaml` description 改了；`name: shu_schedule` 没动（是 Dart 包名，改了要全仓库改 import）。
- `grep -rn "上大\|上海大学\|SHU\|shu_" lib android/app/src/main/res` 只剩 `school_registry.dart` 225-226 行（`fallbackJson`，是 `assets/schools.json` 上大条目的兜底副本，按约定保留）。
  presets / schedule_utils / week_layout / zfsoft_adapter 等注释里的「上大 / 上海大学」都改成了中性说法。
  `privacy_and_about_test` 里有一个扫描 `lib/` 与 `res/` 的测试盯着（排除 school_registry.dart）。

#### 2. 手动录入提效（`course_editor_page.dart` / `course_form.dart`）
- **保存并继续添加**（只在新建时出现，`course-save-continue`）：保存后留在本页，保留星期 / 起止节次 / 周次，清空课名、教师、教室、备注、
  「复制到其他星期」的勾选，颜色回到按课名自动；SnackBar「已添加「X」，继续填下一门（本页已加 N 门）」，焦点回到课名。
  下一门是独立的新课（groupId 按本次是否勾了其他星期重新决定，不会沿用上一门的）。
- **复制到其他星期**：编辑器「时间」下面一排 FilterChip（不含本课的星期），保存时 `CourseForm.copiesToDays` 生成副本：
  新 id、同一个 `groupId`（新建时 `appState.newId()`；编辑已有分组的课沿用原 groupId；编辑无分组的课时原课也被分进新组）、
  `externalKey` 清空、`source = manual`。新建走新的 `AppState.addCourses`（一次保存）；编辑是 `updateCourse` + `addCourses`。
  颜色同步沿用 Phase A 的 `updateCourse(syncGroupColor)`。
- **历史补全**：教师 / 地点换成 `Autocomplete<String>`（传入原来的 controller + FocusNode），候选 = `CourseForm.historyValues`
  （当前课表已有值，trim 去重，按出现次数降序）经 `matchSuggestions` 过滤（空输入不提示、前缀优先、忽略大小写、和输入完全相同的不重复提示、最多 8 条）。
- **周视图长按空格子新建**：这个在 v1.x 就已经有了（`_cellBackground` 的 `InkWell.onLongPress → CourseEditorPage(initialDay, initialStartPeriod)`），
  这次只给每个格子加了 `ValueKey('cell-<星期>-<节次>')` 并补测试。已有课的格子被课程块盖住，长按 = 按下松开 = 点开详情（和以前一样），不会新建。
  注意：**课表一门课都没有时显示的是空状态引导，不是网格**，所以空课表不能长按新建（空状态有「手动添加」按钮）。

#### 3. 单张课表分享与导入（`features/settings/timetable_share.dart`）
- 格式：`{version: 2, kind: "timetable", app: "简课表", exportedAt, timetables: [一张]}`，**不带 settings**；
  文件名 `简课表-<课表名>-yyyyMMdd.json`（`safeFileName` 把 `\/:*?"<>|` 与控制字符换成 `_`，最长 40 字，空了叫「课表」）。
- 导入：`TimetableShare.parse` = `Storage.importJson`（复用 v1→v2 迁移；1.2.0 的完整备份、无 version 的旧单表都能读），一张课表都没有时抛
  `FormatException`；`importInto` 对每张表调用 `AppState.applyImport(overwriteId: null, …)` 新建（永不覆盖），名字冲突加「（2）（3）」，
  **课程 id 重新生成**（同一个文件导两次不会有两张表共用课程 id），groupId / externalKey / 调休 / 导入元数据原样保留，最后一张成为当前课表。
  文件里的 settings（主题等）一律忽略。
- 入口：课表管理页每张课表的 ⋮ →「分享此课表」；课表管理页右上角「从文件导入课表」；设置页「备份」组也加了一条「从文件导入课表」
  （共用 `importTimetableFromFile`）。file_picker / share_plus 通过 `TimetableShare.pickText` / `shareFile` 两个可替换的静态函数调用，测试里换掉。

#### 4. 调休 / 停课编辑 UI
- 学期设置页新增「调休 / 停课」分组：按日期排序列出 overrides（`2026-10-10 周六` / 「按周一的课上 · 国庆调休」，停课红色图标、调休 accent 色图标），
  点一条编辑，右边删除（SnackBar 可撤销），末尾「添加调休 / 停课」。
- 编辑页 `DateOverrideEditorPage`（`date_override_editor.dart`）：日期（默认今天，可改）→ SegmentedButton 三选一
  「停课 / 按某个星期上课 / 指定周次」；「按某个星期」必选星期、可再选周次，「指定周次」必选周次、可再选星期（组合就是 weekday + week）→ 备注（≤30 字）。
  纯数据 `DateOverrideDraft`（`validate` / `toOverride` / `from`）和 `describeDateOverride` 有单测。
- 写入走 `AppState.setDateOverride`；编辑时改了日期会先删旧日期那条；新日期已经有设置时先弹框确认替换。
- 周视图 / 今日页 / 小组件沿用 Phase A 的展开逻辑（停课那天不画课），没改。

#### 5. 检查更新（`lib/core/update/`）
- `update_config.dart`：`sources` = GitHub raw + jsDelivr 两个 `OWNER/REPO` 占位地址；`isConfigured` / `sourcesConfigured(list)`（有占位符或空列表 = 未配置）；
  每源超时 5 秒；`latest.json` 最大 64KB。
- `update_checker.dart`：`UpdateInfo.fromJson`（`versionCode` 可以是数字或数字字符串、必须 ≥1；`versionName` 必填；`changelog` 字符串或字符串数组；
  `downloadUrls` 只留 http(s)；`sha256` 必须 64 位十六进制，转小写）；`UpdateChecker(sources, timeout, fetch, currentVersionCode)`：
  未配置直接 `notConfigured` 不发请求；依次尝试每个源（每个源都 `.timeout(timeout)`，卡住的源不拖后面），第一个合法的为准；
  `isNewer(remote, current)`：本机 versionCode 读不到（0）时不提示；`shouldAutoCheck`：已同意隐私、已配置、本地日历日今天还没查过（上次时间在未来也查）。
  默认网络 `httpFetch` 用 `dart:io HttpClient`，只允许 https，User-Agent `jiankebiao-update-check`（不带机型），非 200 / 超 64KB 抛异常。
  本机版本用 `package_info_plus`（`flutter pub add package_info_plus` → `^10.2.1`；它顺带拉进了 `http` 包，只给 web 用）。
- `update_dialog.dart`：`showUpdateDialog`（版本、更新日志、可选中的 SHA-256；「稍后」/「去下载」→ `launchUrl(mode: externalApplication)`
  依次试 downloadUrls，全失败 SnackBar）；`runAutoUpdateCheck`（先写 `lastUpdateCheck` 再请求，失败也算查过；有新版才弹框）；
  `runManualUpdateCheck`（「正在检查…」→ 新版弹框 / 「已是最新版本」/「检查更新失败：…」）。
- `AppSettings.lastUpdateCheck`（DateTime?，旧存档 → null）+ `AppState.setLastUpdateCheck`。手动检查也会写这个时间（所以手动查过当天不会再自动查）。
- 设置页「关于」组：「检查更新」——未配置时副标题「未配置更新源」且禁用；配置后显示上次检查时间。
- 启动时机：`HomeShell._startupFlow`（AppState 加载完的第一帧之后，隐私确认之后）调用一次 `runAutoUpdateCheck`。

#### 6. 隐私说明 + 首启确认 + 反馈
- `assets/privacy.md`（登记进 pubspec assets），按 REVIEW-2 §7.6 写了 8 节：开发者与联系方式（占位「待补充」）、收集了什么
  （课表仅本地；教务导入时学校能看到 IP 与 WebView UA 里的机型；检查更新暴露 IP；学校清单内置不联网；分享 / 诊断样本由用户决定）、
  权限清单（按上面 aapt2 结果如实列 INTERNET + 4 个 androidx.work 普通权限 + androidx.core 内部权限）、第三方组件清单
  （pubspec 全部 12 个运行时依赖逐个写是否联网；有测试确认清单覆盖 pubspec 的每一个依赖）、存储位置 / 期限 / 删除方式、未成年人、
  更新日期与变更说明、用户权利。
- `lib/core/privacy_policy.dart`：`PrivacyPolicy.version = 1`、`updatedAt`、`assetPath`。实质内容变了就加 1，老用户会再确认一次。
- `privacy_page.dart`：不加 markdown 依赖，自己按行解析（`parseSimpleMarkdown`：# / ## / ### 标题、-/* 列表（2 空格一级缩进）、`1.` 有序列表、
  续行拼接（中文直接接、英文补空格）、`>` 引用、`---`；`parseInlineMarkdown`：`**粗体**`、`` `代码` ``）；`PrivacyPage` 读 asset 渲染；
  `showPrivacyConsentDialog`：不可点外面关、不可返回键关，摘要 4 条 +「阅读完整隐私说明」+「不同意并退出」/「同意」。
- `AppSettings.privacyAcceptedVersion`（int，旧存档 → 0，所以 1.2.0 覆盖安装的老用户也会看到一次）+ `AppState.acceptPrivacy`。
  `restoreFrom`（覆盖式恢复备份）保留本机的 `privacyAcceptedVersion`（取较大值）和 `lastUpdateCheck`：恢复旧备份不会再弹一次隐私确认。
- **同意前不联网**：`HomeShell._startupFlow` 先过隐私这一关，之后才 ①取冷启动快捷方式动作（`import` 会打开教务网页）②处理同意前通过 `actions` 流到达、
  被挂起的动作 ③自动检查更新。不同意 → `SystemNavigator.pop()`（可注入 `onPrivacyDeclined`）。
  核对过启动期其他请求：`main.dart` 的 `SchoolRegistry.ensureLoaded()` 读的是 `rootBundle` 的 `assets/schools.json`（本地，保留）；
  主题读本地 asset；`WidgetSync.push` 写本地 SharedPreferences；都不联网。WebView 只在进入导入流程时才创建。
- 反馈：设置页「反馈」→ `showFeedbackDialog`：已配置（`FeedbackLinks.isConfigured`）时「去 GitHub 反馈」外跳 Issues；未配置时只显示提示、不给链接；
  两种情况都有「复制诊断信息」（`DeviceDiagnostics.format`：`简课表 v<版本>（<build>）/ Android <版本>（API n）/ 机型：<厂商 / 品牌> <型号>`）；
  `FeedbackLinks.email` 非空时多一个「复制邮箱」（现在是空串，所以不显示）。
  设备信息来自 `NativeBridge.deviceInfo()` → MainActivity 新增的 `getDeviceInfo`（只读 `Build.VERSION.RELEASE / SDK_INT / MANUFACTURER / BRAND / MODEL`，
  不需要权限），**没有加 device_info_plus**。`FeedbackLinks.unsupportedSchoolHint` 的「反馈入口将放在…」改成「反馈入口在「设置 → 反馈」」。

#### 7. README
- 仓库根 `README.md` 重写为面向用户：简介、下载与安装（通用 / 华为荣耀含纯净模式 / 小米 / OPPO / vivo，HarmonyOS NEXT 不能装 APK）、首次打开的隐私确认、
  一键导入步骤、扫码登录外跳说明、导不进来的兜底（分享课表 → 手动录入四件套 → 诊断样本）、桌面小组件、调休设置、设置一览、隐私（零上传、
  App 只申请 INTERNET，另有 4 个自动合并的普通权限——**没有写「只有一个权限」**，因为 aapt2 实测不是）、常见问题、已知限制、版本历史（1.0.0~1.3.0 各一行）。
  旧 README 备份在 `.tmpbuild/README.v1.2.0.bak`（临时目录，Phase D 可删）。

#### 和 PLAN / 任务描述不完全一样的地方
- 「反馈」不是直接跳转，而是先弹一个对话框（已配置时里面有「去 GitHub 反馈」）：这样两种状态都能「复制诊断信息」，用户提 issue 时能直接粘贴。
- 「保存并继续添加」之后颜色也重置为按课名自动（否则下一门会沿用上一门的颜色）。
- 编辑已有课程时也能「复制到其他星期」（原课会被分进同一个新组）。
- 设置页「备份」组额外加了一个「从文件导入课表」入口（和课表管理页右上角是同一个函数）。

#### 没做 / 已知问题
- **没有在模拟器 / 真机上看过**：隐私弹窗、调休编辑页、Autocomplete 下拉在小屏上的样子、分享面板、`getDeviceInfo` 实际返回值、检查更新的真实网络请求
  （更新源是占位符，真实 `httpFetch` 没打过外网；只有 https 限制的单测）。Phase D 需要走一遍。
- 更新源、Issues 地址、联系邮箱、隐私说明里的开发者信息全是占位；**换成真实仓库时要同时改 `update_config.dart`、`feedback_links.dart`、`privacy.md` 第一节**，
  改了 privacy.md 的实质内容记得把 `PrivacyPolicy.version` 加 1。
- 4 个 androidx.work 权限没有去掉（`tools:node="remove"` 可能影响 home_widget 的后台刷新，没验证过），只在隐私说明和 README 里如实写明。
- `appVersion`（显示用）仍是 `'1.2.0'`，pubspec 仍是 `1.2.0+6`，按约定留给 Phase D。自动检查比较的是 package_info 的 buildNumber，不受这个字符串影响。
- 「不同意并退出」用 `SystemNavigator.pop()`，Android 上是结束 Activity；下次打开仍会再弹（没有「不同意但继续离线使用」的选项）。
- 空课表时周视图是空状态页，没有网格，所以不能「长按空格子新建」。
- 调休编辑没有限制日期必须在学期内（学期外的日期也能设，Phase A 的展开逻辑会照常处理）。
- 单表分享没有做二维码（REVIEW-2 §4 提到的「压缩后生成二维码」），只有文件。

#### Phase C 改动文件
- 新增：`lib/core/{app_brand,privacy_policy,device_diagnostics}.dart`、`lib/core/update/{update_config,update_checker,update_dialog}.dart`、
  `lib/features/settings/{timetable_share,date_override_editor,privacy_page,feedback_dialog}.dart`、`assets/privacy.md`；
  测试 `test/{course_entry,timetable_share,date_override_editor,update_checker,privacy_and_about}_test.dart`、`test/helpers/harness.dart`。
- 修改：`pubspec.yaml`（description、package_info_plus、assets/privacy.md）/ `pubspec.lock`；
  `android/app/src/main/{AndroidManifest.xml, res/values/strings.xml, res/xml/{day_widget_info,network_security_config}.xml, res/layout/{widget_day,widget_day_item}.xml}`（后三者只改注释）、
  `android/app/src/main/kotlin/cn/shu/schedule/MainActivity.kt`（`getDeviceInfo`）；
  `lib/app.dart`（`main.dart` 核对过、没改）；`lib/core/{app_state,native_bridge,feedback_links,presets,schedule_utils}.dart`、
  `lib/core/theme/{theme_registry,theme_controller}.dart`、`lib/models/{app_settings,timetable}.dart`、
  `lib/features/settings/{settings_page,about_page,backup_service,timetable_manage_page,term_settings_page,periods_editor_page}.dart`、
  `lib/features/timetable/{course_editor_page,course_form,week_view_page,week_layout}.dart`、`lib/features/widgets/add_widget_helper.dart`、
  `lib/features/import/adapters/{school_adapter,school_registry,zfsoft_adapter}.dart`（只改注释）、`assets/themes/themes.json`（主题名）；
  `test/theme_registry_test.dart`；仓库根 `README.md`。

### Phase D（Fable，2026-09-23）集成与交付
- 版本 `1.3.0+7`，`appVersion` 常量同步为 1.3.0。仓库根 `git init`（分支 main），`.gitignore` 排除 keys/、key.properties、dist/、shots/、.tmpbuild/、build 产物、design/.omx。首个提交 8ad7a80。
- 发布包：`dist/简课表-v1.3.0.apk`（universal，58,240,362 B）、`dist/简课表-v1.3.0-arm64.apk`。aapt2：versionCode 7、versionName 1.3.0、label 简课表。
- 模拟器 shu35（API 35）从 release 签名的 1.2.0 `adb install -r` 覆盖安装：示例课表、学期设置、主题全部保留；首启弹隐私说明，同意后进入周视图。
- 真机操作验证（截图 shots/v130/）：设置页新分组（记住教务登录、从文件导入课表、检查更新=未配置更新源禁用态、隐私说明、反馈）；学期设置 → 添加调休/停课 → 保存后周视图日期头显示「停课」且整列不画课、今日页显示「今天停课。」、桌面小组件当天显示无课；导入课表页显示「上海大学 已验证」+「我的学校不在列表」→ 输入含 /jwglxt 的网址识别为「正方教务（实验）」；周视图长按空格子打开新建课程并带入周六/第 1 节，编辑器有「复制到其他星期」「保存并继续添加」和教师/地点历史补全提示。
- 没验证的：真实教务登录到导入（本机连不上 shu.edu.cn）、扫码外跳、Cookie 清理、诊断样本分享面板、单表分享/导入的系统文件选择器、检查更新的真实网络请求（更新源仍是 OWNER/REPO 占位）。
- 遗留：小组件在停课日显示「这天没有课」而不是「停课」（Kotlin 未读 label）；更新源、Issues 地址、隐私说明里的开发者信息需要用户建好 GitHub 仓库后一次性替换；keystore 口令仍在 keys/README.txt 明文里，需要用户自己改口令并异地备份。

## v1.3.1 (2026-10-06) 节假日一键套用

学期设置 →「调休 / 停课」新增「套用节假日安排」：按内置数据一次勾选写入整学期的放假 / 补课；顺带修掉 1.3.0 的遗留「小组件停课日仍显示『这天没有课』」。版本 `1.3.1+8`，`appVersion = '1.3.1'`。没有新增网络请求（数据打包在 asset 里；「查看来源」只是交给系统浏览器打开），`privacy.md` 未改。

### 数据：`assets/holidays.json`（已登记进 pubspec assets）
- `national.2026`：国务院办公厅关于2026年部分节假日安排的通知（国办发明电〔2025〕7号，2025-11-04），
  https://www.gov.cn/gongbao/2025/issue_12406/202511/content_7048922.html 。7 个节日，每个 `off`（放假）+ `work`（调休上班）。
- `schools.shu.terms[0]`（2026-2027 学年秋季学期，2026-09-14 开学，18 周，13 条）：
  校历 https://bksy.shu.edu.cn/jxxl/jnxl.htm （上海大学2026-2027学年校历，本科生院）；
  放假通知 https://www.shu.edu.cn/info/1051/400395.htm （关于2026年中秋节、国庆节放假安排的通知，党政办公室，2026-09-08）。
  9/20 上 10/6（周二）的课、10/10 上 10/7（周三）的课；9/25-27、10/1-7 停课；2027-01-01 停课（校历标注，补课以学校通知为准）。
- 内容按任务给定的已核对版本逐字写入，本阶段没有再联网核对。

### 规则（`lib/core/holiday_presets.dart`）
- `HolidayPresets.fromJson`（容错：缺名字的节日、解析不了的日期、既不停课也没有合法 `actAsDate` 的学校条目、缺开学日期 / 周数的学期、同一天重复的条目都丢掉，不抛）；
  `loadBundled()` 读 rootBundle 并缓存，读不到 / 坏 JSON → 空数据（页面显示空状态）。
- `planFor(config, schoolId) → HolidayPlan{title, sourceText, sourceUrl, items}`；`suggestionsFor` = `planFor(...).items`。
  学期范围 = `[startDate, startDate + totalWeeks*7 - 1]`（`ScheduleUtils.addDays`），只返回范围内的日期，按日期排序。
- 学校路径：`schools[schoolId]` 里先找开学日期（对齐周一后按 dateKey）相同的学期，再找日期范围重叠的；
  `cancelled` → `DateOverride.cancelled(note)`；`actAsDate` → `DateOverride.actAs(week: rawWeekOf(actAsDate, config), weekday: actAsDate.weekday, note)`，
  算出的周 <1 或 >totalWeeks 时带 `warning`（仍可套用）。标题「<校名> · <学期名>」，来源 = 通知；校历（更新日期），链接优先通知。
- 国家路径（没有 schoolId / 学校没有对得上的学期）：学期覆盖到的每个有数据的年份，`off` → 停课（备注「<节日>放假（国家安排）」）；
  `work` → `override == null, needsConfirmation == true`，文案「9月20日（周日）国家调休上班，学校按哪天的课上要看教务通知后手动设置」。标题「国家法定节假日（2026）」。
- `HolidaySuggestion.existing` = 当前课表那天已有的设置；`alreadyApplied`（相同）/ `conflicts`（不同）/ `applicable`（有 override 且未设置）。
- `AppState.applyDateOverrides(Map<DateTime, DateOverride>, {timetableId})`：一次 `_commit()`（只通知 / 保存一次），只覆盖传入的日期，其余手动设置不动；空表 / 没课表是空操作。

### 界面
- `term_settings_page.dart`：「添加调休 / 停课」上方 `override-apply-holidays`（没课表时禁用），push `HolidayApplyPage`。
- `holiday_apply_page.dart`：头部卡片（方案标题、来源、「查看来源」→ 复用 `core/update/update_dialog.dart` 的 `launchExternally`
  ——`external_navigation.dart` 里只有纯函数 `planNavigation`，没有 launcher helper；固定提示「以学校教务通知为准…」）；
  每条 `holiday-item-<yyyy-MM-dd>`：普通 → 默认勾；冲突 → 默认不勾 + 红字「将覆盖：…」；已设置 → 勾 + 禁用 + 右侧「已设置」；
  需要确认 → 普通 ListTile + info 图标，没有勾选框；warning 红字。底部 `holiday-apply`「套用 N 条」（N=0 禁用）→ 写入、返回、SnackBar「已套用 N 条调休 / 停课」。
  没有方案 → 「没有找到适用于当前学期的节假日安排」+ 手动添加提示。测试可注入 `presets`。

### 小组件停课文案（Kotlin）
- `WidgetSnapshot.kt`：`WidgetDay` 多了 `label` / `note`（`optStringOrNull`，缺 / null / 空白 → null）。
- `DayWidgetProvider.render`：`label == "停课"` 时空态用新字符串 `widget_empty_today_cancelled`「今天停课，好好休息 ✨」（offset 0）/
  `widget_empty_other_day_cancelled`「这天停课」，`note` 非空且不是「停课」（无备注时 Dart 写的是 description「停课」）时另起一行附上。调休日不变。

### 质量门（真实跑过）
- `flutter analyze` → `No issues found!`；`flutter test` → `+411: All tests passed!`（1.3.0 是 388，新增 23：
  `holiday_presets_test.dart` 13、`app_state_holiday_apply_test.dart` 3、`holiday_apply_page_test.dart` 7）。
  中途 `privacy_and_about_test` 的品牌扫描抓到 `holiday_presets.dart` 两处注释写了「上海大学」，已改成中性说法（校名只在 asset 里）。
- `flutter build apk --release` → 55.7MB，`dist/简课表-v1.3.1.apk` = 58,357,106 B，aapt2 `versionCode='8' versionName='1.3.1'`、label 简课表。
- **arm64 包没有用 `--split-per-abi` 的产物**：按任务先跑了 `flutter build apk --release --split-per-abi`（成功），但 aapt2 显示 arm64 分包是
  `versionCode='2008'`（Flutter 给分包加 ABI 前缀 2000）。而 `dist/简课表-v1.3.0-arm64.apk` 是 `versionCode='7'`——装了 2008 的人以后无法再
  覆盖安装 universal 的 9、10…，升级链会断。所以改用 1.3.0 同样的方式 `flutter build apk --release --target-platform android-arm64` 重打：
  `dist/简课表-v1.3.1-arm64.apk` = 21,177,992 B，`versionCode='8' versionName='1.3.1'`；`unzip -l` 的 lib/ 结构和 1.3.0 arm64 包完全一致
  （libflutter / libapp 只有 arm64-v8a；libdartjni、libdatastore_shared_counter 三个 ABI 都有，所以 aapt2 的 native-code 列出三个 ABI——
  这意味着 32 位 armv7 手机能装上但会因缺 libflutter 闪退，1.3.0 起就这样，没改）。

### 模拟器（shu35，API 35，截图 `shots/v131/`）
- `adb install -r` universal 包覆盖 1.3.0（versionCode 7 → 8），示例课表与已有的 9/23 停课保留。示例课表开学日期本来就是 2026-09-14、schoolId 为 null，所以看到的是国家方案。
- 01 周视图；02 学期设置里的新入口（在「添加调休 / 停课」上方）；03/04 套用页：标题「国家法定节假日（2026）」、来源、查看来源、提示语，
  9/20、10/10 两条为 info 图标 + 「国家调休上班…」无勾选框，其余 10 条默认勾选，「套用 10 条」；取消 / 重新勾 10/7 → 9 / 10 条；
  05 套用后返回学期设置 +「已套用 10 条调休 / 停课」；06 列表里 10 条新设置 + 原 9/23 停课；07 再次进入：10 条都是「已设置」禁用、「套用 0 条」禁用；
  08 桌面小组件今天（10/6）显示「今天停课，好好休息 ✨ / 国庆节放假（国家安排）」；09 翻到 10/7 显示「这天停课 / 国庆节放假（国家安排）」。

### 没验证 / 遗留
- 上大学校方案（schoolId = shu）只在单测 / widget 测试里验证，没在模拟器上看（要先真实导入上大课表才有 schoolId；本机连不上教务）。
- 「查看来源」没点（会拉起系统浏览器访问外网）。冲突行、warning 行在真机上的样子没看，只有 widget 测试。
- 没有停课备注的停课日（例如 9/23）小组件只显示一行「这天停课」——逻辑上如此，没单独截图。
- 套用页里需要确认的行（ListTile + leading 图标）与勾选行（CheckboxListTile）标题左边距不完全对齐，属于观感小问题，没调。
- 数据只有 2026 国家安排和上大 2026 秋；2027 国家安排（含 2027 元旦、春节）发布后要补进 `holidays.json`。没有远程更新。
- 学校路径下 `actAsWeek` < 1 的条目会被存下来，但 `DateOverride.fromJson` 会把 <1 的周丢掉（重新加载后退化为「这一天本身所在的周」）；界面已用 warning 提醒检查开学日期。

## v1.4.0 (2026-10-07)

依据 `PLAN-1.4.md`（REVIEW-3-market 第六节前 7 条）。同一工作树串行 A → F（G 只读审查，之后修复轮 + 最终打包）。
每个任务一节，统一分为「实现 / 测试 / 模拟器 / 和 PLAN 的偏差 / 没验证 / 遗留」（F 多一个「打包」）；交接单在 `.tmpbuild/plan14/handoff-<字母>.md`。
任务 F 整理格式时没有删改 A–E 记录的事实，只把小标题统一成 `####`，并在 F 已处理的遗留项后面加「（F：…）」。

| 任务 | 内容 | `flutter test` | 模拟器上装的 release 通用包 |
|---|---|---|---|
| A | 更新源一处配置 + Gitee 镜像 + 假日表远程下发 | 411 → 458 | 没打包 |
| B | 本地课前提醒 | 458 → 513 | versionCode 8，sha256 前缀 acb95220 |
| C | 小组件自动切明天 + 状态头部 + 2×1 | 513 → 519（另有 Kotlin JVM 单测 20） | 56.2MB，18958a636913d10b |
| D | ICS 导出 | 519 → 543 | 59,062,475 B，13143932963b35a3 |
| E | 周视图长按列头设调休 + 空状态三入口 | 543 → 573 | 59,078,951 B，d290bdb4de2069ad（第二次） |
| F | 版本 1.4.0+9、文档、打包、模拟器升级验证 | 573（无新增） | 59,078,951 B，db6adb891f572ccb，**versionCode 9** |

修复轮已定的待修项（`.tmpbuild/plan14/fixlist-pre-G.md`，和 G 的发现合并后一起修）：① A 刷新失败也记刷新时间 → 只在 updated / unchanged 时记；
② C 自动看明天后 4×2 翻不回今天；③ E 普通周六也写「…（周一）复课」；④ B 折叠的通知组点开不切「今日」；⑤ D `BackupService` 仍有自己的分享代码。

### A：更新源一处配置 + Gitee 镜像 + 假日表远程下发（opus55）

#### 实现
**仓库配置收口（A1）**
- 新文件 `lib/core/repo_config.dart`：`RepoConfig{githubOwner, githubRepo, giteeOwner='', giteeRepo='', branch='main'}`，
  `isPlaceholder`（OWNER / REPO / 空串）、`isConfigured`、`hasGitee`、`issuesUrl`、`rawUrls(path)`（Gitee raw `gitee.com/{o}/{r}/raw/{branch}/{path}`
  → jsDelivr `cdn.jsdelivr.net/gh/{o}/{r}@{branch}/{path}` → `raw.githubusercontent.com/{o}/{r}/{branch}/{path}`，纯函数，开头的 `/` 去掉）。
  `const kRepo = RepoConfig(githubOwner: 'OWNER', githubRepo: 'REPO')` —— **发布前只改这一行**。`lib/` 里 `OWNER` / `REPO` 只剩这个文件（有测试扫描）。
- `UpdateConfig.sources` 改成 getter：`kRepo.rawUrls('latest.json')`（占位状态下仍是 2 个地址：jsDelivr、raw；**顺序和 1.3 相反**，raw 放最后）；
  `isConfigured = kRepo.isConfigured && sourcesConfigured(sources)`；`placeholder = RepoConfig.placeholderSlug`。
  `UpdateChecker` 记住是否用的默认源：默认源看 `kRepo`，注入的源仍按字符串里有没有 `OWNER/REPO` 判断（老测试的注入方式不变）。
- `FeedbackLinks.issuesUrl` / `isConfigured` 改成从 `kRepo` 派生的 getter（`email` 仍是空串常量）。
- `latest.json` 协议不变（versionCode / versionName / changelog / downloadUrls / sha256），只多认一个可选的 `"holidays": {"sha256"}`
  → `UpdateInfo.holidaysSha256`；`UpdateInfo.parseSha256` 抽成静态方法。没有改用 GitHub Releases API。「检查更新」仍然只提示、不阻断。
- `UpdateChecker.httpFetch(uri, timeout, {int maxBytes = 64 KiB})`：上限变参数，超限文案改成「响应超过 N KiB」，https 报错改成「只允许 https 地址」。
  带可选命名参数的静态方法仍可当 `UpdateFetch` 注入。

**假日表远程下发（A2）**
- `assets/holidays.json` 顶层加 `"updatedAt": "2026-10-06"`（文件保持 UTF-8 / LF / 无 BOM，有测试）。
- `HolidayPresets` 新字段 `version`（没写为 0）、`updatedAt`（DateTime?，只有日期）、`source`（新枚举 `HolidayDataSource.bundled / remote`），
  `isValid`（version == 1）、`updatedAtText`、`schemaVersion = 1`；`fromJson(json, {source})`：顶层 version 写了但 ≠ 1 → 返回不含条目的无效数据；
  **没写 version 仍按当前结构读**（老的容错测试用的手写 JSON 都没写 version）。远程 / 缓存走 `HolidayPresets.tryParseStrict`：必须是对象、version 恰好 1、updatedAt 合法，否则 null。
- 新文件 `lib/core/holiday_repository.dart`：
  - `HolidayRepository({UpdateFetch? fetch, RepoConfig repo = kRepo, FutureOr<Directory> Function()? dirProvider, Future<HolidayPresets> Function()? loadBundled, Duration timeout = 5 s, int maxBytes = 256 KiB})`；
    默认 fetch = `UpdateChecker.httpFetch(..., maxBytes: 256 KiB)`，默认目录 = 新增的 `Storage.dataDirectory()`（尊重 `overrideDirectory`）。
  - `load()`：内置（`HolidayPresets.loadBundled`，静态缓存不动）vs 缓存 `holidays.remote.json`；缓存能严格解析且 `updatedAt` 晚于内置才**整体**用缓存。坏缓存 / 旧缓存 / 读失败一律回退内置，不抛。
  - `refresh({force, required privacyAccepted, now, lastRefresh, onAttempt, manifest})` → `HolidayRefreshResult{status, presets, source, errors}`，
    `HolidayRefreshStatus.notConfigured / skipped / throttled / updated / unchanged / failed`。顺序：kRepo 占位 → notConfigured；未同意 → skipped；
    非 force 且距 `lastRefresh` 不满 24 小时（`shouldRefresh`，比的是两个时刻的真实间隔；上次时间在未来也放行）→ throttled；
    否则先 `onAttempt(now)`（失败也算刷新过，和检查更新一致），再按 `rawUrls('shu_schedule/assets/holidays.json')` 依次下载：
    UTF-8 字节 ≤ maxBytes → （有校验值时）SHA-256 一致 → `tryParseStrict` → 比当前 `load()` 新就 `Storage.writeAtomic` 写缓存 → updated，否则 unchanged（第一个合法来源为准）；全失败 → failed。
  - SHA-256：`manifest` 由调用方传入（自动检查更新后顺带刷新时就是那份 `latest.json`）；没传就自己按 `rawUrls('latest.json')` 读一次，读不到 / 没写就只靠 TLS。不一致的来源算失败、继续试下一个。
  - `refreshFor(AppState, {force, now, manifest})`：`privacyAccepted = privacyAcceptedVersion >= PrivacyPolicy.version`（要求同意 v2）、`lastRefresh/onAttempt` 接 `AppSettings.lastHolidayRefresh`。
- `Storage.writeAtomic(File, String)`（`_writeAtomic` 的公开版，失败时删临时文件；不走课表 / 设置的写队列）。
- `AppSettings.lastHolidayRefresh`（默认 null，toJson / fromJson / copyWith，不升 settingsVersion）；`AppState.setLastHolidayRefresh`；`restoreFrom` 保留设备上的值（同 `lastUpdateCheck`）。
- `HolidayApplyPage({presets, repository})`：头部 `holiday-data-version`「假日表 · 内置 2026-10-06」/「假日表 · 已更新 …」（列表页和空状态都有）；
  AppBar `holiday-refresh`（刷新时转圈禁用）→ `refreshFor(force: true)`，SnackBar：更新源未配置 / 同意隐私说明后才能联网更新假日表 / 假日表已更新（日期）/ 假日表已是最新 / 假日表更新失败：原因；
  updated 后重新 `load()`。进入页面：没注入 presets → `load()` 后静默非 force 刷新，updated 才重新读取；**只注入 presets 不注入 repository 时不做静默刷新**（老测试不碰网络、磁盘）。
  页面文案函数 `holidayDataVersionText` / `describeHolidayRefresh` 是顶层公开函数。
- `runAutoUpdateCheck(..., {HolidayRepository? holidays})`：检查结果是 available / upToDate 时，用这份 `latest.json` 做 manifest 调 `refreshHolidaysQuietly`（新的顶层函数，吞异常），和更新对话框并行，函数返回前等它结束；failed / notConfigured 不刷新。`HomeShell` 加可注入的 `holidayRepository`。
- 发版脚本 `shu_schedule/tool/gen_latest.py`（标准库）：版本默认读 pubspec，`--apk` 可重复（第一个的 SHA-256 进顶层 `sha256`，全部进 `apks`），
  `holidays{sha256, updatedAt, bytes}`（校验 version == 1、有 updatedAt、无 BOM、≤256 KiB，CRLF 警告），`downloadUrls` 默认从 repo_config.dart 的 kRepo 拼 Release 页（Gitee 在前），
  `--refresh-holidays` 只重算 holidays 一段；输出超过 64 KiB 拒绝。用 scratchpad 里的假 APK 跑过：sha256 与 `sha256sum` 一致，缺 APK 退出码 1。用法写在根 README「十一、发布（维护者）」。

**隐私与文案（A3）**
- `PrivacyPolicy.version` 1 → **2**，`updatedAt` → 2026-10-07（老用户升级后会再看到一次同意框，有测试）。
- `privacy.md`：检查更新改为 Gitee → jsDelivr → GitHub；新增第 3 种联网「更新节假日表」（触发时机、只有日期、校验、缓存文件名）；原「学校清单不会联网下载」一句改写为学校清单仍内置、假日表只从配置的仓库镜像下载并缓存；
  INTERNET 用途、Dart 标准库发请求、存储位置补上假日表；第三方组件加 `crypto`；更新记录加第 2 版。
- 同步：隐私确认框（privacy_page.dart）、设置页「隐私说明」副标题「不收集、不上传；只在导入课表、检查更新和更新假日表时联网」、关于页（多一句联网说明、常见问题里的放假 / 调休指向「套用节假日安排」）、根 README「七、隐私」。
- `pubspec.yaml` 加 `crypto: ^3.0.7`（pub.dev 当天最新 3.0.7，原来就是 uuid 带进来的同一版本，lock 里只是 transitive → direct main）。

#### 测试
411 → **458**（+47）。`repo_config_test.dart` 6（Gitee 3 源在前 / 不配 2 源 / 占位判断 / FeedbackLinks 派生 / lib 里占位符只在一处）；
`holiday_repository_test.dart` 25（内置 version / updatedAt、严格解析、load 的内置回退 / 新缓存整体替换 / 旧或同日缓存忽略 / 5 种坏缓存、refresh 的 notConfigured / skipped / throttled+force / shouldRefresh、updated（写缓存、无残留 .tmp、onAttempt）、Gitee 顺序、unchanged、和缓存比、failed（坏 JSON / version 2 / 超限 / 超时）、SHA-256 不一致拒绝并试下一个、自己读 latest.json、gen_latest 口径、lastHolidayRefresh 往返 / 恢复备份保留、dataDirectory、refreshFor 要求 v2 且写回时间后节流）；
`holiday_refresh_wiring_test.dart` 7（同意后顺带刷新且带 manifest、检查失败不刷新、刷新抛异常不影响启动、v1 用户重新确认、privacy.md v2 内容、设置页副标题、isUpdated）；
`holiday_apply_page_test.dart` +7（刷新按钮 + 未配置提示、fake 仓库头部日期 + 静默刷新一次、静默 updated 自动重读、手动 updated / failed / unchanged 提示、空状态、文案函数）；
`update_checker_test.dart` 改写「配置」组（源从 kRepo 派生、jsDelivr 在前 raw 在后、仍未配置）+2（holidays.sha256 解析、Gitee 3 源）。`privacy_and_about_test.dart` 的「未配置更新源 → 禁用」原样通过。

#### 模拟器
- 本任务没打包、没上模拟器（按 PLAN 留给 F）。（F：假日页数据版本与刷新按钮已在 1.4.0 正式包上截图 F-11 / F-12；隐私 v2 重新确认的截图是 B-1。）

#### 和 PLAN 的偏差
1. `dirProvider` 类型是 `FutureOr<Directory> Function()?`（PLAN 写的是同步 `Directory Function()?`），因为默认值 `Storage.dataDirectory()` 是异步的；同步的闭包照样能传。
2. `refresh` 比 PLAN 多了 `lastRefresh` / `onAttempt` / `manifest` 三个可选参数（仓库本身不持有 AppState），另加 `refreshFor(AppState)` 做接线；构造函数多了 `loadBundled` / `timeout` / `maxBytes`。
3. 「没写顶层 version」的数据 `fromJson` 仍照读（只有写了且 ≠ 1 才无效），严格的「必须 = 1」放在 `tryParseStrict`（远程 / 缓存）。
4. 「成功后」理解为检查更新读到了合法 `latest.json`（available / upToDate）。
5. 根 README 没有现成的「发布」一节，新建了「十一、发布（维护者）」；另外顺手改了「七、隐私」里已不准确的联网描述（没碰「给朋友装」）。

#### 没验证 / 遗留
- 没有真实联网：kRepo 仍是占位符，Gitee / jsDelivr / GitHub 的真实下载、jsDelivr 缓存时长、Gitee raw 对 UA 的要求都没测（codemap 记录过本机访问 Gitee 时好时坏）。
- 本任务不打包、没上模拟器（按 PLAN，留给 F）：隐私 v2 重新确认、假日页的数据版本与刷新按钮只在 widget 测试里看过。（F：假日页已在模拟器上看过，见 F-11 / F-12。）
- 刷新失败也会记下刷新时间，24 小时内只能靠页面上的刷新按钮重试（和检查更新「失败也算查过」一致）。（待修清单 ①。）
- 改了 `holidays.json` 却没重新生成 `latest.json` 时，带校验值的客户端会一直拒绝新数据——README 已写明要一起提交。

### B：本地课前提醒（opus55）

#### 实现
**依赖与 Android（B1）**
- pub.dev 当天核对：`flutter_local_notifications` 最新稳定 **22.3.1**（2026-09-13；23.0.0-dev.1..3 是预发布）、`timezone` **0.11.1**（2026-06-29）。pubspec 加 `flutter_local_notifications: ^22.3.1`、`timezone: ^0.11.1`；lock 只新增插件家族（linux 8.0.1 / platform_interface 12.2.0 / web 1.0.0 / windows 3.1.1）和 timezone，http 1.6.0 原本就有。**没加** `flutter_timezone`。
- API 以 pub cache 里 22.3.1 的源码为准（README 的 `show(0, …)` 位置参数示例过时）：`initialize({required settings, onDidReceiveNotificationResponse})`、`zonedSchedule({id, scheduledDate, notificationDetails, androidScheduleMode, title, body, payload})`、`show({id, …})`、`cancelAllPendingNotifications()`、`pendingNotificationRequests()`、`getNotificationAppLaunchDetails()`；Android 端 `requestNotificationsPermission / areNotificationsEnabled / requestExactAlarmsPermission / canScheduleExactNotifications / openAppNotificationSettings / createNotificationChannel`。原生端：精确模式在没权限时抛 `exact_alarms_not_permitted`（所以必须自己选 inexact）；API < 31 时 `canScheduleExactNotifications` 恒 true。
- `build.gradle.kts`：`isCoreLibraryDesugaringEnabled = true` + `dependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }`（文件保持 CRLF）。**AGP 9.1 / Gradle 9.3.1 / `android.newDsl=false` 下直接编过，没改任何构建配置**（首次 2m52s，增量 40–60s）。
- Manifest：`POST_NOTIFICATIONS`、`SCHEDULE_EXACT_ALARM`、`RECEIVE_BOOT_COMPLETED`、`VIBRATE`；`ScheduledNotificationReceiver` + `ScheduledNotificationBootReceiver`（BOOT_COMPLETED / MY_PACKAGE_REPLACED / 两个 QUICKBOOT_POWERON），按插件 README。不用 `USE_EXACT_ALARM`。
- `res/drawable/ic_stat_notify.xml`（快捷方式那张日历，纯白 `#FFFFFFFF`）+ `res/raw/keep.xml`（`tools:keep="@drawable/ic_stat_notify"`）。`aapt2 dump resources` 确认 release 包里有 `drawable/ic_stat_notify`（0x7f070088），模拟器上通知的 icon id 就是它。
- 渠道 `class_reminder`「上课提醒」IMPORTANCE_HIGH、`evening_preview`「明日预告」IMPORTANCE_DEFAULT（`ReminderChannels`，id 发布后不能改）。

**规划器（B2，`lib/core/reminders/reminder_planner.dart`，纯 Dart）**
- `ReminderSettings`（放在 `lib/models/reminder_settings.dart`，由 planner 和 app_settings 再导出；不可变，`leadChoices = [5,10,15,20,30]`，fromJson 容错：不在可选值里的分钟 / 越界时刻回默认）→ `AppSettings.reminders`（默认关闭，旧存档 → 默认，不升 settingsVersion）；`AppState.setReminderSettings`；**恢复备份时跟着备份走**（旧备份没有 → 关闭）。
- `ReminderPlanner.plan({timetable, settings, now, horizonDays = 10})`：今天起 10 天，`effectiveDayOf` + `coursesOnEffective`（调休 / 停课已展开），实际周不在 `[1,totalWeeks]` 的不提醒（同 WidgetSync 的守卫）；`fireAt = DateTime(y,m,d,h,min − lead)`，`<= now` 跳过；按 fireAt、id 排序。**不看 `enabled`**（服务层判断；设置页也用它）。
- 文案：标题「{课名} · HH:mm 上课」，正文用「 · 」连接「地点 · 老师 · 第 s-e 节」（空的省略，单节写「第 5 节」），调休日加「（调休：按第 N 周周X上课）」。预告（每天 previewHour:previewMinute 说明天）：停课「明天停课（备注）」、调休「明天按第 N 周周X上课，共 k 节，HH:mm 开始」、普通「明天 k 节课，HH:mm 课名」，正文是「x月x日 周X · 课程列表（最多 4 门）」。
- id：FNV-1a 32 位，输入 `kind|yyyy-MM-dd|courseId|startPeriod`（预告 `preview|明天||0`），取低 31 位；测试里和 Python 独立实现对过数。测试通知固定 9001 / 9002。
- `cancelledDays(...)`：停课**且原本有课**的日子（设置页「x月x日 停课 · 不提醒」）。

**网关与服务（B3）**
- `ReminderGateway`（init / requestNotificationPermission / permissions / requestExactAlarm / openSettings / scheduleAll(list, exact) / cancelAll / showTest / scheduleTestIn / pending / launchPayload），约定实现不抛异常。`LocalNotificationsGateway`：`tz.TZDateTime.from(本地时间, tz.UTC)`（Location 名 `Etc/UTC`），`exactAllowWhileIdle` / `inexactAllowWhileIdle`，精确失败时这条及后续自动降级；`scheduleAll` 先 `cancelAllPendingNotifications()` 再整批排，并补回还没触发的「1 分钟后测试」。**`flutter test` 里 `FlutterLocalNotificationsPlatform.instance` 是没初始化的 `late`，`resolvePlatformSpecificImplementation` 会抛 LateInitializationError**，所以 `_android` 包了 try/catch → null → 全部空操作（有测试）。
- `ReminderService`（ChangeNotifier）：`replan` 800 ms 防抖；`replanNow` 串行；只有 `enabled && privacyAcceptedVersion >= PrivacyPolicy.version` 才排，否则 `cancelAll`（重复关闭不重复撤）；`init()` 之前只算不排；计划 + 精确与否的签名不变就不重排；暴露 `lastPlan`、`permissions`、`active`。
- 接线：`ShuScheduleApp(reminderGateway:)`，Provider 提供 `ReminderService`；`WidgetsBindingObserver.resumed` → `_scheduleWidgetPush()` + 刷新权限 + `replanNow`；AppState 监听同时触发小组件推送和 `replan`。`HomeShell._startupFlow` 在隐私同意后 `_startReminders`：设 `onTap → _handleAction('today')`、`init()`、`launchPayload()` 非 null → 今日、再 `replanNow`。Provider 里没有服务（只 pump HomeShell 的旧测试）时跳过。

**设置页（B4）**：设置页新分组「上课提醒」（`settings-reminders`，「已开启 · 提前 15 分钟」/「未开启」）→ `ReminderSettingsPage`：`reminder-enabled`（先申请通知权限，拒绝则不保存、SnackBar `reminder-denied` 带「去设置」）、`reminder-lead-<n>`、`reminder-preview` / `reminder-preview-time`（TimePicker）、权限卡（`reminder-perm-notifications` + `reminder-open-settings`，`reminder-perm-exact` + `reminder-request-exact`，`reminder-exact-note` 写 Android 14 默认关闭、未允许时「提醒可能晚几分钟」）、`reminder-test-now` / `reminder-test-later`、「即将触发」按触发日期分组（`reminder-day-<date>` / `reminder-item-<id>` / `reminder-cancelled-<date>` / `reminder-upcoming-empty` / 关闭时 `reminder-upcoming-off`）和「共 N 条，系统里已安排 M 条」（`reminder-pending-count`）。页面改设置后直接 `replanNow`，不等防抖；回到前台时自己也刷新权限。
- 隐私：`privacy.md`「二」加「上课提醒在本机生成……**提醒完全在本机生成，不联网**」；「三、权限清单」改为 App 自己申请 INTERNET / POST_NOTIFICATIONS / SCHEDULE_EXACT_ALARM / VIBRATE / RECEIVE_BOOT_COMPLETED（删掉「只申请了一个权限」，androidx.work 合并的剩三个）；第三方组件加 `flutter_local_notifications`、`timezone`；存储位置补「已安排的提醒由通知组件存在 App 私有存储」；第 2 版更新记录补上提醒。`PrivacyPolicy.version` 没动（仍是 A 改的 2）。同意框（privacy_page.dart）加一条「「上课提醒」默认关闭，打开时才申请通知权限；提醒在本机生成，不联网。」

#### 测试
458 → **513**（+55）：`reminder_planner_test` 19、`reminder_service_test` 11（含 AppSettings 往返 / 落盘 / 恢复备份）、`reminder_settings_page_test` 14、`reminder_wiring_test` 5（ShuScheduleApp + Fake：同意前不 init、冷启动 payload → 今日、运行中点通知 → 今日、resume 后按精确重排、AppState 变化 800 ms 防抖）、`reminder_android_config_test` 6（pubspec / desugaring / manifest / 图标白色 + keep / 渠道 / privacy.md 覆盖 manifest 全部权限）。`flutter analyze` 零问题，`dart format` 0 changed。

#### 模拟器
- 环境：emulator-5554，API 35，release 通用包 versionCode 8 覆盖安装，截图 `shots/v140/B-*.png`。
- 隐私 v2 重新确认（新条目可见）→ 示例课表第 4 周（10/5–10/7 国庆停课，周四 / 五有课）→ 设置「上课提醒 · 未开启」→ 开启：logcat `[reminders] 已安排 28/28 条（exact=false）`；精确闹钟默认「未允许」（Android 14+ 预期）。
- 「1 分钟后测试」11:40:57 → alarm `origWhen=2026-10-07 11:41:58 window=+44s952ms` → 11:42:46 送达：`id=9002 importance=4 channel=class_reminder category=reminder`，`android.title=测试提醒（定时）`；`dumpsys alarm | grep -c cn.shu.schedule` = 86 / 89 / 97（行数，含统计行），其中 `Alarm{…cn.shu.schedule}` 条目 29（28 + 测试）→ 送达后 28。
- 「即将触发」：「10月7日 停课 · 不提醒」、10-07 21:00 预告「明天 3 节课，08:00 大学英语…」、10-08 07:45 / 09:45 / 12:45 …，底部「共 28 条，系统里已安排 28 条」。
- 点通知（单条）→ 切到「今日」；`am kill` 杀进程后定时测试仍在 11:48:15 送达（receiver 拉起新进程），点它冷启动（`act=SELECT_NOTIFICATION`）→ 落在「今日」；冷启动后重排 28 条。「去授权」打开系统「Alarms & reminders」页（没拨开关，按返回回到 App）。

#### 和 PLAN 的偏差
1. `ReminderSettings` 放在 `lib/models/`（models 不反向依赖 core），由 planner 再导出。
2. 停课预告 / 停课行只在「原本有课」的日子出现（长假里本来没课的周末不打扰）。
3. 单节写「第 5 节」而不是「第 5-5 节」；正文各段统一用「 · 」连接。
4. 预告按「触发日在 10 天窗口内」生成（最后一条说的是第 11 天）。
5. 服务按「计划 + 精确与否」签名去重；设置页改动直接 `replanNow`。
6. 同意框多一条提醒说明（隐私说明的摘要，不改版本号）。

#### 没验证 / 遗留
- 精确闹钟授权后的「按精确重排」只在 widget 测试里验证（模拟器上没拨系统开关）；开机后插件 boot receiver 补排没测（不能重启共享模拟器）。
- 系统把同一 App 的 2 条以上通知自动归组后，点**折叠的组摘要**只会用 LAUNCHER intent 打开 App（不带 payload，不切「今日」）；单条点击和冷启动都正常。要彻底解决得给通知设 groupKey + 自己的摘要。（待修清单 ④。）
- 运行中点通知只切 tab，不会关掉已经推上去的子页面（和快捷方式 `today` 现有行为一致）。
- 10 天窗口只在打开 / 回到 App 时往前滚；10 天不开 App 之后就没有提醒了（codemap 风险 3，没有后台 Dart 任务）。OEM 杀后台（MIUI / EMUI）没法在模拟器上验证。
- 模拟器上提醒保持开启状态（28 条闹钟），后续任务看到「简课表」通知属正常。

### C：小组件自动切到明天 + 状态头部 + 2×1「下一节」（opus55）

#### 实现
**共享解析（ShuWidgetProvider.kt 下半段，纯函数）**
- `resolveDisplay(snapshot, now, offset): DisplayDay(dayIndex, daysFromToday, autoTomorrow, isHome)`，`DayWidgetProvider.render` 和 `DayRemoteViewsFactory.onDataSetChanged` 都只调它（原来两处各自 `todayIndex + offset`）。默认那天 = 今天；`isDayOver`（今天有课且最后一节 `endMinutes <= now`，或今天没课 / 停课且 `now >= 18:00`）且快照里有明天 → 明天（`autoTomorrow`）。快照只到今天时继续显示今天。
- **偏移语义改成「距今天的天数」**：0 = 跟着默认那天走，k ≥ 1 = 固定看今天 + k。`nextPageOffset` 从「当前看到的那天」± 1，结果不晚于默认那天就存 0。所以自动看明天时 ▶ 直接到后天（不会出现 offset 0 / 1 都是明天的重复页），◀ 不会退回上完课的今天；白天翻到某天、下课后自动切换时，翻到的那天也不跳。`isHome` 控制 ◀ 调灰和「回到今天」按钮；默认那天是明天时按钮文案是「回到明天」（新 string `widget_back_to_tomorrow`）。
- `relativeDayLabel(days)` 按实际日期差：`epochDayOf("yyyy-MM-dd")`（Hinnant `days_from_civil` 纯整数，不用 Calendar 相减，避开夏令时），快照中间缺天时也说对「后天」。`todayKey` 改用 `Locale.ROOT`。
- 列表高亮：今天 = 第一节 `endMinutes > now`（原来是 `>=`，下课那一分钟还高亮，和头部不一致）；自动看明天 = 明天第一节。

**状态头部（WidgetStatus.kt `dayHeaderSub`，单行）**：今天 →「第 N 周 · 上课中 · 至 11:50」/「第 N 周 · 51 分钟后上课」（≤ 90 分钟，含 90）/「第 N 周 · 下一节 10:00」/ 今天没有后续的课「第 N 周 · 今天」；自动看明天 →「明天 · 第 N 周 · 3 节课」（`courses.size`，和 B 的「明天 k 节课」同口径；0 门是「没有课」）；停课日、翻到的其他日子沿用原来的「第 N 周 · 今天 / 明天 / 后天 / N 天后」，`week = null` 仍是「假期」。停课空态文案不变（`isToday` 由日期差判断，不再看 offset）。

**边界刷新**：`ShuWidgetProvider.scheduleBoundaryRefresh` = `AlarmManager.set(RTC, t, PendingIntent)`，新广播 `ACTION_BOUNDARY_REFRESH`（基类和 DAILY_REFRESH 一样补全 appWidgetIds），每次 `onUpdate` 渲染完重排（同一 PendingIntent 再 set 即替换），`onDisabled` 取消。`nextBoundaryMillis` 取严格晚于现在的最早一个：今天每节课开始 / 结束、**每节开始前 90 分钟**、**倒计时期间 now + 10 分钟**、18:00、次日 00:00:30（Calendar 设字段，夏令时日也是当地钟点）。request code：4×2 每日 0x5149 / 边界 0x514A，2×1 每日 0x514B / 边界 0x514C。不申请精确闹钟（B 的 `SCHEDULE_EXACT_ALARM` 只给提醒用）。官方文档（developer.android.com AlarmManager，当天抓取）：API 19 起 `set` 的时间「不会提前、但可能推迟」以便批量投递；`RTC`「does not wake the device up… not delivered until the next time the device wakes up」。模拟器实测 `set` 的窗口 ≈ 0.75 × 距触发时长、上限 1 小时（见下）。

**2×1「下一节」**：`NextWidgetProvider.kt`（读同一份快照，`findNextClass`：今天第一节 `endMinutes > now` → 上课中 / 下一节；没有就明天第一节；都没有 null）+ `res/layout/widget_next.xml`（色条 + 课程名 14sp 粗 / 时间 12sp / 地点 11sp，单行省略，无列表）+ `widget_next_preview.xml`（选择器 previewLayout）+ `drawable-nodpi/widget_next_preview.png`（420×176，PIL + 微软雅黑画的，配色取自 4×2 的预览图）+ `res/xml/next_widget_info.xml`（minWidth 110dp、minHeight 40dp、minResize 同值、targetCell 2×1、`resizeMode="horizontal|vertical"`、30 分钟周期）+ manifest receiver（label `@string/widget_next_label`「下一节课」）。第二行：「上课中 · 至 11:40」/「10:00-11:40」/「明天 · 08:00-09:40」；空态「近期没有课程」/ 快照缺今天「打开 App 刷新课表」。`MainActivity.requestPinWidget` 没动（仍钉 4×2），`shu_schedule/README.md` 新增「桌面小组件」一节说明 2×1 从桌面小组件列表添加。

**Dart 侧**：`WidgetSync.refreshTargets = [day, next]`（新增 `nextProviderName` / `nextProviderQualified`），快照 schema 不变（v2，Kotlin 用已有的 `start` / `end`）。B 加的 `didChangeAppLifecycleState(resumed) → _scheduleWidgetPush()` 已确认在 `app.dart`，没重复加。顺手改了过时注释：Kotlin 里「上大课表」「今天起 14 天」「v1.2.0 起唯一一个」、app.dart「重算 14 天快照」、manifest / day_widget_info / strings 的「只有这一个小组件」。

#### 测试
Flutter 513 → **519**（`widget_sync_test` 的 refreshTargets 用例改成两个 Provider；新增 `test/widgets/widget_android_config_test.dart` 6 个：refreshTargets ↔ Kotlin 类 ↔ manifest receiver ↔ provider xml、2×1 尺寸 / 布局 id / 预览 / 文案、MainActivity 仍只钉 4×2、request code 互不相同且没有 `setExact*` / `setAlarmClock` / `*_WAKEUP`、Kotlin 里没有「上大课表」「14 天」、README 说明）。**Kotlin JVM 单测 20 个**（`android/app/src/test/kotlin/cn/shu/schedule/widgets/WidgetTimeLogicTest.kt`，`build.gradle.kts` 加 `testImplementation("junit:junit:4.13.2")`，gradle 缓存里已有）：自动切明天的四种触发 / 不触发、快照只到今天、偏移语义、日期差、头部全部文案（含 90 / 91 分钟边界、11:50 下课那一分钟）、2×1 内容、重绘时刻（含每小时每半点「严格在未来、≤ 24h」扫一遍、America/Denver 两个夏令时切换日）、`epochDayOf` 对 `java.time`。**AGP 9 只给 debug 建单测任务**：命令是 `cd android && ./gradlew :app:testDebugUnitTest`（`testReleaseUnitTest` 不存在）。`flutter analyze` 零问题，`dart format` 0 changed。

#### 模拟器
- 环境：emulator-5554，API 35，release 通用包 `flutter build apk --release` 一次，56.2MB，sha256 前 16 位 18958a636913d10b，versionCode 8，`adb install -r` → Success；截图 `shots/v140/C-1 … C-11`。
- 桌面原本就有一个 4×2（id=9）。装包后 `am start` → 4×2 仍是停课文案「第 4 周 · 今天」+「今天停课，好好休息 ✨ / 国庆节放假（国家安排）」（C-1）。App 内「设置 → 添加桌面小组件」弹出的系统确认框仍是 4×2「简课表」（C-4，点了取消，桌面已有一个）。
- 2×1 走启动器：长按桌面 → Widgets → 「简课表 · 2 widgets」展开可见「下一节课 2×1 / 正在上或接下来的一节课：课程名、时间、地点。」（previewLayout，C-2）→ `input draganddrop` 拖到桌面 → `dumpsys appwidget`：`[1] id=12 provider=…NextWidgetProvider`，provider 信息 `min=(28161x10241)`（= 110dp × 40dp）`resizeMode=3 updatePeriodMillis=1800000`。今天停课 → 2×1 显示明天第一节「大学英语综合课程… / 明天 · 08:00-08:45 / 东区 J-101」（C-3）。
- 「上课中」：午休时段（11:40–13:00）没有哪一节包含当前时间，所以**没加临时课**——示例课表周三本来有 13:00-14:40「数据结构」，只临时删了 10/7 的国庆停课（学期设置里删一条）。12:19 4×2 =「第 4 周 · 42 分钟后上课」、数据结构高亮，2×1 =「数据结构 / 13:00-14:40」（C-5）。之后**没再碰 App**（前台一直是启动器），边界闹钟链：`12:28 → 12:42 → 12:52 → 13:00 → 13:30`（`.tmpbuild/plan14/C-alarm-chain.log`），12:32 截图已是「28 分钟后上课」（C-6），13:04 截图两个小组件都是「上课中 · 至 14:40」（C-7）。
- `dumpsys alarm` 原文：`RTC #13: Alarm{c91e32c type 1 origWhen 1791379800000 … cn.shu.schedule}` / `tag=*alarm*:cn.shu.schedule.action.BOUNDARY_REFRESH` / `type=RTC origWhen=2026-10-07 13:30:00.000 window=+19m32s619ms repeatInterval=0 count=0 flags=0x0`（两条，4×2 和 2×1 各一）；2×1 `onEnabled` 的 `DAILY_REFRESH type=RTC origWhen=2026-10-08 00:00:30.000 repeatInterval=86400000`；统计行 `*alarm*:cn.shu.schedule.action.BOUNDARY_REFRESH … 0 wakes 8 alarms`。`type 1` = RTC、`*alarm*` 而非提醒的 `*walarm*`、`flags=0x0`（没有 FLAG_STANDALONE / ALLOW_WHILE_IDLE）= 非精确、不唤醒。窗口实测：距触发 10 分钟 → `+7m`，40 分钟 → `+30m`，5 小时 → `+1h0m0s0ms`（封顶 1 小时）。
- 翻页（非自动）：▶ → 「10月8日 周四 / 第 4 周 · 明天」+「回到今天」、◀ 变亮、无高亮（C-8）→ 回到今天。
- **自动看明天（实机）**：13:06 临时给 10/7 加调休「按周一的课上」（第 4 周周一 08:00-11:40 两门，13:06 已全部下课）→ 4×2「10月8日 周四 / 明天 · 第 4 周 · 3 节课」、明天第一节高亮、◀ 灰、无「回到」按钮；2×1「明天 · 08:00-08:45」（C-9）。此时 ▶ → 「10月9日 周五 / 第 4 周 · 后天」+「回到明天」（C-10，没有重复页）→ ◀ 回到默认的明天。
- 恢复：删掉临时调休 → 「套用节假日安排」显示「套用 1 条」（只有 10/7，其余「已设置」）→ 套用 → 列表里 10/7 回到「停课 · 国庆节放假（国家安排）」；桌面回到 C-1 的样子 + 2×1 明天第一节（C-11）。`grep -cE 'Alarm\{.*cn\.shu\.schedule'` = 31 = 28 条提醒 + 3 条小组件闹钟。副作用：10/7 停课被临时取消期间，B 的提醒按计划在 12:45 发了一条「数据结构」上课提醒（通知栏里那个日历图标），属预期。
- 没 `am force-stop`、没改系统时间。注意 4×2 的 `DAILY_REFRESH`（0x5149）在 C 之前就已不在 `dumpsys alarm` 里（只在 `onEnabled` 注册，之前某次 force-stop / 重装丢了）；现在每次渲染都会重排的边界闹钟里含 00:00:30，链条自续，不依赖它。

#### 和 PLAN 的偏差
1. 偏移改成「距今天的天数」+ `isHome`（见上）：严格按「offset == 0 才切明天、其余 todayIndex + offset」会让自动看明天时 ▶ 第一下停在同一天。代价：自动看明天时小组件上看不到上完课的今天（开 App 看）。（待修清单 ② 要允许翻回今天。）
2. 边界时刻多了「开课前 90 分钟」和「倒计时期间 now + 10 分钟」，否则「N 分钟后上课」最多陈旧 30 分钟（只靠系统周期）。2×1 共用同一个函数，这两类时刻对它是多余的几次重绘（无害，没为它单独加参数）。
3. 列表高亮改为 `endMinutes > now`，自动看明天时高亮明天第一节。
4. 验证「上课中」没加临时课（用的是周三本来的数据结构 + 临时取消停课）；自动看明天额外用了一条临时调休，两者都已恢复。
5. 2×1 的「近期」只看今天 + 明天（按 PLAN）：周五晚上 / 周六会显示「近期没有课程」。

#### 没验证 / 遗留
- 18:00 门槛（今天没课）和跨天 00:00:30 只在 JVM 单测里验证（没等到 18:00，也不改系统时间）。
- 非精确 `set` 的窗口是 0.75 × 距触发时长（≤ 1 小时）：远的边界会晚，靠 30 分钟系统周期重渲染时重排来收紧；Doze / 关屏期间不投递，亮屏后补。OEM 启动器（vivo / MIUI）对 `updatePeriodMillis`、previewLayout 的支持没法在模拟器上验证。
- 设置页「手动添加小组件」对话框没提 2×1（只写在 shu_schedule/README.md）；根 README 由 F 决定是否引用。（F：根 README「四、桌面小组件」已加两个小组件的表和 2×1 的添加方法；App 内对话框仍没提。）

### D：ICS 导出（opus55）

#### 实现
**规范依据（2026-10-07 当天抓取）**：RFC 5545 §3.1 取自 rfc-editor.org/rfc/rfc5545（WebFetch）；该页在 WebFetch 里截断在 §3.3.10，tavily 额度用完，所以 §3.3.11 / §3.6.1 / §3.6.5 / §3.6.6 / §3.8.6.3 / §3.8.7.2 读的是 icalendar.org 上按节拆开的 RFC 原文镜像。按原文落实的要点：一行 ≤ 75 **字节**（不含 CRLF），折行 = 在两个字符之间插「CRLF + 一个空格」，续行的空格也算进 75；TEXT 里 `\` `;` `,` 必须转义、换行写 `\n`、冒号**不**转义、不允许控制字符；VEVENT 的 UID / DTSTAMP 必须且只出现一次，DTEND 与 DURATION 互斥；DTSTAMP 必须 UTC；VTIMEZONE 至少一个 STANDARD / DAYLIGHT，子段里 DTSTART 用本地时间、TZOFFSETFROM / TZOFFSETTO 必填；DISPLAY 型 VALARM 必须有 ACTION、**DESCRIPTION**、TRIGGER，`TRIGGER:-PT15M` 默认相对开始。

**导出器** `lib/features/settings/ics_exporter.dart`（纯 Dart，不碰 IO）：`IcsExporter.build({timetable, alarmMinutes, now})`；`sessionsOf(timetable)` 从 `startDate` 起用 `ScheduleUtils.addDays` 逐日走 `totalWeeks*7` 天（= `[startDate, addDays(startDate, totalWeeks*7-1)]`），每天 `effectiveDayOf` + `coursesOnEffective`，`week < 1 || week > totalWeeks` 跳过（和小组件快照 / 提醒规划器同一条规则；导入数据里周次可以超过总周数）。同一天内按（起始节、结束节、课程 id）排序，保证两次导出顺序一致。头部按 PLAN（`PRODID:-//简课表//1.4//CN`，`X-WR-CALNAME` 是转义后的课表名），VTIMEZONE = `TZID:Asia/Shanghai` + 一个 STANDARD（`DTSTART:19700101T000000`、`TZOFFSETFROM/TO:+0800`、`TZNAME:CST`）。事件：`UID:jkb-{课表id}-{课程id}-{yyyyMMdd}-{起始节}@cn.shu.schedule`、`DTSTAMP`（`now.toUtc()`，Z 结尾）、`DTSTART;TZID=Asia/Shanghai:yyyyMMddTHHmmss` / `DTEND`（本地日期字段 + 作息表的 "HH:mm"，不做跨天的毫秒运算）、`SUMMARY`、`LOCATION`（有才写）、`DESCRIPTION`（`教师：…` / `第 s-e 节` / `第 N 周 周X` / 调休日加 `调休，按第 N 周周X上课（备注）`，用 `EffectiveDay.description`）、`CATEGORIES:课程`；`alarmMinutes != null` 时 VALARM = `ACTION:DISPLAY` + `DESCRIPTION:课名 · 地点` + `TRIGGER:-PT{n}M`。`foldLine` 按 Unicode 码点累加 UTF-8 长度，所以 3 字节汉字、4 字节 emoji 都不会被切开。脏数据：作息表取不到时间的课跳过；结束不晚于开始时不写 DTEND（§3.6.1：DATE-TIME 型 DTSTART 的事件在开始那一刻结束）；同一 UID 只出一次；课名 / 课表名为空时用「课程」/「简课表」。

**分享**：新文件 `lib/features/settings/system_share.dart`（`ShareFileRequest` + `shareFileWithSystemSheet`：写临时目录 → `SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType)]))`，返回面板是否打开）。`TimetableShare._shareWithSystemSheet` 改成调它（`shareFile` / `pickText` / `resetIo` 测试钩子原样不动，去掉了 `dart:io` / path_provider / share_plus 的直接 import）。`lib/features/settings/ics_export_sheet.dart`：`IcsShare.shareFile`（`@visibleForTesting` 钩子）/ `resetIo()` / `requestFor(...)`（mime `text/calendar`，文件名 `jiankebiao-timetable-yyyyMMdd.ics`，用 `AppBrand.slug`）+ `showIcsExportSheet(context, timetable:, clock:)`。`BackupService.exportAndShare` 没改（它要返回值、以前的写法也能用）。

**入口**：`settings_page.dart`「课表」分组「作息时间」后加 tile `settings-export-ics`「导出到日历（.ics）」（没有当前课表时禁用）；`timetable_manage_page.dart` 每张课表的 ⋮ 菜单加 `ics`「导出到日历（.ics）」（导出被点的那一张，不是当前课表）。底部弹窗 `ics-sheet`：标题、`ics-summary`（「「课表名」· 第 1-18 周 · 共 N 节课，调休、停课已算好」，学期内没有课时改成「没有可导出的内容」并禁用按钮）、`ics-hint`（PLAN 原文那句）、一行「导出的是一份快照：之后改课、调休，要重新导出一次」、提醒 ChoiceChip `ics-alarm-0`（无）/ `-10` / `-15` / `-30`（默认 = 上课提醒的 `leadMinutes` 在 10 / 15 / 30 里就用它，否则 15，和提醒开没开无关）、`ics-share`「生成并分享」（成功后关弹窗；失败 SnackBar「导出失败：…」并保留弹窗）。

**文档**：根 `README.md` 只改了「九、已知限制」第 3 条（「App 里没有 ICS 导出（可以用网页工具…）」→ 已内置、在哪里点、是快照）。PLAN 说的 L57-61 在「给朋友装 → iPhone 办法二」里，按 §0「不改『给朋友装』一节」**没动**。`shu_schedule/README.md` 没有这类说法，没改。`assets/privacy.md`「你主动发起的分享」列表加了「导出到日历（.ics）」（措辞补充，没有新依赖 / 权限 / 联网，`PrivacyPolicy.version` 仍是 2，`pubspec.yaml` 没碰）。

#### 测试
519 → **543**（+24）。`test/ics_exporter_test.dart` 17 个（纯 Dart）：事件数 = 手算 54（含第 18 周周日、两天停课、一天调休、一门只在第 19-20 周的课、一条「按第 19 周」的调休）且 = `sessionsOf`；停课日无事件；调休日 = 周一的高数 + UID / 时间 / DESCRIPTION 调休行；周 > 总周数无事件；范围首尾 + 2026-11-02 / 2027-01-11 仍是 08:00（本机 11-01 回拨夏令时）；头部 16 行逐字、每个事件 UID / DTSTAMP 恰一、无 DURATION、无地点不写 LOCATION；DTSTAMP UTC（UTC 与本地 now 两种）；UID 两次导出一致且唯一；CRLF；长中文 + 4 字节 emoji 的 SUMMARY / LOCATION / DESCRIPTION 按字节切 CRLF 后每段 ≤ 75 且能严格 UTF-8 解码、展开还原；`foldLine` 75 / 75 / 52（ASCII）、75 / 73 / 4（汉字）、emoji 每段 18 个；转义（`\ ; , \n \r\n \r`、冒号、控制字符）；VALARM 有无 / TRIGGER / ACTION / DESCRIPTION；默认提醒映射；文件名；空作息表 / 结束早于开始；README 第 3 条与 privacy.md。`test/ics_export_sheet_test.dart` 7 个：tile 位置（「作息时间」之后、「上课提醒」之前）、弹窗内容与默认 15、切 30 后分享（钩子收到 `.ics`、`text/calendar`、`TRIGGER:-PT30M`、事件数 = 课次、弹窗关闭）、提醒 10 → 默认 10 + 选「无」不带 VALARM、提醒 20 → 默认 15、钩子抛错 → SnackBar + 弹窗保留、空课表按钮禁用、课表管理页菜单导出被点的那张。`flutter analyze` 零问题，`dart format` 0 changed。

**Python 独立校验**（`.tmpbuild/plan14/D-ics-dump.dart` 用示例课表 + 国庆停课 / 调休 + 一门超长中文课生成 `D-sample.ics`，`D-ics-check.py` 只用标准库，结果在 `D-ics-check.log`）：1737 个物理行、145 个续行、最长 75 字节、游离 CR/LF 0、坏 UTF-8 段 0；105 个 VEVENT、105 个不同 UID；10/1、10/5 停课 0 个事件，10/10 调休 1 个（高等数学 A(一)，DESCRIPTION 带「调休，按周一上课（国庆调休，补 10/5 的课）」），12/26「按第 19 周」0 个；最后一天 2027-01-15（第 18 周周五，第 19-20 周被截掉）；每个事件的 TEXT 都没有未转义的 `;` `,`；`RESULT: OK`。

#### 模拟器
- 环境：emulator-5554，release 通用包 `flutter build apk --release` 一次，56.3MB / 59062475 字节，sha256 前 16 位 13143932963b35a3，versionCode 仍是 8，`adb install -r` → Success；截图 `shots/v140/D-1 … D-5`。
- 设置「课表」分组出现新 tile（D-1）→ 弹窗「「示例课表」· 第 1-18 周 · 共 220 节课」、默认 15 分钟（D-2，上课提醒是 15）→ 点 30 分钟（D-3，uiautomator：只有「30 分钟」`selected=true`）→「生成并分享」：logcat `START u0 {act=android.intent.action.CHOOSER cmp=com.android.intentresolver/.ChooserActivityLauncher}`，系统面板「Sharing 1 file / jiankebiao-timetable-20261007.ics」（D-4）→ `input keyevent 4` 回到设置页、弹窗已关（D-5）。没 force-stop、没改系统时间；之后 `Alarm{…cn.shu.schedule}` 仍是 31 条（和 C 结束时一样）。

#### 和 PLAN 的偏差
1. VALARM 多了 `DESCRIPTION`（§3.6.6 对 DISPLAY 提醒是必填，PLAN 只列了 ACTION / TRIGGER）。
2. 「无」的 chip key 是 `ics-alarm-0`。
3. 根 README L57-61 没改（在「给朋友装」里，§0 禁止），只改了 L251 那条。
4. 结束不晚于开始时省略 DTEND；取不到时间的课跳过；重复 UID 只出一次（PLAN 没写的脏数据处理）。
5. `PRODID` 按 PLAN 写死 `1.4`，不跟 `appVersion` 走。
6. 弹窗多了「共 N 节课」摘要和「快照」提示；学期内没有课时禁用分享按钮。

#### 没验证 / 遗留
- 真机导入没测：iPhone「日历」打开 .ics、微信转发 .ics 后能不能「添加全部」、Outlook / Google 日历网页导入、Android 上哪个 App 能直接打开 `text/calendar`（模拟器面板里只有 Quick Share / Drive / Messages / Bluetooth / Gmail）。DESCRIPTION 里的 `\n` 在各客户端是否显示成换行也没看。
- 根 README 同一条里「没有课前提醒」是 B 之后的过时说法（不属于 D，留给 F）；「给朋友装 → iPhone 办法二」现在可以改成「让安卓同学在 App 里直接导出 .ics」，由负责那一节的会话决定。（F：「没有课前提醒」已改掉；「给朋友装」仍未动，交给那一节的负责人。）

### E：周视图长按列头设调休 + 空状态三入口（opus55）

#### 实现
**E1 共用流程**：`TermSettingsPage._editOverride` 抽成 `lib/features/settings/date_override_flow.dart` 的顶层 `editDateOverride(context, appState, {DateTime? date, OverrideMode? initialMode})`。行为不变（日期冲突弹「这一天已经有设置」确认替换、改了日期删旧的那条），只有两处收紧：`editing` 由「传了 date」改成「这一天已有设置」（长按一个还没设置的日子，标题是「添加调休 / 停课」）；删旧日期前先确认旧日期真有设置。`initialMode` 在 `DateOverrideDraft.from(...)` 之后 `copyWith(mode:)`。学期设置页两处入口改调它，`override-*` 测试 key 全部没动，原有 4 个 UI 测试原样通过。

**E2 长按列头**
- `EffectiveDay.badge`：停课 →「休」，`actAsWeek` / `actAsWeekday` 任一非空 →「补」，没有设置或只写了备注 → null。`EffectiveDay.label` / `DateOverride.shortLabel`（「停课」/「调休」）**没改**，今日页、小组件快照、Kotlin 照旧。
- 列头 `_weekdayCell`：`Semantics` → `Material(transparency)` → `InkWell(key: weekday-<yyyy-MM-dd>, onLongPress)` → `Ink`（今天的高亮色改用 Ink 画，长按有水波纹）→ `SizedBox.expand` → `FittedBox`。角标是 `override-<yyyy-MM-dd>` key 的小圆角 Container（休：`onSurfaceMuted` 75% 不透明；补：`accent`；字 9 号 `onPrimary`），**放在日期数字右边**而不是下面：模拟器上叠成三行时 CJK 字体把角标顶到 52 高列头的底边（第一次装包截图看到的），并排后每列一样高。没有课表时 `onLongPress = null`（没有地方存）。
- 新文件 `lib/features/timetable/day_override_sheet.dart`：
  - 纯函数 `daySuggestionOf(presets, config, date, {schoolId})` 复用 `HolidayPresets.planFor`（和「套用节假日安排」同一套：有 schoolId 且学校学期对得上用学校条目，否则国家安排），取这一天那条：学校 / 国家放假 →「假日表建议：停课（国庆节）」（备注里「放假」前面的部分，去掉「（国家安排）」）；学校 actAsDate →「假日表建议：按 10/7（周三）课表上课」（由 override 的 week + weekday 从 startDate 推回日期）；国家调休上班日（override 为 null）→「假日表建议：国家调休上班日」，点它打开预置按星期模式的编辑器；已经是这个设置时这一行禁用、副标题「已是这个设置」。
  - `dayOverrideSheetTitle`（「10月8日 周四 · 第 4 周」，学期外写「不在本学期」）、`dayOverrideStateText`（「当前：停课（运动会）」/「当前：调休，按周一上课 · 当天 1 门课」/「当前：按原课表上课 · 当天没有课」）。
  - `DayOverrideSheet`（key `override-sheet`，`isScrollControlled` + `SingleChildScrollView`，行：`override-sheet-suggest` / `-cancel` / `-actas` / `-edit` / `-clear`，另有 `-title` / `-state`）只负责 pop 出选择；`showDayOverrideSheet(context, date, {holidays})` 在面板关掉后用页面自己的 context 执行：套用建议 / 设为停课 / 清除 都是一键 + SnackBar「撤销」（恢复成之前那条），「调休：按某天课表上课」=`editDateOverride(initialMode: weekday)`，「编辑…」= 完整编辑器。已经停课时「设为停课」禁用。
  - 假日表用 `HolidayRepository.load()`（内置或联网更新过的缓存），每次打开面板读一次；`WeekViewPage({holidayRepository, clock})` 可注入，`HomeShell` 把自己的 `holidayRepository` 传下去（`_pages` 从 `static const` 改成 `late final`）。
- 周末列：`_visibleDays(config, timetable, week)` 改成按周算。显示周末 → 7 天；隐藏 → 周一到周五，加上这一周里 `isOverridden`（停课或调休，只写备注不算）或调休展开后有课的周六 / 周日。列头（`_viewWeek`）、网格每一页（`_weekPage` 的 week）、紧凑字号测量（`_weekNeedsCompact`）都用同一个函数，列宽 = 这一页宽 / 这一页列数。翻页时列头在 `onPageChanged` 那一刻换列数（和以前换日期同一时机）。**只加有内容的那一天**：周六补课而周日空着的一周是 6 列（PLAN 原文「把该天也显示出来」；任务说明里写的「7 columns」按 PLAN 理解）。学期设置「显示周末」副标题相应改成「关闭后只显示周一到周五；某周的周六、周日有课或有调休时，那一天照样显示」。
- 周课表 `importRouteName` 挪到新文件 `timetable_empty_state.dart`，`week_view_page.dart` `export ... show importRouteName`，`main.dart` / `app.dart` 的 import 不用改。

**E3 空状态**
- `EmptyState` 加 `tertiaryLabel` / `onTertiary`（第二个 TextButton）和 `keyPrefix`（按钮 key `<prefix>-primary/secondary/tertiary`，不给就没有 key）；外层 `Padding` 换成带同样 padding 的 `SingleChildScrollView`，三个按钮在矮屏上不溢出。
- 新 `TimetableEmptyState`（`lib/features/timetable/timetable_empty_state.dart`）：从教务导入（`pushNamed('/import')`）/ 手动添加（`CourseEditorPage(initialDay, 第 1 节)`）/ 打开同学分享的文件（`importTimetableFromFile(..., replaceEmptyCurrent: true)`）。周视图 `week-empty-*`（说明文字改成「可以从教务系统一键导入、手动添加，也可以打开同学分享给你的课表文件。」）；今日页 `today-empty-*`：没有课表「还没有课表」、有课表但 0 门课「这张课表还没有课程」（以前这种情况只写「今天没有课程」、没有入口）。
- 导入覆盖：`TimetableShare.importInto(..., {overwriteId})`（文件里**第一张**覆盖它，其余照常新建，最后一张成为当前）、`pickAndImport(..., {replaceEmptyCurrent})`（**选完文件后**再看当前课表是否 0 门课）、`TimetableImportOutcome.replacedId`、`importTimetableFromFile(..., {replaceEmptyCurrent = false})`。覆盖走 `applyImport(overwriteId:)`，所以**保留原课表名**（「我的课表」）和 id，换掉课程、学期配置（含调休）、导入元数据；提示「已导入到当前课表「我的课表」，共 N 门课」。课表管理页和设置页的入口仍是默认参数，行为不变。
- 复课：`ScheduleUtils.nextCourseAt(now, tt, {lookaheadDays})` 返回 `({Course course, DateTime date})?`，`nextCourse` 改成调它取 `.course`（行为不变）。今日页 `_resumeText`：只在学期内；`lookaheadDays = daysBetween(今天, startDate + totalWeeks*7 - 1)`；下一节课的日期距今 ≥ 2 天 → 空状态说明文字写「10月8日（周四）复课」，否则照旧「到课表页看看这一周的安排吧。」。所以普通周六（下周一 2 天后）也会写「10月19日（周一）复课」，周日不写——按 PLAN 字面。`TodayPage({clock})` 加了可注入时钟（`ReminderSettingsPage` / ICS 弹窗同样的 `DateTime Function()?` 写法）。

#### 测试
543 → **573**（+30）。`test/week_view_day_override_test.dart` 13 个（时钟固定 2026-10-07，FakeHolidayRepository）：badge / label、面板标题与状态文案、`daySuggestionOf` 学校 actAs / 学校停课 / 国家放假 / 国家上班日 / 已套用；长按 10/8 出面板（标题、状态、没有建议行和清除行）；设为停课 → 列头「休」、课消失、SnackBar 撤销恢复；清除；学校建议一键 → `actAs(week 4, weekday 3, note)`、列头「补」、周三课出现两次、再开面板建议行禁用；国家上班日建议行 → 编辑器按星期模式；「调休：按某天课表上课」→ 编辑器预置、选周一保存；「编辑…」编辑模式；隐藏周末：第 4 周 6 列（周六补课、和列头对齐、能长按）→ 下一周 5 列（周五课对齐）→ 回来 6 列 → 打开显示周末 7 列；周日停课 + 周六有课 → 7 列；没有课表时列头不响应长按。`test/empty_state_entries_test.dart` 9 个：EmptyState key / 无 key；周视图空课表三按钮都能点（导入路由、课程编辑页、文件选择取消）；没有课表也三按钮；今日页 null / 0 门课三按钮、有课后消失；周视图 / 今日页从文件导入覆盖空课表（1 张、id 和名字不变、2 门课、调休带过来、SnackBar 文案）；没有课表时导入新建、用文件里的名字；`pickAndImport` 三种情况；`importInto` 只覆盖第一张。`test/today_resume_test.dart` 8 个：`nextCourseAt` 日期 + 14 天默认找不到 20 天长假；10/1 停课 →「10月8日（周四）复课」；10/3 周六同；10/1-10/20 停课 →「10月21日（周三）复课」；10/7（明天有课）不写；普通周六写 / 周日不写；学期最后一个周末与开学前不写；有课照常列出。改了 `test/week_view_override_test.dart` 的两处断言（「停课」/「调休」→ 角标「休」/「补」，并断言周视图里不再出现这两个词）。`flutter analyze` 零问题，`dart format` 0 changed。

#### 模拟器
- 环境：emulator-5554，release 通用包；**打了两次**：第一次装上后发现角标贴底，改成并排后重打一次，56.3MB / 59078951 字节，sha256 前 16 位 d290bdb4de2069ad，`adb install -r` Success；截图 `shots/v140/E-1 … E-10`。
- 第 4 周 10/5-10/7「休」（E-1）、第 3 周 10/1-10/4「休」（E-2）；长按 10/8 面板「10月8日 周四 · 第 4 周 / 当前：按原课表上课 · 当天 3 门课」（E-3）；长按 10/10「假日表建议：国家调休上班日」（示例课表没有 schoolId，走国家安排；E-4）→ 点它进编辑器、已选「按某个星期上课」（E-5）→ 选周三保存 → 10/10 列头「补」、出现周三的课（E-6，uiautomator 读到「周六 10月10日 调休，按周三上课」）；学期设置关「显示周末」→ 第 4 周 6 列含周六 10/10（E-7）、第 5 周 5 列（E-8）→ 再打开。课表管理新建空的「我的课表」→ 周视图三入口（E-9）、今日页「这张课表还没有课程」三入口（E-10；这两张是第一次的包，空状态和角标改动无关）→ 切回示例课表、删除空课表（课表管理只剩示例课表）。示例课表原来没有 10/10 补课：「套用节假日安排」对没有学校的课表只把国家调休上班日列成「需要手动设置」、不能勾选，所以用长按面板设了「按周三上课」并保留。没 force-stop、没改系统时间；`Alarm{…cn.shu.schedule}` 31 → 35（10/10 多了课，B 的提醒规划器按数据变化重排，符合预期）。

#### 和 PLAN 的偏差
1. 角标放在日期右边（不是下面），原因见上。
2. 隐藏周末时只加有内容的那一天（6 列），不是成对加周六周日。
3. 国家调休上班日没有可直接套用的规则，建议行改为打开编辑器（PLAN 写「一键套用」，这类日子没有可套的内容）。
4. 一键操作统一带「撤销」（PLAN 只要求「设为停课」）。
5. 覆盖空课表时保留原课表名（`applyImport` 既有约定），不改成文件里的名字。
6. 复课文案放在今日页空状态的说明行（标题「今天停课。」下面），顶部副标题不变。（普通周六也写复课属于待修清单 ③。）
7. release 包打了两次（任务说明要求一次），第二次只为验证角标修复。

#### 没验证 / 遗留
- 真机上「打开同学分享的文件」从空状态走系统文件选择器没点（file_picker 弹窗，测试用 `pickText` 钩子）；模拟器只截了入口。
- 模拟器上没截学校数据的「假日表建议：按 10/7（周三）课表上课」（示例课表没有 schoolId；widget 测试覆盖）。
- 根 README「一、功能」第 1 条和版本历史还没提长按列头（PLAN 归 F）。（F：已补，功能列表和「十、版本历史」1.4.0。）
- 学期设置「显示周末」副标题是第二次打包之后改的（纯文案），模拟器上装的包里还是旧的「关闭后课表只显示周一到周五」；F 打正式包时自然带上。（F：1.4.0 正式包里已是新副标题，截图 F-9。）

### F：版本、文档、打包、模拟器升级验证（opus55）

#### 实现
- 版本：`pubspec.yaml` `1.3.1+8` → **`1.4.0+9`**，`lib/core/app_brand.dart` `appVersion` → `'1.4.0'`。grep `1.3.1` / `versionCode` / `+8`（lib、test、android、两个 README、`tool/gen_latest.py`）：
  其余命中都是注释里的版本标记或 1.4.0 示例；`build.gradle.kts` 用 `flutter.versionCode / versionName`，gen_latest 默认读 pubspec，没有测试钉 appVersion 字符串，所以只改这两处。
- 根 `README.md`（「给朋友装」一节**逐字未动**：改前改后用 awk 截出该节比 sha256，都是 fac23437…）：
  开头功能列表（上课提醒、4×2 状态头部 / 自动看明天、2×1、ICS、长按列头、「休」「补」、周末补课列、空状态三入口、假日表联网刷新、Gitee / jsDelivr / GitHub 与一处配置）；
  「一、下载与安装」表格文件名 v1.3.0 → v1.4.0（这一节不属于「给朋友装」）；「3. 升级」加 1.3.x → 1.4.0 会再确认一次隐私、提醒默认关闭；
  「三 → 导不进来」第 1 条加空课表直接导入；「四、桌面小组件」加两个小组件的表、2×1 只能从小组件列表添加、状态头部、自动看明天、边界刷新；
  「五、调休」加提醒 / ICS 同样按调休、假日页版本与刷新按钮；「六、设置一览」加 添加桌面小组件 / 导出到日历（.ics）/ 上课提醒，课表管理 / 学期设置 / 备份 / 检查更新各补一句；
  「七、隐私」权限改成与 privacy.md、`aapt2 dump permissions` 一致（原来「App 自己只申请 INTERNET 一个权限」是 B 之后的过时说法），并写明提醒、导出日历不联网；
  「八」小组件 FAQ 改写 + 新增「上课提醒没响 / 晚了几分钟？」；「九」第 3 条去掉「没有课前提醒」、注明 .ics 还没实测导入；「十」加 1.4.0。
- `shu_schedule/README.md`：新增「上课提醒（v1.4.0）」「导出到日历（.ics，v1.4.0）」「假日表与更新源（v1.4.0）」三节（「桌面小组件」「调休 / 停课」两节 C / E 已写）。
- 本节整理：见 v1.4.0 开头的说明与总表。

#### 测试
- `flutter analyze` → `No issues found!`；`dart format --output=none --set-exit-if-changed lib test` → 120 files，0 changed；`flutter test` → **`+573: All tests passed!`**
  （日志 `.tmpbuild/plan14/testrun-F.log`）。F 没加测试；读 README 的两个测试（`ics_exporter_test`「没有 ICS 导出」、`widget_android_config_test`「下一节课 / 小组件列表」）照样通过。

#### 打包
- `flutter build apk --release` 一次（Gradle 47.7 s）→ `build/app/outputs/flutter-apk/app-release.apk`：56.3MB = **59,078,951 B**，
  sha256 **`db6adb891f572ccb1b3c6f3ec350bcec2c54de4c928b62cf7ece6774a0df773a`**；`aapt2 dump badging` →
  `package: name='cn.shu.schedule' versionCode='9' versionName='1.4.0' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36'`、minSdk 24、targetSdk 35。
  字节数恰好和 E 的第二个包相同，sha256 和 versionCode 不同。
- `aapt2 dump permissions`：INTERNET、POST_NOTIFICATIONS、SCHEDULE_EXACT_ALARM、RECEIVE_BOOT_COMPLETED、VIBRATE、WAKE_LOCK、ACCESS_NETWORK_STATE、FOREGROUND_SERVICE
  + `cn.shu.schedule.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`，和 privacy.md「三、权限清单」一致。
- 按本轮分工**没打 arm64 包、没复制进 `dist/`**（留给最终打包）。
- `python shu_schedule/tool/gen_latest.py --apk shu_schedule/build/app/outputs/flutter-apk/app-release.apk --changelog "…" --out .tmpbuild/plan14/latest-draft.json`
  → 退出码 0，「已写入 …（776 字节）」，并警告「kRepo 还是占位符，downloadUrls 先用占位地址」。内容：`versionCode 9`、`versionName "1.4.0"`、顶层 `sha256` = 上面的 APK sha256、
  `apks[0] = {file: "app-release.apk", abi: "universal", bytes: 59078951}`、`holidays = {sha256: e6d0cb56…2003, updatedAt: "2026-10-06", bytes: 3117}`（与 `sha256sum assets/holidays.json` 一致）、
  `downloadUrls = ["https://github.com/OWNER/REPO/releases/tag/v1.4.0"]`。

#### 模拟器
- 环境：emulator-5554，API 35；截图 `shots/v140/F-1 … F-14`。
- 升级前装的是 B–E 打的 versionCode 8 包（`versionName=1.3.1`，lastUpdateTime 13:57:43）。`adb install -r` → `Success`；
  `dumpsys package cn.shu.schedule` → `versionCode=9 minSdk=24 targetSdk=35` / `versionName=1.4.0` / `lastUpdateTime=2026-10-07 14:07:43`。
- 闹钟：`dumpsys alarm | grep -c cn.shu.schedule` 装前 119 → 装后 119 → 启动后 119；`Alarm{…cn.shu.schedule}` 条目 35 → 35 → 35
  （32 条 `*walarm*` 提醒 + 2 条 `BOUNDARY_REFRESH` + 1 条 `DAILY_REFRESH`）。启动 logcat：`I flutter : [reminders] 已安排 32/32 条（exact=false）`，
  `AppWidgetServiceImpl` 通知 widget 9 和 12 更新。
- 数据保留：第 4 周 10/5-10/7「休」、10/10「补」（读屏「周六 10月10日 调休，按周三上课」）（F-1）；第 3 周 10/1-10/4「休」（F-2）；学期设置列表 9/23、9/25-27、10/1-10/7 停课 + 10/10「按周三的课上」（F-10）。
- **隐私确认框没有再弹**：这台模拟器在 B 时已经用 `PrivacyPolicy.version = 2` 的包同意过 v2，所以从 versionCode 8 升到 9 不会再问，逻辑正确；
  真正的 1.3.1 → 1.4 重新确认截图仍用 B-1。启动后提醒照常重排（`ReminderService` 要求同意 ≥ v2）也说明同意状态保留了。
- 设置页：F-3（桌面小组件 / 课表含「导出到日历（.ics）」/ 上课提醒「已开启 · 提前 15 分钟」/ 显示）、F-4（备份、「关于简课表 v1.4.0」、「检查更新 · 未配置更新源」、隐私说明新副标题）。
- 上课提醒页：权限卡「通知 已允许 / 精确闹钟 未允许：提醒可能晚几分钟」（F-5）；「即将触发」：「10月7日 停课 · 不提醒」、21:00 预告、10/8 07:45 / 09:45 / 12:45 …（F-6）；
  底部「共 32 条，系统里已安排 32 条（含测试提醒）」（F-7）；10/9 21:00 预告「明天按第 4 周周三上课，共 3 节，08:00 开始」、10/10 每条带「（调休：按第 4 周周三上课）」（F-8）。
- 学期设置「显示周末」新副标题「关闭后只显示周一到周五；某周的周六、周日有课或有调休时，那一天照样显示」（F-9）。
- 套用节假日安排：头部「假日表 · 内置 2026-10-06」（F-11）→ 右上角刷新 → SnackBar「更新源未配置」（F-12）。
- 「发送测试提醒」→ 通知栏「测试提醒 / 上课提醒会像这样出现在通知栏。」（F-13）；`dumpsys notification --noredact`：`id=9001 importance=4 … channel=class_reminder … category=reminder`、`icon=Icon(typ=RESOURCE pkg=cn.shu.schedule id=0x7f070088)`。
- 桌面（F-14）：4×2「10月7日 周三 / 第 4 周 · 今天 / 今天停课，好好休息 ✨ / 国庆节放假（国家安排）」；2×1「大学英语综合课程与跨文化交际（三） / 明天 · 08:00-08:45 / 东区 J-101」。
- 没 force-stop、没改系统时间；最后 App 停在课表页第 4 周。

截图对照 PLAN 清单：隐私重新同意 = B-1（复用）；设置页新分组 = F-3 / F-4；上课提醒页 = F-5 … F-8；测试通知 = F-13（另有 B-7 / B-11 的定时测试）；
小组件状态头部 = C-5 / C-6 / C-7 / C-9（复用，C 之后 Kotlin 没再改）+ F-14；2×1 = C-3 / F-14；ICS 弹窗与系统分享面板 = D-2 / D-3 / D-4（复用，UI 没变）；
长按面板与「休」「补」= E-3 / E-4 / E-5 / E-6 + F-1 / F-2；周六补课列 = E-7 / E-8（复用；副标题新文案见 F-9）；空状态三入口 = E-9 / E-10（复用）；假日页数据版本与刷新 = F-11 / F-12（新）。

#### 和 PLAN 的偏差
1. 只打了通用包；arm64 包、复制进 `dist/`、正式 `dist/latest.json` 留给最终打包（本轮任务说明）。`latest.json` 草稿写在 `.tmpbuild/plan14/latest-draft.json`。
2. 隐私重新同意截图复用 B-1（原因见上）。
3. 根 README「一、下载与安装」表格的文件名顺手改成 v1.4.0。

#### 没验证 / 遗留
- 「给朋友装」一节（另一个会话负责）仍写 v1.3.0 的文件名与大小（安卓第 1 步、「解析包错误」那句、纯血鸿蒙第 2 步），「iPhone 办法二」仍让人用网页工具转 .ics——
  现在可以改成让安卓同学在 App 里直接「导出到日历（.ics）」。需要那一节的负责人更新。
- 上面列出的 C / D / E 复用截图都来自 versionCode 8 的包；1.4.0 正式包上只重看了 F-1 … F-14 这些画面。
- 待修清单 ①–⑤ 见本节开头；F 没有改 A–E 的代码。

### 修复轮（opus55）

依据 `.tmpbuild/plan14/fixlist-final.md`（25 条，按编号执行）和 `review-G.md`。没动 `PrivacyPolicy.version`（仍 2）、版本号（仍 1.4.0+9）、`site/`、`keys/`、`key.properties`、根 README「给朋友装」（改前改后该节 sha256 都是 fac23437…）。

#### 实现（按 fixlist 编号）
1. **精确闹钟改为 USE_EXACT_ALARM**（规划者拍板）。官方写法已核对：WebFetch 超时，tavily 额度用完，改用 curl 抓 developer.android.com。
   `reference/android/Manifest.permission#USE_EXACT_ALARM` 原文写明同时用两者时 `SCHEDULE_EXACT_ALARM` 加 `android:maxSdkVersion="32"`；
   `alarms/schedule` 页写了 Android 12+ 非精确闹钟「within one hour」。Manifest 现为 `SCHEDULE_EXACT_ALARM maxSdkVersion=32` + `USE_EXACT_ALARM`。
   保留「能精确就 exactAllowWhileIdle，否则 inexactAllowWhileIdle」的回退。`ReminderPermission` 新增 `exactBySystem`：网关经 `NativeBridge.deviceInfo()['sdkInt']`
   取 API level（可注入），≥33 且能精确时为 true。权限卡文案：「系统已授予：提醒准点送达」/「已允许：…」/「未授权时提醒最多可能晚 1 小时」。
   打开总开关时如果没有精确权限，弹 `reminder-exact-prompt`「去授权」。「1 分钟后测试」的 SnackBar 和说明、privacy.md（权限清单加 USE_EXACT_ALARM、只用于准点提醒，第 2 版变更说明同步）、
   两个 README 里「晚几分钟」的句子全部改掉；根 README:256 那句因果推断（「1 分钟后测试」能按时到，正式提醒就能到）已删。字符串断言测试防止回退。
2. 规划窗口 10 → 14 天。新增 `ReminderKind.horizonEnd`：窗口最后一天 previewHour 发「提醒已排到 x月x日，打开简课表就会续上」（渠道 evening_preview，payload `today`，
   id = FNV(`horizon|日期||0`)）。只在窗口之后学期里还有课时生成。同一时刻排在最后一晚的预告后面。「即将触发」把它单独放在列表末尾。
   **和 fixlist 示例的出入**：示例写「10月21日」，实际写的是最后一个排了上课提醒的日子（今天 10/7 → 10/20）。10/21 的上课提醒并没有排，写 21 日会误导。
3. 提醒页顶部「提醒跟随当前课表：xxx」，设置 tile「已开启 · 提前 15 分钟 · 跟随「xxx」」。`ReminderService.timetableSwitches`（broadcast stream）在提醒开着、
   当前课表 id 变化时发课表名，第一次看到不算。`HomeShell` 弹「上课提醒已切换到「xxx」」，不 hide 当前 SnackBar，导入页自己的提示排在前面。
4. `ReminderService.needsPermission` / `needsPermissionFor(settings)`：提醒开着、权限已查到且通知未授予。tile 显示「已开启 · 没有通知权限」。
   `HomeShell._startReminders` 在 init 之后，若需要就弹 `reminder-needs-permission`（带「去授权」：先申请，系统不再弹框时打开通知设置）。
5. 隐私说明被拒绝时调用 `gateway.cancelAll()`。插件源码已确认：`cancelAllPendingNotifications` 只用 `onAttachedToEngine` 拿到的 Context 和本地缓存
   （FlutterLocalNotificationsPlugin.java L1429 / L1891），Dart 端 instance 由 `registerWith` 设置，都不依赖 `initialize`。
6. 「（含测试提醒）」只在 `pending > plan.length` 时显示；`scheduleTestIn` 先赋 `_pendingTestAt` 再 await，排程失败时清回。规划器补了三个用例：开学前一晚的预告、00:10 的课提前 15 分钟（→ 前一天 23:55）、调休到第 19 周不提醒。
7. 根 README 提醒 FAQ 补了这些：关机期间错过的提醒开机时一起弹出；系统折叠成组时点组标题只打开 App；14 天续排；提醒跟随课表。
8. 4×2 偏移语义改为「距今天的天数」：`OFFSET_DEFAULT = -1` 表示默认那天，0 = 今天。`readOffset` 默认值、`DayWidgetService` 兜底值、`nextPageOffset`
   （落在默认那天时存哨兵，RESET → 哨兵）、`resolveDisplay`（k≥0 = 今天 + k）、箭头可用态（新增 `canPagePrev` = daysFromToday > 0、`canPageNext`）都同步改了。
   头部新增「第 N 周 · 今天 · 已结束」。存储 key 从 `offset_<id>` 改名为 `day_offset_<id>`：老版本存的 0 表示「默认」，不改名的话升级当天会被误读成「今天」。
9. 2×1 往后找 7 天（`NEXT_CLASS_LOOKAHEAD_DAYS`）。标签规则：1 天 →「明天」，2–6 天 → 星期（「周一 · 08:00-08:45」），正好 7 天 → 日期（「10月14日」，避免和今天同一个星期几混淆）。仍然没有 →「近期没有课程」。
10. 小组件「可能晚几分钟」→「可能晚十几到几十分钟（系统省电策略所致）」（根 README 两处、shu_schedule/README 一处）。
11. 假日表只有 updated / unchanged 才记 `lastHolidayRefresh`（参数 `onAttempt` 改名为 `onSuccess`，在成功后调用）。`holiday_repository_test` 原第 260 行的用例改为「成功后记」，
    并新增「失败不记」「refreshFor 失败不写回、下次不被节流」两个用例。
12. 同一地址的 `latest.json` 与 `holidays.json` 并发取，整次刷新受 `totalTimeout`（默认 10 秒，Stopwatch 计时）约束，单个地址取 min(5 s, 剩余)。privacy.md 检查更新那条补了「刷新假日表时会同时读一次版本说明以核对校验值」。
13. 地址返回「不比当前新」时接着试后面的地址。校验时，传入 manifest 的 sha 对不上（manifest 来自还没同步的镜像）就再读这个地址自己的 `latest.json` 核对，否则镜像滞后仍会被 SHA 挡住。测试：Gitee 旧、jsDelivr 新 → updated（有无 SHA 各一个）。
14. 错误串只带「host：简短原因」（`HolidayRepository.shortError`：HttpException 去掉 URL，Socket / TLS 换成中文，其他截到 60 字）。SnackBar 只显示 `firstError`。
15. 关于页拆成两句：「只在…时联网。」+「检查更新和更新节假日表的请求里不带课表或个人信息；从教务导入时，账号密码只提交给学校教务系统。」
16. ICS：`build(utcOffset:)` 默认 +08:00（纯函数，测试注入其他值）；不是 +08:00 时输出浮动本地时间（没有 TZID / VTIMEZONE / X-WR-TIMEZONE）。弹窗 `utcOffset` 默认取 `DateTime.now().timeZoneOffset`，
    不是 +8 时显示「将按手机当前时区导出」。PRODID 改用 `appVersion`（→ `-//简课表//1.4.0//CN`）。注：模拟器时区是 GMT，在它上面导出会走浮动时间。
17. 弹窗、分享文字、两个 README 都改为：「建议导入到一个单独的日历；课表或调休有变化时，先清空那个日历再重新导入，日历不会自动删除已取消的课」。
18. 隐藏周末时，停课日只有「原本有课」才单独出列（周视图本地 `_wouldHaveClasses`，与规划器同一判断），调休照旧出列。原第 515 行的用例改为 6 列 + 10/11 不出列，另加「10/3、10/4 停课原本无课 → 5 列」「原本有课的周六停课 → 出列带休」。
19. 复课规则抽成顶层 `resumeTextFor(now, timetable)`：今天被停课覆盖 / 工作日没课且下一上课日 ≥2 天 / 周末且下一上课日晚于下周一。
    **除第 136 行外还改了第 128 行的用例**（10/7 停课、明天复课：按新规则「今天被停课覆盖」就写）。新增「普通周末不写」「周末接长假写」「工作日没课 2 天」三个用例，两个 README 同步。
20. `TimetableShare.pickAndImport(confirmReplaceTerm:)`：覆盖空课表、并且 `hasCustomTermSettings`（有 overrides 或开学日 ≠ 默认）时先确认，取消就返回 null、什么都不改。
    `importTimetableFromFile` 弹 `import-replace-term-confirm`「当前课表的学期设置会被文件里的替换，继续？」。
21. 「当天 N 门课」→「当天 N 节课」，预告「共 k 节」→「共 k 节课」、「等 N 节」→「等 N 节课」，ICS 弹窗 “添加全部” → 「添加全部」。课表管理 / 导入 SnackBar 里的「N 门课」数的是课程条目，没改。
22. `BackupService.exportAndShare` 改走 `shareFileWithSystemSheet`，文件名、MIME、subject、text 都不变。
23. `shu_schedule/android/app/build.gradle.kts`、`shu_schedule/README.md` 恢复 CRLF（Python 先统一成 LF 再转 CRLF）。`git ls-files --eol` 现为 `i/crlf w/crlf`，`git diff --stat` 为 12 行 / 49 行（=真实改动）。全仓库没有其他 i/w 不一致的文件。
24. 根 README「十一、发布」补了：APK 不进仓库只放 Releases（jsDelivr 有体积上限，数值未查证）；`holidays.json` 与 `latest.json` 同一次提交；镜像滞后会接着试、并发、10 秒。
25. 新 `test/privacy_consistency_test.dart`：同意框的「从教务导入 / 检查新版本 / 节假日表」对应 privacy.md 第二节的三个加粗标题，另外核对共同说法（不会发出任何网络请求、不带任何、IP 地址、本机生成）、第二节恰好 4 个场景，以及关于页文案。
- 测试缺口 2 **已做**：新 `test/reminder_gateway_test.dart` 用 `AndroidFlutterLocalNotificationsPlugin` 子类替换 `FlutterLocalNotificationsPlatform.instance`，
  测了精确 → 非精确回退、`_restorePendingTest`、`cancelAll` 清测试、P3-14 的竞态、`exactBySystem`（sdk 35 / 32 / null）。P3-14 的用例做过反向验证：把赋值挪回 await 之后，这条测试会失败。

#### 测试
- `flutter analyze` → No issues found!；`dart format --set-exit-if-changed lib test` → 0 changed；`flutter test` → **+613: All tests passed!**（573 → 613，日志 `.tmpbuild/plan14/testrun-X.log`）。
- `./gradlew :app:testDebugUnitTest` → BUILD SUCCESSFUL，`WidgetTimeLogicTest tests="24" failures="0" errors="0"`（20 → 24）。

#### 打包与模拟器（emulator-5554，API 35，设备时区 GMT）
- 只打了一次通用包：`flutter build apk --release` → 59,112,183 B（56.4MB），sha256 `121d45b52b5c431a1929ca221f6ff18f5b5d2cced6a4336d7793288df2dc12e8`；
  aapt2：`versionCode='9' versionName='1.4.0'`；permissions 里有 `SCHEDULE_EXACT_ALARM' maxSdkVersion='32'` 和 `USE_EXACT_ALARM`。`adb install -r` → Success；
  `dumpsys package`：`android.permission.USE_EXACT_ALARM: granted=true`。
- (a) 启动 logcat 显示 `[reminders] 已安排 41/41 条（exact=true）`。`dumpsys alarm`：41 条 ScheduledNotificationReceiver 闹钟全部是 `window=0 exactAllowReason=policy_permission flags=0x5`，`window=+1h` 为 0 条
  （修复前 F 的抓取是 32 条 `window=+1h`）。小组件的 3 条（2 BOUNDARY_REFRESH + DAILY_REFRESH）仍是非精确 RTC。权限卡「系统已授予：提醒准点送达」：X-2；tile：X-1。
- (b)(c) 当时设备时间 15:20–16:15，今天 10/7 停课（没有课），要到 18:00 才进入「自动看明天」；明天 10/8 有课，2×1 不会往后找。按指令**只靠 JVM 测试**，没有改数据也没有改时间。
  补看了一项：4×2 ▶ →「10月8日 · 第 4 周 · 明天 + 回到今天」，◀ 回到「10月7日 · 第 4 周 · 今天」（X-6 / X-5），说明 key 改名后翻页正常。
- (d) 「即将触发」末尾是「21:00 提醒已排到 10月20日，打开简课表就会续上」，计数行「共 41 条，系统里已安排 41 条。…接下来 14 天。」（没有「含测试提醒」）：X-3。
- (e) 假日页刷新 → SnackBar 只显示「更新源未配置」：X-4。crash 缓冲区没有 cn.shu.schedule。没有 force-stop、没有改系统时间。

#### 没做 / 遗留
- 按 fixlist 不做：P3-2（滑动途中列头和网格列数短暂不一致）、fixlist ④（通知组摘要；README 已说明点组标题只打开 App）。
- 自动看明天时 ◀ 回到今天、2×1 往后找到周一，都只有 JVM 测试，没在设备上看。
- 检查更新（UpdateChecker）本身仍是「第一个成功的源为准」，镜像滞后会让它看不到新版本（不在本轮范围）。
- 国产 ROM / 深度 Doze 下精确提醒的实际送达时刻仍没实测（review-G「未能验证」1）；.ics 在各日历 App 里的导入行为同样没实测。

### 发布包（最终打包，opus55）

- **通用包没有重打**：`find shu_schedule/lib shu_schedule/android shu_schedule/assets shu_schedule/pubspec.yaml shu_schedule/pubspec.lock -newer <修复轮的 app-release.apk> -type f`
  只列出 `shu_schedule/android/.gradle/9.3.1/…` 和 `.gradle/buildOutputCleanup/` 下 5 个 Gradle 自己的 lock / 状态文件（修复轮之后跑 `testDebugUnitTest` 留下的，已 gitignore），
  没有源码、资源、asset 或 pubspec 改动，所以直接复制修复轮的包；没有重跑 `flutter test`（仍是修复轮的 +613）。
- arm64 包：`flutter build apk --release --target-platform android-arm64`（Gradle 45.8s，日志 `.tmpbuild/plan14/P-build-arm64.log`），先复制通用包再打，避免同名输出被覆盖。

| 文件 | 字节 | SHA-256 |
|---|---|---|
| `dist/简课表-v1.4.0.apk`（通用） | 59,112,183（56.4 MiB / 59.1 MB） | `121d45b52b5c431a1929ca221f6ff18f5b5d2cced6a4336d7793288df2dc12e8` |
| `dist/简课表-v1.4.0-arm64.apk` | 21,539,853（20.5 MiB / 21.5 MB） | `1b20299b91a225d770cbd8bf4d3aa8a7ce09d56d5f32fd2330162758d9c00d1d` |
| `dist/latest.json` | 1,240 | （内容见下） |

- 两个包 `aapt2 dump badging | head -3` 相同：`package: name='cn.shu.schedule' versionCode='9' versionName='1.4.0' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36' compileSdkVersionCodename='16'`
  / `minSdkVersion:'24'` / `targetSdkVersion:'35'`。两个包都是 **versionCode 9**（没用 `--split-per-abi`，不会出现 2009）。
- `native-code`：通用包 `'arm64-v8a' 'armeabi-v7a' 'x86_64'`；**arm64 包也是这三个**——`unzip -l` 看 libflutter.so / libapp.so 只有 arm64-v8a，
  插件带的 libdartjni.so、libdatastore_shared_counter.so 三个 ABI 都有。和 1.3.0 / 1.3.1 的 arm64 包 lib/ 结构完全一致（v1.3.1 一节已记），这次没改构建配置。
  推断（未在 32 位真机 / 模拟器上验证）：32 位 armv7 手机能装上 arm64 包但启动时缺 libflutter 闪退，所以根 README「一」的表格补了「或装上后一打开就闪退（少数 32 位老手机）时改用通用包」，
  并把「体积小一半」改成实际的「约 21.5 MB，只有通用包的三分之一多」/「约 59 MB」（README 沿用「给朋友装」的十进制 MB）。「给朋友装」一节没动（改前改后截该节 sha256 都是 fac23437…）。
- `dist/latest.json`：`gen_latest.py --version 1.4.0+9 --apk "dist/简课表-v1.4.0-arm64.apk" --apk "dist/简课表-v1.4.0.apk" --changelog-file .tmpbuild/plan14/changelog-1.4.0.txt --out dist/latest.json`
  （D:/conda/miniconda3/python.exe，exit 0）。arm64 包放第一个，所以顶层 `sha256` = arm64 包（README「十一」的约定）；`holidays` = `e6d0cb56…2003` / 2026-10-06 / 3117 B，与 `sha256sum` 一致，
  `holidays.json` 是 LF、`core.autocrlf=false`、无 .gitattributes，提交后哈希不变。changelog 六行，以「· 」开头（和 App 把数组渲染成「· 」行的样式一致）。
- **`kRepo` 还是 `OWNER/REPO` 占位**：`downloadUrls` 是 `https://github.com/OWNER/REPO/releases/tag/v1.4.0`，脚本给了警告。改好 `shu_schedule/lib/core/repo_config.dart` 的 `kRepo`
  并重新生成之前，这份 `latest.json` 不能用（App 在占位状态下也不会去读它）；APK 只传 Releases，`latest.json` 和 `holidays.json` 同一次提交到仓库根 / `assets`。
- 截图都在 `shots/v140/`（61 张）：B-（提醒，15）、C-（小组件，11）、D-（ICS，5）、E-（长按调休 / 空状态，10）、F-（1.3.1 → 1.4.0 升级验证，14）、X-（修复轮，6）。

## v1.5.0 (2026-10-14)

依据 `PLAN-1.5.md` 与两轮评审定稿的 `.tmpbuild/plan15/fixlist-1.5.md`（20 项）。核心目标：按用户产品反馈收敛——去掉没人看的入口和工程术语，该自动的自动。

### 决策 D1–D10（含下午修订）
- **D1**：删掉首次启动的隐私同意弹窗与 `AppSettings.privacyAcceptedVersion`；「隐私说明」页保留，换为白话短文（`assets/privacy.md`）。
- **D2（下午修订）**：去掉底部导航栏与「今日」页；周课表铺满整屏作为首页，头部右上角加齿轮图标（`week-settings`）push 进入设置页；点击上课提醒通知 `popUntil(isFirst)` 回到课表本周。
- **D3**：删掉长按桌面图标的三个快捷方式（`shortcuts.xml`、三张图标、字符串、Manifest meta-data 与 intent-filter、通道 action）。
- **D4**：「添加桌面小组件」改为底部面板，含「当天课程 · 4×2」「下一节课 · 2×1」两张带预览图的卡片和「添加到桌面」按钮；底部按手机品牌给手动步骤；原生 `requestPinAppWidget` 传入 `PinResultReceiver` 回调弹 Toast 并回传 Dart 更新卡片状态。
- **D5**：删掉单张课表文件分享 / 导入（课表管理「选择文件」「分享此课表」、设置「从文件导入课表」、空状态「打开同学分享的文件」及 `timetable_share.dart`）。
- **D6**：备份保留但合并为一个入口「备份与恢复」，面板内含「导出备份文件」「从备份文件恢复」（恢复对话框按钮顺序「取消 / 覆盖 / 合并」，「合并」为主按钮，「覆盖」用危险色）。
- **D7**：上课提醒页去术语，删「权限」分组，仅在缺通知权限或「闹钟和提醒」被关时显示条件提示卡（`ReminderProblem`）。
- **D8（下午修订）**：开学日期自动化——① 教务识别到周次直接用；② 否则取覆盖今天或开学前 28 天内即将开学的学校校历作为默认，并在确认导入时弹面板确认；③ 都没有则弹不预选的「现在是第几周？」面板；手动新建课表或空状态首次加课时同样询问；周视图顶部「第 N 周 ▾」和学期设置「按当前周次设置」均可快速校正。
- **D9**：校历建议一键套用面板（「按 ×× 校历」），在导入后回首页、启动时、假期表联网刷新带来本校本学期新建议时提示一键套用放假 / 调休。
- **D10**：版本 `1.5.0+10`（`appVersion = '1.5.0'`）。

### 各任务摘要（交接单在 `.tmpbuild/plan15/handoff-*.md`）
- **A（壳层）**：删 `today_page.dart`、首次隐私同意框、图标快捷方式；空状态收敛为「从教务导入 / 手动添加」两个按钮；测试 613 → 590。
- **B（设置与文案）**：设置页重排为「课表 / 显示 / 桌面 / 其他」四组；新增 `backup_sheet.dart` 合并备份入口；删单表分享；提醒页换条件提示卡；替换白话 `privacy.md`；测试 590 → 607。
- **C（小组件添加面板）**：`MainActivity.kt` 支持 `day` / `next` 两个 provider 并挂 `PinResultReceiver`；新增 `widget_add_guide.dart` 按品牌给手动步骤，重写 `add_widget_helper.dart`；测试 607 → 646，Kotlin JVM 单测 24/24。
- **A2（无底栏首页）**：去掉 `NavigationBar`，`HomeShell` 直出 `WeekViewPage`，右上角齿轮进设置，点通知回到课表本周；测试 646 → 649。
- **D（开学日期与校历建议）**：新增 `term_resolver.dart`、`week_number_sheet.dart`、`calendar_suggestion_sheet.dart`；接入导入预览、周视图周次选择面板、学期设置「学校校历」与 `HomeShell` 三处触发点；正方周次探测追加 `AreaFive` 地址；测试 649 → 704。
- **E（术语与收尾）**：统一「假期表」用词；启动通知权限按钮改为「去允许通知」；`restoreFrom` 备份路径只打日志不再触发设置页红卡；更新弹窗去掉 SHA-256；删无调用的 `nextCourse` / `nextCourseAt`；测试 704 → 705。

### 两轮评审修复（`fixlist-1.5.md` 全部 20 项）
1. **确认过的开学日期不再被校历推翻（F1-1）**：`AppSettings` 新增 `termStartConfirmed`，在教务识别导入、周次面板确认、周视图校正、学期设置改日期 / 选校历、校历面板一键套用、手动新建课表选周时写入；`calendarSuggestionDismissed` 改为按本校本学期条目指纹 `termKey = '<schoolId>|<term.startDate>|<entriesHash>'` 记录（「先不用」与「一键套用」均写入），顶层 `updatedAt` 或外校变更不再打扰，一键套用后用户删单条调休不再重弹；`deleteTimetable` 同步清理两张表。
2. **开学前 28 天内导入支持校历（F1-2）**：`resolveTermStart` 新增 28 天即将开学窗口与 `upcoming` 标记，`showWeekNumberSheet` 支持顶部「还没开学（x月x日开学）」默认选项。
3. **手动新建课表询问第几周（F1-3）**：课表管理「新建课表」与空状态首次「手动添加」保存前均弹出 `showWeekNumberSheet`；关掉面板按本周一暂定并弹 SnackBar 引导顶部校正；`ScheduleConfig.defaults()` 注释明确仅留给测试、示例课表与坏存档兜底。
4. **周视图随开学日期 / 课表切换回到本周（F1-4）**：`_WeekViewPageState.build` 跟踪 `_seenStartDate` 与 `_seenTimetableId`，变化时重算 `_viewWeek` 并 `jumpToPage`。
5. **预览页 `schoolId` 来源统一（F1-5）**：State 统一取 `r.schoolId ?? widget.adapter?.id` 供校历解析与 `applyImport` 共用。
6. **消除真实 IO 时序偶发失败（F1-6）**：`test/helpers/harness.dart` 新增 `settleUntil`，替换写盘后弹 SnackBar 的固定轮数等待。
7. **校正周次入口显眼化（F2-7）**：周视图顶部「第 N 周」右侧加 16px `Icons.expand_more`；⋮ 菜单项改为「选择 / 校正周次」；学期设置「按当前周次设置」副标题动态显示当前周次；关于页常见问题同步指向顶部「第 N 周」。
8. **未配置更新源时隐藏死入口（F2-8）**：`!isConfigured` 时隐藏设置页「检查更新」与假期表页「联网更新假期表」按钮，反馈弹窗改为白话提示并去掉「开发中的版本」。
9. **主题描述去色值（F2-9）**：「经典蓝」描述改为「沉稳的深蓝，正式清爽，清晰安排每一天。」，设置页「主题」副标题只显示主题名，全部主题描述无 `#` 色值。
10. **学期设置「学校校历」优化（F2-10）**：移至「按当前周次设置」下方，标题拼学校名（如「上海大学校历」），点选弹带「撤销」的 SnackBar，保留用户自定义学期名，`schools.json` 学期名格式与 `holidays.json` 统一。
11. **校历建议面板折叠旧条目与去重描述（F2-11）**：仅逐条列出今天及以后的条目，已过去的折叠为「另有 n 条已经过去的，也会一起补上」；每条优先显示 `note`、日期统一「9月20日 周日」；副文案改为「现在课表显示的是第 N 周」。
12. **隐私说明统一「假期表」（F2-12）**：`assets/privacy.md` 第 3 条与 `PLAN-1.5.md` §3、测试断言同步改为「3. 更新假期表（和检查版本用同一个地址）。」。
13. **关于页与提醒页白话（F2-13 / F2-14）**：关于页四句按现界面重写（右上角 ⋮、「一键导入课表」、去「后端服务器 / 应用目录」）；提醒页副标题、分组标题（「接下来的提醒」）与页脚白话化。
14. **出错提示与「导入记录」白话（F2-15）**：反馈弹窗「Android 版本」→「系统版本」；`Storage` 损坏恢复统一白话提示（细节走 `debugPrint`）；假期表刷新失败 / 检查更新失败改为白话；`ZfsoftAdapter` 跳过脏数据的提醒合并去字段名；「诊断样本」统一改为「导入记录」。
15. **课程门数按同名+同教师去重（F2-16）**：`Timetable.uniqueCourseCount` / `formatCourseCount` / `courseCountText`（「8 门课（每周 15 节）」），课表管理、导入确认按钮、导入 SnackBar、删除确认框统一使用。
16. **恢复备份对话框按钮防误触（F2-17）**：按钮顺序改为「取消 / 覆盖 / 合并」，「合并」用 `FilledButton` 主按钮，「覆盖」文字用 `colorScheme.error`。
17. **叫法与注释统一 + 小组件添加成功回传（F2-18 / F2-19 / F2-20）**：开学日期统一「9月14日（周一）」，4×2 卡片改为「当天课程 · 4×2」；Manifest 权限注释同步；`MainActivity.onPinned` + `PinResultReceiver` 回传 `onWidgetPinned` 到 `NativeBridge.pinned`，面板收到后显示「已添加到桌面 ✓」并取消手动行高亮。
18. **文档清理**：根 `README.md`（含「给朋友装」）、`shu_schedule/README.md`（保持 CRLF）与 `site/index.html` 清理已删功能「分享此课表 / 从文件导入课表 / 今日页 / 图标快捷方式 / 首次隐私同意框」旧文案，补充 v1.5.0 说明与版本记录。

### 验证与发布包
- 静态检查与单测：`dart format --output=none --set-exit-if-changed lib test` → 0 changed；`flutter analyze` → `No issues found!`；`flutter test` 连跑两次均 **+720: All tests passed!**；Android 原生单测 `gradlew :app:testDebugUnitTest` → **BUILD SUCCESSFUL**（`WidgetTimeLogicTest` 24/24）。
- 发布包（均未使用 `--split-per-abi`，`aapt2 dump badging` 核对两个包均为 `versionCode='10' versionName='1.5.0'`、`minSdkVersion:'24'`、`targetSdkVersion:'35'`，`apksigner verify` 均 `Verifies`）：

| 文件 | 字节 | SHA-256 |
|---|---|---|
| `dist/简课表-v1.5.0.apk`（通用） | 59,315,446（56.6 MiB / 59.3 MB） | `9135df1a5053680d9b36e4dcc42a164c9fa1e1a33a79bbf566ddc81c4315f83d` |
| `dist/简课表-v1.5.0-arm64.apk` | 21,726,732（20.7 MiB / 21.7 MB） | `635cae01f3ebe0e4520783aaa7864b99857b65fa8a4e17bb4a5799740d2e8788` |
| `dist/latest.json` | 1,305 | `f7899ba95800772ef348fdff1b9dddf5309ce129f56eedde4b619ca0ba40d967` |

### 遗留
- 更新源 `kRepo` 仍为 `OWNER/REPO` 占位符：未配置时 App 自动隐藏「检查更新」与假期表手动刷新按钮、不发更新请求；正式建仓发布前替换 `lib/core/repo_config.dart` 并重跑 `tool/gen_latest.py`。
- 正方周次探测新增的 `index_cxshjdAreaFive.html` 尚未在真实校园网教务环境实测。
- 部分国产桌面（如小米 / vivo 某些版本）`requestPinAppWidget` 返回 `true` 但不弹系统框的情况无法在原生模拟器复现，已由面板手动步骤兜底。
- 本次因电脑重启恢复后避免过热，未额外启动 Android 模拟器重拍截图（前期任务 C / build / R1 已在 `shots/v150/` 留存实机截图，本次改动全部由 720 条单元 / Widget 测试与 Kotlin 单测覆盖）。
