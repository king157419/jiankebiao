import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shu_schedule/app.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/reminders/reminder_service.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';
import 'package:shu_schedule/features/settings/theme_picker_page.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';

import 'helpers/fake_holiday_repository.dart';
import 'helpers/fake_reminder_gateway.dart';
import 'helpers/harness.dart';
import 'helpers/reminder_fixtures.dart';

/// v1.5.0 任务 A2（PLAN-1.5 D2，2026-10-08 下午修订）：没有底部导航栏，
/// 周课表铺满整屏作为首页，头部右上角「更多 ⋮」左边的齿轮（`week-settings`）
/// push 设置页；点上课提醒通知（运行中 / 冷启动）→ `popUntil(isFirst)` 关掉
/// 压在上面的页面，周视图回到本周。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = TempStorage();
  setUp(() => storage.setUp('home_shell'));
  tearDown(storage.tearDown);

  // 开学 2026-09-14，2026-10-07 是第 4 周周三。
  DateTime clock() => DateTime(2026, 10, 7, 10);

  final gear = find.byKey(const ValueKey<String>('week-settings'));

  Future<(AppState, ThemeController)> seeded(WidgetTester tester) => loadState(
    tester,
    seed: (s) async {
      await s.addTimetable(buildTimetable(overrides: octoberOverrides()));
      await s.setReminderSettings(const ReminderSettings(enabled: true));
      // 今天已经自动检查过更新：启动流程不会去联网。
      await s.setLastUpdateCheck(DateTime(2026, 10, 7, 8));
    },
  );

  /// 只 pump HomeShell（注入时钟），Provider 里自己放一个 [ReminderService]。
  Future<ReminderService> pumpShell(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
    FakeReminderGateway gateway,
  ) async {
    final reminders = ReminderService(gateway: gateway, clock: clock);
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ThemeController>.value(value: controller),
          ChangeNotifierProvider<ReminderService>.value(value: reminders),
        ],
        child: MaterialApp(
          theme: controller.current.toThemeData(),
          home: HomeShell(
            clock: clock,
            holidayRepository: FakeHolidayRepository(
              data: HolidayPresets.empty,
            ),
          ),
        ),
      ),
    );
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
    return reminders;
  }

  /// 卸载（停掉周视图的分钟计时器）再释放 ReminderService。
  Future<void> unmount(WidgetTester tester, ReminderService reminders) async {
    await tester.pumpWidget(const SizedBox());
    reminders.dispose();
    await settleWithRealIo(tester, rounds: 5);
  }

  /// 周视图 PageView 实际停在第几周（不只看头部文字：翻页动画要真的跑完）。
  int pageWeek(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!.round() +
      1;

  /// [of] 里第一个图标实际画出来的颜色。
  Color? iconColor(WidgetTester tester, Finder of) => tester
      .widget<RichText>(
        find.descendant(of: of, matching: find.byType(RichText)).first,
      )
      .text
      .style
      ?.color;

  /// 打开设置页（点齿轮），确认设置页在最上面。
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(gear);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(gear, findsNothing, reason: '周视图被设置页盖住');
  }

  testWidgets('首页就是周视图：没有底部导航栏，「更多 ⋮」左边有齿轮，颜色和 ⋮ 一致', (tester) async {
    final (state, controller) = await seeded(tester);
    final reminders = await pumpShell(
      tester,
      state,
      controller,
      FakeReminderGateway(),
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationDestination), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(WeekViewPage), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('今日'), findsNothing);
    expect(find.text('第 4 周'), findsOneWidget);
    expect(pageWeek(tester), 4);

    expect(gear, findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    final more = find.byTooltip('更多');
    expect(more, findsOneWidget);
    expect(tester.getCenter(gear).dx, lessThan(tester.getCenter(more).dx));
    expect(
      (tester.getCenter(gear).dy - tester.getCenter(more).dy).abs(),
      lessThan(1),
      reason: '齿轮和 ⋮ 在同一行',
    );
    final header = controller.current.colors.headerText;
    expect(iconColor(tester, gear), header);
    expect(iconColor(tester, more), header);
    await unmount(tester, reminders);
  });

  testWidgets('周视图点齿轮 → 设置页出现 → 返回键回到周视图（还在原来那一周）', (tester) async {
    final (state, controller) = await seeded(tester);
    final reminders = await pumpShell(
      tester,
      state,
      controller,
      FakeReminderGateway(),
    );
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    expect(find.text('第 5 周'), findsOneWidget);

    await openSettings(tester);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('设置')),
      findsOneWidget,
    );
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.text('课表管理'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(gear, findsOneWidget);
    expect(find.text('第 5 周'), findsOneWidget, reason: '周视图状态保留');
    expect(pageWeek(tester), 5);
    expect(tester.takeException(), isNull);
    await unmount(tester, reminders);
  });

  testWidgets('运行中点通知：设置页和它上面的子页面全部关掉，周视图从第 5 周回到本周（第 4 周）', (tester) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway();
    final reminders = await pumpShell(tester, state, controller, gateway);
    expect(gateway.initCalls, 1);
    expect(find.text('第 4 周'), findsOneWidget);
    expect(find.text('回到本周'), findsNothing);

    // 翻到下一周，进设置，再从设置进「主题」。
    await tester.tap(find.byTooltip('下一周'));
    await tester.pumpAndSettle();
    expect(find.text('第 5 周'), findsOneWidget);
    expect(find.text('回到本周'), findsOneWidget);
    await openSettings(tester);
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    expect(find.byType(ThemePickerPage), findsOneWidget);

    gateway.tap('class|2026-10-08');
    await tester.pumpAndSettle();
    expect(find.byType(ThemePickerPage), findsNothing);
    expect(find.byType(SettingsPage), findsNothing);
    expect(gear, findsOneWidget);
    expect(find.text('第 4 周'), findsOneWidget);
    expect(find.text('第 5 周'), findsNothing);
    expect(find.text('回到本周'), findsNothing);
    expect(pageWeek(tester), 4, reason: '翻页动画在设置页退场时也要跑完');

    // 已经在课表本周时再点一次：不出错，仍在本周，周视图还在。
    gateway.tap('preview|2026-10-08');
    await tester.pumpAndSettle();
    expect(find.byType(WeekViewPage), findsOneWidget);
    expect(find.text('第 4 周'), findsOneWidget);
    expect(pageWeek(tester), 4);
    expect(tester.takeException(), isNull);
    await unmount(tester, reminders);
  });

  testWidgets('续排提醒的旧 payload（today）同样关掉设置页、回到课表本周', (tester) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway();
    final reminders = await pumpShell(tester, state, controller, gateway);
    await tester.tap(find.byTooltip('上一周'));
    await tester.pumpAndSettle();
    expect(find.text('第 3 周'), findsOneWidget);
    await openSettings(tester);

    gateway.tap(ReminderPlanner.horizonEndPayload);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('第 4 周'), findsOneWidget);
    expect(find.text('回到本周'), findsNothing);
    expect(pageWeek(tester), 4);
    await unmount(tester, reminders);
  });

  testWidgets('点通知冷启动：落在周视图本周，没有页面压在上面', (tester) async {
    final (state, controller) = await seeded(tester);
    final gateway = FakeReminderGateway(launch: 'class|2026-10-07');
    final reminders = await pumpShell(tester, state, controller, gateway);
    expect(gateway.initCalls, 1);
    expect(find.byType(SettingsPage), findsNothing);
    expect(gear, findsOneWidget);
    expect(find.text('第 4 周'), findsOneWidget);
    expect(find.text('回到本周'), findsNothing);
    expect(pageWeek(tester), 4);
    expect(gateway.scheduleCalls, isNotEmpty, reason: '冷启动同样排程');
    await unmount(tester, reminders);
  });
}
