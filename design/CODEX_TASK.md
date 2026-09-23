# 任务：为「上大课表」Android 课程表 App 设计主题系统（可爱、美丽、有辨识度）

背景：我们在用 Flutter 复刻 WakeUp 课程表（无广告版），首发学校是上海大学。你负责视觉设计，不写 Flutter 代码。
本工作目录可写，请把所有产出写到当前目录（D:\desk\claudex\12\design）。

## 产出 1：themes.json（必须，严格 JSON，可被程序直接读取）
设计 6 套主题，每套包含以下字段（颜色用 #RRGGBB 或 #AARRGGBB）：
{
  "id": "sakura",            // 英文 id
  "name": "樱花粉",          // 中文名
  "description": "...",      // 一句话描述气质
  "isDark": false,
  "colors": {
    "primary", "onPrimary", "secondary", "background", "surface", "surfaceVariant",
    "onSurface", "onSurfaceMuted", "outline", "todayHighlight", "gridLine",
    "timeColumnText", "headerText", "accent", "danger"
  },
  "courseColors": ["#..", ... 10 个用于课程块的柔和色，同一主题内彼此易区分，深浅适合白/深色文字],
  "courseTextOnBlock": "#..",   // 课程块上的文字颜色
  "cornerRadius": 14,           // 课程块圆角 dp
  "blockOpacity": 0.92,
  "fontHint": "rounded|serif|sans", // 字体气质建议
  "decor": { "backgroundAsset": "sakura_bg.png" 或 null, "emoji": "🌸", "widgetStyle": "glass|flat|paper" }
}
6 套建议方向（可调整）：樱花粉、薄荷奶绿、奶油杏、蓝莓夜（深色）、星空紫（深色）、上大蓝（以上海大学校色 #1F4E9C 一带为主的正式清爽风）。
要求：文字对比度满足 WCAG AA（正文 ≥ 4.5:1）；课程块 10 色在同一主题内不撞色；深色主题的课程色要降低饱和、提高透明感。

## 产出 2：DESIGN.md
- 每个主题的设计理念、适用场景
- 课表页布局建议：顶部周次栏、左侧节次时间列（上海大学一天 12 节，1-4 上午、5-8 下午、9-12 晚上，第 4/8 节后有长间隔）、课程块内文字层级（课程名 > 地点 > 教师）、当前时刻指示线
- 桌面小组件（Android AppWidget）两种规格的视觉稿说明：4x2「今日课程」列表卡片、4x4「本周课表」网格；给出每种规格的字号/间距/圆角/背景透明度建议
- 空状态、导入成功、周末无课等小插画/表情建议

## 产出 3（可选但很希望有）：背景插画
如果你有 image_gen 图像生成能力，请为「樱花粉」「薄荷奶绿」「星空紫」各生成 1 张竖版手机壁纸风格的淡雅背景（低对比、大量留白、适合在上面叠加课程表，不要文字），保存为 assets/sakura_bg.png、assets/mint_bg.png、assets/galaxy_bg.png（PNG，宽约 1080，高约 1920 或接近比例）。生成后请确认文件存在并记录尺寸到 DESIGN.md。如果没有图像生成能力，就在 DESIGN.md 里写明，并给出用纯 CSS/Flutter 渐变实现的替代方案（渐变色 stops）。

## 产出 4：preview.html
一个单文件 HTML（内联 CSS/JS），顶部有主题切换按钮，下面渲染一张示例周课表（周一到周日、12 节、放 6 门示例课程，课程名用真实上大课程名例如「高等数学A(2)」「大学英语」「程序设计」「线性代数」「体育」「思想道德与法治」）以及 4x2 小组件预览，用来快速看效果。颜色必须从 themes.json 的值抄过来（可直接内联 JSON）。

完成后请列出所有产出文件路径。
