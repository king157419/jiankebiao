import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_brand.dart';
import 'core/app_state.dart';
import 'core/holiday_presets.dart';
import 'core/holiday_repository.dart';
import 'core/reminders/reminder_service.dart';
import 'core/theme/theme_controller.dart';
import 'core/update/update_checker.dart';
import 'core/update/update_dialog.dart';
import 'features/import/adapters/school_registry.dart';
import 'features/settings/calendar_suggestion_sheet.dart';
import 'features/timetable/week_view_page.dart';
import 'models/timetable.dart';
import 'features/widgets/palette_mapper.dart';
import 'features/widgets/widget_sync.dart';

/// 应用外壳：Provider + MaterialApp + 首页 [HomeShell]（周课表铺满整屏，
/// 右上角齿轮进设置；v1.5.0 起没有底部导航栏）。
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

  /// 上课提醒的系统通道（测试注入 Fake）。为 null 时用真实的
  /// [LocalNotificationsGateway]（flutter_local_notifications）。
  final ReminderGateway? reminderGateway;

  const ShuScheduleApp({
    super.key,
    this.appState,
    this.themeController,
    this.extraRoutes = const <String, WidgetBuilder>{},
    this.reminderGateway,
  });

  @override
  State<ShuScheduleApp> createState() => _ShuScheduleAppState();
}

class _ShuScheduleAppState extends State<ShuScheduleApp>
    with WidgetsBindingObserver {
  late final AppState _appState;
  late final ThemeController _themeController;
  late final bool _ownsState;

  /// 上课提醒（v1.4.0）。AppState 一变就防抖重排；回到前台时刷新权限并按新的
  /// 「现在」重排。`HomeShell._startupFlow` 里 init 之前只算不排。
  late final ReminderService _reminders;

  /// 小组件推送的防抖计时器。一次导入会连续触发 3~4 次 `AppState._commit()`
  /// （createTimetable / replaceCourses / updateConfig），每次都要重算整学期快照
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
    _reminders = ReminderService(
      gateway: widget.reminderGateway ?? LocalNotificationsGateway(),
    );
    _appState.addListener(_onAppStateChanged);
    _themeController.addListener(_scheduleWidgetPush);
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetDebounce?.cancel();
    _appState.removeListener(_onAppStateChanged);
    _themeController.removeListener(_scheduleWidgetPush);
    _reminders.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    _scheduleWidgetPush();
    _reminders.replan(_appState);
  }

  /// 回到前台：用户可能刚在系统设置里改了通知 / 精确闹钟权限，也可能跨了天
  /// （提醒窗口要往前滚、小组件的「今天」要更新）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _scheduleWidgetPush();
    if (!_appState.isLoaded) return;
    unawaited(_refreshReminders());
  }

  Future<void> _refreshReminders() async {
    await _reminders.refreshPermissions();
    await _reminders.replanNow(_appState);
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
        ChangeNotifierProvider<ReminderService>.value(value: _reminders),
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

/// 首页：周课表铺满整屏（v1.5.0 删掉了「今日」页、底部导航栏、首次启动的隐私
/// 同意框和长按图标的快捷方式）。设置页由周视图右上角的齿轮（key `week-settings`）
/// `push` 打开，自带返回键。
///
/// AppState 加载完之后跑一次启动流程（[_startupFlow]）：初始化上课提醒 → 校历建议
/// 面板（有建议且没点过「先不用」时）→ 自动检查更新（顺带刷新假日表）。
///
/// 校历建议面板（PLAN-1.5 D9）的三个触发点都在这里：(a) 导入完成
/// （`AppState.pendingCalendarPromptFor`）；(b) 启动时；(c) 假日表联网更新带来新建议
/// （SnackBar「假期表有更新」→「查看」）。弹面板前先 `popUntil(isFirst)`，面板总是
/// 盖在周视图上。
///
/// 点上课提醒通知（App 在运行，或者冷启动是点通知拉起来的）→ 关掉压在课表上面的
/// 所有页面（设置、导入等），并让周视图回到本周（[_showTimetableNow]）。
/// 修复轮（v1.4.0）：提醒开着却没有通知权限时弹一次「去允许通知」SnackBar；提醒开着时
/// 当前课表换了，弹「上课提醒已切换到「xxx」」。
class HomeShell extends StatefulWidget {
  /// 自动检查更新用的 checker（测试注入）；不传时用默认源。
  final UpdateChecker? updateChecker;

  /// 自动检查更新成功后顺带刷新假日表、校历建议读假日表用的仓库（测试注入）；
  /// 不传时用默认仓库（内置表，或联网更新过的较新缓存）。
  final HolidayRepository? holidayRepository;

  /// 测试用时钟（周视图的「本周」、自动检查更新的「今天」）；不传时用 [DateTime.now]。
  final DateTime Function()? clock;

  const HomeShell({
    super.key,
    this.updateChecker,
    this.holidayRepository,
    this.clock,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// 「加载完成后的启动流程只跑一次」的开关。
  bool _startupScheduled = false;

  late final UpdateChecker _updateChecker =
      widget.updateChecker ?? UpdateChecker();

  StreamSubscription<String>? _reminderSwitchSub;

  /// 每加 1，周视图就回到本周（点通知、导入完成、按校历改了开学日期时用）。
  final ValueNotifier<int> _showCurrentWeek = ValueNotifier<int>(0);

  late final HolidayRepository _holidays =
      widget.holidayRepository ?? HolidayRepository();

  /// 正在监听 `pendingCalendarPromptFor` 的 AppState（触发点 (a)）。
  AppState? _promptSource;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = Provider.of<AppState>(context, listen: false);
    if (!identical(appState, _promptSource)) {
      _promptSource?.pendingCalendarPromptFor.removeListener(
        _onCalendarPromptRequested,
      );
      _promptSource = appState;
      appState.pendingCalendarPromptFor.addListener(_onCalendarPromptRequested);
    }
  }

  @override
  void dispose() {
    _promptSource?.pendingCalendarPromptFor.removeListener(
      _onCalendarPromptRequested,
    );
    _reminderSwitchSub?.cancel();
    _showCurrentWeek.dispose();
    super.dispose();
  }

  DateTime _today() => (widget.clock ?? DateTime.now)();

  /// AppState 加载完之后的启动流程，只跑一次：
  /// 1. 初始化上课提醒（含「点通知冷启动」→ 回到课表本周）；
  /// 2. 校历建议（触发点 (b)）：当前课表有建议、且没对这一版假日表点过「先不用」→ 弹面板；
  /// 3. 自动检查更新（每天最多一次，见 [runAutoUpdateCheck]），成功后顺带刷新假日表；
  ///    假日表真的更新了且带来新建议 → SnackBar「假期表有更新」（触发点 (c)）。
  Future<void> _startupFlow() async {
    final appState = context.read<AppState>();
    await _startReminders(appState);
    if (!mounted) return;
    await _offerCalendarOnStartup(appState);
    if (!mounted) return;
    await runAutoUpdateCheck(
      context,
      appState,
      _updateChecker,
      now: widget.clock?.call(),
      holidays: _holidays,
      onHolidaysUpdated: _onHolidaysUpdated,
    );
  }

  // ------------------------------------------------------------ 校历建议（D9）

  /// 当前用的假日表；读不到时是空表（不抛异常）。
  Future<HolidayPresets> _loadHolidays() async {
    try {
      return await _holidays.load();
    } catch (_) {
      return HolidayPresets.empty;
    }
  }

  /// [timetable] 按校历的建议；没有 `schoolId` 或什么都不差时为 null。
  /// `schools.json` 的学期预设和校名从 [SchoolRegistry] 同步取（`main` 启动时预读）。
  CalendarSuggestion? _suggestionFor(
    Timetable? timetable,
    HolidayPresets presets, {
    bool allowTermFix = true,
    Map<String, String> termStartConfirmed = const <String, String>{},
  }) {
    final schoolId = timetable?.schoolId;
    if (timetable == null || schoolId == null) return null;
    final school = SchoolRegistry.byId(schoolId);
    return buildCalendarSuggestion(
      tt: timetable,
      presets: presets,
      today: _today(),
      schoolPresets: school?.termPresets,
      schoolName: school?.name,
      allowTermFix: allowTermFix,
      termStartConfirmed: termStartConfirmed,
    );
  }

  /// [timetable] 在 [presets] 下对应的学期内容指纹；无法匹配时为 null。
  String? _termKeyFor(Timetable? timetable, HolidayPresets? presets) {
    final schoolId = timetable?.schoolId;
    if (timetable == null || schoolId == null || presets == null) return null;
    final school = SchoolRegistry.byId(schoolId);
    return calendarSuggestionTermKey(
      tt: timetable,
      presets: presets,
      today: _today(),
      schoolPresets: school?.termPresets,
    );
  }

  /// 触发点 (b)：启动时。课表没有 `schoolId` 就不读假日表。
  Future<void> _offerCalendarOnStartup(AppState appState) async {
    if (appState.currentTimetable?.schoolId == null) return;
    final presets = await _loadHolidays();
    if (!mounted) return;
    final suggestion = _suggestionFor(
      appState.currentTimetable,
      presets,
      termStartConfirmed: appState.settings.termStartConfirmed,
    );
    if (suggestion == null ||
        suggestion.isDismissedIn(
          appState.settings.calendarSuggestionDismissed,
        )) {
      return;
    }
    await _showCalendarSuggestion(suggestion);
  }

  /// 触发点 (a)：导入预览页写入成功、退回首页后，在下一帧弹面板（和「已导入 n 门课程」
  /// SnackBar 并存）。
  void _onCalendarPromptRequested() {
    if (_promptSource?.pendingCalendarPromptFor.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_offerCalendarAfterImport());
    });
  }

  /// 刚导入完：导入可能改了开学日期，周视图先回到本周；面板只给放假 / 调休
  /// （教务识别的、用户刚确认过的周次优先，不建议改开学日期），不看「先不用」的标记。
  Future<void> _offerCalendarAfterImport() async {
    final appState = context.read<AppState>();
    final id = appState.pendingCalendarPromptFor.value;
    if (id == null) return;
    appState.pendingCalendarPromptFor.value = null;
    _showCurrentWeek.value++;
    Timetable? imported() {
      for (final t in appState.timetables) {
        if (t.id == id) return t;
      }
      return null;
    }

    if (imported()?.schoolId == null) return;
    final presets = await _loadHolidays();
    if (!mounted) return;
    final suggestion = _suggestionFor(
      imported(),
      presets,
      allowTermFix: false,
      termStartConfirmed: appState.settings.termStartConfirmed,
    );
    if (suggestion == null) return;
    await _showCalendarSuggestion(suggestion);
  }

  /// 触发点 (c)：自动检查更新顺带下载到了新的假日表。
  /// 用旧 presets 和新 presets 各算一次 termKey，不同且建议非空才弹 SnackBar「假期表有更新」。
  void _onHolidaysUpdated(
    HolidayPresets? previousPresets,
    HolidayPresets presets,
  ) {
    if (!mounted) return;
    final appState = context.read<AppState>();
    final tt = appState.currentTimetable;
    final oldKey = _termKeyFor(tt, previousPresets);
    final newKey = _termKeyFor(tt, presets);
    if (oldKey == newKey) return;
    final suggestion = _suggestionFor(
      tt,
      presets,
      termStartConfirmed: appState.settings.termStartConfirmed,
    );
    if (suggestion == null ||
        suggestion.isDismissedIn(
          appState.settings.calendarSuggestionDismissed,
        )) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey<String>('calendar-holidays-updated'),
        content: const Text('假期表有更新'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            if (!mounted) return;
            // 点「查看」时按最新的课表重新算一遍（这期间可能已经手动改过）。
            final state = context.read<AppState>();
            final latest = _suggestionFor(
              state.currentTimetable,
              presets,
              termStartConfirmed: state.settings.termStartConfirmed,
            );
            if (latest != null) unawaited(_showCalendarSuggestion(latest));
          },
        ),
      ),
    );
  }

  /// 关掉压在周视图上面的页面，弹校历建议面板；套用时改了开学日期就回到本周。
  Future<void> _showCalendarSuggestion(CalendarSuggestion suggestion) async {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    final applied = await offerCalendarSuggestion(context, suggestion);
    if (applied && suggestion.termFix != null && mounted) {
      _showCurrentWeek.value++;
    }
  }

  /// 初始化上课提醒并处理「点通知冷启动」。Provider 里没有 [ReminderService]
  /// （只 pump 了 HomeShell 的测试）时什么都不做。
  Future<void> _startReminders(AppState appState) async {
    final reminders = context.read<ReminderService?>();
    if (reminders == null) return;
    reminders.onTap = (_) => _showTimetableNow();
    _reminderSwitchSub ??= reminders.timetableSwitches.listen(
      _onReminderTimetableSwitched,
    );
    await reminders.init();
    final payload = await reminders.gateway.launchPayload();
    if (!mounted) return;
    if (payload != null) _showTimetableNow();
    unawaited(reminders.replanNow(appState));
    if (reminders.needsPermissionFor(appState.settings.reminders)) {
      _showNeedsPermission(reminders);
    }
  }

  /// 点通知：关掉压在周视图上面的页面（设置页、导入页、弹窗等），周视图回到本周
  /// （不管通知是哪一种、payload 是什么）。周视图就是第一个路由。
  void _showTimetableNow() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    _showCurrentWeek.value++;
  }

  /// 提醒开着、通知权限没有（比如从备份恢复到新手机）：启动时提示一次。
  void _showNeedsPermission(ReminderService reminders) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey<String>('reminder-needs-permission'),
        content: const Text('上课提醒已开启，但没有通知权限，提醒发不出来'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '去允许通知',
          onPressed: () => unawaited(_grantNotifications(reminders)),
        ),
      ),
    );
  }

  Future<void> _grantNotifications(ReminderService reminders) async {
    final granted = await reminders.gateway.requestNotificationPermission();
    final p = await reminders.refreshPermissions();
    // 用户以前点过「不允许」，系统不再弹框 → 打开系统里本 App 的通知设置。
    if (!granted && !p.notifications) await reminders.gateway.openSettings();
  }

  void _onReminderTimetableSwitched(String name) {
    if (!mounted) return;
    // 不 hideCurrentSnackBar：导入页自己的「已导入…」提示排在前面，这条接着出。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: const ValueKey<String>('reminder-timetable-switched'),
        content: Text('上课提醒已切换到「$name」'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    if (!appState.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_startupScheduled) {
      _startupScheduled = true;
      // 等这一帧画完再跑：build 里不能弹 SnackBar / dialog。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startupFlow();
      });
    }
    // 长按列头「假期表建议」和自动检查更新用同一个（可注入的）假日表仓库。
    return WeekViewPage(
      holidayRepository: widget.holidayRepository,
      clock: widget.clock,
      showCurrentWeekSignal: _showCurrentWeek,
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
