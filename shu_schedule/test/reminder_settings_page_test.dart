import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/reminders/reminder_service.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/features/settings/reminder_settings_page.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';

import 'helpers/fake_reminder_gateway.dart';
import 'helpers/harness.dart';
import 'helpers/reminder_fixtures.dart';

/// v1.4.0 B4：设置 →「上课提醒」。
///
/// v1.5.0（D7）：「权限」分组换成总开关下面的条件提示卡（`reminder-problem-card`），
/// 页面上不再出现「精确闹钟」「Android 13」「USE_EXACT_ALARM」这类词。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = TempStorage();
  setUp(() => storage.setUp('reminder_page'));
  tearDown(storage.tearDown);

  final now = DateTime(2026, 10, 7, 7);
  ValueKey<String> k(String s) => ValueKey<String>(s);

  Future<(AppState, ThemeController)> seeded(
    WidgetTester tester, {
    bool enabled = false,
  }) => loadState(
    tester,
    seed: (s) async {
      await s.addTimetable(buildTimetable(overrides: octoberOverrides()));
      if (enabled) {
        await s.setReminderSettings(const ReminderSettings(enabled: true));
      }
    },
  );

  Future<ReminderService> pumpPage(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
    FakeReminderGateway gateway,
  ) async {
    final service = ReminderService(gateway: gateway, clock: () => now);
    addTearDown(service.dispose);
    await pumpApp(
      tester,
      state,
      controller,
      ReminderSettingsPage(service: service),
      size: const Size(900, 4000),
    );
    await tester.pumpAndSettle();
    return service;
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
  }

  bool switchValue(WidgetTester tester, String key) =>
      tester.widget<SwitchListTile>(find.byKey(k(key))).value;

  group('设置页入口', () {
    testWidgets('「上课提醒」tile：未开启 / 已开启 · 提前 N 分钟 · 跟随「课表」', (tester) async {
      final (state, controller) = await seeded(tester);
      await pumpApp(
        tester,
        state,
        controller,
        SettingsPage(updateChecker: UpdateChecker(sources: const <String>[])),
      );
      final tile = find.byKey(k('settings-reminders'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(of: tile, matching: find.text('未开启')),
        findsOneWidget,
      );

      await tester.runAsync(
        () => state.setReminderSettings(
          const ReminderSettings(enabled: true, leadMinutes: 20),
        ),
      );
      await tester.pump();
      expect(
        find.descendant(
          of: tile,
          matching: find.text('已开启 · 提前 20 分钟 · 跟随「测试课表」'),
        ),
        findsOneWidget,
      );

      // 没有 Provider 时页面自己兜底建一个（真实网关在测试里是空操作）。
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byKey(k('reminder-enabled')), findsOneWidget);
      expect(
        find.byKey(k('reminder-problem-card')),
        findsNothing,
        reason: '权限查不到（unknown）时不显示提示卡，免得误报',
      );
    });
  });

  group('总开关', () {
    testWidgets('打开：先申请通知权限，允许后保存并排程', (tester) async {
      final (state, controller) = await seeded(tester);
      final gateway = FakeReminderGateway(notificationsAllowed: false);
      await pumpPage(tester, state, controller, gateway);
      expect(switchValue(tester, 'reminder-enabled'), isFalse);
      expect(find.byKey(k('reminder-upcoming-off')), findsOneWidget);

      await tapAndSettle(tester, find.byKey(k('reminder-enabled')));

      expect(gateway.permissionRequests, 1);
      expect(state.settings.reminders.enabled, isTrue);
      expect(switchValue(tester, 'reminder-enabled'), isTrue);
      expect(gateway.scheduleCalls, isNotEmpty);
      expect(gateway.scheduled, isNotEmpty);
    });

    testWidgets('打开：权限被拒 → 开关弹回、提示去设置', (tester) async {
      final (state, controller) = await seeded(tester);
      final gateway = FakeReminderGateway(
        notificationsAllowed: false,
        grantOnRequest: false,
      );
      await pumpPage(tester, state, controller, gateway);

      await tapAndSettle(tester, find.byKey(k('reminder-enabled')));

      expect(gateway.permissionRequests, 1);
      expect(state.settings.reminders.enabled, isFalse);
      expect(switchValue(tester, 'reminder-enabled'), isFalse);
      expect(gateway.scheduleCalls, isEmpty);
      expect(find.byKey(k('reminder-denied')), findsOneWidget);
      await tester.tap(find.text('去设置').last);
      await tester.pump();
      expect(gateway.openSettingsCalls, 1);
    });

    testWidgets('关闭：撤销全部提醒', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      final gateway = FakeReminderGateway();
      await pumpPage(tester, state, controller, gateway);
      await tapAndSettle(tester, find.byKey(k('reminder-enabled')));
      expect(state.settings.reminders.enabled, isFalse);
      expect(gateway.cancelAllCalls, greaterThanOrEqualTo(1));
      expect(gateway.scheduled, isEmpty);
    });
  });

  group('偏好', () {
    testWidgets('提前分钟 ChoiceChip：5/10/15/20/30，点 30 保存并重排', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      final gateway = FakeReminderGateway();
      await pumpPage(tester, state, controller, gateway);
      for (final n in <int>[5, 10, 15, 20, 30]) {
        expect(find.byKey(k('reminder-lead-$n')), findsOneWidget);
      }
      expect(
        tester.widget<ChoiceChip>(find.byKey(k('reminder-lead-15'))).selected,
        isTrue,
      );

      await tapAndSettle(tester, find.byKey(k('reminder-lead-30')));

      expect(state.settings.reminders.leadMinutes, 30);
      expect(
        tester.widget<ChoiceChip>(find.byKey(k('reminder-lead-30'))).selected,
        isTrue,
      );
      expect(
        gateway.scheduleCalls.last.reminders.first.fireAt,
        DateTime(2026, 10, 7, 9, 30),
      );
    });

    testWidgets('明日预告开关 + 时间行', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      await pumpPage(tester, state, controller, FakeReminderGateway());
      expect(switchValue(tester, 'reminder-preview'), isTrue);
      final timeTile = find.byKey(k('reminder-preview-time'));
      expect(
        find.descendant(of: timeTile, matching: find.text('21:00')),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(timeTile).enabled, isTrue);

      await tapAndSettle(tester, find.byKey(k('reminder-preview')));

      expect(state.settings.reminders.eveningPreview, isFalse);
      expect(tester.widget<ListTile>(timeTile).enabled, isFalse);
    });

    testWidgets('预告时间：点开时间选择器', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      await pumpPage(tester, state, controller, FakeReminderGateway());
      await tester.tap(find.byKey(k('reminder-preview-time')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(state.settings.reminders.previewHour, 21);
    });
  });

  group('提示卡（D7）', () {
    test('problemFor：只在提醒开着、权限查到时判断；通知优先', () {
      const ok = ReminderPermission(notifications: true, exactAlarms: true);
      const noNotif = ReminderPermission(
        notifications: false,
        exactAlarms: true,
      );
      const noExact = ReminderPermission(
        notifications: true,
        exactAlarms: false,
      );
      const neither = ReminderPermission(
        notifications: false,
        exactAlarms: false,
      );
      expect(problemFor(enabled: true, permission: ok), isNull);
      expect(
        problemFor(enabled: true, permission: noNotif),
        ReminderProblem.notifications,
      );
      expect(
        problemFor(enabled: true, permission: noExact),
        ReminderProblem.exactAlarms,
      );
      expect(
        problemFor(enabled: true, permission: neither),
        ReminderProblem.notifications,
      );
      expect(problemFor(enabled: false, permission: neither), isNull);
      expect(
        problemFor(enabled: true, permission: ReminderPermission.unknown),
        isNull,
      );
    });

    testWidgets('没有通知权限 → 卡片「提醒发不出来 · 去允许通知」；系统不再弹框就打开系统设置', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      final gateway = FakeReminderGateway(
        notificationsAllowed: false,
        grantOnRequest: false,
      );
      await pumpPage(tester, state, controller, gateway);

      final card = find.byKey(k('reminder-problem-card'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('提醒发不出来')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('去允许通知')),
        findsOneWidget,
      );
      // 卡片紧跟在总开关下面。
      expect(
        tester.getTopLeft(card).dy,
        greaterThan(tester.getTopLeft(find.byKey(k('reminder-enabled'))).dy),
      );
      expect(
        tester.getTopLeft(card).dy,
        lessThan(tester.getTopLeft(find.text('提前多久提醒')).dy),
      );

      await tapAndSettle(tester, find.byKey(k('reminder-problem-action')));

      expect(gateway.permissionRequests, 1);
      expect(gateway.openSettingsCalls, 1);
      expect(card, findsOneWidget, reason: '还是没有权限，卡片留着');
    });

    testWidgets('没有通知权限，点「去允许通知」后系统弹框允许了 → 通知那张卡消失', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      final gateway = FakeReminderGateway(
        notificationsAllowed: false,
        exactAllowed: true,
      );
      await pumpPage(tester, state, controller, gateway);
      expect(find.text('提醒发不出来'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(k('reminder-problem-action')));

      expect(gateway.permissionRequests, 1);
      expect(gateway.openSettingsCalls, 0, reason: '系统框里允许了就不用再去设置');
      expect(find.byKey(k('reminder-problem-card')), findsNothing);
    });

    testWidgets('两种问题都有时只说通知；通知好了再说「闹钟和提醒」', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      final gateway = FakeReminderGateway(notificationsAllowed: false);
      await pumpPage(tester, state, controller, gateway);
      expect(find.byKey(k('reminder-problem-card')), findsOneWidget);
      expect(find.text('提醒发不出来'), findsOneWidget);
      expect(find.text('提醒可能不准时'), findsNothing);

      await tapAndSettle(tester, find.byKey(k('reminder-problem-action')));

      expect(find.text('提醒发不出来'), findsNothing);
      expect(find.text('提醒可能不准时'), findsOneWidget);
    });

    testWidgets('「闹钟和提醒」没开 → 卡片「提醒可能不准时 · 去系统设置」，点了按精确重排、卡片消失', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      final gateway = FakeReminderGateway();
      final service = await pumpPage(tester, state, controller, gateway);
      await tester.runAsync(() => service.replanNow(state));
      await tester.pump();

      final card = find.byKey(k('reminder-problem-card'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('提醒可能不准时')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('去系统设置允许「闹钟和提醒」')),
        findsOneWidget,
      );
      expect(gateway.scheduleCalls.last.exact, isFalse);

      await tapAndSettle(tester, find.byKey(k('reminder-problem-action')));

      expect(gateway.exactRequests, 1);
      expect(gateway.scheduleCalls.last.exact, isTrue);
      expect(card, findsNothing);
    });

    testWidgets('一切正常 → 没有卡片，页面上没有「精确」「Android」之类的词', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      final gateway = FakeReminderGateway(
        exactAllowed: true,
        exactBySystem: true,
      );
      await pumpPage(tester, state, controller, gateway);
      expect(find.byKey(k('reminder-problem-card')), findsNothing);
      for (final word in <String>[
        '精确',
        'Android',
        'USE_EXACT_ALARM',
        '权限', // 「权限」分组删掉了
        '1 小时',
      ]) {
        expect(find.textContaining(word), findsNothing, reason: word);
      }
    });

    testWidgets('提醒关着 → 不显示卡片（哪怕没有通知权限）', (tester) async {
      final (state, controller) = await seeded(tester);
      await pumpPage(
        tester,
        state,
        controller,
        FakeReminderGateway(notificationsAllowed: false),
      );
      expect(find.byKey(k('reminder-problem-card')), findsNothing);
    });

    testWidgets('打开总开关时「闹钟和提醒」没开 → 弹框说白话，点「去设置」按精确重排', (tester) async {
      final (state, controller) = await seeded(tester);
      final gateway = FakeReminderGateway();
      await pumpPage(tester, state, controller, gateway);

      await tapAndSettle(tester, find.byKey(k('reminder-enabled')));
      expect(state.settings.reminders.enabled, isTrue);
      final dialog = find.byKey(k('reminder-exact-prompt'));
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text('提醒想准点送达，需要在系统里允许「闹钟和提醒」。'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('精确')),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('以后再说')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('去设置')),
        findsOneWidget,
      );

      await tapAndSettle(tester, find.byKey(k('reminder-exact-prompt-go')));
      expect(find.byKey(k('reminder-exact-prompt')), findsNothing);
      expect(gateway.exactRequests, 1);
      expect(gateway.scheduleCalls.last.exact, isTrue);
      expect(find.byKey(k('reminder-problem-card')), findsNothing);
    });

    testWidgets('打开总开关时「闹钟和提醒」没开 →「以后再说」：不去设置，卡片留着', (tester) async {
      final (state, controller) = await seeded(tester);
      final gateway = FakeReminderGateway();
      await pumpPage(tester, state, controller, gateway);

      await tapAndSettle(tester, find.byKey(k('reminder-enabled')));
      await tapAndSettle(tester, find.byKey(k('reminder-exact-prompt-later')));
      expect(find.byKey(k('reminder-exact-prompt')), findsNothing);
      expect(gateway.exactRequests, 0);
      expect(state.settings.reminders.enabled, isTrue);
      expect(find.text('提醒可能不准时'), findsOneWidget);
    });

    testWidgets('打开总开关时已有精确闹钟 → 不弹框', (tester) async {
      final (state, controller) = await seeded(tester);
      final gateway = FakeReminderGateway(
        exactAllowed: true,
        exactBySystem: true,
      );
      await pumpPage(tester, state, controller, gateway);
      await tapAndSettle(tester, find.byKey(k('reminder-enabled')));
      expect(state.settings.reminders.enabled, isTrue);
      expect(find.byKey(k('reminder-exact-prompt')), findsNothing);
      expect(gateway.exactRequests, 0);
      expect(gateway.scheduleCalls.last.exact, isTrue);
    });
  });

  group('测试按钮', () {
    testWidgets('「发送测试提醒」立即发；「1 分钟后测试」走定时', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      final gateway = FakeReminderGateway();
      final service = await pumpPage(tester, state, controller, gateway);
      await tester.runAsync(() => service.replanNow(state));
      await tester.pump();

      await tapAndSettle(tester, find.byKey(k('reminder-test-now')));
      expect(gateway.showTestCalls, 1);

      final count = find.byKey(k('reminder-pending-count'));
      String countText() => tester
          .widget<Text>(find.descendant(of: count, matching: find.byType(Text)))
          .data!;
      expect(countText(), '接下来 14 天共 14 条提醒；每次打开简课表都会往后补上');
      expect(find.text('接下来的提醒'), findsOneWidget);
      expect(find.text('切换课表或重新导入后，提醒会跟着换'), findsOneWidget);

      await tapAndSettle(tester, find.byKey(k('reminder-test-later')));
      expect(gateway.testDelays, <Duration>[const Duration(minutes: 1)]);
      expect(find.textContaining('07:01 左右'), findsOneWidget);
      expect(find.textContaining('（系统可能让提醒晚到）'), findsOneWidget);
      expect(countText(), '接下来 14 天共 14 条提醒；每次打开简课表都会往后补上');
      expect(countText(), isNot(contains('系统里已安排')));
    });

    testWidgets('没有通知权限且被拒 → 不发测试通知', (tester) async {
      final (state, controller) = await seeded(tester);
      final gateway = FakeReminderGateway(
        notificationsAllowed: false,
        grantOnRequest: false,
      );
      await pumpPage(tester, state, controller, gateway);
      await tapAndSettle(tester, find.byKey(k('reminder-test-later')));
      expect(gateway.testDelays, isEmpty);
      expect(find.byKey(k('reminder-denied')), findsOneWidget);
    });
  });

  group('即将触发', () {
    testWidgets('按日期分组；停课日一行「x月x日 停课 · 不提醒」', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      await pumpPage(tester, state, controller, FakeReminderGateway());

      expect(find.byKey(k('reminder-day-2026-10-07')), findsOneWidget);
      expect(find.text('10月7日 周三'), findsOneWidget);
      expect(
        find.text('大学英语 · 10:00 上课'),
        findsNWidgets(2),
        reason: '10-07 / 10-14',
      );
      expect(find.text('09:45'), findsNWidgets(2));
      final preview = ReminderPlanner.stableId(
        'preview',
        DateTime(2026, 10, 8),
        '',
        0,
      );
      expect(
        find.descendant(
          of: find.byKey(k('reminder-item-$preview')),
          matching: find.text('明天 1 节课，13:00 体育'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(k('reminder-day-2026-10-10')), findsOneWidget);
      expect(find.text('A101 · 张老师 · 第 1-2 节（调休：按第 4 周周一上课）'), findsOneWidget);

      final cancelled = find.byKey(k('reminder-cancelled-2026-10-12'));
      expect(cancelled, findsOneWidget);
      expect(
        find.descendant(of: cancelled, matching: find.text('10月12日 停课 · 不提醒')),
        findsOneWidget,
      );
      expect(
        find.byKey(k('reminder-cancelled-2026-10-11')),
        findsNothing,
        reason: '周日本来没课',
      );

      // 分组顺序按日期。
      final y7 = tester.getTopLeft(find.byKey(k('reminder-day-2026-10-07'))).dy;
      final y10 = tester
          .getTopLeft(find.byKey(k('reminder-day-2026-10-10')))
          .dy;
      final y12 = tester.getTopLeft(cancelled).dy;
      expect(y7 < y10 && y10 < y12, isTrue);

      expect(find.byKey(k('reminder-pending-count')), findsOneWidget);
      expect(find.textContaining('接下来 14 天'), findsOneWidget);
    });

    testWidgets('顶部写提醒跟随的课表；列表最后是续排那一句（P2-1 / P2-2）', (tester) async {
      final (state, controller) = await seeded(tester, enabled: true);
      await pumpPage(tester, state, controller, FakeReminderGateway());

      expect(
        find.descendant(
          of: find.byKey(k('reminder-timetable')),
          matching: find.text('提醒跟随当前课表：测试课表'),
        ),
        findsOneWidget,
      );
      final end = find.byKey(k('reminder-horizon-end'));
      expect(end, findsOneWidget);
      expect(
        find.descendant(of: end, matching: find.text('提醒已排到 10月20日，打开简课表就会续上')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: end, matching: find.text('21:00')),
        findsOneWidget,
      );
      // 续排那一句在所有日期分组之后、计数行之前。
      final endY = tester.getTopLeft(end).dy;
      final lastDayY = tester
          .getTopLeft(find.byKey(k('reminder-day-2026-10-20')))
          .dy;
      final countY = tester
          .getTopLeft(find.byKey(k('reminder-pending-count')))
          .dy;
      expect(lastDayY < endY && endY < countY, isTrue);
      final preview21 = ReminderPlanner.stableId(
        'preview',
        DateTime(2026, 10, 21),
        '',
        0,
      );
      expect(
        tester.getTopLeft(find.byKey(k('reminder-item-$preview21'))).dy < endY,
        isTrue,
        reason: '最后一晚的预告也在它前面',
      );
    });

    testWidgets('没有课表 → 空提示', (tester) async {
      final (state, controller) = await loadState(
        tester,
        seed: (s) =>
            s.setReminderSettings(const ReminderSettings(enabled: true)),
      );
      await pumpPage(tester, state, controller, FakeReminderGateway());
      expect(find.byKey(k('reminder-upcoming-empty')), findsOneWidget);
    });
  });

  group('真实网关', () {
    test('flutter test 里没有插件原生端 → 全部是安全的空操作', () async {
      final gateway = LocalNotificationsGateway();
      await gateway.init((_) {});
      expect(await gateway.permissions(), ReminderPermission.unknown);
      expect(await gateway.requestNotificationPermission(), isFalse);
      await gateway.scheduleAll(const <PlannedReminder>[], exact: true);
      await gateway.cancelAll();
      await gateway.showTest();
      await gateway.scheduleTestIn(const Duration(minutes: 1));
      expect(await gateway.pending(), isEmpty);
      expect(await gateway.launchPayload(), isNull);
    });
  });
}
