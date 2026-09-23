# v1.3.0 「去上大化 + 地基」实施计划（2026-09-23）

依据：REVIEW-2-product.md §9 v1.3 清单（Opus 5.5），由 Fable 总控拆分为 4 个阶段，opus55 逐阶段实现。
版本：pubspec `1.3.0+7`。包名 `cn.shu.schedule` 不动，签名 key 不动。

## 全局约束（每个阶段都要遵守）
- 工具链：每条命令前 `source /d/desk/claudex/12/env.sh && export TEMP=D:/desk/claudex/12/.tmpbuild TMP=D:/desk/claudex/12/.tmpbuild && mkdir -p "$TEMP"`。C 盘 0 字节可用，不设 TEMP 时 flutter test 会静默挂死。
- 项目目录 `/d/desk/claudex/12/shu_schedule`。不是 git 仓库（Phase D 才 init），不要 git 操作。
- 日期运算只用 `ScheduleUtils.addDays` / 日历加减，禁止 `Duration(days:)`（机器时区含夏令时）。
- 每阶段结束：`flutter analyze` 零 issue，`flutter test` 全绿，新增行为必须有单测。不要跑 gradle 发布构建（Fable 在 Phase D 统一构建）；需要验证 Kotlin/XML 编译时只允许 `flutter build apk --debug --target-platform android-arm64`，且同一时间只能有一个 gradle 构建。
- 老用户从 1.2.0 覆盖安装必须零数据丢失：所有 JSON 读取都要兼容旧格式，新增字段给默认值，并有「旧 JSON → 新模型」的迁移测试。
- 每阶段把「做了什么 / 没做什么 / 已知问题」追加到 `/d/desk/claudex/12/NOTES.md` 的 `## v1.3.0` 节（Phase A 新建该节）。
- 不要改包名、不要改 `DayWidgetProvider` 类名、不要改 keystore。

## 命名决定
- App 显示名改为「简课表」（strings.xml `app_name`、Manifest label、shortcuts、小组件 label、about、备份文件名、分享文案）。名字集中到一个 Dart 常量 `AppBrand.name` 与 `res/values/strings.xml` 两处，方便再改。
- 「上大课表」只在 NOTES/README 历史里保留。
- 来源标记 `sourceTag` 改为 `'${systemType}-${schoolId}'`（现在是 `zfsoft-shu`，保持向后兼容读取）。

## Phase A：数据模型与规则（opus55）
1. `ScheduleConfig` 新增 `overrides: Map<String /*yyyy-MM-dd*/, DateOverride>`；`DateOverride { bool cancelled; int? actAsWeek; int? actAsWeekday; String? note }`。`coursesOn(date)`（或等价入口）、今日页、周视图、`WidgetSync` 快照三处一致生效。单测覆盖：停课日、按其他星期上课（如国庆后周六上周一）、指定周次。
2. 休息带从作息推导：`WeekLayout` 不再写死 `[3,7]`；规则「相邻节次间隔 ≥ 40 分钟画一条带」，`ScheduleConfig.breakAfter` 可选手动覆盖（null=自动）。上午 5 节的 fixture 要正确。
3. `Course` 新增可选 `groupId`（同一门课多个时段），编辑器改颜色时同组同步；`externalKey`（导入时 `kch+jxbmc` 之类稳定键）。
4. `Timetable` 新增 `schoolId`, `systemType`, `termCode`, `importedAt`（均可空）。
5. 备份格式：`exportJson` 写 `version: 2`，`importJson` 按 version 分支，v1 → v2 迁移函数 + 测试；`AppSettings.settingsVersion` 同步处理。
6. 小组件快照从 14 天改为覆盖整学期：`snapshotDays = min(totalWeeks*7 + 7, 150)`，快照体积要测（SharedPreferences 单 key 上限内），并用 `overrides` 展开。Kotlin 端「打开 App 刷新」的兜底保留。
7. `demo_timetable.dart`、presets 里的上大专属内容保留但改名为通用示例（不影响功能）。

## Phase B：导入引擎泛化（opus55）
1. `network_security_config.xml`：明文放行改为 `edu.cn`（含子域），去掉 shu.edu.cn 专项。
2. `web_login_page.dart`：`onNavigationRequest` 拦截非 http(s) scheme，用 `url_launcher` 外跳（企业微信/微信/QQ 扫码登录），失败时 SnackBar 提示；加依赖 `url_launcher`。
3. `SchoolAdapter` 扩展：`allowedHosts`（登录判定用 host 列表）、`userAgent`（可空）、`presets`（学期预设，可空）、`captureMode`（先只实现 `fetch`，枚举里预留 `currentPage`）。`ImportResult` 加 `detectedPeriods`（可空）、`termCode`、`schoolId`、`systemType`。
4. 预览页：作息按「`detectedPeriods` ?? 当前课表作息 ?? 让用户选模板」；周次识别失败时不再 `nearestPreset(shuTermPresets)` 猜上大校历，而是让用户在预览页选「本学期第一周的周一」（日期选择器），默认值为最近的周一。
5. 导入完成后清理 WebView Cookie 与本地存储（`WebViewCookieManager.clearCookies()` 等）；设置页加「记住教务登录」开关，默认关闭。
6. `SchoolRegistry` 改为从 `assets/schools.json` 加载（结构：`{id,name,pinyin,aliases,type,entryUrl,baseUrl,allowedHosts,overrides:{},periodProfileId,status:"verified|community|experimental"}`），上大为唯一 `verified` 条目；学校选择页显示状态标签；「我的学校不在列表」入口：输入教务网址 → 按 URL 特征猜 type（目前只有 zfsoft，猜不到就提示暂不支持并给反馈入口）。
7. 诊断样本导出：导入失败或用户点击「导出诊断样本」时，把抓到的原始响应前 200KB 本地脱敏（学号 8-12 位数字、手机号、姓名字段）写入文件并用 share_plus 分享。
8. `sourceTag` 改为 `'${systemType}-${schoolId}'`，`course_detail_sheet` 显示兼容旧值。

## Phase C：产品层（opus55）
1. 品牌改名「简课表」（见命名决定），所有中文文案里去掉「上大」（历史文档除外）。
2. 手动录入提效：课程编辑器「保存并继续添加」（保留星期/周次，清课名）；周视图空格子长按直接新建（带入星期与节次）；「复制到其他星期」；教师/教室历史补全（从当前课表已有值）。
3. 单张课表分享与导入：设置或课表管理页「分享此课表」导出单表 JSON 文件（share_plus）；「从文件导入课表」用 file_picker 读入并新建课表（复用备份格式 v2 的单表子集）。
4. 调休编辑 UI：学期设置页新增「调休 / 停课」列表，可按日期添加：停课 / 按某星期上课 / 指定周次。
5. 检查更新：`lib/core/update/`，启动后每天最多一次拉 `latest.json`（字段 `versionCode, versionName, changelog, downloadUrls[], sha256`），源列表在一个常量文件里（GitHub raw + jsDelivr 镜像），每源 5 秒超时，不阻塞启动；有新版弹对话框显示更新日志，按钮跳系统浏览器（url_launcher）；设置页加「检查更新」手动入口。源 URL 里 owner/repo 用占位符 `OWNER/REPO`，检测到占位符时自动禁用并在设置页显示「未配置更新源」。加依赖 `package_info_plus`；网络用 `dart:io HttpClient`，不加 dio。
6. 隐私说明页（assets 内置 Markdown 或纯文本，按 REVIEW-2 §7.6 的条款写）+ 首次启动一次性「隐私说明」确认弹窗（同意前不做任何联网请求）+ 设置页「反馈」入口（跳 GitHub Issues 占位 URL，并提供复制邮箱）。
7. README.md 重写为面向用户的说明（安装、导入、常见问题、隐私），NOTES.md v1.3.0 节补齐。

## Phase D：集成与交付（Fable）
1. `git init`（仓库根 `/d/desk/claudex/12`，忽略 keys/、shu_schedule/android/key.properties、dist/、shots/、.tmpbuild/、build/、.dart_tool/ 等），首次提交。
2. 版本 `1.3.0+7`，release 构建（universal + arm64），aapt2 核对。
3. 模拟器 shu35：从 1.2.0 覆盖安装，验证数据保留、小组件、调休、新导入预览、更新检查禁用态、隐私弹窗；截图到 shots/v130/。
4. dist/简课表-v1.3.0.apk、-arm64.apk，交付说明。
