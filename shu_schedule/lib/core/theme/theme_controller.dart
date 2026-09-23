import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle;

import '../app_state.dart';
import 'app_theme.dart';
import 'theme_registry.dart';

/// 主题状态：持有全部主题，并读写 `AppState.settings.themeId`。
///
/// 用法（Phase 3 接线）：
/// ```dart
/// final appState = AppState();
/// await appState.load();
/// final themeController = ThemeController(appState);
/// await themeController.load();
/// ```
class ThemeController extends ChangeNotifier {
  ThemeController(this._appState);

  final AppState _appState;

  List<AppTheme> _themes = const <AppTheme>[builtinShuTheme];
  bool _loaded = false;

  /// 是否已经从 assets 读过主题表。
  bool get isLoaded => _loaded;

  /// 全部可选主题。
  List<AppTheme> get themes => List<AppTheme>.unmodifiable(_themes);

  /// 当前主题；设置里的 themeId 不存在时回退到「经典蓝」。
  AppTheme get current =>
      ThemeRegistry.resolve(_themes, _appState.settings.themeId);

  /// 从 `assets/themes/themes.json` 加载主题表。失败时保留内置兜底主题。
  Future<void> load({AssetBundle? bundle}) async {
    _themes = await ThemeRegistry.load(bundle: bundle);
    _loaded = true;
    notifyListeners();
  }

  /// 切换主题并写入设置（AppState 内部会自动持久化）。
  Future<void> select(String themeId) async {
    if (_appState.settings.themeId == themeId) return;
    await _appState.setThemeId(themeId);
    notifyListeners();
  }
}
