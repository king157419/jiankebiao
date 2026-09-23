import 'package:flutter/widgets.dart';

/// 桌面小组件用的一组颜色。
///
/// 这是小组件自己的调色板，**故意不依赖 `AppTheme`**：Phase 3 接线时从主题映射过来
/// （见 NOTES.md「B3 记录」）。这样 B1 的主题实现和小组件可以各自演进。
///
/// 所有颜色最终会以 `#RRGGBB` 写进快照 JSON，由原生 Kotlin 用
/// `android.graphics.Color.parseColor` 解析。
@immutable
class WidgetPalette {
  /// 小组件最外层背景（周表图片的底色）。
  final Color background;

  /// 文字所在的不透明底板色（小组件根容器背景）。
  final Color surface;

  /// 正文文字色。
  final Color text;

  /// 次要文字色（时间、地点、教师）。
  final Color mutedText;

  /// 强调色（当前/下一节课、周次胶囊）。
  final Color accent;

  /// 今天这一列/这一行的浅色高亮底。
  final Color todayHighlight;

  /// 是否深色主题（原生端可据此微调分隔线）。
  final bool isDark;

  /// 课程块底色，固定 10 个，对应 `Course.colorIndex` 0..9。
  final List<Color> courseColors;

  /// 课程块上的文字色。
  final Color courseTextOnBlock;

  const WidgetPalette({
    required this.background,
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.accent,
    required this.todayHighlight,
    required this.isDark,
    required this.courseColors,
    required this.courseTextOnBlock,
  });

  /// 兜底调色板（design/themes.json 的「樱花粉」）。
  ///
  /// 主题还没加载好、或者主题映射失败时用它，保证小组件永远有可读的颜色。
  factory WidgetPalette.fallback() => const WidgetPalette(
    background: Color(0xFFFFF7FA),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF342632),
    mutedText: Color(0xFF68505F),
    accent: Color(0xFF933E6A),
    todayHighlight: Color(0xFFF5DCE8),
    isDark: false,
    courseColors: <Color>[
      Color(0xFFF4C4D4),
      Color(0xFFEAC7F1),
      Color(0xFFD2D0F1),
      Color(0xFFB8D8F2),
      Color(0xFFBFE5E5),
      Color(0xFFD5ECBB),
      Color(0xFFF0E4B1),
      Color(0xFFF4D1AF),
      Color(0xFFDFCFBE),
      Color(0xFFC7D7BF),
    ],
    courseTextOnBlock: Color(0xFF352D3B),
  );

  /// 取第 [index] 个课程色；越界自动取模，空表时回退到 [accent]。
  Color courseColor(int index) {
    if (courseColors.isEmpty) return accent;
    final i = index % courseColors.length;
    return courseColors[i < 0 ? i + courseColors.length : i];
  }

  /// 补齐/裁剪到恰好 10 个课程色，方便从任意长度的主题色表构造。
  static List<Color> normalizeCourseColors(List<Color> input) {
    if (input.isEmpty) return WidgetPalette.fallback().courseColors;
    return List<Color>.generate(10, (i) => input[i % input.length]);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'background': hex(background),
    'surface': hex(surface),
    'text': hex(text),
    'mutedText': hex(mutedText),
    'accent': hex(accent),
    'todayHighlight': hex(todayHighlight),
    'courseTextOnBlock': hex(courseTextOnBlock),
    'isDark': isDark,
    'courseColors': courseColors.map(hex).toList(),
  };

  /// `Color` → `"#RRGGBB"`（丢掉 alpha，小组件底板必须不透明）。
  static String hex(Color color) {
    final argb = color.toARGB32();
    return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
