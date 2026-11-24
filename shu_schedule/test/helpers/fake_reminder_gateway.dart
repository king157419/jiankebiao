import 'package:shu_schedule/core/reminders/reminder_service.dart';

/// 一次 [FakeReminderGateway.scheduleAll] 调用。
class FakeScheduleCall {
  final List<PlannedReminder> reminders;
  final bool exact;

  const FakeScheduleCall(this.reminders, {required this.exact});
}

/// 不碰插件的提醒通道（v1.4.0 测试用）。记录每一次调用，权限状态可以直接改。
///
/// - [grantOnRequest]：`requestNotificationPermission` 时是否「用户点了允许」；
/// - [exactOnRequest]：`requestExactAlarm` 时是否「用户打开了精确闹钟」；
/// - [launch]：冷启动 payload（null = 不是点通知启动的）。
class FakeReminderGateway implements ReminderGateway {
  FakeReminderGateway({
    this.notificationsAllowed = true,
    this.exactAllowed = false,
    this.exactBySystem = false,
    this.grantOnRequest = true,
    this.exactOnRequest = true,
    this.launch,
  });

  bool notificationsAllowed;
  bool exactAllowed;

  /// Android 13+ 的 USE_EXACT_ALARM（安装即授予）。
  bool exactBySystem;
  bool grantOnRequest;
  bool exactOnRequest;
  String? launch;

  int initCalls = 0;
  ReminderTapHandler? tapHandler;
  int permissionRequests = 0;
  int exactRequests = 0;
  int openSettingsCalls = 0;
  int cancelAllCalls = 0;
  int showTestCalls = 0;
  final List<Duration> testDelays = <Duration>[];
  final List<FakeScheduleCall> scheduleCalls = <FakeScheduleCall>[];

  /// 「系统里」现在排着的提醒（scheduleAll 先清空再放进去，和真实实现一致）。
  final Map<int, PlannedReminder> scheduled = <int, PlannedReminder>{};
  bool testPending = false;

  /// 模拟用户点了一条通知。
  void tap(String? payload) => tapHandler?.call(payload);

  @override
  Future<void> init(ReminderTapHandler onTap) async {
    initCalls++;
    tapHandler = onTap;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    permissionRequests++;
    if (grantOnRequest) notificationsAllowed = true;
    return notificationsAllowed;
  }

  @override
  Future<ReminderPermission> permissions() async => ReminderPermission(
    notifications: notificationsAllowed,
    exactAlarms: exactAllowed,
    exactBySystem: exactAllowed && exactBySystem,
  );

  @override
  Future<bool> requestExactAlarm() async {
    exactRequests++;
    if (exactOnRequest) exactAllowed = true;
    return exactAllowed;
  }

  @override
  Future<void> openSettings() async => openSettingsCalls++;

  @override
  Future<void> scheduleAll(
    List<PlannedReminder> reminders, {
    required bool exact,
  }) async {
    scheduleCalls.add(
      FakeScheduleCall(List<PlannedReminder>.of(reminders), exact: exact),
    );
    scheduled
      ..clear()
      ..addEntries(
        reminders.map((r) => MapEntry<int, PlannedReminder>(r.id, r)),
      );
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
    testPending = false;
  }

  @override
  Future<void> showTest() async => showTestCalls++;

  @override
  Future<void> scheduleTestIn(Duration delay) async {
    testDelays.add(delay);
    testPending = true;
  }

  @override
  Future<List<PendingReminder>> pending() async => <PendingReminder>[
    for (final r in scheduled.values)
      PendingReminder(
        id: r.id,
        title: r.title,
        body: r.body,
        payload: r.payload,
      ),
    if (testPending) const PendingReminder(id: 9002, payload: 'test'),
  ];

  @override
  Future<String?> launchPayload() async => launch;
}
