import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/reminders/reminder_service.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/models/app_settings.dart';

import 'helpers/fake_reminder_gateway.dart';
import 'helpers/harness.dart';
import 'helpers/reminder_fixtures.dart';

/// v1.4.0 B3：ReminderService（防抖、开关门槛、去重）与 AppSettings.reminders。
///
/// v1.5.0：删掉了「同意当前版本隐私说明才排程」这道门槛（首启同意框没了）。
void main() {
  final storage = TempStorage();
  setUp(() => storage.setUp('reminder_service'));
  tearDown(storage.tearDown);

  final now = DateTime(2026, 10, 7, 7);

  Future<AppState> seeded({bool enabled = true}) async {
    final state = AppState();
    await state.load();
    await state.addTimetable(buildTimetable(overrides: octoberOverrides()));
    await state.setReminderSettings(ReminderSettings(enabled: enabled));
    return state;
  }

  ReminderService serviceFor(
    FakeReminderGateway gateway, {
    Duration debounce = const Duration(milliseconds: 30),
  }) => ReminderService(gateway: gateway, debounce: debounce, clock: () => now);

  group('ReminderService', () {
    test('init 之前只算计划，不碰系统；init 之后才排程', () async {
      final state = await seeded();
      final gateway = FakeReminderGateway();
      final service = serviceFor(gateway);
      addTearDown(service.dispose);

      await service.replanNow(state);
      expect(service.lastPlan, isNotEmpty);
      expect(gateway.scheduleCalls, isEmpty);
      expect(gateway.cancelAllCalls, 0);

      await service.init();
      await service.init(); // 重复调用只初始化一次
      expect(gateway.initCalls, 1);
      expect(service.permissions.notifications, isTrue);
      expect(service.permissions.exactAlarms, isFalse);

      await service.replanNow(state);
      expect(gateway.scheduleCalls, hasLength(1));
      final call = gateway.scheduleCalls.single;
      expect(call.exact, isFalse, reason: '没有精确闹钟权限 → 非精确');
      expect(
        call.reminders.map((r) => r.id),
        service.lastPlan.map((r) => r.id),
      );
      expect(service.active, isTrue);
    });

    test('计划没变不重复排程；权限变成精确后整批重排', () async {
      final state = await seeded();
      final gateway = FakeReminderGateway();
      final service = serviceFor(gateway);
      addTearDown(service.dispose);
      await service.init();

      await service.replanNow(state);
      await service.replanNow(state);
      expect(gateway.scheduleCalls, hasLength(1));

      gateway.exactAllowed = true;
      await service.refreshPermissions();
      await service.replanNow(state);
      expect(gateway.scheduleCalls, hasLength(2));
      expect(gateway.scheduleCalls.last.exact, isTrue);

      await service.replanNow(state, force: true);
      expect(gateway.scheduleCalls, hasLength(3));
    });

    test('改提前分钟数 → 重排；关掉 → 撤销一次（重复关闭不再撤）', () async {
      final state = await seeded();
      final gateway = FakeReminderGateway();
      final service = serviceFor(gateway);
      addTearDown(service.dispose);
      await service.init();
      await service.replanNow(state);

      await state.setReminderSettings(
        state.settings.reminders.copyWith(leadMinutes: 5),
      );
      await service.replanNow(state);
      expect(gateway.scheduleCalls, hasLength(2));
      expect(
        gateway.scheduleCalls.last.reminders.first.fireAt,
        DateTime(2026, 10, 7, 9, 55),
      );

      await state.setReminderSettings(
        state.settings.reminders.copyWith(enabled: false),
      );
      await service.replanNow(state);
      await service.replanNow(state);
      expect(gateway.cancelAllCalls, 1);
      expect(gateway.scheduled, isEmpty);
      expect(service.active, isFalse);
    });

    test('replan 防抖：连续多次只排一次', () async {
      final state = await seeded();
      final gateway = FakeReminderGateway();
      final service = serviceFor(gateway);
      addTearDown(service.dispose);
      await service.init();

      service.replan(state);
      service.replan(state);
      service.replan(state);
      expect(gateway.scheduleCalls, isEmpty, reason: '防抖窗口内还没排');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(gateway.scheduleCalls, hasLength(1));
    });

    test('默认防抖 800 ms', () {
      final service = ReminderService(gateway: FakeReminderGateway());
      addTearDown(service.dispose);
      expect(service.debounce, const Duration(milliseconds: 800));
    });

    test('提醒开着时当前课表换了 → timetableSwitches 发新课表名（P2-2）', () async {
      final state = await seeded();
      final gateway = FakeReminderGateway();
      final service = serviceFor(gateway);
      addTearDown(service.dispose);
      final names = <String>[];
      final sub = service.timetableSwitches.listen(names.add);
      addTearDown(sub.cancel);
      await service.init();

      await service.replanNow(state);
      await Future<void>.delayed(Duration.zero);
      expect(names, isEmpty, reason: '第一次只记下当前课表，不算切换');

      final other = await state.createTimetable(name: '同学的课表');
      await service.replanNow(state);
      await Future<void>.delayed(Duration.zero);
      expect(names, <String>['同学的课表']);

      await state.renameTimetable(other.id, '改个名');
      await service.replanNow(state);
      await Future<void>.delayed(Duration.zero);
      expect(names, hasLength(1), reason: '改名不算切换');

      // 提醒关着时切换不提示；再打开也不补发。
      await state.setReminderSettings(
        state.settings.reminders.copyWith(enabled: false),
      );
      await service.replanNow(state);
      await state.switchTimetable('t');
      await service.replanNow(state);
      await state.setReminderSettings(
        state.settings.reminders.copyWith(enabled: true),
      );
      await service.replanNow(state);
      await Future<void>.delayed(Duration.zero);
      expect(names, hasLength(1));
    });

    test('needsPermission：开着但通知权限没给（从备份恢复到新手机，P2-3）', () async {
      final state = await seeded();
      final gateway = FakeReminderGateway(notificationsAllowed: false);
      final service = serviceFor(gateway);
      addTearDown(service.dispose);
      expect(
        service.needsPermissionFor(state.settings.reminders),
        isFalse,
        reason: '还没查过权限（unknown）不下结论',
      );
      await service.init();
      await service.replanNow(state);
      expect(service.needsPermission, isTrue);
      expect(service.needsPermissionFor(state.settings.reminders), isTrue);
      expect(
        service.needsPermissionFor(const ReminderSettings()),
        isFalse,
        reason: '关着就不需要',
      );

      gateway.notificationsAllowed = true;
      await service.refreshPermissions();
      expect(service.needsPermission, isFalse);
    });

    test('点通知 → onTap 收到 payload', () async {
      final gateway = FakeReminderGateway();
      final service = serviceFor(gateway);
      addTearDown(service.dispose);
      final taps = <String?>[];
      service.onTap = taps.add;
      await service.init();
      gateway.tap('class|2026-10-07');
      expect(taps, <String?>['class|2026-10-07']);
    });
  });

  group('AppSettings.reminders', () {
    test('旧 settings.json（没有 reminders）→ 出厂默认（关闭）', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'currentTimetableId': 'a',
        'settingsVersion': 2,
      });
      expect(s.reminders, const ReminderSettings());
      expect(s.reminders.enabled, isFalse);
    });

    test('JSON 往返；copyWith 保留 / 替换', () {
      final s = AppSettings(
        reminders: const ReminderSettings(enabled: true, leadMinutes: 20),
      );
      final back = AppSettings.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(
        back.reminders,
        const ReminderSettings(enabled: true, leadMinutes: 20),
      );
      expect(s.copyWith(themeId: 'mint').reminders, s.reminders);
      expect(
        s.copyWith(reminders: const ReminderSettings()).reminders.enabled,
        isFalse,
      );
    });

    test('设置会落盘，重新 load 还在', () async {
      final state = await seeded();
      final again = AppState();
      await again.load();
      expect(again.settings.reminders.enabled, isTrue);
      expect(state.settings.reminders, again.settings.reminders);
    });

    test('恢复备份：提醒偏好跟着备份走（旧备份没有 → 关闭）', () async {
      final state = await seeded();
      expect(state.settings.reminders.enabled, isTrue);
      final old = Storage.importJson(
        File('test/fixtures/v1_2_0/backup_v1.json').readAsStringSync(),
      );
      await state.restoreFrom(old);
      expect(state.settings.reminders.enabled, isFalse);

      final withReminders = Storage.importJson(
        Storage.exportJson(
          state.timetables,
          state.settings.copyWith(
            reminders: const ReminderSettings(enabled: true, leadMinutes: 10),
          ),
        ),
      );
      await state.restoreFrom(withReminders);
      expect(
        state.settings.reminders,
        const ReminderSettings(enabled: true, leadMinutes: 10),
      );
    });
  });
}
