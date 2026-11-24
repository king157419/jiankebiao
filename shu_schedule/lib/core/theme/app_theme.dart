import 'package:flutter/material.dart';

/// 主题的 15 个颜色 token，字段与 `assets/themes/themes.json` 的 `colors` 一一对应。
@immutable
class ThemeColors {
  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color outline;
  final Color todayHighlight;
  final Color gridLine;
  final Color timeColumnText;
  final Color headerText;
  final Color accent;
  final Color danger;

  const ThemeColors({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.outline,
    required this.todayHighlight,
    required this.gridLine,
    required this.timeColumnText,
    required this.headerText,
    required this.accent,
    required this.danger,
  });

  factory ThemeColors.fromJson(Map<String, dynamic> json) {
    Color pick(String key, Color fallback) =>
        parseHexColor(json[key], fallback: fallback);
    final surface = pick('surface', const Color(0xFFFFFFFF));
    final onSurface = pick('onSurface', const Color(0xFF1F2430));
    return ThemeColors(
      primary: pick('primary', const Color(0xFF1F4E9C)),
      onPrimary: pick('onPrimary', const Color(0xFFFFFFFF)),
      secondary: pick('secondary', const Color(0xFF3C5A85)),
      background: pick('background', surface),
      surface: surface,
      surfaceVariant: pick('surfaceVariant', surface),
      onSurface: onSurface,
      onSurfaceMuted: pick('onSurfaceMuted', onSurface),
      outline: pick('outline', const Color(0xFF8C9BB2)),
      todayHighlight: pick('todayHighlight', const Color(0x1F1F4E9C)),
      gridLine: pick('gridLine', const Color(0xFFE2E7F0)),
      timeColumnText: pick('timeColumnText', onSurface),
      headerText: pick('headerText', onSurface),
      accent: pick('accent', const Color(0xFF1F4E9C)),
      danger: pick('danger', const Color(0xFFB3261E)),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'primary': hexOf(primary),
    'onPrimary': hexOf(onPrimary),
    'secondary': hexOf(secondary),
    'background': hexOf(background),
    'surface': hexOf(surface),
    'surfaceVariant': hexOf(surfaceVariant),
    'onSurface': hexOf(onSurface),
    'onSurfaceMuted': hexOf(onSurfaceMuted),
    'outline': hexOf(outline),
    'todayHighlight': hexOf(todayHighlight),
    'gridLine': hexOf(gridLine),
    'timeColumnText': hexOf(timeColumnText),
    'headerText': hexOf(headerText),
    'accent': hexOf(accent),
    'danger': hexOf(danger),
  };
}

/// 主题的装饰信息：背景插画、表情、小组件样式。
@immutable
class ThemeDecor {
  /// 背景插画文件名（相对 `assets/images/`）；null 表示纯色背景。
  final String? backgroundAsset;

  /// 空状态等场景使用的表情。
  final String emoji;

  /// 小组件底板样式：`glass` | `paper` | `flat`（B3 使用）。
  final String widgetStyle;

  const ThemeDecor({
    this.backgroundAsset,
    this.emoji = '📘',
    this.widgetStyle = 'flat',
  });

  factory ThemeDecor.fromJson(Map<String, dynamic> json) {
    final raw = json['backgroundAsset'];
    return ThemeDecor(
      backgroundAsset: raw is String && raw.trim().isNotEmpty
          ? raw.trim()
          : null,
      emoji: json['emoji'] is String && (json['emoji'] as String).isNotEmpty
          ? json['emoji'] as String
          : '📘',
      widgetStyle: json['widgetStyle'] is String
          ? json['widgetStyle'] as String
          : 'flat',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'backgroundAsset': backgroundAsset,
    'emoji': emoji,
    'widgetStyle': widgetStyle,
  };
}

/// 一套完整主题。字段与 `themes.json` 的一个条目一一对应。
@immutable
class AppTheme {
  final String id;
  final String name;
  final String description;
  final bool isDark;
  final ThemeColors colors;

  /// 课程块底色，固定 10 个。
  final List<Color> courseColors;

  /// 课程块上的文字颜色（课程名 / 地点 / 教师共用，只靠字号字重分层级）。
  final Color courseTextOnBlock;

  /// 课程块圆角（dp）。
  final double cornerRadius;

  /// 课程块底色的不透明度；**只作用于课程块背景**，不能整体降低组件透明度。
  final double blockOpacity;

  /// 字体气质：`rounded` | `serif` | `sans`。不指定需要下载的字体。
  final String fontHint;

  final ThemeDecor decor;

  const AppTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.isDark,
    required this.colors,
    required this.courseColors,
    required this.courseTextOnBlock,
    required this.cornerRadius,
    required this.blockOpacity,
    required this.fontHint,
    required this.decor,
  });

  /// 第 [index] 个课程色（自动取模，越界不崩溃）。
  Color courseColor(int index) {
    if (courseColors.isEmpty) return colors.primary;
    final i = index % courseColors.length;
    return courseColors[i < 0 ? i + courseColors.length : i];
  }

  /// 课程块实际绘制的底色（已应用 [blockOpacity]）。
  Color courseBlockColor(int index) =>
      courseColor(index).withValues(alpha: blockOpacity);

  /// 背景插画的完整 asset 路径；没有插画时为 null。
  ///
  /// themes.json 里写的是 `*.png`（设计稿原图），工程内实际打包的是压缩过的
  /// `*.webp`，这里统一把扩展名换成 `.webp`。
  String? get backgroundAssetPath {
    final raw = decor.backgroundAsset;
    if (raw == null || raw.isEmpty) return null;
    final dot = raw.lastIndexOf('.');
    final base = dot > 0 ? raw.substring(0, dot) : raw;
    return 'assets/images/$base.webp';
  }

  /// 标题用字体族；只有 `serif` 气质的主题会给大标题换衬线，正文一律系统字体。
  String? get titleFontFamily => fontHint == 'serif' ? 'serif' : null;

  /// 映射成 Material 3 的 [ThemeData]。
  ThemeData toThemeData() {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.primary,
      onPrimary: colors.onPrimary,
      primaryContainer: colors.primary.withValues(alpha: isDark ? 0.28 : 0.16),
      onPrimaryContainer: colors.onSurface,
      secondary: colors.secondary,
      onSecondary: onColorFor(colors.secondary),
      secondaryContainer: colors.surfaceVariant,
      onSecondaryContainer: colors.onSurface,
      tertiary: colors.accent,
      onTertiary: onColorFor(colors.accent),
      error: colors.danger,
      onError: onColorFor(colors.danger),
      errorContainer: colors.danger.withValues(alpha: isDark ? 0.28 : 0.14),
      onErrorContainer: colors.onSurface,
      surface: colors.surface,
      onSurface: colors.onSurface,
      surfaceContainerLowest: colors.surface,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surfaceVariant,
      surfaceContainerHigh: colors.surfaceVariant,
      surfaceContainerHighest: colors.surfaceVariant,
      onSurfaceVariant: colors.onSurfaceMuted,
      outline: colors.outline,
      outlineVariant: colors.gridLine,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: colors.onSurface,
      onInverseSurface: colors.surface,
      inversePrimary: colors.accent,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
    );

    return base.copyWith(
      scaffoldBackgroundColor: colors.background,
      dividerColor: colors.gridLine,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        foregroundColor: colors.headerText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colors.headerText,
          fontWeight: FontWeight.w600,
          fontFamily: titleFontFamily,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
          side: BorderSide(color: colors.gridLine),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.onSurfaceMuted,
        textColor: colors.onSurface,
      ),
      dividerTheme: DividerThemeData(color: colors.gridLine, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(cornerRadius + 6),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.onSurface,
        contentTextStyle: TextStyle(color: colors.surface),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>(
          (states) =>
              states.contains(WidgetState.selected) ? colors.onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (states) =>
              states.contains(WidgetState.selected) ? colors.primary : null,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colors.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.outline),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cornerRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(cornerRadius),
        ),
        filled: true,
        fillColor: colors.surface,
      ),
    );
  }

  factory AppTheme.fromJson(Map<String, dynamic> json) {
    final rawColors = json['colors'];
    final rawDecor = json['decor'];
    final rawCourseColors = json['courseColors'];
    final courseColors = <Color>[];
    if (rawCourseColors is List) {
      for (final c in rawCourseColors) {
        courseColors.add(parseHexColor(c, fallback: const Color(0xFFB8D8F2)));
      }
    }
    if (courseColors.isEmpty) {
      courseColors.addAll(_fallbackCourseColors);
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('主题缺少 id');
    }
    final radius = json['cornerRadius'];
    final opacity = json['blockOpacity'];
    return AppTheme(
      id: id,
      name: json['name'] is String ? json['name'] as String : id,
      description: json['description'] is String
          ? json['description'] as String
          : '',
      isDark: json['isDark'] == true,
      colors: ThemeColors.fromJson(
        rawColors is Map
            ? Map<String, dynamic>.from(rawColors)
            : <String, dynamic>{},
      ),
      courseColors: List<Color>.unmodifiable(courseColors),
      courseTextOnBlock: parseHexColor(
        json['courseTextOnBlock'],
        fallback: const Color(0xFF1F2430),
      ),
      cornerRadius: (radius is num ? radius.toDouble() : 12.0).clamp(0.0, 40.0),
      blockOpacity: (opacity is num ? opacity.toDouble() : 0.95).clamp(
        0.1,
        1.0,
      ),
      fontHint: json['fontHint'] is String
          ? json['fontHint'] as String
          : 'sans',
      decor: ThemeDecor.fromJson(
        rawDecor is Map
            ? Map<String, dynamic>.from(rawDecor)
            : <String, dynamic>{},
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'description': description,
    'isDark': isDark,
    'colors': colors.toJson(),
    'courseColors': courseColors.map(hexOf).toList(),
    'courseTextOnBlock': hexOf(courseTextOnBlock),
    'cornerRadius': cornerRadius,
    'blockOpacity': blockOpacity,
    'fontHint': fontHint,
    'decor': decor.toJson(),
  };

  @override
  String toString() => 'AppTheme($id, $name)';
}

const List<Color> _fallbackCourseColors = <Color>[
  Color(0xFFF2C6D2),
  Color(0xFFE6C8EE),
  Color(0xFFCFCFEE),
  Color(0xFFB5D6F0),
  Color(0xFFBCE3E3),
  Color(0xFFD3EAB9),
  Color(0xFFEEE2AF),
  Color(0xFFF2CFAD),
  Color(0xFFDDCDBC),
  Color(0xFFC5D5BD),
];

/// 解析 `#RRGGBB` / `#AARRGGBB`；失败返回 [fallback]。
Color parseHexColor(Object? value, {required Color fallback}) {
  if (value is! String) return fallback;
  var text = value.trim();
  if (text.startsWith('#')) text = text.substring(1);
  if (text.length == 6) text = 'FF$text';
  if (text.length != 8) return fallback;
  final parsed = int.tryParse(text, radix: 16);
  if (parsed == null) return fallback;
  return Color(parsed);
}

/// 把颜色转回 `#RRGGBB` 文本。
String hexOf(Color color) {
  int channel(double v) => (v * 255).round().clamp(0, 255);
  final r = channel(color.r).toRadixString(16).padLeft(2, '0');
  final g = channel(color.g).toRadixString(16).padLeft(2, '0');
  final b = channel(color.b).toRadixString(16).padLeft(2, '0');
  return '#${(r + g + b).toUpperCase()}';
}

/// 在给定底色上应该用深字还是浅字。
Color onColorFor(Color background) => background.computeLuminance() > 0.5
    ? const Color(0xFF1B1B1F)
    : const Color(0xFFFFFFFF);
