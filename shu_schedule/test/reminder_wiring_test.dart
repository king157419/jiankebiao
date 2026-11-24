import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/app.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/reminders/reminder_service.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';

import 'helpers/fake_reminder_gateway.dart';
import 'helpers/harness.dart';
import 'helpers/reminder_fixtures.dart';

/// v1.4.0 B3 接线：ShuScheduleApp / HomeShell 与 ReminderService。
///
/// v1.5.0：没有隐私同意框了，启动就 init。任务 A2 起没有底部导航栏：设置页由
/// 周视图右上角齿轮（`week-settings`）push 进来，点通知 → 关掉设置页、周视图回到
/// 本周。「回到本周」的细节（注入时钟、翻页动画）见 `home_shell_test.dart`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = TempStorage();
  setUp(() => storage.setUp('reminder_wiring'));
  tearDown(storage.tearDown);

  Future<(AppState, ThemeController)> seeded(WidgetTester tester) => loadState(
    tester,
    seed: (s) async {
      await s.addTimetable(buildTimetable(overrides: octoberOverrides()));
      await s.setReminderSettings(const ReminderSettings(enabled: true));
    },
  );

  Future<void> pumpShuApp(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
    FakeReminderGateway gateway,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ShuScheduleApp(
        appState: state,
        themeController: controller,
        reminderGateway: gateway,
      ),
    );
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
  }

  final gear = find.byKey(const ValueKey<String>('week-settings'));

  Future<void> sendLifecycle(WidgetTester tester, AppLifecycleState s) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(s.toString()),
      (_) {},
    );
    await tester.pump();
  }

  /// 收尾：卸载 App（停掉防抖计时器），再让真实 IO 写完。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settleWithRealIo(tester, rounds: 5);
  }

  testWidgets('启动就 init 并排程（没有隐私同意框）', (tester) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway();
    await pumpShuApp(tester, state, controller, gateway);

    expect(find.text('不同意并退出'), findsNothing);
    expect(gateway.initCalls, 1);
    expect(gateway.scheduleCalls, isNotEmpty);
    expect(gateway.cancelAllCalls, 0);
    await unmount(tester);
  });

  testWidgets('开着提醒但没有通知权限 → 启动时弹「去允许通知」，设置 tile 写明（P2-3 / P3-8）', (
    tester,
  ) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway(
      notificationsAllowed: false,
      grantOnRequest: false,
    );
    await pumpShuApp(tester, state, controller, gateway);

    final bar = find.byKey(const ValueKey<String>('reminder-needs-permission'));
    expect(bar, findsOneWidget);
    expect(find.text('上课提醒已开启，但没有通知权限，提醒发不出来'), findsOneWidget);
    // v1.5.0 任务 E：按钮和提醒页提示卡同一个说法。
    expect(find.text('去授权'), findsNothing);
    await tester.tap(find.text('去允许通知'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(gateway.permissionRequests, 1);
    expect(gateway.openSettingsCalls, 1, reason: '系统不再弹框 → 打开通知设置');

    await tester.tap(gear);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('settings-reminders')),
        matching: find.text('已开启 · 没有通知权限'),
      ),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('有通知权限 → 启动时不弹（P2-3）', (tester) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway();
    await pumpShuApp(tester, state, controller, gateway);
    expect(
      find.byKey(const ValueKey<String>('reminder-needs-permission')),
      findsNothing,
    );
    await unmount(tester);
  });

  testWidgets('提醒开着时切换当前课表 → SnackBar「上课提醒已切换到「xxx」」（P2-2）', (tester) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway();
    await pumpShuApp(tester, state, controller, gateway);
    expect(
      find.byKey(const ValueKey<String>('reminder-timetable-switched')),
      findsNothing,
    );

    unawaited(state.createTimetable(name: '同学的课表'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('reminder-timetable-switched')),
      findsOneWidget,
    );
    expect(find.text('上课提醒已切换到「同学的课表」'), findsOneWidget);
    await settleWithRealIo(tester, rounds: 5);
    await unmount(tester);
  });

  testWidgets('点通知冷启动 → 落在周视图，没有页面压在上面', (tester) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway(launch: 'class|2026-10-07');
    await pumpShuApp(tester, state, controller, gateway);
    expect(gateway.initCalls, 1);
    expect(find.byType(WeekViewPage), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(gear, findsOneWidget);
    expect(find.text('回到本周'), findsNothing);
    await unmount(tester);
  });

  testWidgets('不是点通知启动的 → 停在周视图；先 push 设置页，点通知 → 设置页被 pop、周视图在本周', (
    tester,
  ) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway();
    await pumpShuApp(tester, state, controller, gateway);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('回到本周'), findsNothing);

    // 先离开本周（这里没注入时钟：哪个方向能翻就往哪翻），再进设置。
    final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
    final prev = find.widgetWithIcon(IconButton, Icons.chevron_left);
    await tester.tap(
      tester.widget<IconButton>(next).onPressed != null ? next : prev,
    );
    await tester.pumpAndSettle();
    expect(find.text('回到本周'), findsOneWidget);
    await tester.tap(gear);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(gear, findsNothing);

    gateway.tap('preview|2026-10-08');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(gear, findsOneWidget);
    expect(find.text('回到本周'), findsNothing);
    await unmount(tester);
  });

  testWidgets('回到前台：刷新权限并重排（精确闹钟刚被允许 → 按精确重排）', (tester) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway();
    await pumpShuApp(tester, state, controller, gateway);
    final before = gateway.scheduleCalls.length;
    expect(before, greaterThanOrEqualTo(1));
    expect(gateway.scheduleCalls.last.exact, isFalse);

    gateway.exactAllowed = true;
    await sendLifecycle(tester, AppLifecycleState.paused);
    await sendLifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(gateway.scheduleCalls.length, before + 1);
    expect(gateway.scheduleCalls.last.exact, isTrue);
    await unmount(tester);
  });

  testWidgets('AppState 变化 → 800 ms 防抖后重排', (tester) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway();
    await pumpShuApp(tester, state, controller, gateway);
    final before = gateway.scheduleCalls.length;

    // 在 fake async 区里改（监听器同步触发，防抖计时器才是假时间里的计时器）；
    // 写盘是真实 IO，最后由 settleWithRealIo 收尾。
    unawaited(
      state.setReminderSettings(
        state.settings.reminders.copyWith(leadMinutes: 30),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(gateway.scheduleCalls.length, before, reason: '还在防抖窗口里');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(gateway.scheduleCalls.length, before + 1);

    await settleWithRealIo(tester, rounds: 5);
    unawaited(
      state.setReminderSettings(
        state.settings.reminders.copyWith(enabled: false),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(gateway.cancelAllCalls, 1);
    expect(gateway.scheduled, isEmpty);
    await unmount(tester);
  });
}
