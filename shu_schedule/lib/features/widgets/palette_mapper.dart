import '../../core/theme/app_theme.dart';
import 'widget_palette.dart';

/// 把 App 主题（[AppTheme]）映射成桌面小组件用的 [WidgetPalette]。
///
/// 小组件面对的是任意壁纸，所以 [WidgetPalette.surface] 必须是不透明色
/// —— `ThemeColors.surface` 在 themes.json 里本来就是不透明的 `#RRGGBB`，
/// 写进快照时 `WidgetPalette.hex` 还会再丢一次 alpha。
///
/// 见 NOTES.md「B3 记录 §3.1」。
WidgetPalette paletteFromTheme(AppTheme theme) => WidgetPalette(
  background: theme.colors.background,
  surface: theme.colors.surface,
  text: theme.colors.onSurface,
  mutedText: theme.colors.onSurfaceMuted,
  accent: theme.colors.accent,
  todayHighlight: theme.colors.todayHighlight,
  isDark: theme.isDark,
  courseColors: WidgetPalette.normalizeCourseColors(theme.courseColors),
  courseTextOnBlock: theme.courseTextOnBlock,
);
