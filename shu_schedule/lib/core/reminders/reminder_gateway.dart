import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../native_bridge.dart';
import 'reminder_planner.dart';

/// 点通知时的回调，参数是通知的 payload。
typedef ReminderTapHandler = void Function(String? payload);

/// 通知相关的权限状态（每次从系统现查，不存盘）。
@immutable
class ReminderPermission {
  /// 系统允许本 App 发通知（Android 13+ 的 POST_NOTIFICATIONS，以及用户没在系统里关掉）。
  final bool notifications;

  /// 能排精确闹钟（Android 13+ 由 USE_EXACT_ALARM 在安装时授予；Android 12 / 12L
  /// 是可以被用户收回的 SCHEDULE_EXACT_ALARM；更老的系统恒为 true）。
  final bool exactAlarms;

  /// 精确闹钟是系统在安装时授予的（Android 13+ 的 USE_EXACT_ALARM，用户不能收回）。
  /// 只用于诊断和测试；v1.5.0 起提醒页不再展示权限细节，只看 [exactAlarms]。
  final bool exactBySystem;

  /// false = 还没查过 / 这个平台查不了（界面显示「检查中」而不是「未允许」）。
  final bool known;

  const ReminderPermission({
    required this.notifications,
    required this.exactAlarms,
    this.exactBySystem = false,
    this.known = true,
  });

  static const ReminderPermission unknown = ReminderPermission(
    notifications: false,
    exactAlarms: false,
    known: false,
  );

  @override
  bool operator ==(Object other) =>
      other is ReminderPermission &&
      other.notifications == notifications &&
      other.exactAlarms == exactAlarms &&
      other.exactBySystem == exactBySystem &&
      other.known == known;

  @override
  int get hashCode =>
      Object.hash(notifications, exactAlarms, exactBySystem, known);

  @override
  String toString() =>
      'ReminderPermission(notifications: $notifications, '
      'exact: $exactAlarms, bySystem: $exactBySystem, known: $known)';
}

/// 系统里已经排好、还没触发的一条通知。
@immutable
class PendingReminder {
  final int id;
  final String? title;
  final String? body;
  final String? payload;

  const PendingReminder({
    required this.id,
    this.title,
    this.body,
    this.payload,
  });
}

/// 「把提醒交给系统」这件事的抽象。真实实现是 [LocalNotificationsGateway]；
/// 测试用 `test/helpers/fake_reminder_gateway.dart`（插件在 `flutter test` 里
/// 没有原生端，`zonedSchedule` 还会对 Android 实现强制解包，必须隔开）。
///
/// 约定：实现不向调用方抛异常（插件 / 系统出错时记日志并返回保守值），
/// 界面代码可以直接 await。
abstract class ReminderGateway {
  /// 初始化插件、建好两个通知渠道，登记点通知的回调。可以重复调用。
  Future<void> init(ReminderTapHandler onTap);

  /// 申请通知权限（Android 13+ 弹系统框；更老的系统直接返回当前状态）。
  Future<bool> requestNotificationPermission();

  Future<ReminderPermission> permissions();

  /// 打开系统「闹钟和提醒」授权页；返回之后是否已允许。
  Future<bool> requestExactAlarm();

  /// 打开系统里本 App 的通知设置页。
  Future<void> openSettings();

  /// 先 `cancelAllPendingNotifications()`，再把 [reminders] 整批交给系统。
  /// [exact] = 用精确闹钟（USE_EXACT_ALARM / SCHEDULE_EXACT_ALARM），否则用非精确闹钟
  /// （Android 12+ 上系统可能推迟最多约 1 小时）。
  Future<void> scheduleAll(
    List<PlannedReminder> reminders, {
    required bool exact,
  });

  /// 撤掉所有还没触发的提醒。
  Future<void> cancelAll();

  /// 立即发一条测试通知。
  Future<void> showTest();

  /// [delay] 之后发一条测试通知，走和正式提醒同一条 `zonedSchedule` 链路。
  Future<void> scheduleTestIn(Duration delay);

  /// 系统里还没触发的通知（含测试通知）。
  Future<List<PendingReminder>> pending();

  /// 冷启动是不是点通知拉起来的：是 → 通知的 payload（没有 payload 时为 ''）；
  /// 否 → null。
  Future<String?> launchPayload();
}

/// 基于 flutter_local_notifications 22.3.1 的实现（只做 Android）。
///
/// 时间：所有提醒都是一次性的绝对时刻，用 `tz.TZDateTime.from(本地时间, tz.UTC)`
/// 表示同一个瞬间即可，不需要 IANA 时区库和设备时区名（PLAN-1.4 B1）。
class LocalNotificationsGateway implements ReminderGateway {
  LocalNotificationsGateway({
    FlutterLocalNotificationsPlugin? plugin,
    Future<int?> Function()? sdkInt,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _sdkIntLoader = sdkInt ?? _deviceSdkInt;

  final FlutterLocalNotificationsPlugin _plugin;

  /// 读 Android API level（判断精确闹钟是不是 USE_EXACT_ALARM 授予的）。
  final Future<int?> Function() _sdkIntLoader;
  Future<int?>? _sdkInt;

  static Future<int?> _deviceSdkInt() async {
    final v = (await NativeBridge.instance.deviceInfo())['sdkInt'];
    return v is num ? v.toInt() : null;
  }

  /// USE_EXACT_ALARM 从 API 33（Android 13）起生效（清单里 SCHEDULE_EXACT_ALARM
  /// 写了 maxSdkVersion=32）。
  static const int useExactAlarmSdk = 33;

  /// 状态栏小图标（res/drawable/ic_stat_notify.xml，res/raw/keep.xml 保住它）。
  static const String smallIcon = 'ic_stat_notify';

  /// 测试通知的固定 id（正式提醒的 FNV id 撞上它的概率可以忽略）。
  static const int testNowId = 9001;
  static const int testScheduledId = 9002;

  /// 「1 分钟后测试」还没触发时的时刻。整批重排会先 cancelAllPending，
  /// 这里记住它，重排完再补回去，免得测试通知被一次无关的重排吃掉。
  DateTime? _pendingTestAt;
  Duration _pendingTestDelay = Duration.zero;

  /// Android 实现；不是 Android，或者插件的 Dart 端没注册（`flutter test` 里
  /// `FlutterLocalNotificationsPlatform.instance` 是没初始化的 late 字段，
  /// 一读就抛 LateInitializationError）→ null，所有方法退化成空操作。
  AndroidFlutterLocalNotificationsPlugin? get _android {
    try {
      return _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
    } catch (_) {
      return null;
    }
  }

  static const AndroidNotificationChannel _classChannel =
      AndroidNotificationChannel(
        ReminderChannels.classReminder,
        ReminderChannels.classReminderName,
        description: ReminderChannels.classReminderDescription,
        importance: Importance.high,
      );

  static const AndroidNotificationChannel _previewChannel =
      AndroidNotificationChannel(
        ReminderChannels.eveningPreview,
        ReminderChannels.eveningPreviewName,
        description: ReminderChannels.eveningPreviewDescription,
        importance: Importance.defaultImportance,
      );

  static NotificationDetails _details(String channel) {
    final isClass = channel != ReminderChannels.eveningPreview;
    final c = isClass ? _classChannel : _previewChannel;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        c.id,
        c.name,
        channelDescription: c.description,
        importance: c.importance,
        priority: isClass ? Priority.high : Priority.defaultPriority,
        icon: smallIcon,
        category: AndroidNotificationCategory.reminder,
        visibility: NotificationVisibility.private,
      ),
    );
  }

  @override
  Future<void> init(ReminderTapHandler onTap) async {
    final android = _android;
    if (android == null) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(smallIcon),
        ),
        onDidReceiveNotificationResponse: (response) => onTap(response.payload),
      );
      await android.createNotificationChannel(_classChannel);
      await android.createNotificationChannel(_previewChannel);
    } catch (e) {
      debugPrint('[reminders] 初始化通知插件失败：$e');
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    final android = _android;
    if (android == null) return false;
    try {
      return await android.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('[reminders] 申请通知权限失败：$e');
      return false;
    }
  }

  @override
  Future<ReminderPermission> permissions() async {
    final android = _android;
    if (android == null) return ReminderPermission.unknown;
    try {
      final notifications = await android.areNotificationsEnabled() ?? false;
      final exact = await android.canScheduleExactNotifications() ?? false;
      final sdk = await (_sdkInt ??= _sdkIntLoader());
      return ReminderPermission(
        notifications: notifications,
        exactAlarms: exact,
        exactBySystem: exact && sdk != null && sdk >= useExactAlarmSdk,
      );
    } catch (e) {
      debugPrint('[reminders] 查询通知权限失败：$e');
      return ReminderPermission.unknown;
    }
  }

  @override
  Future<bool> requestExactAlarm() async {
    final android = _android;
    if (android == null) return false;
    try {
      return await android.requestExactAlarmsPermission() ?? false;
    } catch (e) {
      debugPrint('[reminders] 申请精确闹钟权限失败：$e');
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    final android = _android;
    if (android == null) return;
    try {
      await android.openAppNotificationSettings();
    } catch (e) {
      debugPrint('[reminders] 打开通知设置失败：$e');
    }
  }

  @override
  Future<void> scheduleAll(
    List<PlannedReminder> reminders, {
    required bool exact,
  }) async {
    if (_android == null) return;
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (e) {
      debugPrint('[reminders] 撤销旧提醒失败：$e');
    }
    var useExact = exact;
    var ok = 0;
    for (final r in reminders) {
      // 插件要求时刻在未来（validateDateIsInTheFuture）；规划到现在可能过了几秒。
      if (!r.fireAt.isAfter(DateTime.now())) continue;
      try {
        await _zoned(
          r.id,
          r.fireAt,
          r.title,
          r.body,
          r.channel,
          r.payload,
          useExact,
        );
        ok++;
      } catch (e) {
        if (useExact) {
          // 精确闹钟权限刚被收回（插件抛 exact_alarms_not_permitted）：
          // 这条和后面的都退回非精确闹钟。
          debugPrint('[reminders] 精确闹钟不可用，改用非精确：$e');
          useExact = false;
          try {
            await _zoned(
              r.id,
              r.fireAt,
              r.title,
              r.body,
              r.channel,
              r.payload,
              false,
            );
            ok++;
          } catch (e2) {
            debugPrint('[reminders] 安排提醒 ${r.id} 失败：$e2');
          }
        } else {
          debugPrint('[reminders] 安排提醒 ${r.id} 失败：$e');
        }
      }
    }
    await _restorePendingTest(useExact);
    debugPrint('[reminders] 已安排 $ok/${reminders.length} 条（exact=$useExact）');
  }

  Future<void> _zoned(
    int id,
    DateTime fireAt,
    String title,
    String body,
    String channel,
    String payload,
    bool exact,
  ) => _plugin.zonedSchedule(
    id: id,
    scheduledDate: tz.TZDateTime.from(fireAt, tz.UTC),
    notificationDetails: _details(channel),
    androidScheduleMode: exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle,
    title: title,
    body: body,
    payload: payload,
  );

  Future<void> _restorePendingTest(bool exact) async {
    final at = _pendingTestAt;
    if (at == null) return;
    if (!at.isAfter(DateTime.now())) {
      _pendingTestAt = null;
      return;
    }
    try {
      await _scheduleTest(at, _pendingTestDelay, exact);
    } catch (e) {
      debugPrint('[reminders] 补回测试提醒失败：$e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (_android == null) return;
    _pendingTestAt = null;
    try {
      await _plugin.cancelAllPendingNotifications();
    } catch (e) {
      debugPrint('[reminders] 撤销提醒失败：$e');
    }
  }

  @override
  Future<void> showTest() async {
    if (_android == null) return;
    try {
      await _plugin.show(
        id: testNowId,
        title: '测试提醒',
        body: '上课提醒会像这样出现在通知栏。',
        notificationDetails: _details(ReminderChannels.classReminder),
        payload: 'test',
      );
    } catch (e) {
      debugPrint('[reminders] 发送测试提醒失败：$e');
    }
  }

  @override
  Future<void> scheduleTestIn(Duration delay) async {
    final android = _android;
    if (android == null) return;
    final at = DateTime.now().add(delay);
    // 先记下来再 await：如果一次整批重排的 cancelAllPending 恰好落在下面排程的
    // 前后，重排结束时的 _restorePendingTest 能把它补回来（review-G P3-14）。
    _pendingTestAt = at;
    _pendingTestDelay = delay;
    try {
      final exact = await android.canScheduleExactNotifications() ?? false;
      await _scheduleTest(at, delay, exact);
    } catch (e) {
      if (_pendingTestAt == at) _pendingTestAt = null;
      debugPrint('[reminders] 安排测试提醒失败：$e');
    }
  }

  Future<void> _scheduleTest(DateTime at, Duration delay, bool exact) {
    final minutes = delay.inMinutes;
    final ago = minutes >= 1 ? '$minutes 分钟' : '${delay.inSeconds} 秒';
    return _zoned(
      testScheduledId,
      at,
      '测试提醒（定时）',
      '$ago前安排的提醒按时到了，定时提醒工作正常。',
      ReminderChannels.classReminder,
      'test',
      exact,
    );
  }

  @override
  Future<List<PendingReminder>> pending() async {
    if (_android == null) return const <PendingReminder>[];
    try {
      final list = await _plugin.pendingNotificationRequests();
      return <PendingReminder>[
        for (final p in list)
          PendingReminder(
            id: p.id,
            title: p.title,
            body: p.body,
            payload: p.payload,
          ),
      ];
    } catch (e) {
      debugPrint('[reminders] 读取已安排的提醒失败：$e');
      return const <PendingReminder>[];
    }
  }

  @override
  Future<String?> launchPayload() async {
    if (_android == null) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return details.notificationResponse?.payload ?? '';
    } catch (e) {
      debugPrint('[reminders] 读取启动通知失败：$e');
      return null;
    }
  }
}
