# 课表类 App 市场比对与简课表可借鉴之处

调研日期 2026-10-06。对象是简课表 v1.3.1（Flutter，仅安卓，侧载），对照 21 款课表类产品和格式。简课表自身的事实取自本仓库源码和任务给出的产品状态；竞品事实取自已核实档案，未核实的标「待核实」。

## 结论先行

简课表现在能演示出来的差异只剩一条：调休做成覆盖层，一键套用国务院假日表和上大放假补课通知后，周视图、今日页、小组件三处一致，原课程不动。「无广告无账号」「支持调休」都已有对手。最大缺口是上课提醒和日历（ICS）互通，同校 ShuYo 已有提醒。1.4 应先配好更新源，再做本地提醒、小组件自动切到明天、ICS 导出。

## 一、总览比对表

「可信度」一列：数字是核实员给的置信度；「待核实」表示未经核实或置信度低于 0.75。

| 产品 | 类别 | 平台 | 商业模式与广告 | 课表获取 | 调休与节假日 | 小组件与提醒 | 分享与导出 | 开源 | 维护 | 口碑/人气 | 可信度 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **简课表 1.3.1** | 独立课表 | 安卓侧载 | 免费·无广告 | WebView 注入+文件 | 内置假日表一键套 | 单日组件·无提醒 | JSON 文件 | 未公开 | 2026-10 在更 | 无数据 | 本地仓库 |
| 超级课程表 | 综合商用 | iOS/安卓/鸿蒙 | 广告+电商·重 | 内置浏览器识别 | 无 | 有·有提醒 | 二维码/截图 | 闭源 | 约月更 | iOS 2.9（1.5 万） | 0.86 |
| 今日校园 | 校方门户 | 全平台+PC | 学校采购·无广告 | 学校后台同步 | 学校配置 | 无组件·日程提醒 | 日程分享 | 闭源 | 约月更 | iOS 1.28（8.7 万） | 0.86 |
| 喜鹊儿 | 教务厂商 | iOS/安卓 | 学校采购 | 学校开通直连 | 学校发布调课 | 插件·推送 | 无 | 闭源 | 说明多为修 bug | iOS 1.15（2.2 万） | 待核实 |
| 华为日历课程表 | 系统预装 | 华为设备 | 免费·宿主有推荐 | 拍照/超表导入 | 无 | 卡片·课前提醒 | 分享课表 | 闭源 | 随系统 | 无评分 | 0.80 |
| 安卓厂商课表 | 系统预装 | 本品牌手机 | 免费 | 拍照+手动 | 无 | 岛/胶囊·系统提醒 | 未核实 | 闭源 | 随系统 | 无 | 待核实（0.6） |
| 小爱课程表 | 系统内置 | 小米设备 | 免费·有埋点 | 拍照 OCR | 无 | 4×4·弱提醒 | 链接分享 | 闭源 | 半停滞 | 无 | 0.86 |
| WakeUp 现行版 | 商用课表 | 安卓/iOS/鸿蒙 | 广告+会员 | WebView 抓 HTML | 付费调课工具 | 4 种·有提醒 | ICS/口令 | 闭源 | 约 12 天一版 | iOS 1.71；应用宝 4.8 | 0.86 |
| WakeUp 开源版 | 开源课表 | 安卓 | 2–5 元授权 | WebView+解析器 | 无 | 日/周·试验提醒 | ICS/备份 | Apache-2.0 | 2020 停更已删库 | 573 星 | 0.86 |
| 拾光课程表 | 开源课表 | 安卓+桌面实验 | 免费·无广告 | WebView+远程脚本 | 在线假日接口 | 4 种·精确提醒 | ICS/JSON/日历 | Apache-2.0 | 约月更 | 940 星 / 9.9k 下载 | 0.86 |
| 小律课程表 | 独立课表 | iPhone/iPad | 免费·无广告 | AI 截图/ICS | 节假日自动停课 | 灵动岛·日历闹钟 | 口令/图片 | 闭源 | 1–3 周一版 | 4.97（2165） | 待核实 |
| 极简课程表 | 独立课表 | iOS/Watch/安卓 | 买断·广告反复 | 网址+AI+代做 | 整天调休 | 多款·有提醒 | 日历（会员） | 闭源 | 在更 | 4.74（9323） | 待核实（0.72） |
| Celechron | 单校·浙大 | iOS/Watch/安卓 | 免费·无广告 | 原生代登录 | 远程校历 | iOS 组件·靠日历 | ICS/系统日历 | GPL-3.0 | 活跃 | 4.9（183）/ 350 星 | 0.86 |
| XDYou | 单校·西电 | 安卓/iOS/桌面 | 免费·捐赠 | 原生代登录 | 教务调停课 | 双端·7 天提醒 | ICS/系统日历 | MPL-2.0 | 约月更 | 4.5（125）/ 325 星 | 0.85 |
| 旦挞 | 单校·复旦 | 7 个平台 | 免费·公益横幅 | 原生代登录 | 无 | 无课表组件·无 | ICS | GPL/AGPL | 在更 | 4.6（468）/ 427 星 | 0.86 |
| THU Info | 单校·清华 | 安卓/iOS/鸿蒙 | 公益·无广告 | 原生代登录 | 学校数据自带 | 3 种·无提醒 | ICS | BSL 1.1 | 很活跃 | 4.8（188）/ 233 星 | 待核实 |
| ShuYo | 单校·上大 | 安卓（iOS 未上架） | 免费·自建后端 | 原生表单代登录 | 手动整日复制 | 3 尺寸·提醒+闹钟 | 无 | GPL-3.0 | 2026-09 v0.5.0 | 21 星 | 待核实 |
| 上大课表 | 单校·上大 | 安卓侧载 | 免费·无广告 | WebView SSO | 手动调休上课 | 3 尺寸·无提醒 | JSON 备份 | MIT | 停更 17 天 | 5 星 / 69 下载 | 待核实 |
| 滴答清单 | 通用日程 | 全平台+Web | 订阅·无广告 | 教务网页+识图 | 仅休/班角标 | 有·有提醒 | 无 ICS | 闭源 | 频繁 | 4.88（14.9 万） | 0.85 |
| Structured | 通用日程 | Apple/安卓/Web | 订阅/买断 | 手动+外部日历 | 无 | 全套·有提醒 | JSON | 闭源 | 活跃 | 4.87（1.3 万） | 0.85 |
| ClassIsland | 教室大屏 | Win/mac/Linux | 免费 | 手动+CSES | 手动预定课表 | 常驻横条·强提醒 | CSES | GPL-3.0 | 单人主力 | 2849 星 | 0.86 |
| CSES | 交换格式 | 文件格式 | ➖ | ➖ | 格式不支持 | ➖ | YAML/转 ICS | MIT | v1 冻结 | 42 星 | 0.85 |

评分均为 iOS 中国区 2026-10-06 快照，括号内为评分数。按行来源：超表 https://apps.apple.com/cn/app/id573868981 ；今日校园 https://apps.apple.com/cn/app/id1207509945 ；喜鹊儿 https://apps.apple.com/cn/app/id1152127141 ；华为 https://consumer.huawei.com/cn/support/content/zh-cn15939840/ ；厂商课表 https://www.ithome.com/0/925/392.htm ；小爱 https://open-schedule-prod.ai.xiaomi.com/docs/help/README.md ；WakeUp 现行 https://apps.apple.com/cn/app/id1553402284 ；WakeUp 开源 https://gitcode.com/gh_mirrors/wa/WakeupSchedule_Kotlin ；拾光 https://github.com/ShiGuangSchedule/shiguangschedule ；小律 https://itunes.apple.com/lookup?id=6758077325&country=cn ；极简 https://apps.apple.com/cn/app/id1581272719 ；Celechron https://github.com/Celechron/Celechron ；XDYou https://github.com/BenderBlog/traintime_pda ；旦挞 https://github.com/DanXi-Dev/DanXi ；THU Info https://github.com/thu-info-community/thu-info-app ；ShuYo https://github.com/shuosc/ShuYo ；上大课表 https://github.com/zmdld11/SHU-Class-Schedule ；滴答 https://help.dida365.com/articles/6950372717036044288 ；Structured https://apps.apple.com/cn/app/id1499198946 ；ClassIsland https://github.com/ClassIsland/ClassIsland ；CSES https://github.com/SmartTeachCN/CSES 。

**资料分歧与处理**（以有来源且经核实者为准）：

1. 上大课表有没有提醒：商业视角写「同校三款里只有简课表没有提醒」，但设计、技术两章和上大课表源码（只申请联网和安装包权限，没有通知代码）都显示上大课表也没有提醒。这里采用后者：三款里只有 ShuYo 有提醒（来源：https://github.com/zmdld11/SHU-Class-Schedule ）。
2. 简课表「检查更新」：产品状态写有 GitHub 更新源，但本仓库 `lib/core/update/update_config.dart` 的源仍是 `OWNER/REPO` 占位符，功能实际禁用；反馈入口同样是占位（`lib/core/feedback_links.dart`）；站点挂的是 v1.3.0（`site/index.html`）。
3. 极简课程表的广告：商业视角写 2025-11 加开屏广告、2026-09 撤回（来源：https://apps.apple.com/cn/app/id1581272719 ）；批评员转述应用宝 2026-09 有评论说「现在有开屏广告了」。两种说法都未核实，只能确定广告策略反复。
4. 拾光：最新版是 2026-10-06 发布的 v2.1.0（附桌面实验包），不是 v2.0.0；它不支持 ICS 导入，#139 实际是拒绝（来源：https://github.com/ShiGuangSchedule/shiguangschedule/releases/tag/v2.1.0 ）。
5. Celechron 的远程校历对研究生「自定义周次」课程不生效（来源：https://github.com/Celechron/Celechron/blob/main/lib/model/semester.dart ）。
6. WakeUp：VIP 免广告在 6.1.65（2026-05-06），账号同步在 6.0.80（2025-11-21）；作业帮收购只有多知「或收购」报道和同楼办公等旁证（来源：https://apps.apple.com/cn/app/id1553402284 ；http://www.duozhi.com/industry/insight/2025082717618.shtml ）。
7. 今日校园 9.9.22 起课表可以独立上架；华为「从超表一键导入」首发于 HarmonyOS 6.1（2026-06-01），不是鸿蒙 7（来源：https://apps.apple.com/cn/app/id1207509945 ；http://www.edutoutiao.com/train/18088.html ）。超表的「3618 所」是版本说明里的固定模板，不能当作覆盖证据。

## 二、同校格局：上海大学

| 维度 | ShuYo（待核实） | 上大课表（待核实） | 简课表 1.3.1 |
|---|---|---|---|
| 出品·许可 | 上大开源社区 SHUOSC，GPL-3.0 | 个人 zmdld11，MIT | 个人，源码未公开 |
| 栈·分发 | Flutter；安卓侧载，iOS 未上架 | Kotlin+Compose；GitHub 侧载 | Flutter；站点侧载 |
| 学校范围 | 仅上大 | 仅上大 | 学校注册表，上大已验证 |
| 导入 | 原生表单代登录，取正方 JSON | WebView 统一认证，同源取 JSON | WebView 登录注入；同学 JSON 文件 |
| 凭据 | 不存密码，Cookie 明文（#16） | 不碰密码；release 包把教务原文写进 logcat | 不碰密码，导入后清登录态 |
| 不登录能否用 | 不能 | 能 | 能 |
| 调休补课 | 整日复制/清空，刷新即丢（#9） | 长按列头设调休，列头标「补」；教务单周换教师打标 | 日期覆盖层三种；一键套国务院表+上大通知 |
| 提醒 | 课前通知+早课闹钟+iOS 实时活动 | 无 | 无 |
| 小组件 | 3 尺寸，下课后切明天 | 3 尺寸，课后预览明天 | 单日手动翻页，次日 00:00:30 回今天 |
| 教务外功能 | 空教室、教务通知、课程评价、论坛 | 无 | 无 |
| 服务器 | 自建 api.shuyo.work | 无 | 无 |
| 热度 | 21 星；Release 32 次下载 | 5 星；69 次下载 | 无公开数据 |

来源：ShuYo https://github.com/shuosc/ShuYo 、https://raw.githubusercontent.com/Lilin-1024/ShuYo/main/README.md 、https://github.com/shuosc/ShuYo/issues/16 、https://github.com/shuosc/ShuYo/issues/9 ；上大课表 https://github.com/zmdld11/SHU-Class-Schedule 、https://github.com/zmdld11/SHU-Class-Schedule/releases/tag/v0.5.1 、https://github.com/zmdld11/SHU-Class-Schedule/blob/main/app/src/main/java/io/github/zmdld11/shuschedule/ui/importer/ImportViewModel.kt ；简课表取自本仓库 `site/index.html`、`DayWidgetProvider.kt`。

判断：

- **ShuYo 是功能上的对手，上大课表是定位上的对手。** ShuYo 功能更全，但要强制登录、用原生表单收密码、自建服务器；上大课表和简课表一样不碰密码、数据纯本地。简课表不该和 ShuYo 拼「上大一站式」。
- **三款里只有简课表能把学校的放假补课通知一键写进课表**，而且不改原课程；ShuYo 的整日复制一刷新就丢，上大课表要逐日手调。这是在上大能当面演示的唯一硬差异。上大课表的「教务调课打标」只覆盖单周换教师，不算调休。
- **两个短板要先补**：提醒（ShuYo 已有），以及小组件课后自动切到明天（另两款都有）。
- **名字撞车**：简课表 1.0–1.2 版也叫「上大课表」，和 zmdld11 的项目同名（来源：本仓库 `site/index.html`），口头推荐时容易混淆，对外应统一用「简课表」。
- **体量都很小**：三款都是侧载，公开下载数只有几十次，真实用户量没法比较。

## 三、产品与交互设计视角

调休自动化分五档：L0 不处理；L1 用户按日手调；L2 内置或在线假日表一键套用；L3 维护者远程下发；L4 学校官方数据自带。CSES 是文件格式，不列入本表。

| 产品 | 首屏·首次引导 | 周视图密度手段 | 小组件实时状态 | 调休档位 | 手动录入 |
|---|---|---|---|---|---|
| **简课表** | 课表首屏；仅隐私同意 | 休息带、冲突 +N | 单日翻页，无实时 | L2 | 复制到他日、连续添加 |
| 超级课程表 | 运营位在前；账号前置 | 非本周灰显；晚课要滚 | 有；iOS 用户称组件消失 | L0 | 未核实 |
| 今日校园 | 门户；实名+设备校验 | 未核实 | 未见 | L0 | 学生不可改 |
| 喜鹊儿（待核实） | 8 类 30 余入口；强绑手机 | 高饱和色块、截断 | 有插件 | L4 | 只能加备注 |
| 华为日历 | 日历子模块；「立即创建」气泡 | 午休带、连堂合并 | 「上课中/N 分钟后」 | L0 | 课名候选 |
| 小爱课程表 | 周视图首屏；3 项确认 | 午/晚休带、便签格 | 曾只剩 4×4 | L0 | 点空格预填、PC 编辑 |
| WakeUp 现行版 | 加 Tab 与搜题；空网格 | 一屏 1–8 节 | 4 种+锁屏；YOYO 卡片 | L1（付费） | 复制上一时段、CSV |
| 拾光课程表 | 周视图；无引导 | 斜纹降级并排 | 4 种+明日预告；Android 16 实时通知 | L2（周视图不生效） | 拖拽、拉伸 |
| 小律（待核实） | 直进课表；启动公告打断 | 高度/字号滑杆、早午晚分割 | 主屏/锁屏+灵动岛 | L2 | AI 截图+剪贴板 |
| 极简（待核实） | 功能挤在编辑模式 | 早中晚分卡 | 多款+灵动岛+Watch | L1 | 路径深 |
| Celechron | 时间线首屏，网格在二级 | 按半学期 | iOS 倒计时；安卓无 | L3 | 不能手动录课 |
| XDYou | 首页卡片 | 周点阵、已结束褪色 | 今明切换 | L4 | 无按周重复 |
| 旦挞 | 三步聚光引导 | 单色块 | 无课表组件 | L0 | 逐个点周次 |
| THU Info（待核实） | 登录即同步 | 单元高度 0–20 档 | 3 种；iOS 无 | L4 | 点空白按坐标预填 |
| ShuYo（待核实） | 强制登录 | 拖动跳周、进度点 | 课后切明天；iOS 实时活动 | L1 | 两段式点击、冲突校验 |
| 上大课表（待核实） | 周视图首屏 | 非本周按格互斥 | 3 尺寸 | L1 | 点空格预填、周次实时预览 |
| 滴答清单 | 需在设置里开启 | 每天 12 节上限 | 小尺寸挤掉时间 | L0 | AI 识图+预览 |
| Structured | 日时间轴；预置任务 | 三档密度 | 锁屏/StandBy/实时活动 | L0 | 拖拽改时 |
| ClassIsland | 桌面横条；向导+聚光 | 简称+当前课展开 | 横条即组件 | L1 | 刷子式填格 |

来源同总览表各行；补充：小爱 https://i.ai.mi.com/h5/precache/ai-schedule/ ；Structured https://help.structured.app/en/articles/1897986 ；ClassIsland https://docs.classisland.tech/app/basic.html ；拾光 https://sgschedule.jursin.top/ ；喜鹊儿、极简见各自 App Store 页。

**1. 首屏没问题，风险在二级入口和首启。** 喜鹊儿这类门户把课表埋在 30 多个入口里（来源：https://apps.apple.com/cn/app/id1152127141 ，待核实）。简课表打开就是课表，但「套用节假日安排」放在学期设置的二级页（来源：本仓库 `lib/features/settings/term_settings_page.dart`），国庆前用户未必找得到。侧载没有商店截图帮忙介绍，首启要先保证周次算对。小爱首启只确认学历、总周数、当前周三项（来源：https://i.ai.mi.com/h5/precache/ai-schedule/ ）；反例是 ShuYo，首次同步时把当周设成第 1 周（来源：https://raw.githubusercontent.com/shuosc/ShuYo/main/lib/data/repositories/academic_schedule_repository.dart ，待核实）。简课表的导入预览已经会让用户确认开学日期（来源：本仓库 `lib/features/import/pages/import_preview_page.dart`），缺的是空状态。华为在网格首格放「+」并配气泡（来源：https://consumer.huawei.com/cn/support/content/zh-cn15939840/ ）；今日校园长假时显示「近期没有课程，请享受假期吧」（来源：https://apps.apple.com/cn/app/id1207509945 ），国庆停课时正好可以用来告诉用户哪天复课。

**2. 周视图密度看两点：晚课要不要往下滚，颜色分不分得清。** 超表有评论抱怨晚课要往下滑才看得到（来源：https://itunes.apple.com/cn/rss/customerreviews/page=1/id=573868981/sortby=mostrecent/json ）。THU Info 的单元高度滑杆调到 0 档时，全天正好一屏（来源：https://github.com/thu-info-community/thu-info-app/blob/master/apps/thu-info-app/src/ui/schedule/schedule.tsx ，待核实）。上大课表只在本格没有本周课时才画非本周课，比拾光的斜纹并排更省地方（来源：https://github.com/zmdld11/SHU-Class-Schedule/issues/22 ，待核实）。简课表导入时按课名哈希从 10 种颜色里取色（来源：本仓库 `zfsoft_adapter.dart` 的 `colorIndexFor`），8 门课里至少有两门撞色的概率约 98%（上大课表的防撞做法见 https://github.com/zmdld11/SHU-Class-Schedule/issues/42 ，待核实）。可访问性方面，只有 Structured（VoiceOver、读写障碍字体，来源：https://developer.apple.com/design/awards/ ）和小爱（TalkBack 标签）有证据。

**3. 小组件：同校两款已经按时间自动切换，实时状态的展示通道多半要靠厂商合作。** ShuYo 按 #7 的反馈改成了课后显示明天（来源：https://github.com/shuosc/ShuYo/issues/7 ，待核实），拾光有「明日预告」（来源：https://raw.githubusercontent.com/ShiGuangSchedule/shiguangschedule/main/picture/all_widget.png ）；简课表则要手点 ▶，第二天 00:00:30 才回到今天（来源：本仓库 `DayWidgetProvider.kt`）。华为中卡写「第 1-2 节 上课中 / 第 3-4 节 51 分钟后上课」，扫一眼就懂（来源：https://consumer.huawei.com/cn/support/content/zh-cn15939840/ ）。荣耀官方写明 YOYO 建议里的上课提醒数据来自 WakeUp（来源：https://www.honor.com/cn/support/content/zh-cn15849482/ ），这是 WakeUp 在分发上的护城河。连小爱自家的课表，上超级岛都要靠 LSPosed 模块（来源：https://github.com/Xposed-Modules-Repo/com.xiaoai.islandnotify ）。侧载 App 能用的只有标准通知和 Android 16 的实时更新通知，拾光已经在用（来源：https://sgschedule.jursin.top/guide/user/course-notification.html ）。

**4. 提醒做差了比不做更伤口碑，差异点应放在「读同一份调休结果」。** 小爱的提醒优先级低，常被折叠（来源：https://web.vip.miui.com/page/info/mio/mio/detail?postId=49251538 ，见「相关动态」）。极简会逐条列出近 7 天待触发的提醒供用户核对（来源：https://apps.apple.com/cn/app/id1581272719 ，待核实），值得照搬。简课表的提醒如果读同一份有效日程，就能做到停课日不响、补课日照常响、前一晚预告「明天按周三上课」。ShuYo（没有调休数据）和拾光（周视图不认假期）都做不到这一点。

**5. 调休要比的是同一档里的质量。** L1 有上大课表、ShuYo、极简；L2 有小律（待核实）和拾光；L3 有 Celechron（来源：http://calendar.celechron.top/2026-2027-1.json ）；L4 有 THU Info、XDYou。简课表的短板在就地操作和粒度。上大课表长按列头就能设置，并在列头标出补课来源（来源：https://github.com/zmdld11/SHU-Class-Schedule/releases/tag/v0.5.1 ，待核实）；极简的用户反复要求只调半天或单节（来源：https://itunes.apple.com/cn/rss/customerreviews/page=1/id=1581272719/sortby=mostrecent/json ，待核实）。

**6. 手动录入的好设计，都在省掉「开表单、选星期、选节次」这三步。** 小爱、THU Info、上大课表都是点空格自动预填。ShuYo 加了两段式点击和保存前的冲突校验（来源：https://raw.githubusercontent.com/shuosc/ShuYo/main/lib/features/home/academic_schedule_editor_page.dart ，待核实）。THU Info 在修改或删除时会问作用范围：仅这一次、每周同时段，还是全部（来源：https://github.com/thu-info-community/thu-info-app/blob/master/apps/thu-info-app/src/redux/scheduleData.ts ，待核实）。反面是旦挞，周次只能逐个点（来源：https://github.com/DanXi-Dev/DanXi/blob/main/lib/widget/dialogs/manually_add_course_dialog.dart ）。简课表缺的是冲突提示和「仅这一次」；后者正好能弥补调休只能按整天设置的不足。

## 四、导入与技术架构视角

| 产品 | 兜底·文件导入 | 教务凭据 | 覆盖与适配生态 | 提醒送达 | 栈·离线 |
|---|---|---|---|---|---|
| **简课表** | 同学 JSON；无 CSV/ICS/OCR | 不碰密码 | schools.json 随包；1 所已验证 | 无 | Flutter；全离线 |
| ShuYo（待核实） | 手动；无分享 | 不存密码，Cookie 明文 | 仅上大 | 64 条滚动+早课闹钟 | Flutter；轻后端 |
| 上大课表（待核实） | 手动、备份 | 不碰密码 | 仅上大 | 无 | Kotlin；本地 |
| 超级课程表 | 扫码复制、碰一碰 | 剪贴板「记住账密」 | 自称 3618 所 | 推送保活 | 强制账号 |
| 今日校园 | 个人日程 | 统一认证+绑手机 | 1200+ 为全业务口径 | 日程提醒 | 云端 |
| 喜鹊儿（待核实） | ➖ | 密码经厂商网关 | 青果客户 | 推送 | 强在线 |
| 华为日历 | 手动、超表导入 | ➖ | 教务导入已下线 | 系统级 | 预装 |
| 厂商课表（待核实） | YOYO/小布借 WakeUp 数据 | ➖ | 无教务直连 | 私有通道 | 品牌锁定 |
| 小爱课程表 | 链接分享、PC 编辑 | ➖ | 1445 所脚本作废 | 低优先级通知 | 在线 H5 |
| WakeUp 现行版 | 账密、HTML、CSV、口令、备份 | 称不存 | 1200+～3000+ 不一 | 有；YOYO 数据源 | 账号+广告 |
| WakeUp 开源版 | HTML、CSV、备份 | SSL 错误放行 | CourseAdapter 已删库 | 须先放小部件 | Kotlin；无账号 |
| 拾光课程表 | JSON、WakeUp 分享码 | 不存密码；自定义源无签名 | 索引 241 条、139 人贡献 | 精确闹钟 | KMP；无账号 |
| Celechron | 不能手动录课 | 安全存储存密码 | 仅浙大 | 靠日历 | Flutter；本地 |
| XDYou | 手动、缓存 | 明文存密码 | 仅西电 | 7 天滚动 | Flutter；无服务器 |
| 旦挞 | 手动 | 加密存密码 | 仅复旦 | 无 | Flutter+Swift |
| THU Info（待核实） | 手动；无文件 | Keychain 存密码 | 仅清华 | 无 | RN，含鸿蒙 |
| 小律（待核实） | ICS、口令 | ➖ | 与学校无关 | 日历+闹钟 | iOS 原生；无账号 |
| 极简（待核实） | 秘钥经服务器中转 | 未核实 | 自称 2700 家 | 仅当前课表 | iCloud |
| 滴答清单 | 手动 | 未核实 | 1000/400 两种口径 | 有 | 强制账号 |
| ClassIsland | CSES、迁移向导 | ➖ | 教室大屏 | 横幅/TTS | .NET；本地 |
| CSES | YAML | ➖ | 桌面大屏为主 | ➖ | v1 冻结 |

来源同总览表各行；简课表一行取自本仓库 `assets/schools.json`、`pubspec.yaml`（无通知相关依赖）。

**1. 代登录拿到的数据最准，但只能服务一所学校；WebView 注入是唯一既能推广到多校、又不碰密码的路线。** 走代登录的五款（ShuYo、Celechron、XDYou、旦挞、THU Info）全是单校产品。它们的数据确实更好，比如 XDYou 能读到教务的调课、停课、补课记录（来源：https://github.com/BenderBlog/traintime_pda/blob/main/lib/repository/ids_session/classtable_session.dart ）。代价是学校一改接口，所有用户一起登不上，旦挞就因此停摆约 10 周（来源：https://github.com/DanXi-Dev/DanXi/issues/542 ）。拍照识别门槛最低，但用户直说「根本不准」（来源：https://www.bilibili.com/video/BV1kWtB6EEEq/ ）。判断：坚持现有路线，拍照或 AI 识别只当兜底。

**2. 学校覆盖比的是适配的交付管线，宣传的学校数说明不了什么。** 超表的「3618 所」在 25 个版本里一直没变，是模板文案（来源：https://apps.apple.com/cn/app/id573868981 ）。能核对的是拾光：适配脚本放在独立仓库，和 App 发版解耦，App 内置离线快照，有 139 人贡献（来源：https://github.com/ShiGuangSchedule/shiguang_warehouse ）。中心化方案可能一夜清零。小爱的教务导入一下线，1445 所学校的社区脚本全部作废（来源：https://open-schedule-prod.ai.xiaomi.com/docs/help/README.md ）；CourseAdapter 先归档、后删库（来源：https://web.archive.org/web/20251225123425/https://github.com/YZune/CourseAdapter ）。简课表的适配随 APK 打包，修一所学校就要用户重装一次。判断：先把解析层做成纯 Dart 并配上脱敏样本，方便外校同学贡献；外置适配以后再说。

**3. 导入路径太少，而 WakeUp 流失的用户正是一个窗口。** WakeUp 的兜底依次是通用教务类型、HTML 源码、CSV 模板、口令、备份（来源：https://www.wakeup.fun/doc/import_schedule.html ）。小律把识别交给用户自选的大模型，App 只解析剪贴板里的 JSON，自己不维护任何学校适配（来源：https://apps.apple.com/cn/app/id6758077325 ，待核实）。珞珈能直接导入 WakeUp 的文件和分享码（来源：https://www.whu.sb/features ）。简课表只有两条导入路径。判断：按成本从低到高依次补上「从其他 App 打开文件导入」、CSV 模板、AI 提示词、ICS 导入，全部复用现有的预览页；不要学拾光逆向 WakeUp 的私有口令（来源：https://github.com/ShiGuangSchedule/shiguang_warehouse/blob/main/resources/GLOBAL_TOOLS/wake_up.js ）。

**4. 「不碰密码」是用户能自己验证的差异，细节要做到位。** 自己保存凭据的产品都出过问题：ShuYo 的 Cookie 和 XDYou 的密码都是明文存储（来源：https://github.com/shuosc/ShuYo/issues/16 ；https://github.com/BenderBlog/traintime_pda/issues/141 ）。WebView 路线本身也会出漏洞。WakeUp 3.621 对非 Google 渠道一律放行 SSL 错误，「申请适配」还会上传整页 HTML（来源：https://gitcode.com/gh_mirrors/wa/WakeupSchedule_Kotlin ）；上大课表把教务返回的原文写进了 logcat。判断：把「导入后清 Cookie」「SSL 错误默认拒绝」「正式版不打原始日志」写进发版检查清单。将来加提醒和日历，要新增通知、精确闹钟、日历三类权限，隐私说明必须同步修改。

**5. 调休的分水岭在于用覆盖层，还是直接改写课程。** 改写课程的做法都留下了隐患。ShuYo 一刷新课表，手动调整就被覆盖（来源：https://github.com/shuosc/ShuYo/issues/9 ）；拾光调课直接改数据库，单周课改 day 字段，多周课克隆一条新记录（来源：https://github.com/ShiGuangSchedule/shiguangschedule/blob/main/shared/src/commonMain/kotlin/com/xingheyuzhuan/shiguangschedule/data/repository/CourseTableRepository.kt ）。简课表把调休存在配置的 overrides 里，覆盖导入时沿用旧配置，所以调休不会丢；但课程列表会被整表替换，手动改过的课就没了（来源：本仓库 `lib/core/app_state.dart` 的 `applyImport`、`import_preview_page.dart`）。正方适配器已经会生成稳定的 externalKey（来源：本仓库 `zfsoft_adapter.dart`），做差异合并的条件已经具备。THU Info 用稳定的 localId 存用户的修改，每次刷新后重新叠加（来源：https://github.com/thu-info-community/thu-info-app/blob/master/apps/thu-info-app/src/redux/scheduleData.ts ，待核实），可以直接参照。

**6. 提醒有三种送达方式，侧载 App 只能用其中两种。** 第一种是厂商私有通道，侧载 App 进不去，而且并不稳定：YOYO 的课程卡最晚要 24 小时才生效（来源：https://www.honor.com/cn/support/content/zh-cn15849482/ ）。第二种是 App 自己发本地通知，这条路可行。XDYou 滚动安排未来 7 天的提醒（来源：https://github.com/BenderBlog/traintime_pda/blob/main/lib/repository/notification/course_reminder_service.dart ），拾光开机后会重新安排（来源：https://sgschedule.jursin.top/guide/user/course-notification.html ）。但 Android 14 起，新装应用默认拿不到精确闹钟权限（来源：https://developer.android.com/about/versions/14/changes/schedule-exact-alarms ），必须设计降级方案。第三种是交给系统日历，由 VALARM 触发提醒（来源：https://github.com/Celechron/Celechron/blob/main/lib/model/calendar_to_ical.dart ）。判断：第二、三种都做，而且都读同一份有效日程。

**7. ICS 是唯一通用的导出格式，质量好坏看三点：逐日展开、带时区、UID 稳定。** WakeUp 早期和旦挞都因为不带时区，导出的课整体偏了 8 小时（来源：http://web.archive.org/web/2020/https://github.com/YZune/WakeupSchedule_Kotlin/issues/12 ；https://github.com/DanXi-Dev/DanXi/issues/522 ）。THU Info 每次课单独生成一个事件，UID 保持稳定（来源：https://github.com/thu-info-community/thu-info-app/blob/master/apps/thu-info-app/src/utils/calendar.ts ）；拾光导出时会跳过假期（来源：https://sgschedule.jursin.top/guide/user/export-and-share.html ）。直接写入系统日历也有坑：THU Info 有用户反映课程被整批删掉（来源：https://github.com/thu-info-community/thu-info-app/issues/473 ），多数华为手表只同步近 7 天的日程（来源：https://consumer.huawei.com/cn/support/content/zh-cn15972606 ）。CSES 没有开学日期字段，增加该字段的提议已被关闭（来源：https://github.com/SmartTeachCN/CSES/issues/20 ），表达不了大学课表。判断：先做 .ics 文件导出，再做系统日历和 ICS 导入，CSES 放到最后。

## 五、商业、分发与合规视角

| 产品 | 分发渠道 | 安装信任·更新触达 | 隐私合规信号 | 维护可持续性 |
|---|---|---|---|---|
| **简课表** | Vercel 站点侧载，arm64 包 21.1MB | 站点公示 SHA-256；更新源占位、检查更新禁用 | 只申请联网权限；无商店标签背书 | 单人；仓库地址仍是占位 |
| 超级课程表 | 商店、官网 APK、鸿蒙 | 商店 | 隐私标签含跨 App 追踪 | 公司 27 人 |
| 今日校园 | 全平台商店+PC | 学校强制安装 | 2020 年被工信部通报 | 金智 IPO 撤回终止 |
| 喜鹊儿（待核实） | 商店 | 服务端拒绝旧版登录 | 收集精确位置 | 更新说明只写修 bug |
| 华为日历 | 预装 | 系统级 | 拍照识别要联网上传 | 教务导入已下线 |
| 小爱课程表 | 超级小爱内置；iOS 已下架 | 系统级 | onetrack 埋点 | 半停滞 |
| WakeUp 现行版 | 商店、鸿蒙、YOYO 数据源 | 应用宝「无广告」标签失实 | 隐私标签含第三方广告 | 作业帮系，开源库已删 |
| 拾光课程表 | GitHub+Gitee 镜像+加速代理 | 网盘有非官方包 | 无隐私政策；FAQ 让人在群里给账密 | 适配仓库 139 人 |
| 小律（待核实） | 仅 App Store | 商店 | 「未收集数据」 | 公司主体 |
| 极简（待核实） | App Store、小米商店 | 商店 | 标签与政策不一致 | 个人转公司 |
| Celechron | App Store+R2 直链 | 1.3.x Release 未附 APK；校历走 HTTP | 「未收集数据」 | 多人维护 |
| XDYou | GitHub、F-Droid、App Store | F-Droid 包由原作者签名 | 「未收集数据」 | 30 位贡献者 |
| 旦挞 | App Store、Play、F-Droid、AUR | 多渠道 | 17+（有 UGC） | 接口变更停摆 10 周 |
| THU Info（待核实） | 商店+TUNA/BFSU 镜像 | CI 生成构建溯源证明 | 统计上报自建服务器 | 社区维护 |
| ShuYo（待核实） | 侧载 | Release 32 次下载 | 隐私政策简略过时 | 341 次提交 316 次出自一人 |
| 上大课表（待核实） | GitHub 侧载，应用内更新 | v0.3.2 起固定签名 | release 包写 logcat | 连发 13 版后停更 |
| 滴答清单 | 全平台商店 | 商店 | 课表图片服务端识别 | 半年更新说明未提课表 |
| ClassIsland | GitHub、deepin/统信商店 | SignPath 免费签名 | Sentry 遥测默认开 | 核心靠一人 |

来源同总览表各行；补充：超表隐私政策 https://www.super.cn/webPage/privacy.html ；今日校园通报 https://www.secrss.com/articles/25141 、IPO https://www.yicai.com/news/102667821.html ；XDYou https://f-droid.org/zh_Hans/packages/io.github.benderblog.traintime_pda/ ；拾光 FAQ https://sgschedule.jursin.top/faq.html ；上大课表签名 https://github.com/zmdld11/SHU-Class-Schedule/issues/17 ；简课表取自本仓库 `site/index.html`、`update_config.dart`、`AndroidManifest.xml`。

**1. 「无广告」的承诺能撑多久，取决于成本结构和所有权。** WakeUp 开源时期承诺「永不加广告」，靠 2–5 元的诚信授权收费（来源：https://gitcode.com/gh_mirrors/wa/WakeupSchedule_Kotlin ）。被报道「或收购」之后，6.0.80 上线账号同步，2025-12 起出现开屏和摇一摇广告，6.1.65 推出 VIP 免广告，iOS 评分跌到 1.71（来源：https://apps.apple.com/cn/app/id1553402284 ）。用户已经有了戒心，小律的评论里有人说「怕他会变」（来源：https://itunes.apple.com/cn/rss/customerreviews/page=1/id=6758077325/sortby=mostrecent/json ）。简课表没有服务器，边际成本为零，不需要变现；但仓库地址还是占位符，「无广告」目前只有开发者自己作证。

**2. 付费墙和服务器是产品变质的两个起点。** Structured 的低分评论多在骂重复任务要付费（来源：https://itunes.apple.com/us/rss/customerreviews/page=1/id=1499198946/sortBy=mostRecent/json ）；反过来，极简的「6 元终身」是好评里常见的理由（待核实）。ShuYo 自建了后端，极简的分享秘钥要经 api.kotal.cn 中转，两者都背上了持续成本。简课表真要收钱，只考虑捐赠或一次性买断。

**3. 侧载的下载量天花板很低。** ShuYo 的 Release 只下载了 32 次，上大课表 69 次（待核实）。拾光被 HelloGitHub 收录、有 940 星，累计下载也只有 9.9k，用户原话是「唯一的门槛就是GitHub」（来源：https://hellogithub.com/repository/9f09baa3931a4f79940100829d4d0ca4 ）。对照之下，WakeUp 仅在华为渠道就装了 2122 万次（来源：http://www.duozhi.com/industry/insight/2025082717618.shtml ）。商店之外的折中渠道有 F-Droid（XDYou 已上架）和国内镜像（拾光用 Gitee，THU Info 用 TUNA、BFSU）。多端先靠 ICS 覆盖 iPhone 和电脑，比另做一个 iOS 端划算：Flutter 项目一碰到 iOS 的小组件和闹钟，就得写原生 Swift（来源：https://github.com/shuosc/ShuYo ）。

**4. 更新能否触达用户，决定了 1.3.1 的差异点能不能活到 2027 年。** 「套用节假日安排」依赖内置的 2026 年假日表，明年就会过期；而更新源和反馈入口都还是占位，站点上挂的还是 v1.3.0（来源：本仓库 `update_config.dart`、`feedback_links.dart`、`site/index.html`）。已经装了 App 的用户，目前没有任何途径得知新版。Celechron 和旦挞用远程 JSON/TOML 下发校历，数据错了当天就能改，但 Celechron 走 HTTP 明文（来源：http://calendar.celechron.top/2026-2027-1.json ）。喜鹊儿是反例，服务端直接拒绝旧版本登录（来源：https://github.com/MoicLoi/XiaoQue-UniversityTimetable ，待核实）。

**5. 口碑两极分化，而安卓端的不满几乎看不到。** iOS 中国区，靠广告或学校强制安装的产品在 1–3 分，独立、无广告的产品在 4.5 分以上（见总览表）。安卓上 WakeUp 在应用宝仍是 4.8 分（来源：https://sj.qq.com/appdetail/com.suda.yzune.wakeupschedule ），不满的用户转而用旧版和去广告模组自救（来源：https://github.com/zichen0116/wakeup-versions ；https://post.smzdm.com/p/apqx2ndw ）。这批人还没有被无广告的课表接住，但侧载够不着大多数人，简课表只能吃到一小块。

**6. 个人项目和公司产品都会撤，社区化适配最稳。** ClassIsland 9 月的提交全部出自一人，作者还因为状态不好休息过一阵（来源：https://github.com/ClassIsland/ClassIsland/releases/tag/2.1.1.1 ）。小爱下线教务导入、WakeUp 删库，都让社区写的适配一夜失效。简课表已有 schools.json 和 holidays.json 两个数据文件，可以从这里开始社区化。签名是单人项目最大的单点风险：简课表靠同一签名覆盖安装来保留数据（来源：本仓库 `site/index.html`），keystore 一旦丢失，所有用户都得卸载重装，所以必须离线备份。

## 六、值得简课表借鉴的做法（按优先级）

| # | 做法 | 来自 | 为什么适合简课表 | 工作量 | 建议版本 |
|---|---|---|---|---|---|
| 1 | 换掉更新源和反馈入口的占位，加 Gitee 镜像；检查更新只提示、不阻断 | 拾光、THU Info | raw 和 jsDelivr 两个源已预置；不做，后面所有改进都到不了用户手里 | 小 | 1.4 |
| 2 | 本地课前提醒：滚动安排 7 天，开机、改课、改调休后重排；前一晚预告「明天停课」「明天按周三上课」；提供权限状态页和测试提醒；拿不到精确闹钟时降级 | XDYou、ShuYo、拾光、华为 | 补最大缺口；复用已统一的有效日程，停课不响、补课照响是竞品做不到的 | 中 | 1.4 |
| 3 | 小组件课后自动切到明天；头部写「上课中·至 11:50」「51 分钟后上课」；加 2×1 尺寸只显示下一节 | ShuYo、拾光、华为 | 只需改 WidgetSnapshot 和 DayWidgetProvider；同校两款都已有 | 小 | 1.4 |
| 4 | ICS 导出：按有效日期逐日展开，带 TZID，UID 用「课程+日期+节次」生成，可选附带 VALARM | THU Info、Celechron、拾光 | 不需要服务器就能覆盖 iPhone 和电脑，并带上调休结果 | 中 | 1.4 |
| 5 | 调休就地设置：长按列头弹出现有的三种覆盖，列头标「休」「补」；选补课日时先列出 holidays.json 里的补班日，并排预览两天的课 | 上大课表、拾光 | 数据结构不动，把 1.3.1 的能力挪到看课表的地方 | 中 | 1.4 |
| 6 | 2027 年假日表：国务院通知一出就发版内置；之后改为随 latest.json 增量下发，附 sha256，仍由用户逐条勾选 | Celechron、旦挞 | 不做的话，核心卖点明年就失效；不能学 Celechron 走 HTTP | 中 | 1.4 内置，2.0 远程 |
| 7 | 空状态给出「教务导入 / 手动添加 / 打开同学文件」三个入口；长假时显示复课日期 | 华为、今日校园、小爱 | 侧载用户看不到商店介绍；开学日期确认已经有了，只差空状态 | 小 | 1.4 |
| 8 | 课程配色防撞；非本周课按格互斥显示 | 上大课表（待核实） | 现在按课名哈希取 10 色，8 门课撞色的概率约 98% | 小 | 1.4 |
| 9 | 单节覆盖：长按课程选「仅本周 / 本周起 / 全部」，存成「日期+节次」的覆盖 | THU Info、Structured | 补上调休只能按整天设置的不足，复用现有覆盖层 | 中 | 2.0 |
| 10 | 重新导入时做差异合并，保留手动修改和备注 | THU Info | 正方适配器已有稳定的 externalKey，而 applyImport 目前整表替换课程 | 中 | 2.0 |
| 11 | 扩充兜底导入：从其他 App 打开 JSON/CSV、CSV 模板、AI 提示词+剪贴板、ICS 与 WakeUp 导出文件，全部走现有预览页 | WakeUp、拾光、小律 | 全程离线；能接住想离开 WakeUp 的用户 | 中 | 2.0 |
| 12 | 解析层改成纯 Dart，配脱敏样本和命令行试跑 | CourseAdapter、拾光测试插件 | 让外校同学能贡献适配，正方适配可以从实验级升到已验证 | 中 | 2.0 |
| 13 | 公开源码，CI 生成构建溯源证明；开捐赠渠道代替广告 | THU Info、XDYou、ClassIsland | 让「无广告、无 SDK」能被外人查证，也能覆盖签名、域名等小额成本 | 中 | 2.0 |
| 14 | 写入系统日历：建独立日历，关闭同步时整体删除 | Celechron、XDYou | 不靠厂商合作也能用上系统提醒界面；但华为云空间不同步三方账户的日程，效果打折 | 中 | 2.0 |
| 15 | 适配脚本外置、可热更新，只认官方源并校验哈希 | 拾光 | 修一所学校不必重装；但要先做完第 12 条、有了社区贡献者才有意义 | 大 | 暂不 |

各条的依据见前文对应洞察；第 14 条华为限制的来源：https://consumer.huawei.com/cn/support/content/zh-cn16010818 。

## 七、应当避免的做法

1. **先承诺无广告，再加开屏或摇一摇广告**（WakeUp、极简、超表）。把「无广告、无第三方 SDK」写进隐私说明，守住这个成本最低的承诺。
2. **首启强制登录，或把账号放在使用之前**（ShuYo、超表、喜鹊儿）。保留跳过、手动录入、文件导入三条不需要登录的路径。
3. **保存或代交教务密码、明文存 Cookie、在群里收账号**（ShuYo、XDYou #141、拾光 FAQ）。WebView 登录、不碰密码是简课表现成的合规优势，不要倒退。
4. **调休时直接改写课程，或者各模块各算一套日程**（ShuYo、拾光）。提醒、ICS、新组件都要调用同一个有效日期函数，并配一致性测试。
5. **把提醒押在低优先级通道或厂商通道上，或者要求先放小部件才生效**（小爱、荣耀 YOYO、WakeUp 开源版）。侧载 App 进不去这些通道，用户也没法确认提醒到底开没开。
6. **粗糙的 ICS 导出**，比如不带时区、缺 UID、UNTIL 写法不合规（WakeUp 早期、旦挞、XDYou）。这类错误要等导入日历后才暴露，应该用测试样本兜住。
7. **在「看一眼」的路径上设障碍，或者悄悄砍功能**：启动公告（小律）、服务端拒绝旧版（喜鹊儿）、改版砍掉组件尺寸（小爱、超表）。改版要写进更新说明，并给出替代方案。
8. **供应链失守**：换签名或丢失 keystore（上大课表 #17）、注入来源未经校验的适配 JS（拾光的自定义源）、逆向竞品私有协议，或上传含个人信息的整页 HTML（拾光、WakeUp）。

## 八、本报告的局限

- **待核实**：THU Info、小律（核实员没来得及跑），以及本轮补做的 ShuYo、上大课表、极简（研究员置信度 0.72，截图多为 2021–2022 年旧图）、安卓厂商系统课表合集（0.6）、喜鹊儿。补做 5 份的原始档案没有随任务提供，本报告只用了三个视角章节和批评员意见里带来源的转述。
- **没有数据的维度**：提醒在国产 ROM 和 Android 14 以上的实际送达率；导入成功率与新生上手时长；可访问性（只有 Structured、小爱两家有证据，简课表自身未审计）；冷启动和耗电；Flutter 能否上鸿蒙 NEXT；上架国内商店的备案门槛；各家的真实用户量（同校三款都只有零星下载数）。
- **数据偏差**：评分几乎都是 iOS 快照，而简课表只做安卓；安卓商店评分很少，应用宝的「无广告」标签也不可信。体积只有零星数据：简课表通用包 58MB、arm64 包 21.1MB（来源：本仓库 `site/index.html`），拾光单 ABI 包约 4.84MB（来源：https://github.com/ShiGuangSchedule/shiguangschedule/releases/tag/v2.0.0 ），WakeUp iOS 版 112.6MB（来源：https://apps.apple.com/cn/app/id1553402284 ）。
- **未建档**：学习通（超星课表）、ClassTable、小应校园、珞珈 Luotopia、星课程表。
- **简课表自身**：事实取自本地仓库，已复核的有：更新源是占位符、只申请联网权限、没有通知相关依赖、导入时整表替换课程、按课名哈希取色、小组件 00:00:30 跨天。线上站点和发布状态可能已经变了。
- 调研日期为 2026-10-06。拾光在当天发布了 v2.1.0，时效性强的条目以各自的发布页为准。

## 九、来源

网页与代码仓库（去重，按首次出现顺序）：

- https://apps.apple.com/cn/app/id573868981
- https://apps.apple.com/cn/app/id1207509945
- https://apps.apple.com/cn/app/id1152127141
- https://consumer.huawei.com/cn/support/content/zh-cn15939840/
- https://www.ithome.com/0/925/392.htm
- https://open-schedule-prod.ai.xiaomi.com/docs/help/README.md
- https://apps.apple.com/cn/app/id1553402284
- https://gitcode.com/gh_mirrors/wa/WakeupSchedule_Kotlin
- https://github.com/ShiGuangSchedule/shiguangschedule
- https://itunes.apple.com/lookup?id=6758077325&country=cn
- https://apps.apple.com/cn/app/id1581272719
- https://github.com/Celechron/Celechron
- https://github.com/BenderBlog/traintime_pda
- https://github.com/DanXi-Dev/DanXi
- https://github.com/thu-info-community/thu-info-app
- https://github.com/shuosc/ShuYo
- https://github.com/zmdld11/SHU-Class-Schedule
- https://help.dida365.com/articles/6950372717036044288
- https://apps.apple.com/cn/app/id1499198946
- https://github.com/ClassIsland/ClassIsland
- https://github.com/SmartTeachCN/CSES
- https://github.com/ShiGuangSchedule/shiguangschedule/releases/tag/v2.1.0
- https://github.com/Celechron/Celechron/blob/main/lib/model/semester.dart
- http://www.duozhi.com/industry/insight/2025082717618.shtml
- http://www.edutoutiao.com/train/18088.html
- https://raw.githubusercontent.com/Lilin-1024/ShuYo/main/README.md
- https://github.com/shuosc/ShuYo/issues/16
- https://github.com/shuosc/ShuYo/issues/9
- https://github.com/zmdld11/SHU-Class-Schedule/releases/tag/v0.5.1
- https://github.com/zmdld11/SHU-Class-Schedule/blob/main/app/src/main/java/io/github/zmdld11/shuschedule/ui/importer/ImportViewModel.kt
- https://i.ai.mi.com/h5/precache/ai-schedule/
- https://help.structured.app/en/articles/1897986
- https://docs.classisland.tech/app/basic.html
- https://sgschedule.jursin.top/
- https://raw.githubusercontent.com/shuosc/ShuYo/main/lib/data/repositories/academic_schedule_repository.dart
- https://itunes.apple.com/cn/rss/customerreviews/page=1/id=573868981/sortby=mostrecent/json
- https://github.com/thu-info-community/thu-info-app/blob/master/apps/thu-info-app/src/ui/schedule/schedule.tsx
- https://github.com/zmdld11/SHU-Class-Schedule/issues/22
- https://github.com/zmdld11/SHU-Class-Schedule/issues/42
- https://developer.apple.com/design/awards/
- https://github.com/shuosc/ShuYo/issues/7
- https://raw.githubusercontent.com/ShiGuangSchedule/shiguangschedule/main/picture/all_widget.png
- https://www.honor.com/cn/support/content/zh-cn15849482/
- https://github.com/Xposed-Modules-Repo/com.xiaoai.islandnotify
- https://sgschedule.jursin.top/guide/user/course-notification.html
- https://web.vip.miui.com/page/info/mio/mio/detail?postId=49251538
- http://calendar.celechron.top/2026-2027-1.json
- https://itunes.apple.com/cn/rss/customerreviews/page=1/id=1581272719/sortby=mostrecent/json
- https://raw.githubusercontent.com/shuosc/ShuYo/main/lib/features/home/academic_schedule_editor_page.dart
- https://github.com/thu-info-community/thu-info-app/blob/master/apps/thu-info-app/src/redux/scheduleData.ts
- https://github.com/DanXi-Dev/DanXi/blob/main/lib/widget/dialogs/manually_add_course_dialog.dart
- https://github.com/BenderBlog/traintime_pda/blob/main/lib/repository/ids_session/classtable_session.dart
- https://github.com/DanXi-Dev/DanXi/issues/542
- https://www.bilibili.com/video/BV1kWtB6EEEq/
- https://github.com/ShiGuangSchedule/shiguang_warehouse
- https://web.archive.org/web/20251225123425/https://github.com/YZune/CourseAdapter
- https://www.wakeup.fun/doc/import_schedule.html
- https://apps.apple.com/cn/app/id6758077325
- https://www.whu.sb/features
- https://github.com/ShiGuangSchedule/shiguang_warehouse/blob/main/resources/GLOBAL_TOOLS/wake_up.js
- https://github.com/BenderBlog/traintime_pda/issues/141
- https://github.com/ShiGuangSchedule/shiguangschedule/blob/main/shared/src/commonMain/kotlin/com/xingheyuzhuan/shiguangschedule/data/repository/CourseTableRepository.kt
- https://github.com/BenderBlog/traintime_pda/blob/main/lib/repository/notification/course_reminder_service.dart
- https://developer.android.com/about/versions/14/changes/schedule-exact-alarms
- https://github.com/Celechron/Celechron/blob/main/lib/model/calendar_to_ical.dart
- http://web.archive.org/web/2020/https://github.com/YZune/WakeupSchedule_Kotlin/issues/12
- https://github.com/DanXi-Dev/DanXi/issues/522
- https://github.com/thu-info-community/thu-info-app/blob/master/apps/thu-info-app/src/utils/calendar.ts
- https://sgschedule.jursin.top/guide/user/export-and-share.html
- https://github.com/thu-info-community/thu-info-app/issues/473
- https://consumer.huawei.com/cn/support/content/zh-cn15972606
- https://github.com/SmartTeachCN/CSES/issues/20
- https://www.super.cn/webPage/privacy.html
- https://www.secrss.com/articles/25141
- https://www.yicai.com/news/102667821.html
- https://f-droid.org/zh_Hans/packages/io.github.benderblog.traintime_pda/
- https://sgschedule.jursin.top/faq.html
- https://github.com/zmdld11/SHU-Class-Schedule/issues/17
- https://itunes.apple.com/cn/rss/customerreviews/page=1/id=6758077325/sortby=mostrecent/json
- https://itunes.apple.com/us/rss/customerreviews/page=1/id=1499198946/sortBy=mostRecent/json
- https://hellogithub.com/repository/9f09baa3931a4f79940100829d4d0ca4
- https://github.com/MoicLoi/XiaoQue-UniversityTimetable
- https://sj.qq.com/appdetail/com.suda.yzune.wakeupschedule
- https://github.com/zichen0116/wakeup-versions
- https://post.smzdm.com/p/apqx2ndw
- https://github.com/ClassIsland/ClassIsland/releases/tag/2.1.1.1
- https://consumer.huawei.com/cn/support/content/zh-cn16010818
- https://github.com/ShiGuangSchedule/shiguangschedule/releases/tag/v2.0.0

本仓库文件（简课表自身事实，未公开）：`shu_schedule/lib/core/update/update_config.dart`、`shu_schedule/lib/core/feedback_links.dart`、`shu_schedule/lib/core/app_state.dart`、`shu_schedule/lib/features/import/pages/import_preview_page.dart`、`shu_schedule/lib/features/import/adapters/zfsoft_adapter.dart`、`shu_schedule/lib/features/settings/term_settings_page.dart`、`shu_schedule/android/app/src/main/kotlin/cn/shu/schedule/widgets/DayWidgetProvider.kt`、`shu_schedule/android/app/src/main/AndroidManifest.xml`、`shu_schedule/assets/schools.json`、`shu_schedule/pubspec.yaml`、`site/index.html`。
