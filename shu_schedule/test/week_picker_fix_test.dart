import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/app.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/fake_holiday_repository.dart';
import 'helpers/harness.dart';

/// v1.5.0（PLAN-1.5 D8）：周视图点「第 N 周」弹出的「选择周次」面板底部
/// 「本周不是第 N 周？点这里校正」（key `week-picker-fix`）→「现在是第几周？」→
/// 改开学日期、SnackBar「已把本周设为第 x 周」、周视图回到本周。
///
/// 今天固定 2026-10-08 10:00（周四）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = TempStorage();
  setUp(() => storage.setUp('week_picker_fix'));
  tearDown(storage.tearDown);

  DateTime clock() => DateTime(2026, 10, 8, 10);

  final fix = find.byKey(const ValueKey<String>('week-picker-fix'));
  final weekSheet = find.byKey(const ValueKey<String>('week-number-sheet'));
  final weekSheetConfirm = find.byKey(
    const ValueKey<String>('week-number-confirm'),
  );
  Finder chip(int w) => find.byKey(ValueKey<String>('week-number-$w'));

  Future<(AppState, ThemeController)> seeded(
    WidgetTester tester, {
    DateTime? start,
  }) => loadState(
    tester,
    seed: start == null
        ? null
        : (s) => s.addTimetable(
            Timetable(
              id: 'tt',
              name: '我的课表',
              config: ScheduleConfig(
                name: '2026-2027 秋',
                startDate: start,
                totalWeeks: 18,
              ),
              courses: <Course>[
                Course(
                  id: 'c1',
                  name: '高等数学',
                  day: 4,
                  startPeriod: 1,
                  endPeriod: 2,
                  weeks: <int>[for (var w = 1; w <= 18; w++) w],
                ),
              ],
            ),
          ),
  );

  Future<void> pumpWeek(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
  ) async {
    await pumpApp(tester, state, controller, WeekViewPage(clock: clock));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settleWithRealIo(tester, rounds: 5);
  }

  int pageWeek(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!.round() +
      1;

  String fixLabel(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: fix, matching: find.byType(Text)))
      .data!;

  bool selected(WidgetTester tester, int w) =>
      tester.widget<ChoiceChip>(chip(w)).selected;

  testWidgets(
    '开学日期错设成本周（10/5）：点「第 1 周」→「本周不是第 1 周？」→ 选第 4 周 → 9/14 开学、回到第 4 周',
    (tester) async {
      final (state, controller) = await seeded(
        tester,
        start: DateTime(2026, 10, 5),
      );
      await pumpWeek(tester, state, controller);
      expect(find.text('第 1 周'), findsOneWidget);
      final expandIcon = tester.widget<Icon>(find.byIcon(Icons.expand_more));
      expect(expandIcon.size, 16);
      expect(expandIcon.color, controller.current.colors.headerText);

      await tester.tap(find.text('第 1 周'));
      await tester.pumpAndSettle();
      expect(find.text('选择周次'), findsOneWidget);
      expect(fixLabel(tester), '本周不是第 1 周？点这里校正');

      await tester.tap(fix);
      await tester.pumpAndSettle();
      expect(find.text('选择周次'), findsNothing);
      expect(weekSheet, findsOneWidget);
      expect(find.text('现在是第几周？'), findsOneWidget);
      expect(selected(tester, 1), isTrue, reason: '预选按现在的开学日期算出的周次');

      await tester.tap(chip(4));
      await tester.pumpAndSettle();
      await tester.tap(weekSheetConfirm);
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();

      expect(state.currentConfig.startDate, DateTime(2026, 9, 14));
      expect(state.settings.termStartConfirmed['tt'], '2026-09-14');
      expect(find.text('已把本周设为第 4 周'), findsOneWidget);
      expect(find.text('第 4 周'), findsOneWidget);
      expect(pageWeek(tester), 4);
      expect(find.text('回到本周'), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets('关掉「现在是第几周？」面板 → 什么都不改', (tester) async {
    final (state, controller) = await seeded(
      tester,
      start: DateTime(2026, 10, 5),
    );
    await pumpWeek(tester, state, controller);
    await tester.tap(find.text('第 1 周'));
    await tester.pumpAndSettle();
    await tester.tap(fix);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(450, 20));
    await settleWithRealIo(tester, rounds: 5);
    await tester.pumpAndSettle();
    expect(weekSheet, findsNothing);
    expect(state.currentConfig.startDate, DateTime(2026, 10, 5));
    expect(find.textContaining('已把本周设为'), findsNothing);
    await unmount(tester);
  });

  testWidgets('还没开学（今天在第 1 周之前）：菜单「选择 / 校正周次」里也有这一行，说「现在是第几周？」，不预选', (
    tester,
  ) async {
    final (state, controller) = await seeded(
      tester,
      start: DateTime(2026, 10, 19),
    );
    await pumpWeek(tester, state, controller);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择 / 校正周次'));
    await tester.pumpAndSettle();
    expect(fixLabel(tester), '现在是第几周？点这里校正');

    await tester.tap(fix);
    await tester.pumpAndSettle();
    for (var w = 1; w <= 18; w++) {
      expect(selected(tester, w), isFalse, reason: '第 $w 周');
    }
    await tester.tap(chip(4));
    await tester.pumpAndSettle();
    await tester.tap(weekSheetConfirm);
    await settleUntil(tester, find.text('已把本周设为第 4 周'));
    await tester.pumpAndSettle();
    expect(state.currentConfig.startDate, DateTime(2026, 9, 14));
    expect(find.text('已把本周设为第 4 周'), findsOneWidget);
    expect(pageWeek(tester), 4);
    await unmount(tester);
  });

  testWidgets('一张课表都没有 → 「选择周次」里没有校正这一行', (tester) async {
    final (state, controller) = await seeded(tester);
    await pumpWeek(tester, state, controller);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择 / 校正周次'));
    await tester.pumpAndSettle();
    expect(find.text('选择周次'), findsOneWidget);
    expect(fix, findsNothing);
    await unmount(tester);
  });

  testWidgets(
    'R2-3：HomeShell → 齿轮 → 学期设置 →「按当前周次设置」选 4 → 返回两次 → 头部「第 4 周」且页面在第 4 周；切换课表也回到本周',
    (tester) async {
      final (state, controller) = await loadState(
        tester,
        seed: (s) async {
          await s.addTimetable(
            Timetable(
              id: 't1',
              name: '表一',
              config: ScheduleConfig(
                name: '2026 秋',
                startDate: DateTime(2026, 10, 5), // 第 1 周
                totalWeeks: 18,
              ),
              courses: <Course>[
                Course(
                  id: 'c1',
                  name: '表一课',
                  day: 4,
                  startPeriod: 1,
                  endPeriod: 2,
                ),
              ],
            ),
          );
          await s.addTimetable(
            Timetable(
              id: 't2',
              name: '表二',
              config: ScheduleConfig(
                name: '2026 秋',
                startDate: DateTime(2026, 8, 31), // 10/8 是第 6 周
                totalWeeks: 18,
              ),
              courses: <Course>[
                Course(
                  id: 'c2',
                  name: '表二课',
                  day: 4,
                  startPeriod: 1,
                  endPeriod: 2,
                ),
              ],
            ),
          );
          await s.switchTimetable('t1');
          await s.setLastUpdateCheck(DateTime(2026, 10, 8, 8));
        },
      );
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(
          clock: clock,
          holidayRepository: FakeHolidayRepository(data: HolidayPresets.empty),
        ),
      );
      await settleWithRealIo(tester, rounds: 5);
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);
      expect(pageWeek(tester), 1);

      // 齿轮 → 学期设置 →「按当前周次设置」→ 选 4 → 确定 → 返回两次。
      await tester.tap(find.byKey(const ValueKey<String>('week-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('学期设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('term-set-by-week')));
      await tester.pumpAndSettle();
      await tester.tap(chip(4));
      await tester.pumpAndSettle();
      await tester.tap(weekSheetConfirm);
      await settleUntil(tester, find.text('已把本周设为第 4 周'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('第 4 周'), findsOneWidget);
      expect(pageWeek(tester), 4);
      expect(find.text('回到本周'), findsNothing);

      // 切换到表二（8/31 开学，10/8 是第 6 周）→ 自动跳到第 6 周。
      await tester.runAsync(() => state.switchTimetable('t2'));
      await tester.pumpAndSettle();
      expect(find.text('第 6 周'), findsOneWidget);
      expect(pageWeek(tester), 6);
      await unmount(tester);
    },
  );
}
