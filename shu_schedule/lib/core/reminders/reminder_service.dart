import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import 'reminder_gateway.dart';
import 'reminder_planner.dart';

export 'reminder_gateway.dart';
export 'reminder_planner.dart';

/// 把 [ReminderPlanner] 的结果交给 [ReminderGateway]，并记住权限状态。
///
/// - [replan]：800 ms 防抖（一次导入会连续触发好几次 AppState 变化，
///   和小组件推送同一个思路）；
/// - 只有 `settings.reminders.enabled` 才排程，否则撤掉全部提醒；
/// - [init] 之前只算计划、不碰系统；`HomeShell` 的启动流程调用 [init]，
///   它会补一次排程；
/// - 计划和权限都没变时不重复排程（每次 AppState 变化都会触发 replan，
///   改主题也算），回到前台时 [replanNow] 会按新的「现在」重新算；
/// - 提醒跟着「当前课表」走：提醒开着时当前课表换了（切换或导入课表后、
///   删掉当前课表），[timetableSwitches] 发出新课表的名字，`HomeShell`
///   弹 SnackBar（v1.4.0 修复轮，review-G P2-2）；
/// - [needsPermission]：提醒开着但系统不让发通知（典型场景：换新手机后从备份
///   恢复，「开启」跟着备份过来了，通知权限却从没申请过，review-G P2-3）。
class ReminderService extends ChangeNotifier {
  ReminderService({
    required this.gateway,
    this.debounce = const Duration(milliseconds: 800),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReminderGateway gateway;
  final Duration debounce;
  final DateTime Function() _clock;

  /// 点通知时调用（`HomeShell` 设置成关掉压在周视图上面的页面、回到本周）。
  ReminderTapHandler? onTap;

  Future<void>? _initFuture;
  bool _initialized = false;
  ReminderPermission _permissions = ReminderPermission.unknown;
  List<PlannedReminder> _lastPlan = const <PlannedReminder>[];
  bool _active = false;
  String? _lastSignature;
  bool? _lastWasCancel;
  Timer? _timer;
  AppState? _pendingState;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;
  ReminderSettings _lastSettings = const ReminderSettings();

  /// 上一次（init 之后）重排时的当前课表 id；`_seenTimetable` 区分「还没看过」和「没有课表」。
  String? _lastTimetableId;
  bool _seenTimetable = false;
  final StreamController<String> _switches =
      StreamController<String>.broadcast();

  /// 提醒开着时当前课表换了 → 新课表的名字。
  Stream<String> get timetableSwitches => _switches.stream;

  bool get initialized => _initialized;

  /// 最近一次查到的权限状态。
  ReminderPermission get permissions => _permissions;

  /// 最近一次算出的计划（不管有没有交给系统）。
  List<PlannedReminder> get lastPlan => _lastPlan;

  /// 当前是否有提醒交给了系统。
  bool get active => _active;

  /// 提醒开着、但系统不让发通知（权限查过且未授予）。按最近一次重排时的偏好算。
  bool get needsPermission => needsPermissionFor(_lastSettings);

  /// 同上，按给定的偏好算（设置页 tile 用 AppState 里最新的偏好）。
  bool needsPermissionFor(ReminderSettings settings) =>
      settings.enabled && _permissions.known && !_permissions.notifications;

  DateTime now() => _clock();

  /// 初始化插件（可以重复调用，只做一次），然后查一次权限。
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    await gateway.init((payload) => onTap?.call(payload));
    _initialized = true;
    await refreshPermissions();
  }

  /// 从系统现查权限；变了就通知界面。
  Future<ReminderPermission> refreshPermissions() async {
    final p = await gateway.permissions();
    if (p != _permissions) {
      _permissions = p;
      _notify();
    }
    return p;
  }

  /// 防抖地重排（AppState 每次变化都调这个）。
  void replan(AppState state) {
    _pendingState = state;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      final s = _pendingState;
      _pendingState = null;
      if (s != null && !_disposed) unawaited(replanNow(s));
    });
  }

  /// 立刻重排（串行执行，不会和另一次重排交错）。
  /// [force] = 计划没变也重新交给系统。
  Future<void> replanNow(AppState state, {bool force = false}) {
    _timer?.cancel();
    _pendingState = null;
    final next = _queue.then((_) => _replan(state, force));
    _queue = next.catchError((Object e) {
      debugPrint('[reminders] 重排失败：$e');
    });
    return _queue;
  }

  Future<void> _replan(AppState state, bool force) async {
    if (_disposed || !state.isLoaded) return;
    final settings = state.settings.reminders;
    _lastSettings = settings;
    _lastPlan = ReminderPlanner.plan(
      timetable: state.currentTimetable,
      settings: settings,
      now: _clock(),
    );
    if (!_initialized) {
      _notify();
      return;
    }
    _trackTimetable(state, settings.enabled);
    if (settings.enabled) {
      final exact = _permissions.exactAlarms;
      final signature = _signatureOf(_lastPlan, exact);
      if (force || signature != _lastSignature) {
        await gateway.scheduleAll(_lastPlan, exact: exact);
        _lastSignature = signature;
      }
      _active = true;
      _lastWasCancel = false;
    } else {
      if (force || _lastWasCancel != true) {
        await gateway.cancelAll();
      }
      _lastSignature = null;
      _active = false;
      _lastWasCancel = true;
    }
    _notify();
  }

  /// 记下当前课表；提醒开着时它换了 → 发事件（第一次看到不算切换）。
  void _trackTimetable(AppState state, bool remindersOn) {
    final tt = state.currentTimetable;
    final id = tt?.id;
    final switched = _seenTimetable && id != _lastTimetableId;
    _lastTimetableId = id;
    _seenTimetable = true;
    if (switched && remindersOn && tt != null && !_switches.isClosed) {
      _switches.add(tt.name);
    }
  }

  static String _signatureOf(List<PlannedReminder> plan, bool exact) {
    final b = StringBuffer(exact ? 'E' : 'I');
    for (final r in plan) {
      b
        ..write('\n')
        ..write(r.id)
        ..write('@')
        ..write(r.fireAt.millisecondsSinceEpoch)
        ..write('|')
        ..write(r.title)
        ..write('|')
        ..write(r.body);
    }
    return b.toString();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_switches.close());
    super.dispose();
  }
}
