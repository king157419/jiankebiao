# CARBON-本次修改说明（简课表 v1.5.0）

## 一、改了哪些文件、为什么

本次任务对照备份目录 `D:\desk\_carbon_backup_1117\jiankebiao\` 检查后，确认上次电脑重启前已完成 `fixlist-1.5.md`（20 项）的大部分业务代码改动与版本号升级，但尚未完成测试补齐与修复、静态检查清零、README 与官网旧文案清理、版本记录更新及正式安装包构建。本次完整保留已有成果（未删任何源码、文档、数据文件），接着把剩余工作全部收尾。

### 1. 业务逻辑与界面文案（对比备份共修改 40 个应用与规划文件，含重启前成果与本次收尾）

- **开学日期确认与校历建议不打扰（第 1、11 条）**
  - `shu_schedule/lib/models/app_settings.dart`：新增 `termStartConfirmed`（记录用户或教务已确认过的开学日期，兼容旧存档与备份恢复），更新 `calendarSuggestionDismissed` 说明。
  - `shu_schedule/lib/core/app_state.dart`：新建课表、导入课表、更新配置、校历一键套用均支持记录已确认开学日期与学期内容指纹 `termKey`，提供带状态回滚的 `restoreTimetableConfig`；删除课表时同步清理对应记录。
  - `shu_schedule/lib/features/settings/calendar_suggestion_sheet.dart`：新增按「学校 + 学期开学日 + 排好序的校历条目哈希」计算的 `calendarSuggestionTermKey`（本次补上哈希前显式排序 `entries.sort()`）；用户或教务确认过开学日期后不再提议改开学日；面板把今天之前的旧条目折叠为「另有 n 条已经过去的，也会一起补上」，每条只显示一种描述，日期统一写成「9月20日 周日」，当前状态改为「现在课表显示的是第 N 周」。
  - `shu_schedule/lib/app.dart`、`shu_schedule/lib/core/holiday_repository.dart`、`shu_schedule/lib/core/update/update_dialog.dart`：启动与联网刷新假期表时均传入 `termStartConfirmed`；联网刷新前后对比本校本学期的 `termKey`，只有本校条目真的变了且有未套用建议时才弹「假期表有更新」提示；检查更新失败改为白话「没能检查更新，稍后再试」（详细错误只打日志）。
- **开学前 28 天预导入与统一学校标识（第 2、5、18 条）**
  - `shu_schedule/lib/core/term_resolver.dart`：当前不在学期内时，自动匹配 28 天内即将开学的校历学期并标记 `upcoming = true`，展示「还没开学」。
  - `shu_schedule/lib/features/settings/week_number_sheet.dart`：支持开学前默认选中「还没开学（x月x日开学）」；新增手动建表询问周次的 `createTimetableWithWeekPrompt`（关掉面板按本周一暂定并弹提示）。
  - `shu_schedule/lib/features/import/pages/import_preview_page.dart`：统一用 `r.schoolId ?? widget.adapter?.id` 解析校历并写入课表；支持开学前确认弹窗；开学日期统一显示「9月14日（周一）」；确认按钮与导入完成提示改用按课程去重后的门数；「诊断样本」改为「导入记录」（本次顺手清掉一处未使用的 `zfsoft_adapter.dart` 引用，消除静态检查警告）。
- **手动新建课表询问周次、周视图自动回本周、入口显眼化（第 3、4、7 条）**
  - `shu_schedule/lib/features/settings/timetable_manage_page.dart`、`shu_schedule/lib/features/timetable/course_editor_page.dart`、`shu_schedule/lib/features/timetable/timetable_empty_state.dart`、`shu_schedule/lib/models/schedule_config.dart`、`shu_schedule/lib/core/presets.dart`：课表管理新建课表、以及一张课表都没有时空状态点「手动添加」保存前，都会弹出「现在是第几周？」面板；`ScheduleConfig.defaults()` 明确仅留给测试、示例课表和坏存档兜底。
  - `shu_schedule/lib/features/timetable/week_view_page.dart`：监听开学日期与课表切换，变化后自动回到新课表的本周；顶部「第 N 周」右侧加上下拉小箭头，右上角菜单「跳转到某一周」改名「选择 / 校正周次」。
- **隐藏未配置的死入口、主题去色值、学期设置校历优化（第 8、9、10 条）**
  - `shu_schedule/lib/features/settings/settings_page.dart`、`shu_schedule/lib/features/settings/holiday_apply_page.dart`、`shu_schedule/lib/features/settings/feedback_dialog.dart`：更新源未配置（仍为占位符）时隐藏「检查更新」和「联网更新假期表」按钮；反馈弹窗改为白话提示、「Android 版本」改为「系统版本」；设置页「主题」副标题只显示主题名；假期表刷新失败改为白话「假期表这次没更新成功，稍后会再试」。
  - `shu_schedule/assets/themes/themes.json`、`shu_schedule/lib/core/theme/theme_registry.dart`：「经典蓝」描述去掉 `#1F4E9C` 十六进制色值，改为白话描述。
  - `shu_schedule/lib/features/settings/term_settings_page.dart`、`shu_schedule/assets/schools.json`：「按当前周次设置」副标题动态显示当前第几周；「学校校历」移到它正下方并拼上学校名，点选后弹带「撤销」的提示且不覆盖用户自己起的学期名；统一学期命名格式。
- **白话文案、去重门数、恢复防误触、小组件回传（第 12–20 条）**
  - `shu_schedule/assets/privacy.md`、`PLAN-1.5.md`：第 3 条统一改为「更新假期表」。
  - `shu_schedule/lib/features/settings/about_page.dart`、`shu_schedule/lib/features/settings/reminder_settings_page.dart`：关于页与上课提醒页按评审意见全部换成学生好懂的白话（「接下来的提醒」等）。
  - `shu_schedule/lib/core/storage.dart`、`shu_schedule/lib/features/import/adapters/zfsoft_adapter.dart`、`shu_schedule/lib/core/feedback_links.dart`、`shu_schedule/lib/features/import/diagnostics/diagnostic_sample.dart`、`shu_schedule/lib/features/import/pages/school_select_page.dart`、`shu_schedule/lib/features/import/pages/web_login_page.dart`：存档恢复、教务脏数据跳过提示全部去掉内部文件名与字段名（技术细节只打日志），「诊断样本」统一改为「导入记录」。
  - `shu_schedule/lib/models/timetable.dart`：新增按「同名 + 同教师」去重的课程门数统计（如「8 门课（每周 15 节）」）。
  - `shu_schedule/lib/features/settings/backup_sheet.dart`：恢复备份弹窗按钮顺序改为「取消 / 覆盖 / 合并」，「合并」设为主按钮，「覆盖」标红防误点。
  - `shu_schedule/android/app/src/main/AndroidManifest.xml`、`MainActivity.kt`、`PinResultReceiver.kt`、`shu_schedule/lib/core/native_bridge.dart`、`shu_schedule/lib/features/widgets/add_widget_helper.dart`：更新权限注释；「当日课程」统一叫「当天课程」；用户在系统弹窗确认添加小组件后，原生端把结果传回界面显示「已添加到桌面 ✓」并取消手动步骤高亮。
  - `shu_schedule/pubspec.yaml`、`shu_schedule/lib/core/app_brand.dart`：版本号升至 `1.5.0+10`。
  - *签名配置说明*：正式版签名配置位于 `shu_schedule/android/key.properties` 与 `keys/` 目录，本次只按项目原有构建脚本直接调用，未读取、未改动、也未在此摘抄任何密钥或口令值。

### 2. 单元测试补齐与防抖改造（本次完成，共修改 17 个测试文件）

- `shu_schedule/test/helpers/harness.dart`、`test/week_view_day_override_test.dart`：新增 `settleUntil` 轮询真实文件写入，消除并行跑全量测试时偶发等不到底部提示的抖动（第 6 条）。
- `shu_schedule/test/helpers/fake_holiday_repository.dart`、`test/calendar_suggestion_test.dart`、`test/calendar_suggestion_wiring_test.dart`、`test/term_resolver_test.dart`、`test/week_number_sheet_test.dart`、`test/week_picker_fix_test.dart`、`test/term_settings_page_test.dart`、`test/empty_state_entries_test.dart`、`test/settings_page_test.dart`、`test/backup_sheet_test.dart`、`test/holiday_apply_page_test.dart`、`test/reminder_settings_page_test.dart`、`test/privacy_and_about_test.dart`、`test/privacy_consistency_test.dart`、`test/models_test.dart`、`test/migration_test.dart`、`test/ics_exporter_test.dart`、`test/core/native_bridge_test.dart`、`test/add_widget_sheet_test.dart`、`test/widgets/widget_android_config_test.dart`、`test/import/import_preview_page_test.dart`、`test/import/zfsoft_adapter_test.dart`、`test/import/diagnostics_test.dart`：同步新文案断言，并逐条补齐 `fixlist-1.5.md` 要求的全部新测试（教务识别周次重启不弹、校正周次重启不弹、套用后删单条调休重启不弹、同校条目变才弹、开学前 28 天导入、手动建表两条路径及关面板提示、改周次与切课表自动回本周、更新源开关态、门数去重、小组件回传等），总用例数从 705 增至 **720**。

### 3. 文档清理、版本记录与安装包产物（本次完成）

- `README.md`、`shu_schedule/README.md`（保持 CRLF 换行）、`site/index.html`：把已删除功能「分享此课表 / 从文件导入课表 / 打开同学分享的文件 / 今日页 / 长按图标快捷方式 / 首次启动隐私同意框」的旧文案全部清掉，同步 v1.5.0 新功能说明与版本历史（iPhone 导入日历办法同步改为直接用安卓端内置「导出到日历（.ics）」）。
- `NOTES.md`：新增 `## v1.5.0 (2026-10-14)` 完整记录（决策 D1–D10、各阶段摘要、20 项修复、验证数据、安装包大小与校验值、遗留事项）。
- `dist/简课表-v1.5.0.apk`、`dist/简课表-v1.5.0-arm64.apk`、`dist/latest.json`：构建正式签名通用包与 arm64 包（未使用 `--split-per-abi`，核对 `versionCode=10`），并用 `tool/gen_latest.py` 更新 `dist/latest.json`。

---

## 二、怎么验证的（测试命令与结果最后几行原样粘贴）

## 二、怎么验证的（测试命令与结果最后几行原样粘贴）

所有命令均先加载项目自带的 `D:\desk\claudex\12\env.ps1`（使用 `D:\desk\sdk\` 安卓与 Flutter 环境，临时目录指向 `D:\desk\claudex\12\.tmpbuild`），且严格串行运行，不同时开多个编译进程。

### 1. 代码格式与静态检查
命令：
```powershell
. D:\desk\claudex\12\env.ps1
Set-Location "D:\desk\claudex\12\shu_schedule"
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
```
结果最后几行原样粘贴：
```text
Formatted 134 files (0 changed) in 0.55 seconds.
EXIT=0
Analyzing shu_schedule...                                       
No issues found! (ran in 4.0s)
EXIT=0
```

### 2. Flutter 全量单元测试（连跑两遍验证稳定性）
命令：
```powershell
flutter test --no-pub -r expanded
```
第 1 遍结果最后几行原样粘贴：
```text
00:36 +719: D:/desk/claudex/12/shu_schedule/test/import/import_preview_page_test.dart: ImportPreviewDefaults 作息优先级：识别出的 > 当前课表 > 模板
00:36 +720: All tests passed!
EXIT=0
```
第 2 遍结果最后几行原样粘贴：
```text
00:35 +719: D:/desk/claudex/12/shu_schedule/test/import/import_preview_page_test.dart: ImportPreviewDefaults 作息优先级：识别出的 > 当前课表 > 模板
00:35 +720: All tests passed!
EXIT=0
```

### 3. Android 原生 Kotlin 单元测试
命令：
```powershell
Set-Location "D:\desk\claudex\12\shu_schedule\android"
.\gradlew.bat :app:testDebugUnitTest --no-daemon
```
结果最后几行原样粘贴：
```text
> Task :app:compileDebugUnitTestKotlin
> Task :app:compileDebugUnitTestJavaWithJavac NO-SOURCE
> Task :app:processDebugUnitTestJavaRes
> Task :app:testDebugUnitTest

BUILD SUCCESSFUL in 2m 5s
195 actionable tasks: 190 executed, 5 up-to-date
```

### 4. 构建 v1.5.0 正式安装包、生成 `dist/latest.json` 并校验包信息与签名
命令：
```powershell
Set-Location "D:\desk\claudex\12\shu_schedule"
flutter build apk --release --no-pub
Copy-Item -Force "build\app\outputs\flutter-apk\app-release.apk" "..\dist\简课表-v1.5.0.apk"
flutter build apk --release --target-platform android-arm64 --no-pub
Copy-Item -Force "build\app\outputs\flutter-apk\app-release.apk" "..\dist\简课表-v1.5.0-arm64.apk"
& "D:\conda\miniconda3\python.exe" "tool\gen_latest.py" --apk "..\dist\简课表-v1.5.0-arm64.apk" --apk "..\dist\简课表-v1.5.0.apk" --changelog $changelog --out "..\dist\latest.json"
& "D:\desk\sdk\android\build-tools\36.1.0\aapt2.exe" dump badging "..\dist\简课表-v1.5.0-arm64.apk"
& "D:\desk\sdk\android\build-tools\36.1.0\apksigner.bat" verify -v "..\dist\简课表-v1.5.0-arm64.apk"
```
结果最后几行原样粘贴：
```text
Running Gradle task 'assembleRelease'...                          176.5s
√ Built build\app\outputs\flutter-apk\app-release.apk (56.6MB)

Running Gradle task 'assembleRelease'...                          122.3s
√ Built build\app\outputs\flutter-apk\app-release.apk (20.7MB)
警告：lib/core/repo_config.dart 的 kRepo 还是占位符，downloadUrls 先用占位地址；发布前改好 kRepo 再重新生成。
已写入 D:\desk\claudex\12\dist\latest.json（1305 字节）

package: name='cn.shu.schedule' versionCode='10' versionName='1.5.0' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36' compileSdkVersionCodename='16'
minSdkVersion:'24'
targetSdkVersion:'35'

Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Number of signers: 1

简课表-v1.5.0.apk | bytes=59315446 | sha256=9135df1a5053680d9b36e4dcc42a164c9fa1e1a33a79bbf566ddc81c4315f83d
简课表-v1.5.0-arm64.apk | bytes=21726732 | sha256=635cae01f3ebe0e4520783aaa7864b99857b65fa8a4e17bb4a5799740d2e8788
latest.json | bytes=1305 | sha256=f7899ba95800772ef348fdff1b9dddf5309ce129f56eedde4b619ca0ba40d967
Stopping Daemon(s)
1 Daemon stopped
```

---

## 三、还剩什么没做

1. **未执行任何 Git 提交或远程发布**：严格遵守安全规则，未执行 `git commit / push / reset / checkout / stash`，未部署网页，未上传安装包，未发送任何通知消息，也未触碰 `D:\desk\webip\web` 目录。
2. **线上仓库地址仍为占位符**：按 `fixlist-1.5.md` 第 8 条规划拍板，本版暂不配置真实仓库地址（`shu_schedule/lib/core/repo_config.dart` 的 `kRepo` 保持 `OWNER/REPO`），界面已隐藏未配置的死入口。等你建好公开仓库发布时，改好 `kRepo` 再跑一遍 `tool/gen_latest.py` 即可启用在线更新。
3. **未额外启动安卓模拟器重截画面**：因电脑刚经历过热或意外重启，为遵守降温要求没有再拉起安卓模拟器（`shots/v150/` 已有评审前期的截图，本次 20 项逻辑与文案改动已全部通过 720 项自动化测试与正式包校验覆盖）。
4. **`site/` 目录中的历史静态安装包仍为 v1.3.0**：已按要求清掉 `site/index.html` 里「分享此课表」等已删功能的旧文案并补上版本记录；由于禁止删除旧文件且不执行线上部署，未删除或替换 `site/jiankebiao-v1.3.0-arm64.apk`。
