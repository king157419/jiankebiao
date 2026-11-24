import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/presets.dart';
import '../../core/reminders/reminder_service.dart';
import '../../core/schedule_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';

/// 打开总开关时「闹钟和提醒」关着，弹框里的说明（v1.5.0 去术语）。
const String reminderExactPromptText = '提醒想准点送达，需要在系统里允许「闹钟和提醒」。';

/// 「测试」分组下面的一句说明。
const String reminderTestNote = '「1 分钟后测试」和正式提醒用同一套定时方式，收到它说明通知能正常送达。';

/// 设置 →「上课提醒」（v1.4.0，PLAN-1.4 B4）。
///
/// 总开关、提前分钟、明日预告、测试按钮、接下来
/// [ReminderPlanner.defaultHorizonDays] 天的提醒列表。
/// 提醒完全在本机生成（[ReminderPlanner]），交给系统闹钟定时发出，不联网。
///
/// v1.5.0（D7）：删掉「权限」分组和那段技术说明，只在有问题时在总开关下面
/// 显示一张提示卡（[problemFor]）。文案不出现权限名和系统版本号：
/// 「通知」「闹钟和提醒」是系统设置里的名字，用户能找到。
/// 背景：没有精确闹钟时，Android 12+ 的非精确闹钟在触发时刻之后一小时内投递
/// （developer.android.com/develop/background-work/services/alarms/schedule），
/// 界面上只说「可能不准时 / 可能晚到」。
class ReminderSettingsPage extends StatefulWidget {
  /// 测试注入；不传时用 Provider 里的（`ShuScheduleApp` 提供）。
  final ReminderService? service;

  /// 「现在」（测试注入）；不传时用 [ReminderService.now]。
  final DateTime Function()? clock;

  const ReminderSettingsPage({super.key, this.service, this.clock});

  @override
  State<ReminderSettingsPage> createState() => _ReminderSettingsPageState();
}

/// 提醒页顶部提示卡的种类（v1.5.0，D7）。
enum ReminderProblem {
  /// 系统不让发通知：提醒根本发不出来。
  notifications,

  /// 「闹钟和提醒」被关（只有 Android 12 / 12L 能关）：提醒可能晚到。
  exactAlarms,
}

/// 要不要显示提示卡、显示哪一种（纯函数）。
///
/// 只在提醒开着、权限已经查到时判断（查不到时不误报）；两种问题都有时
/// 只说通知那个——它不解决，另一个也没意义。
ReminderProblem? problemFor({
  required bool enabled,
  required ReminderPermission permission,
}) {
  if (!enabled || !permission.known) return null;
  if (!permission.notifications) return ReminderProblem.notifications;
  if (!permission.exactAlarms) return ReminderProblem.exactAlarms;
  return null;
}

class _ReminderSettingsPageState extends State<ReminderSettingsPage>
    with WidgetsBindingObserver {
  late final ReminderService _service;
  bool _ownsService = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final provided =
        widget.service ?? Provider.of<ReminderService?>(context, listen: false);
    if (provided != null) {
      _service = provided;
    } else {
      // 正常运行时 ShuScheduleApp 一定会提供；这里只是兜底。
      _service = ReminderService(gateway: LocalNotificationsGateway());
      _ownsService = true;
    }
    _service.addListener(_onServiceChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_onServiceChanged);
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  /// 从系统设置页回来时重新查权限（用户可能刚打开了「通知」/「闹钟和提醒」）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  ReminderGateway get _gateway => _service.gateway;

  DateTime _now() => (widget.clock ?? _service.now)();

  Future<void> _refresh() async {
    await _service.init();
    await _service.refreshPermissions();
  }

  /// 保存偏好并立刻重排（不等 App 层 800 ms 的防抖，界面上马上能看到结果）。
  Future<void> _save(AppState appState, ReminderSettings value) async {
    await appState.setReminderSettings(value);
    await _service.replanNow(appState);
  }

  /// 确保有通知权限：没有就申请一次；还是没有 → 提示去系统设置，返回 false。
  Future<bool> _ensureNotificationPermission() async {
    final messenger = ScaffoldMessenger.of(context);
    await _service.init();
    if (_service.permissions.notifications) return true;
    final granted = await _gateway.requestNotificationPermission();
    await _service.refreshPermissions();
    if (granted || _service.permissions.notifications) return true;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey<String>('reminder-denied'),
          content: const Text('没有通知权限，提醒发不出来。请在系统设置里允许本 App 发送通知。'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: _gateway.openSettings,
          ),
        ),
      );
    return false;
  }

  Future<void> _setEnabled(AppState appState, bool value) async {
    final current = appState.settings.reminders;
    if (!value) {
      await _save(appState, current.copyWith(enabled: false));
      return;
    }
    setState(() => _busy = true);
    try {
      // 被拒绝时开关保持关闭（它绑定的是已保存的设置，没保存就会弹回去）。
      if (!await _ensureNotificationPermission()) return;
      await _save(appState, current.copyWith(enabled: true));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // 「闹钟和提醒」只有 Android 12 / 12L 上能被用户关掉（13+ 安装时就有）；
    // 关着时主动问一次（review-G P1-1）。
    final perm = _service.permissions;
    if (mounted && appState.settings.reminders.enabled) {
      if (perm.known && !perm.exactAlarms) await _promptExact(appState);
    }
  }

  Future<void> _promptExact(AppState appState) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey<String>('reminder-exact-prompt'),
        title: const Text('让提醒准点送达'),
        content: const Text(reminderExactPromptText),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('reminder-exact-prompt-later'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('以后再说'),
          ),
          FilledButton(
            key: const ValueKey<String>('reminder-exact-prompt-go'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );
    if (go == true && mounted) await _requestExact(appState);
  }

  Future<void> _pickPreviewTime(AppState appState) async {
    final s = appState.settings.reminders;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.previewHour, minute: s.previewMinute),
      helpText: '明日预告时间',
    );
    if (picked == null) return;
    await _save(
      appState,
      s.copyWith(previewHour: picked.hour, previewMinute: picked.minute),
    );
  }

  Future<void> _requestExact(AppState appState) async {
    await _gateway.requestExactAlarm();
    await _service.refreshPermissions();
    // 精确 / 非精确换了，整批重新交给系统。
    await _service.replanNow(appState, force: true);
  }

  /// 提示卡「去允许通知」：系统还能弹框就先弹；以前点过「不允许」、
  /// 系统不再弹框时，打开系统里本 App 的通知设置。
  Future<void> _fixNotifications() async {
    final granted = await _gateway.requestNotificationPermission();
    final p = await _service.refreshPermissions();
    if (!granted && !p.notifications) await _gateway.openSettings();
  }

  Future<void> _testNow() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _ensureNotificationPermission()) return;
    await _gateway.showTest();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已发送测试提醒，下拉通知栏看看')));
  }

  Future<void> _testLater() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await _ensureNotificationPermission()) return;
    const delay = Duration(minutes: 1);
    final at = _now().add(delay);
    await _gateway.scheduleTestIn(delay);
    final late = _service.permissions.exactAlarms ? '' : '（系统可能让提醒晚到）';
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('已安排：${_hm(at)} 左右会收到一条测试提醒$late，可以先回到桌面')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final s = appState.settings.reminders;
    final perm = _service.permissions;
    final timetableName = appState.currentTimetable?.name;

    return Scaffold(
      appBar: AppBar(title: const Text('上课提醒')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          ListTile(
            key: const ValueKey<String>('reminder-timetable'),
            dense: true,
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(
              timetableName == null
                  ? '还没有课表，提醒会跟随之后的当前课表'
                  : '提醒跟随当前课表：$timetableName',
            ),
            subtitle: const Text('切换课表或重新导入后，提醒会跟着换'),
          ),
          SwitchListTile(
            key: const ValueKey<String>('reminder-enabled'),
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('上课提醒'),
            subtitle: const Text('上课前在通知栏提醒你；提醒完全在本机生成，不联网'),
            value: s.enabled,
            onChanged: _busy ? null : (v) => _setEnabled(appState, v),
          ),
          ..._problemCard(
            theme,
            problemFor(enabled: s.enabled, permission: perm),
            appState,
          ),
          _group(theme, '提前多久提醒'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: <Widget>[
                for (final n in ReminderSettings.leadChoices)
                  ChoiceChip(
                    key: ValueKey<String>('reminder-lead-$n'),
                    label: Text('$n 分钟'),
                    selected: s.leadMinutes == n,
                    onSelected: (_) =>
                        _save(appState, s.copyWith(leadMinutes: n)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          SwitchListTile(
            key: const ValueKey<String>('reminder-preview'),
            secondary: const Icon(Icons.nights_stay_outlined),
            title: const Text('明日预告'),
            subtitle: const Text('前一天晚上告诉你明天几节课，以及停课、调休'),
            value: s.eveningPreview,
            onChanged: (v) => _save(appState, s.copyWith(eveningPreview: v)),
          ),
          ListTile(
            key: const ValueKey<String>('reminder-preview-time'),
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('预告时间'),
            subtitle: Text(s.previewTimeText),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            enabled: s.eveningPreview,
            onTap: () => _pickPreviewTime(appState),
          ),
          const Divider(),
          _group(theme, '测试'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  key: const ValueKey<String>('reminder-test-now'),
                  icon: const Icon(Icons.notifications_outlined, size: 18),
                  label: const Text('发送测试提醒'),
                  onPressed: _testNow,
                ),
                OutlinedButton.icon(
                  key: const ValueKey<String>('reminder-test-later'),
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text('1 分钟后测试'),
                  onPressed: _testLater,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              reminderTestNote,
              style: TextStyle(
                fontSize: 12,
                color: theme.colors.onSurfaceMuted,
              ),
            ),
          ),
          const Divider(),
          _group(theme, '接下来的提醒'),
          ..._upcoming(theme, appState, s),
        ],
      ),
    );
  }

  /// 总开关下面的提示卡；没有问题时什么都不放。
  List<Widget> _problemCard(
    AppTheme theme,
    ReminderProblem? problem,
    AppState appState,
  ) {
    if (problem == null) return const <Widget>[];
    final notifications = problem == ReminderProblem.notifications;
    return <Widget>[
      Card(
        key: const ValueKey<String>('reminder-problem-card'),
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    notifications
                        ? Icons.notifications_off_outlined
                        : Icons.alarm_outlined,
                    size: 20,
                    color: theme.colors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notifications ? '提醒发不出来' : '提醒可能不准时',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                notifications
                    ? '系统没有允许简课表发通知，上课提醒不会出现。'
                    : '系统里的「闹钟和提醒」没有打开，提醒可能晚到。',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colors.onSurfaceMuted,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const ValueKey<String>('reminder-problem-action'),
                  onPressed: notifications
                      ? _fixNotifications
                      : () => _requestExact(appState),
                  child: Text(notifications ? '去允许通知' : '去系统设置允许「闹钟和提醒」'),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _upcoming(
    AppTheme theme,
    AppState appState,
    ReminderSettings s,
  ) {
    final muted = TextStyle(fontSize: 12, color: theme.colors.onSurfaceMuted);
    if (!s.enabled) {
      return <Widget>[
        Padding(
          key: const ValueKey<String>('reminder-upcoming-off'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '开启上课提醒后，这里会列出接下来 '
            '${ReminderPlanner.defaultHorizonDays} 天的提醒。',
            style: muted,
          ),
        ),
      ];
    }
    final now = _now();
    final timetable = appState.currentTimetable;
    final plan = ReminderPlanner.plan(
      timetable: timetable,
      settings: s,
      now: now,
    );
    final cancelled = <String>{
      for (final d in ReminderPlanner.cancelledDays(
        timetable: timetable,
        now: now,
      ))
        ScheduleUtils.dateKey(d),
    };
    final groups = <String, List<PlannedReminder>>{};
    PlannedReminder? horizonEnd;
    for (final r in plan) {
      // 续排提醒单独放在列表最后（它说的是「之后还没排」，不属于哪一天的课）。
      if (r.kind == ReminderKind.horizonEnd) {
        horizonEnd = r;
        continue;
      }
      final key = ScheduleUtils.dateKey(r.fireAt);
      (groups[key] ??= <PlannedReminder>[]).add(r);
    }
    final keys = <String>{...groups.keys, ...cancelled}.toList()..sort();

    final out = <Widget>[];
    if (keys.isEmpty) {
      out.add(
        Padding(
          key: const ValueKey<String>('reminder-upcoming-empty'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            '接下来 ${ReminderPlanner.defaultHorizonDays} 天没有要提醒的课。',
            style: muted,
          ),
        ),
      );
    }
    for (final key in keys) {
      final date = DateTime.parse(key);
      final dateText = '${date.month}月${date.day}日';
      if (cancelled.contains(key)) {
        out.add(
          ListTile(
            key: ValueKey<String>('reminder-cancelled-$key'),
            dense: true,
            leading: const Icon(Icons.event_busy_outlined),
            title: Text('$dateText 停课 · 不提醒'),
          ),
        );
      }
      final items = groups[key];
      if (items == null) continue;
      out.add(
        Padding(
          key: ValueKey<String>('reminder-day-$key'),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
          child: Text(
            '$dateText ${weekdayNamesCn[date.weekday]}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colors.onSurface,
            ),
          ),
        ),
      );
      for (final r in items) {
        out.add(
          ListTile(
            key: ValueKey<String>('reminder-item-${r.id}'),
            dense: true,
            leading: SizedBox(
              width: 48,
              child: Text(
                _hm(r.fireAt),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            title: Text(r.title),
            subtitle: Text(r.body),
            trailing: r.kind == ReminderKind.eveningPreview
                ? const Icon(Icons.nights_stay_outlined, size: 18)
                : null,
          ),
        );
      }
    }
    if (horizonEnd != null) {
      out.add(
        ListTile(
          key: const ValueKey<String>('reminder-horizon-end'),
          dense: true,
          leading: SizedBox(
            width: 48,
            child: Text(
              _hm(horizonEnd.fireAt),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          title: Text(horizonEnd.title),
          subtitle: Text(
            '${horizonEnd.fireAt.month}月${horizonEnd.fireAt.day}日晚上会发这一条通知',
          ),
          trailing: const Icon(Icons.update, size: 18),
        ),
      );
    }
    out.add(
      Padding(
        key: const ValueKey<String>('reminder-pending-count'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text(
          '接下来 ${ReminderPlanner.defaultHorizonDays} 天共 ${plan.length} 条提醒；'
          '每次打开简课表都会往后补上',
          style: muted,
        ),
      ),
    );
    return out;
  }

  Widget _group(AppTheme theme, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: theme.colors.headerText,
      ),
    ),
  );

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
