import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/reminders/reminder_service.dart';
import 'package:timezone/timezone.dart' as tz;

/// 一次 zonedSchedule 调用。
class _Call {
  final int id;
  final AndroidScheduleMode mode;
  const _Call(this.id, this.mode);
}

/// 假的插件 Android 实现：不走 MethodChannel，只记录调用（review-G 测试缺口 2）。
///
/// 换到 `FlutterLocalNotificationsPlatform.instance` 上之后，
/// `FlutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation` 会返回它
/// （flutter test 里 defaultTargetPlatform 是 android），网关的真实代码路径都能跑到。
class _FakeAndroidPlugin extends AndroidFlutterLocalNotificationsPlugin {
  bool canExact = true;

  /// 精确闹钟被收回：exactAllowWhileIdle 抛插件的 exact_alarms_not_permitted。
  bool rejectExact = false;

  final List<_Call> calls = <_Call>[];

  /// 「系统里」排着的通知（id → 模式）。
  final Map<int, AndroidScheduleMode> pending = <int, AndroidScheduleMode>{};
  int cancelPendingCalls = 0;

  /// 不为 null 时，id 等于 [blockId] 的那次排程**先登记、再卡住**，直到它完成。
  int? blockId;
  Completer<void>? gate;

  @override
  Future<bool?> canScheduleExactNotifications() async => canExact;

  @override
  Future<bool?> areNotificationsEnabled() async => true;

  @override
  Future<void> cancelAllPendingNotifications() async {
    cancelPendingCalls++;
    pending.clear();
  }

  @override
  Future<List<PendingNotificationRequest>>
  pendingNotificationRequests() async => <PendingNotificationRequest>[
    for (final id in pending.keys)
      PendingNotificationRequest(id, null, null, null),
  ];

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
    AndroidNotificationDetails? notificationDetails,
    AndroidScheduleMode scheduleMode = AndroidScheduleMode.exact,
  }) async {
    calls.add(_Call(id, scheduleMode));
    if (rejectExact &&
        scheduleMode == AndroidScheduleMode.exactAllowWhileIdle) {
      throw PlatformException(code: 'exact_alarms_not_permitted');
    }
    pending[id] = scheduleMode;
    final g = gate;
    if (id == blockId && g != null) {
      blockId = null;
      await g.future;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAndroidPlugin fake;
  setUp(() {
    fake = _FakeAndroidPlugin();
    FlutterLocalNotificationsPlatform.instance = fake;
  });

  List<PlannedReminder> plan(int n) {
    final base = DateTime.now().add(const Duration(hours: 2));
    return <PlannedReminder>[
      for (var i = 0; i < n; i++)
        PlannedReminder(
          id: 100 + i,
          fireAt: base.add(Duration(minutes: i)),
          title: 't$i',
          body: 'b$i',
          channel: ReminderChannels.classReminder,
          payload: 'class|x',
          kind: ReminderKind.classStart,
          date: DateTime(base.year, base.month, base.day),
        ),
    ];
  }

  LocalNotificationsGateway gateway({int? sdk = 35}) =>
      LocalNotificationsGateway(sdkInt: () async => sdk);

  test('有精确闹钟：整批用 exactAllowWhileIdle，先撤旧的', () async {
    await gateway().scheduleAll(plan(3), exact: true);
    expect(fake.cancelPendingCalls, 1);
    expect(fake.pending.length, 3);
    expect(fake.pending.values.toSet(), <AndroidScheduleMode>{
      AndroidScheduleMode.exactAllowWhileIdle,
    });
  });

  test('精确闹钟刚被收回：这一条和后面的都退回 inexactAllowWhileIdle', () async {
    fake.rejectExact = true;
    await gateway().scheduleAll(plan(3), exact: true);
    expect(fake.pending.length, 3, reason: '一条都没丢');
    expect(fake.pending.values.toSet(), <AndroidScheduleMode>{
      AndroidScheduleMode.inexactAllowWhileIdle,
    });
    // 只有第一条试过精确，之后直接走非精确。
    expect(
      fake.calls
          .where((c) => c.mode == AndroidScheduleMode.exactAllowWhileIdle)
          .length,
      1,
    );
  });

  test('没有精确闹钟：直接用非精确', () async {
    await gateway().scheduleAll(plan(2), exact: false);
    expect(fake.calls.map((c) => c.mode).toSet(), <AndroidScheduleMode>{
      AndroidScheduleMode.inexactAllowWhileIdle,
    });
  });

  test('「1 分钟后测试」不会被之后的整批重排吃掉；cancelAll 后不再补回', () async {
    final g = gateway();
    await g.scheduleTestIn(const Duration(minutes: 1));
    expect(
      fake.pending.keys,
      contains(LocalNotificationsGateway.testScheduledId),
    );

    await g.scheduleAll(plan(2), exact: true);
    expect(
      fake.pending.keys,
      containsAll(<int>[100, 101, LocalNotificationsGateway.testScheduledId]),
      reason: '_restorePendingTest 补回测试通知',
    );

    await g.cancelAll();
    expect(fake.pending, isEmpty);
    await g.scheduleAll(plan(1), exact: true);
    expect(fake.pending.keys, <int>[100], reason: 'cancelAll 清掉了待补的测试');
  });

  test('scheduleTestIn 先记下时刻再 await：中途插进来的整批重排也能补回（P3-14）', () async {
    final g = gateway();
    fake
      ..blockId = LocalNotificationsGateway.testScheduledId
      ..gate = Completer<void>();
    // 测试通知已经交给系统，但 scheduleTestIn 还卡在 await 上……
    final testing = g.scheduleTestIn(const Duration(minutes: 1));
    await Future<void>.delayed(Duration.zero);
    expect(
      fake.pending.keys,
      contains(LocalNotificationsGateway.testScheduledId),
    );
    // ……这时来了一次整批重排：先 cancelAllPending（测试通知没了），排完再补。
    await g.scheduleAll(plan(1), exact: true);
    fake.gate!.complete();
    await testing;
    expect(
      fake.pending.keys,
      containsAll(<int>[100, LocalNotificationsGateway.testScheduledId]),
    );
  });

  test('权限：Android 13+ 精确闹钟算「系统授予」，Android 12 不算', () async {
    final p35 = await gateway(sdk: 35).permissions();
    expect(p35.notifications, isTrue);
    expect(p35.exactAlarms, isTrue);
    expect(p35.exactBySystem, isTrue);

    final p32 = await gateway(sdk: 32).permissions();
    expect(p32.exactAlarms, isTrue);
    expect(p32.exactBySystem, isFalse);

    fake.canExact = false;
    final revoked = await gateway(sdk: 32).permissions();
    expect(revoked.exactAlarms, isFalse);
    expect(revoked.exactBySystem, isFalse);

    final unknownSdk = await gateway(sdk: null).permissions();
    expect(unknownSdk.exactBySystem, isFalse);
  });
}
