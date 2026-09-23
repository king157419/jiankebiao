import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'app_theme.dart';

/// 内置兜底主题「经典蓝」（id 仍是历史上的 `shu`，存档里的 themeId 靠它兼容）。
///
/// 只在 `assets/themes/themes.json` 读取或解析失败时使用，
/// 内容与 themes.json 里 id = `shu` 的条目保持一致。
const AppTheme builtinShuTheme = AppTheme(
  id: 'shu',
  name: '经典蓝',
  description: '以 #1F4E9C 为主色的正式清爽风，清晰安排每一天。',
  isDark: false,
  colors: ThemeColors(
    primary: Color(0xFF1F4E9C),
    onPrimary: Color(0xFFFFFFFF),
    secondary: Color(0xFF315C77),
    background: Color(0xFFF3F7FC),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFE5EDF7),
    onSurface: Color(0xFF21334D),
    onSurfaceMuted: Color(0xFF536780),
    outline: Color(0xFF91A8C4),
    todayHighlight: Color(0xFFD9E7FB),
    gridLine: Color(0xFFD5E0ED),
    timeColumnText: Color(0xFF48617E),
    headerText: Color(0xFF1F406E),
    accent: Color(0xFF235E96),
    danger: Color(0xFFB03549),
  ),
  courseColors: <Color>[
    Color(0xFFB7D8F4),
    Color(0xFFA8DDE7),
    Color(0xFFC1DED4),
    Color(0xFFD1E4BE),
    Color(0xFFECE0B4),
    Color(0xFFEACCB4),
    Color(0xFFE5C2CC),
    Color(0xFFDEBCE7),
    Color(0xFFC9CBF5),
    Color(0xFFD1D8DF),
  ],
  courseTextOnBlock: Color(0xFF26364D),
  cornerRadius: 12,
  blockOpacity: 0.96,
  fontHint: 'sans',
  decor: ThemeDecor(emoji: '▦', widgetStyle: 'flat'),
);

/// 从 assets 读取主题表。
class ThemeRegistry {
  ThemeRegistry._();

  static const String assetPath = 'assets/themes/themes.json';

  /// 默认主题 id（设置里没存 themeId 或存了不认识的 id 时用它）。
  static const String defaultThemeId = 'shu';

  /// 读取并解析 `assets/themes/themes.json`。
  ///
  /// 读取失败 / JSON 非法 / 解析出 0 套主题时，回退到 `[builtinShuTheme]`，
  /// 不抛异常。
  static Future<List<AppTheme>> load({AssetBundle? bundle}) async {
    try {
      final text = await (bundle ?? rootBundle).loadString(assetPath);
      final themes = parse(text);
      if (themes.isEmpty) return const <AppTheme>[builtinShuTheme];
      return themes;
    } catch (e) {
      debugPrint('ThemeRegistry: 读取主题失败（$e），回退到内置「经典蓝」。');
      return const <AppTheme>[builtinShuTheme];
    }
  }

  /// 解析主题 JSON 文本；顶层必须是数组。单条解析失败只跳过那一条。
  static List<AppTheme> parse(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! List) {
      throw const FormatException('themes.json 顶层不是数组');
    }
    final result = <AppTheme>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        result.add(AppTheme.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // 跳过无法解析的单条主题。
      }
    }
    return result;
  }

  /// 按 id 找主题；找不到时依次退回 [defaultThemeId]、第一套、内置主题。
  static AppTheme resolve(List<AppTheme> themes, String? id) {
    if (themes.isEmpty) return builtinShuTheme;
    if (id != null && id.isNotEmpty) {
      for (final t in themes) {
        if (t.id == id) return t;
      }
    }
    for (final t in themes) {
      if (t.id == defaultThemeId) return t;
    }
    return themes.first;
  }
}
