import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/app_brand.dart';
import 'core/app_state.dart';
import 'core/native_bridge.dart';
import 'core/privacy_policy.dart';
import 'core/theme/theme_controller.dart';
import 'core/update/update_checker.dart';
import 'core/update/update_dialog.dart';
import 'features/settings/privacy_page.dart';
import 'features/settings/settings_page.dart';
import 'features/timetable/today_page.dart';
import 'features/timetable/week_view_page.dart';
import 'features/widgets/add_widget_helper.dart';
import 'features/widgets/palette_mapper.dart';
import 'features/widgets/widget_sync.dart';

/// 应用外壳：Provider + MaterialApp + 底部三个 tab。
///
/// Phase 3 接线方式（`lib/main.dart`）：
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   runApp(ShuScheduleApp(
///     extraRoutes: <String, WidgetBuilder>{
///       importRouteName: (_) => const ImportFlowPage(),   // B2 提供
///     },
///   ));
/// }
/// ```
/// [appState] / [themeController] 只在测试里需要注入；不传时由本 Widget
/// 自己创建并 `load()`。
class ShuScheduleApp extends StatefulWidget {
  /// 由外部注入的状态（测试用）。为 null 时内部创建。
  final AppState? appState;

  /// 由外部注入的主题控制器（测试用）。为 null 时内部创建。
  final ThemeController? themeController;

  /// 额外路由。Phase 3 在这里注册 `/import`（B2 的 `ImportFlowPage`），
  /// 之后 `Navigator.pushNamed(context, importRouteName)` 就能用。
  ///
  /// 占位示例：
  /// ```dart
  /// routes: <String, WidgetBuilder>{
  ///   // importRouteName: (_) => const ImportFlowPage(),
  /// }
  /// ```
  final Map<String, WidgetBuilder> extraRoutes;

  const ShuScheduleApp({
    super.key,
    this.appState,
    this.themeController,
    this.extraRoutes = const <String, WidgetBuilder>{},
  });

  @override
  State<ShuScheduleApp> createState() => _ShuScheduleAppState();
}

class _ShuScheduleAppState extends State<ShuScheduleApp> {
  late final AppState _appState;
  late final ThemeController _themeController;
  late final bool _ownsState;

  /// 小组件推送的防抖计时器。一次导入会连续触发 3~4 次 `AppState._commit()`
  /// （createTimetable / replaceCourses / updateConfig），每次都要重算 14 天快照
  /// 并写盘，所以必须合并（NOTES.md「B3 记录 §3.2」）。
  Timer? _widgetDebounce;

  /// 防抖窗口。
  static const Duration _widgetPushDelay = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _ownsState = widget.appState == null;
    _appState = widget.appState ?? AppState();
    _themeController = widget.themeController ?? ThemeController(_appState);
    _appState.addListener(_scheduleWidgetPush);
    _themeController.addListener(_scheduleWidgetPush);
    _bootstrap();
  }

  @override
  void dispose() {
    _widgetDebounce?.cancel();
    _appState.removeListener(_scheduleWidgetPush);
    _themeController.removeListener(_scheduleWidgetPush);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_ownsState && !_appState.isLoaded) {
      await _appState.load();
    }
    if (!_themeController.isLoaded) {
      await _themeController.load();
    }
    // 启动后无条件推一次：小组件的「今天高亮」和周次只有被 push 时才会更新，
    // 跨天/跨周之后必须靠这一次把它们拉回正确状态。
    _widgetDebounce?.cancel();
    await _pushWidgets();
  }

  /// 数据或主题变更后安排一次推送（防抖 800ms）。
  void _scheduleWidgetPush() {
    _widgetDebounce?.cancel();
    _widgetDebounce = Timer(_widgetPushDelay, _pushWidgets);
  }

  /// 把当前课表 + 当前主题推给桌面小组件。
  ///
  /// `WidgetSync.push` 自己吞掉全部异常，这里不需要再 try/catch；
  /// 没有课表时不推（传 null 会 NPE）。
  Future<void> _pushWidgets() async {
    final timetable = _appState.currentTimetable;
    if (timetable == null) return;
    await WidgetSync.push(
      timetable,
      paletteFromTheme(_themeController.current),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <ChangeNotifierProvider<ChangeNotifier>>[
        ChangeNotifierProvider<AppState>.value(value: _appState),
        ChangeNotifierProvider<ThemeController>.value(value: _themeController),
      ],
      child: Consumer<ThemeController>(
        builder: (_, controller, _) {
          final theme = controller.current;
          return MaterialApp(
            title: AppBrand.name,
            debugShowCheckedModeBanner: false,
            theme: theme.toThemeData(),
            home: const HomeShell(),
            routes: widget.extraRoutes,
            onUnknownRoute: (settings) => MaterialPageRoute<void>(
              builder: (_) => _NotWiredPage(routeName: settings.name ?? ''),
            ),
          );
        },
      ),
    );
  }
}

/// 底部导航：课表 / 今日 / 设置。
///
/// 顺带负责处理「长按 App 图标」的三个快捷方式（见 `NativeBridge`）：
/// - `today` → 切到「今日」tab；
/// - `import` → 打开导入流程；
/// - `add_widget` → 走和设置页同一个「添加桌面小组件」流程。
///
/// v1.3.0：AppState 加载完之后先过「隐私说明」这一关——没同意过当前版本
/// （`AppSettings.privacyAcceptedVersion < PrivacyPolicy.version`）就弹一次性确认框，
/// **同意之前不做任何联网请求**：自动检查更新不跑，快捷方式动作（`import` 会打开
/// 教务网页）先挂起，同意后再处理。不同意 → 退出 App。
class HomeShell extends StatefulWidget {
  /// 测试注入用；不传时用全局单例。
  final NativeBridge? bridge;

  /// 自动检查更新用的 checker（测试注入）；不传时用默认源。
  final UpdateChecker? updateChecker;

  /// 用户点「不同意并退出」时调用（测试注入）；默认退出 App。
  final VoidCallback? onPrivacyDeclined;

  const HomeShell({
    super.key,
    this.bridge,
    this.updateChecker,
    this.onPrivacyDeclined,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// 冷启动那次 `getLaunchAction` 只取一次（原生那边也只会给一次）。
  /// 同时也是「加载完成后的启动流程（隐私 → 快捷方式 → 更新检查）只跑一次」的开关。
  bool _launchActionRequested = false;

  /// 隐私说明已同意（本次启动里确认过）。之前到达的快捷方式动作先放进 [_pendingActions]。
  bool _privacyReady = false;
  final List<String> _pendingActions = <String>[];

  late final UpdateChecker _updateChecker =
      widget.updateChecker ?? UpdateChecker();

  StreamSubscription<String>? _actionSub;

  static const List<Widget> _pages = <Widget>[
    WeekViewPage(),
    TodayPage(),
    SettingsPage(),
  ];

  NativeBridge get _bridge => widget.bridge ?? NativeBridge.instance;

  @override
  void initState() {
    super.initState();
    // App 已经在跑时，快捷方式的动作从这条流里来。
    _actionSub = _bridge.actions.listen(_handleAction);
  }

  @override
  void dispose() {
    _actionSub?.cancel();
    super.dispose();
  }

  /// AppState 加载完之后的启动流程，只跑一次：
  /// 1. 隐私说明（没同意过当前版本就弹框；不同意退出）；
  /// 2. 冷启动携带的快捷方式动作 + 同意前挂起的动作；
  /// 3. 自动检查更新（每天最多一次，见 [runAutoUpdateCheck]）。
  Future<void> _startupFlow() async {
    final appState = context.read<AppState>();
    if (appState.settings.privacyAcceptedVersion < PrivacyPolicy.version) {
      final accepted = await showPrivacyConsentDialog(context);
      if (!mounted) return;
      if (!accepted) {
        final declined = widget.onPrivacyDeclined;
        if (declined != null) {
          declined();
        } else {
          try {
            await SystemNavigator.pop();
          } catch (_) {
            // 非 Android 环境没有这个通道，忽略。
          }
        }
        return;
      }
      await appState.acceptPrivacy(PrivacyPolicy.version);
      if (!mounted) return;
    }
    _privacyReady = true;
    await _consumeLaunchAction();
    if (!mounted) return;
    final pending = List<String>.from(_pendingActions);
    _pendingActions.clear();
    pending.forEach(_handleAction);
    if (!mounted) return;
    await runAutoUpdateCheck(context, appState, _updateChecker);
  }

  /// 取冷启动携带的动作。只在 AppState 已经加载完、隐私说明已同意之后调用，
  /// 否则 `import` 会推到一个还在转圈的页面上（或在同意前打开教务网页）。
  Future<void> _consumeLaunchAction() async {
    final action = await _bridge.launchAction();
    if (action == null || !mounted) return;
    _handleAction(action);
  }

  void _handleAction(String action) {
    if (!mounted) return;
    if (!_privacyReady) {
      _pendingActions.add(action);
      return;
    }
    switch (action) {
      case 'today':
        setState(() => _index = 1);
      case 'import':
        Navigator.of(context).pushNamed(importRouteName);
      case 'add_widget':
        requestAddWidget(context);
      default:
        debugPrint('[HomeShell] 未知的快捷方式动作：$action');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (!appState.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_launchActionRequested) {
      _launchActionRequested = true;
      // 等这一帧画完再跳：build 里不能 push 路由，也不能弹 dialog。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startupFlow();
      });
    }
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: '课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '今日',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

/// 路由还没接线时的兜底页（Phase 3 注册 `/import` 后就不会出现）。
class _NotWiredPage extends StatelessWidget {
  final String routeName;

  const _NotWiredPage({required this.routeName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('尚未接入')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '功能「$routeName」还没有接入。\n'
            '导入流程会在集成阶段注册到这个路由上。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
