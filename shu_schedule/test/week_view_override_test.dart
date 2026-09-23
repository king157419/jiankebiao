import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/features/timetable/today_page.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/period_time.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

/// v1.3.0 Phase A：周视图 / 今日页里的调休、停课与自动休息带。
///
/// 和 week_view_test 一样：磁盘 / asset I/O 必须包在 `tester.runAsync` 里。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shu_week_override_test');
    Storage.overrideDirectory = tempDir;
  });

  tearDown(() async {
    Storage.overrideDirectory = null;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monday = ScheduleUtils.addDays(today, -(now.weekday - 1));
  // 本周里另一天（和今天不同的星期）。
  final otherWeekday = now.weekday % 7 + 1;
  final otherDate = ScheduleUtils.addDays(monday, otherWeekday - 1);

  Future<(AppState, ThemeController)> buildState({
    Map<String, DateOverride>? overrides,
    List<PeriodTime>? periods,
  }) async {
    final state = AppState();
    await state.load();
    await state.addTimetable(
      Timetable(
        id: 'tt',
        name: '调休课表',
        config: ScheduleConfig(
          name: '2026-2027 秋',
          startDate: monday,
          totalWeeks: 18,
          periods: periods,
          overrides: overrides,
        ),
        courses: <Course>[
          Course(
            id: 'c1',
            name: '今天这个星期的课',
            location: 'J101',
            day: now.weekday,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[for (var w = 1; w <= 18; w++) w],
          ),
        ],
      ),
    );
    final controller = ThemeController(state);
    await controller.load();
    return (state, controller);
  }

  Future<void> pumpPage(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
    Widget page,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ThemeController>.value(value: controller),
        ],
        child: MaterialApp(theme: controller.current.toThemeData(), home: page),
      ),
    );
    await tester.pump();
  }

  testWidgets('周视图：今天停课 + 另一天调休成今天的星期，课程只出现在调休那天', (tester) async {
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      (state, controller) = await buildState(
        overrides: <String, DateOverride>{
          ScheduleUtils.dateKey(today): const DateOverride.cancelled(),
          ScheduleUtils.dateKey(otherDate): DateOverride.actAs(
            weekday: now.weekday,
          ),
        },
      );
    });
    await pumpPage(tester, state, controller, const WeekViewPage());
    expect(tester.takeException(), isNull);

    // 日期头标出了这两天。
    expect(
      find.byKey(ValueKey<String>('override-${ScheduleUtils.dateKey(today)}')),
      findsOneWidget,
    );
    expect(find.text('停课'), findsOneWidget);
    expect(find.text('调休'), findsOneWidget);
    // 课程只画一次（在调休那天的列里），停课的今天不画。
    expect(find.text('今天这个星期的课'), findsOneWidget);
    final blockX = tester.getCenter(find.text('今天这个星期的课')).dx;
    final otherLabelX = tester
        .getCenter(
          find.byKey(
            ValueKey<String>('override-${ScheduleUtils.dateKey(otherDate)}'),
          ),
        )
        .dx;
    expect((blockX - otherLabelX).abs(), lessThan(30), reason: '在调休那一列');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('周视图：没有调休时日期头不标记，课程照常', (tester) async {
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      (state, controller) = await buildState();
    });
    await pumpPage(tester, state, controller, const WeekViewPage());
    expect(find.text('停课'), findsNothing);
    expect(find.text('调休'), findsNothing);
    expect(find.text('今天这个星期的课'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('周视图：上午 5 节的作息，休息带画在第 5、9 节后', (tester) async {
    const fiveMorning = <PeriodTime>[
      PeriodTime(index: 1, start: '08:00', end: '08:45'),
      PeriodTime(index: 2, start: '08:55', end: '09:40'),
      PeriodTime(index: 3, start: '10:00', end: '10:45'),
      PeriodTime(index: 4, start: '10:55', end: '11:40'),
      PeriodTime(index: 5, start: '11:50', end: '12:35'),
      PeriodTime(index: 6, start: '14:00', end: '14:45'),
      PeriodTime(index: 7, start: '14:55', end: '15:40'),
      PeriodTime(index: 8, start: '16:00', end: '16:45'),
      PeriodTime(index: 9, start: '16:55', end: '17:40'),
      PeriodTime(index: 10, start: '19:00', end: '19:45'),
      PeriodTime(index: 11, start: '19:55', end: '20:40'),
    ];
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      (state, controller) = await buildState(periods: fiveMorning);
    });
    tester.view.physicalSize = const Size(420, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPage(tester, state, controller, const WeekViewPage());
    expect(tester.takeException(), isNull);

    final noon = find.text('午间休息');
    final evening = find.text('晚间休息');
    expect(noon, findsOneWidget);
    expect(evening, findsOneWidget);
    // 午间带在「12:35」（第 5 节结束）下面、「14:00」（第 6 节开始）上面。
    final noonY = tester.getCenter(noon).dy;
    expect(noonY, greaterThan(tester.getCenter(find.text('12:35')).dy));
    expect(noonY, lessThan(tester.getCenter(find.text('14:00')).dy));
    final eveningY = tester.getCenter(evening).dy;
    expect(eveningY, greaterThan(tester.getCenter(find.text('17:40')).dy));
    expect(eveningY, lessThan(tester.getCenter(find.text('19:00')).dy));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('今日页：停课日不列课程，副标题写明停课', (tester) async {
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      (state, controller) = await buildState(
        overrides: <String, DateOverride>{
          ScheduleUtils.dateKey(today): const DateOverride.cancelled(
            note: '运动会',
          ),
        },
      );
    });
    await pumpPage(tester, state, controller, const TodayPage());
    expect(find.text('今天这个星期的课'), findsNothing);
    expect(find.textContaining('第 1 周 · 停课（运动会）'), findsOneWidget);
    expect(find.text('今天停课。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('今日页：调休日列出被换过来的那天的课', (tester) async {
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      // 今天按「本周另一天」的星期上课：原本今天的课不上。
      (state, controller) = await buildState(
        overrides: <String, DateOverride>{
          ScheduleUtils.dateKey(today): DateOverride.actAs(
            weekday: otherWeekday,
          ),
        },
      );
    });
    await pumpPage(tester, state, controller, const TodayPage());
    expect(find.text('今天这个星期的课'), findsNothing);
    expect(find.textContaining('调休，按'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
