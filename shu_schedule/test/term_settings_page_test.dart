import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/features/import/adapters/school_registry.dart';
import 'package:shu_schedule/features/settings/term_settings_page.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/fake_holiday_repository.dart';
import 'helpers/harness.dart';

/// v1.5.0（PLAN-1.5 D8）：学期设置页——「按当前周次设置」，以及只列本校校历的「学校校历」
/// （替换原来的「一键套用预设」内置示例学期）。今天固定 2026-10-08。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = TempStorage();
  setUp(() => storage.setUp('term_settings_page'));
  tearDown(() async {
    SchoolRegistry.resetForTest();
    await storage.tearDown();
  });

  DateTime clock() => DateTime(2026, 10, 8, 10);
  final bundled = HolidayPresets.fromJson(
    jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map,
  );

  final byWeek = find.byKey(const ValueKey<String>('term-set-by-week'));
  final calendar = find.byKey(const ValueKey<String>('term-school-calendar'));

  Future<AppState> pumpPage(
    WidgetTester tester, {
    String? schoolId = 'shu',
    String termName = '我的学期',
    DateTime? start,
    bool withTimetable = true,
    FakeHolidayRepository? repo,
  }) async {
    final (state, controller) = await loadState(
      tester,
      seed: withTimetable
          ? (s) => s.addTimetable(
              Timetable(
                id: 'tt',
                name: '我的课表',
                schoolId: schoolId,
                config: ScheduleConfig(
                  name: termName,
                  startDate: start ?? DateTime(2026, 9, 14),
                  totalWeeks: 18,
                ),
              ),
            )
          : null,
    );
    await pumpApp(
      tester,
      state,
      controller,
      TermSettingsPage(
        holidays: repo ?? FakeHolidayRepository(data: bundled),
        clock: clock,
      ),
    );
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('有 schoolId：「上海大学校历」紧挨「按当前周次设置」下面，不覆盖用户学期名，点选带 SnackBar 与撤销', (
    tester,
  ) async {
    SchoolRegistry.loadFromJson(File('assets/schools.json').readAsStringSync());
    final state = await pumpPage(tester);

    expect(calendar, findsOneWidget);
    expect(find.text('上海大学校历'), findsOneWidget);
    expect(find.text('一键套用预设'), findsNothing);
    expect(find.text('2026-2027 学年秋季学期'), findsOneWidget);
    expect(find.text('2026-2027 学年春季学期'), findsOneWidget);
    // 位置：在「按当前周次设置」下面、「总周数」上面。
    expect(
      tester.getTopLeft(calendar).dy,
      greaterThan(tester.getTopLeft(byWeek).dy),
    );
    expect(
      tester.getTopLeft(calendar).dy,
      lessThan(tester.getTopLeft(find.text('总周数')).dy),
    );
    expect(
      find.text(exampleTermPresets.first.name),
      findsNothing,
      reason: '和假日表同一天开学的那条只留假日表的名字',
    );
    final autumn = find.byKey(
      const ValueKey<String>('term-calendar-2026-09-14'),
    );
    final spring = find.byKey(
      const ValueKey<String>('term-calendar-2027-02-22'),
    );
    expect(
      find.descendant(of: autumn, matching: find.byIcon(Icons.check)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: spring, matching: find.byIcon(Icons.check)),
      findsNothing,
    );
    expect(find.text('2027-02-22 开学 · 18 周'), findsOneWidget);

    // 点秋季 → SnackBar「已按校历设为 9月14日开学（现在第 4 周）」+ 确认标记。
    await tester.tap(autumn);
    await settleUntil(tester, find.text('已按校历设为 9月14日开学（现在第 4 周）'));
    expect(find.text('已按校历设为 9月14日开学（现在第 4 周）'), findsOneWidget);
    expect(state.currentConfig.name, '我的学期', reason: '保留用户自己起的学期名');
    expect(state.settings.termStartConfirmed['tt'], '2026-09-14');

    // 点春季 → 改到 2027-02-22，仍保留「我的学期」，点「撤销」还原。
    await tester.tap(spring);
    await settleUntil(tester, find.text('已按校历设为 2月22日开学（还没开学）'));
    await tester.pumpAndSettle();
    expect(state.currentConfig.startDate, DateTime(2027, 2, 22));
    expect(state.currentConfig.name, '我的学期');
    expect(state.currentConfig.totalWeeks, 18);
    expect(state.settings.termStartConfirmed['tt'], '2027-02-22');

    await tester.tap(find.text('撤销'));
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
    expect(state.currentConfig.startDate, DateTime(2026, 9, 14));
    expect(state.settings.termStartConfirmed['tt'], '2026-09-14');
  });

  testWidgets('学期名还是默认值（「我的课表」）时，点校历学期会一起换成校历学期名', (tester) async {
    SchoolRegistry.loadFromJson(File('assets/schools.json').readAsStringSync());
    final state = await pumpPage(
      tester,
      termName: '我的课表',
      start: DateTime(2026, 10, 5),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('term-calendar-2026-09-14')),
    );
    await settleUntil(tester, find.text('已按校历设为 9月14日开学（现在第 4 周）'));
    expect(state.currentConfig.name, '2026-2027 学年秋季学期');
  });

  testWidgets('没有 schoolId：没有「学校校历」，也不读假日表；「按当前周次设置」照样在', (tester) async {
    final repo = FakeHolidayRepository(data: bundled);
    await pumpPage(tester, schoolId: null, repo: repo);
    expect(calendar, findsNothing);
    expect(find.text('学校校历'), findsNothing);
    expect(find.text('一键套用预设'), findsNothing);
    expect(repo.loads, 0);
    expect(byWeek, findsOneWidget);
    expect(tester.widget<ListTile>(byWeek).enabled, isTrue);
  });

  testWidgets('学校没有校历（假日表、学校清单都没有）→ 不显示「学校校历」', (tester) async {
    await pumpPage(tester, schoolId: 'nope');
    expect(calendar, findsNothing);
  });

  testWidgets('「按当前周次设置」在开学日期下面、副标题动态；选第 4 周 → 开学日期 9月14日（周一），SnackBar', (
    tester,
  ) async {
    final state = await pumpPage(tester, start: DateTime(2026, 10, 5));
    final startTile = find.text('开学日期');
    expect(find.text('10月5日（周一）'), findsOneWidget);
    expect(
      tester.getTopLeft(byWeek).dy,
      greaterThan(tester.getTopLeft(startTile).dy),
    );
    expect(find.text('按当前周次设置'), findsOneWidget);
    expect(find.text('现在是第 1 周；不对就点这里改'), findsOneWidget);

    await tester.tap(byWeek);
    await tester.pumpAndSettle();
    expect(find.text('现在是第几周？'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey<String>('week-number-1')),
          )
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey<String>('week-number-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('week-number-confirm')));
    await settleUntil(tester, find.text('已把本周设为第 4 周'));
    await tester.pumpAndSettle();
    expect(state.currentConfig.startDate, DateTime(2026, 9, 14));
    expect(state.settings.termStartConfirmed['tt'], '2026-09-14');
    expect(find.text('9月14日（周一）'), findsOneWidget);
    expect(find.text('现在是第 4 周；不对就点这里改'), findsOneWidget);
    expect(find.text('已把本周设为第 4 周'), findsOneWidget);
  });

  testWidgets('没有课表 → 「按当前周次设置」禁用', (tester) async {
    await pumpPage(tester, withTimetable: false);
    expect(tester.widget<ListTile>(byWeek).enabled, isFalse);
    expect(calendar, findsNothing);
  });
}
