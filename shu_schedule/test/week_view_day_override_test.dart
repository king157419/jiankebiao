import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/features/settings/date_override_editor.dart';
import 'package:shu_schedule/features/timetable/day_override_sheet.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/fake_holiday_repository.dart';
import 'helpers/harness.dart';

/// v1.4.0 任务 E2：周视图长按列头设调休 / 停课、「休」「补」角标、按周显示周末。
///
/// 时钟固定在 2026-10-07（周三，第 4 周：10/5-10/11），开学 2026-09-14。
void main() {
  final now = DateTime(2026, 10, 7, 10);
  DateTime fixedClock() => now;
  const weekdayCourseNames = <String>['', '周一课', '周二课', '周三课', '周四课', '周五课'];

  Timetable timetable({
    Map<String, DateOverride>? overrides,
    bool showWeekend = false,
    String? schoolId,
  }) => Timetable(
    id: 'tt',
    name: '长按测试',
    schoolId: schoolId,
    config: ScheduleConfig(
      name: '2026 秋',
      startDate: DateTime(2026, 9, 14),
      totalWeeks: 18,
      showWeekend: showWeekend,
      overrides: overrides,
    ),
    courses: <Course>[
      for (var d = 1; d <= 5; d++)
        Course(
          id: 'c$d',
          name: weekdayCourseNames[d],
          day: d,
          startPeriod: 1,
          endPeriod: 2,
          weeks: <int>[for (var w = 1; w <= 18; w++) w],
        ),
    ],
  );

  /// 学校数据：10/10 周六按 10/7（周三）上课；10/6 停课。国家数据：国庆 10/1-10/7 放假、10/10 上班。
  final presets = HolidayPresets.fromJson(<String, dynamic>{
    'version': 1,
    'updatedAt': '2026-10-06',
    'national': <String, dynamic>{
      '2026': <String, dynamic>{
        'holidays': <dynamic>[
          <String, dynamic>{
            'name': '国庆节',
            'off': <String>[for (var d = 1; d <= 7; d++) '2026-10-0$d'],
            'work': <String>['2026-10-10'],
          },
        ],
      },
    },
    'schools': <String, dynamic>{
      'demo': <String, dynamic>{
        'name': '示例大学',
        'terms': <dynamic>[
          <String, dynamic>{
            'id': '2026-autumn',
            'name': '2026 秋',
            'startDate': '2026-09-14',
            'totalWeeks': 18,
            'entries': <dynamic>[
              <String, dynamic>{
                'date': '2026-10-06',
                'cancelled': true,
                'note': '国庆节放假',
              },
              <String, dynamic>{
                'date': '2026-10-10',
                'actAsDate': '2026-10-07',
                'note': '国庆调休，上 10 月 7 日（周三）的课',
              },
            ],
          },
        ],
      },
    },
  });

  Finder header(String date) => find.byKey(ValueKey<String>('weekday-$date'));
  Finder badge(String date) => find.byKey(ValueKey<String>('override-$date'));
  Finder sheetKey(String k) => find.byKey(ValueKey<String>(k));

  /// [block] 的中心落在 [column] 这一列列头的左右边界之内。
  void expectInColumn(WidgetTester tester, Finder block, Finder column) {
    final x = tester.getCenter(block).dx;
    final rect = tester.getRect(column);
    expect(x, inInclusiveRange(rect.left, rect.right));
  }

  int headerCount() => find
      .byWidgetPredicate(
        (w) =>
            w is InkWell &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('weekday-'),
      )
      .evaluate()
      .length;

  group('纯函数', () {
    test('EffectiveDay.badge：停课「休」、调休「补」、只有备注 / 没有设置为 null；label 不变', () {
      final config = timetable(
        overrides: <String, DateOverride>{
          '2026-10-01': const DateOverride.cancelled(note: '国庆'),
          '2026-10-10': DateOverride.actAs(weekday: 1),
          '2026-10-11': DateOverride.actAs(week: 3),
          '2026-10-12': const DateOverride(note: '只是备注'),
        },
      ).config;
      String? b(int m, int d) =>
          ScheduleUtils.effectiveDayOf(DateTime(2026, m, d), config).badge;
      expect(b(10, 1), '休');
      expect(b(10, 10), '补');
      expect(b(10, 11), '补');
      expect(b(10, 12), isNull);
      expect(b(10, 13), isNull);
      // 今日页 / 小组件 / Kotlin 仍然用「停课」/「调休」。
      expect(
        ScheduleUtils.effectiveDayOf(DateTime(2026, 10, 1), config).label,
        '停课',
      );
      expect(
        ScheduleUtils.effectiveDayOf(DateTime(2026, 10, 10), config).label,
        '调休',
      );
    });

    test('面板标题与当前状态文案', () {
      final config = timetable().config;
      expect(
        dayOverrideSheetTitle(DateTime(2026, 10, 8), config),
        '10月8日 周四 · 第 4 周',
      );
      expect(
        dayOverrideSheetTitle(DateTime(2026, 9, 1), config),
        '9月1日 周二 · 不在本学期',
      );
      final withOverrides = timetable(
        overrides: <String, DateOverride>{
          '2026-10-08': const DateOverride.cancelled(note: '运动会'),
          '2026-10-10': DateOverride.actAs(weekday: 1),
        },
      ).config;
      expect(
        dayOverrideStateText(
          ScheduleUtils.effectiveDayOf(DateTime(2026, 10, 8), withOverrides),
          courseCount: 0,
        ),
        '当前：停课（运动会）',
      );
      expect(
        dayOverrideStateText(
          ScheduleUtils.effectiveDayOf(DateTime(2026, 10, 10), withOverrides),
          courseCount: 1,
        ),
        '当前：调休，按周一上课 · 当天 1 节课',
      );
      expect(
        dayOverrideStateText(
          ScheduleUtils.effectiveDayOf(DateTime(2026, 10, 11), withOverrides),
          courseCount: 0,
        ),
        '当前：按原课表上课 · 当天没有课',
      );
    });

    test('daySuggestionOf：学校条目（按某天上课 / 停课）、国家放假与调休上班日、没有建议', () {
      final school = timetable(schoolId: 'demo').config;
      final makeUp = daySuggestionOf(
        presets,
        school,
        DateTime(2026, 10, 10),
        schoolId: 'demo',
      )!;
      expect(makeUp.title, '假期表建议：按 10/7（周三）课表上课');
      expect(makeUp.detail, '国庆调休，上 10 月 7 日（周三）的课 · 示例大学');
      expect(
        makeUp.override,
        DateOverride.actAs(week: 4, weekday: 3, note: '国庆调休，上 10 月 7 日（周三）的课'),
      );
      expect(makeUp.alreadyApplied, isFalse);
      final off = daySuggestionOf(
        presets,
        school,
        DateTime(2026, 10, 6),
        schoolId: 'demo',
      )!;
      expect(off.title, '假期表建议：停课（国庆节）');
      expect(off.override, const DateOverride.cancelled(note: '国庆节放假'));
      expect(
        daySuggestionOf(
          presets,
          school,
          DateTime(2026, 10, 8),
          schoolId: 'demo',
        ),
        isNull,
      );

      // 没有学校：国家安排。
      final plain = timetable().config;
      final national = daySuggestionOf(presets, plain, DateTime(2026, 10, 2))!;
      expect(national.title, '假期表建议：停课（国庆节）');
      expect(national.override!.cancelled, isTrue);
      final work = daySuggestionOf(presets, plain, DateTime(2026, 10, 10))!;
      expect(work.title, '假期表建议：国家调休上班日');
      expect(work.override, isNull);

      // 已经是这个设置。
      final applied = timetable(
        schoolId: 'demo',
        overrides: <String, DateOverride>{
          '2026-10-06': const DateOverride.cancelled(note: '国庆节放假'),
        },
      ).config;
      expect(
        daySuggestionOf(
          presets,
          applied,
          DateTime(2026, 10, 6),
          schoolId: 'demo',
        )!.alreadyApplied,
        isTrue,
      );
    });
  });

  group('周视图长按列头', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('v140_week_long_press'));
    tearDown(storage.tearDown);

    Future<AppState> pumpWeek(
      WidgetTester tester, {
      required Timetable tt,
      HolidayPresets? data,
    }) async {
      final (state, controller) = await loadState(
        tester,
        seed: (s) => s.addTimetable(tt),
      );
      await pumpApp(
        tester,
        state,
        controller,
        WeekViewPage(
          clock: fixedClock,
          holidayRepository: FakeHolidayRepository(
            data: data ?? HolidayPresets.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return state;
    }

    Future<void> openSheet(WidgetTester tester, String date) async {
      await tester.longPress(header(date));
      await tester.pumpAndSettle();
      expect(sheetKey('override-sheet'), findsOneWidget);
    }

    testWidgets('长按 10/8 列头：弹出面板，标题「10月8日 周四 · 第 4 周」和当前状态', (tester) async {
      await pumpWeek(tester, tt: timetable());
      expect(headerCount(), 5);
      await openSheet(tester, '2026-10-08');
      expect(find.text('10月8日 周四 · 第 4 周'), findsOneWidget);
      expect(find.text('当前：按原课表上课 · 当天 1 节课'), findsOneWidget);
      // 没有假期表建议、没有已有设置 → 不显示这两行。
      expect(sheetKey('override-sheet-suggest'), findsNothing);
      expect(sheetKey('override-sheet-clear'), findsNothing);
      expect(sheetKey('override-sheet-cancel'), findsOneWidget);
      expect(sheetKey('override-sheet-actas'), findsOneWidget);
      expect(find.text('编辑…'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('「设为停课」一键生效：列头显示「休」、课程消失；SnackBar 撤销恢复', (tester) async {
      final state = await pumpWeek(tester, tt: timetable());
      expect(find.text('周四课'), findsOneWidget);
      await openSheet(tester, '2026-10-08');
      await tester.tap(sheetKey('override-sheet-cancel'));
      await settleUntil(tester, find.text('已把 10月8日 设为停课'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(sheetKey('override-sheet'), findsNothing);
      expect(
        state.currentConfig.overrideOn(DateTime(2026, 10, 8)),
        const DateOverride.cancelled(),
      );
      expect(
        find.descendant(of: badge('2026-10-08'), matching: find.text('休')),
        findsOneWidget,
      );
      expect(find.text('周四课'), findsNothing);
      expect(find.text('已把 10月8日 设为停课'), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await settleWithRealIo(tester);
      expect(state.currentConfig.overrideOn(DateTime(2026, 10, 8)), isNull);
      expect(badge('2026-10-08'), findsNothing);
      expect(find.text('周四课'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('已有设置时有「清除」：一键删掉，角标消失', (tester) async {
      final state = await pumpWeek(
        tester,
        tt: timetable(
          overrides: <String, DateOverride>{
            '2026-10-08': const DateOverride.cancelled(note: '运动会'),
          },
        ),
      );
      expect(
        find.descendant(of: badge('2026-10-08'), matching: find.text('休')),
        findsOneWidget,
      );
      await openSheet(tester, '2026-10-08');
      expect(find.text('当前：停课（运动会）'), findsOneWidget);
      // 已经是停课 →「设为停课」不可点。
      final cancelTile = tester.widget<ListTile>(
        sheetKey('override-sheet-cancel'),
      );
      expect(cancelTile.enabled, isFalse);

      await tester.tap(sheetKey('override-sheet-clear'));
      await settleUntil(tester, find.text('已清除 10月8日 的设置'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.currentConfig.overrideOn(DateTime(2026, 10, 8)), isNull);
      expect(badge('2026-10-08'), findsNothing);
      expect(find.text('已清除 10月8日 的设置'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('假期表建议（学校条目）：长按周六 10/10，一键按 10/7（周三）上课，列头显示「补」', (
      tester,
    ) async {
      final state = await pumpWeek(
        tester,
        tt: timetable(schoolId: 'demo', showWeekend: true),
        data: presets,
      );
      expect(find.text('周三课'), findsOneWidget);
      await openSheet(tester, '2026-10-10');
      expect(sheetKey('override-sheet-suggest'), findsOneWidget);
      expect(find.text('假期表建议：按 10/7（周三）课表上课'), findsOneWidget);
      await tester.tap(sheetKey('override-sheet-suggest'));
      await settleUntil(tester, find.textContaining('已按假期表把 10月10日 设为'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        state.currentConfig.overrideOn(DateTime(2026, 10, 10)),
        DateOverride.actAs(week: 4, weekday: 3, note: '国庆调休，上 10 月 7 日（周三）的课'),
      );
      expect(
        find.descendant(of: badge('2026-10-10'), matching: find.text('补')),
        findsOneWidget,
      );
      // 周三课在 10/7 和补课的 10/10 各出现一次。
      expect(find.text('周三课'), findsNWidgets(2));
      expect(find.textContaining('已按假期表把 10月10日 设为'), findsOneWidget);

      // 再长按：建议已经套用过，这一行不可点。
      await openSheet(tester, '2026-10-10');
      expect(
        tester.widget<ListTile>(sheetKey('override-sheet-suggest')).enabled,
        isFalse,
      );
      expect(find.text('已是这个设置'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('「调休：按某天课表上课」打开编辑器并预置按星期模式，保存后写入', (tester) async {
      final state = await pumpWeek(tester, tt: timetable(showWeekend: true));
      await openSheet(tester, '2026-10-10');
      await tester.tap(sheetKey('override-sheet-actas'));
      await tester.pumpAndSettle();

      expect(find.byType(DateOverrideEditorPage), findsOneWidget);
      expect(find.text('添加调休 / 停课'), findsOneWidget);
      expect(find.text('2026-10-10 周六'), findsOneWidget);
      // 预置 weekday 模式：必填的星期下拉框在。
      expect(find.text('按星期几的课上 *'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('override-weekday')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('周一').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('override-save')));
      await tester.pumpAndSettle();
      await settleWithRealIo(tester);

      expect(
        state.currentConfig.overrideOn(DateTime(2026, 10, 10)),
        DateOverride.actAs(weekday: 1),
      );
      expect(find.byType(DateOverrideEditorPage), findsNothing);
      expect(
        find.descendant(of: badge('2026-10-10'), matching: find.text('补')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('假期表建议（国家调休上班日）：没有可直接套用的规则，点了打开按星期上课的编辑器', (tester) async {
      final state = await pumpWeek(
        tester,
        tt: timetable(showWeekend: true),
        data: presets,
      );
      await openSheet(tester, '2026-10-10');
      expect(find.text('假期表建议：国家调休上班日'), findsOneWidget);
      await tester.tap(sheetKey('override-sheet-suggest'));
      await tester.pumpAndSettle();
      expect(find.byType(DateOverrideEditorPage), findsOneWidget);
      expect(find.text('按星期几的课上 *'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(state.currentConfig.overrideOn(DateTime(2026, 10, 10)), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('「编辑…」打开完整编辑器，已有设置时是编辑模式', (tester) async {
      await pumpWeek(
        tester,
        tt: timetable(
          overrides: <String, DateOverride>{
            '2026-10-08': const DateOverride.cancelled(note: '运动会'),
          },
        ),
      );
      await openSheet(tester, '2026-10-08');
      await tester.tap(find.text('编辑…'));
      await tester.pumpAndSettle();
      expect(find.text('编辑调休 / 停课'), findsOneWidget);
      expect(find.text('2026-10-08 周四'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(DateOverrideEditorPage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('隐藏周末时按周显示：有补课的周六单独出一列，下一周回到 5 列', (tester) async {
      final state = await pumpWeek(
        tester,
        tt: timetable(
          overrides: <String, DateOverride>{
            '2026-10-10': DateOverride.actAs(weekday: 1, note: '国庆调休'),
          },
        ),
      );
      expect(tester.takeException(), isNull);
      // 第 4 周：周一到周五 + 周六（补课），周日没有课也没有设置 → 不显示。
      expect(header('2026-10-10'), findsOneWidget);
      expect(header('2026-10-11'), findsNothing);
      expect(headerCount(), 6);
      expect(
        find.descendant(of: badge('2026-10-10'), matching: find.text('补')),
        findsOneWidget,
      );
      // 补课那天画的是周一的课，而且和列头对齐（列头和网格用同一份列表）。
      expect(find.text('周一课'), findsNWidgets(2));
      expectInColumn(tester, find.text('周一课').last, header('2026-10-10'));

      // 周六可以直接长按。
      await tester.longPress(header('2026-10-10'));
      await tester.pumpAndSettle();
      expect(find.text('10月10日 周六 · 第 4 周'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // 点遮罩关掉面板
      await tester.pumpAndSettle();
      expect(sheetKey('override-sheet'), findsNothing);

      // 下一周：没有周末课 / 设置 → 5 列，没有报错。
      await tester.tap(find.byTooltip('下一周'));
      await tester.pumpAndSettle();
      expect(find.text('第 5 周'), findsOneWidget);
      expect(headerCount(), 5);
      expect(header('2026-10-17'), findsNothing);
      expect(header('2026-10-16'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // 第 5 周周五的课和周五列头对齐（列宽按 5 列分）。
      expectInColumn(tester, find.text('周五课'), header('2026-10-16'));

      // 再翻回来又是 6 列。
      await tester.tap(find.byTooltip('上一周'));
      await tester.pumpAndSettle();
      expect(headerCount(), 6);
      expect(tester.takeException(), isNull);

      // 设置里打开显示周末 → 每周都是 7 列。
      await tester.runAsync(
        () =>
            state.updateConfig(state.currentConfig.copyWith(showWeekend: true)),
      );
      await tester.pumpAndSettle();
      expect(headerCount(), 7);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('隐藏周末：原本没课的周日停课不出列（P3-1）；周六有课照常显示', (tester) async {
      final tt = timetable(
        overrides: <String, DateOverride>{
          '2026-10-11': const DateOverride.cancelled(),
        },
      );
      tt.courses.add(
        Course(
          id: 'sat',
          name: '周六课',
          day: 6,
          startPeriod: 3,
          endPeriod: 4,
          weeks: const <int>[4],
        ),
      );
      await pumpWeek(tester, tt: tt);
      expect(headerCount(), 6);
      expect(header('2026-10-10'), findsOneWidget);
      expect(header('2026-10-11'), findsNothing);
      expect(badge('2026-10-11'), findsNothing);
      expect(find.text('周六课'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('隐藏周末 + 10/3 周六、10/4 周日停课且原本无课 → 第 3 周仍是 5 列（测试缺口 6）', (
      tester,
    ) async {
      final tt = timetable(
        overrides: <String, DateOverride>{
          '2026-10-03': const DateOverride.cancelled(note: '国庆节'),
          '2026-10-04': const DateOverride.cancelled(note: '国庆节'),
        },
      );
      await pumpWeek(tester, tt: tt);
      await tester.tap(find.byTooltip('上一周'));
      await tester.pumpAndSettle();
      expect(find.text('第 3 周'), findsOneWidget);
      expect(headerCount(), 5);
      expect(header('2026-10-03'), findsNothing);
      expect(header('2026-10-04'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('隐藏周末：原本有课的周六停课照样出列，带「休」', (tester) async {
      final tt = timetable(
        overrides: <String, DateOverride>{
          '2026-10-03': const DateOverride.cancelled(note: '国庆节'),
        },
      );
      tt.courses.add(
        Course(
          id: 'sat3',
          name: '第 3 周周六课',
          day: 6,
          startPeriod: 1,
          endPeriod: 2,
          weeks: const <int>[3],
        ),
      );
      await pumpWeek(tester, tt: tt);
      await tester.tap(find.byTooltip('上一周'));
      await tester.pumpAndSettle();
      expect(headerCount(), 6);
      expect(header('2026-10-03'), findsOneWidget);
      expect(
        find.descendant(of: badge('2026-10-03'), matching: find.text('休')),
        findsOneWidget,
      );
      expect(find.text('第 3 周周六课'), findsNothing, reason: '停课了，不画课');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('没有课表时列头不响应长按（没有地方存）', (tester) async {
      final (state, controller) = await loadState(tester);
      await pumpApp(
        tester,
        state,
        controller,
        WeekViewPage(
          clock: fixedClock,
          holidayRepository: FakeHolidayRepository(data: HolidayPresets.empty),
        ),
      );
      await tester.pumpAndSettle();
      expect(state.currentTimetable, isNull);
      final cells = find.byWidgetPredicate(
        (w) =>
            w is InkWell &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('weekday-'),
      );
      expect(cells, findsNWidgets(7));
      expect(
        tester.widgetList<InkWell>(cells).every((w) => w.onLongPress == null),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
