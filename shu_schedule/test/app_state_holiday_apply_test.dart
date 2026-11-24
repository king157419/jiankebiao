import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/harness.dart';

/// v1.3.1：`AppState.applyDateOverrides`（「套用节假日安排」一次写入多天）。
void main() {
  final storage = TempStorage();
  setUp(() => storage.setUp('holiday_apply_state_test'));
  tearDown(storage.tearDown);

  Future<AppState> seeded({Map<String, DateOverride>? overrides}) async {
    final state = AppState();
    await state.load();
    await state.addTimetable(
      Timetable(
        id: 'tt',
        name: '秋季',
        schoolId: 'shu',
        config: ScheduleConfig(
          name: '2026 秋',
          startDate: DateTime(2026, 9, 14),
          totalWeeks: 18,
          overrides: overrides,
        ),
      ),
    );
    return state;
  }

  test('一次写入全部条目（只通知 / 保存一次），无关的手动设置原样保留', () async {
    const manual = DateOverride.cancelled(note: '运动会');
    final state = await seeded(
      overrides: <String, DateOverride>{
        '2026-11-06': manual,
        '2026-10-02': const DateOverride.cancelled(note: '旧备注'),
      },
    );
    final presets = HolidayPresets.fromJson(
      jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map,
    );
    final items = presets.suggestionsFor(
      config: state.currentConfig,
      schoolId: state.currentTimetable!.schoolId,
    );
    expect(items, hasLength(13));

    var notified = 0;
    state.addListener(() => notified++);
    await state.applyDateOverrides(<DateTime, DateOverride>{
      for (final s in items) s.date: s.override!,
    });
    expect(notified, 1);

    final overrides = state.currentConfig.overrides;
    expect(overrides, hasLength(14)); // 13 + 无关的 11/06
    expect(overrides['2026-11-06'], manual);
    expect(
      overrides['2026-10-02'],
      const DateOverride.cancelled(note: '国庆节放假'),
    );
    expect(
      overrides['2026-09-20'],
      DateOverride.actAs(week: 4, weekday: 2, note: '国庆调休，上 10 月 6 日（周二）的课'),
    );

    // 重新加载：已落盘。
    final reloaded = AppState();
    await reloaded.load();
    final again = reloaded.currentConfig.overrides;
    expect(again, hasLength(14));
    expect(again['2026-11-06'], manual);
    expect(again['2026-10-10']!.actAsWeek, 4);
    expect(again['2026-10-10']!.actAsWeekday, 3);
    expect(again['2027-01-01']!.cancelled, isTrue);
  });

  test('空表 / 没有课表时什么都不做', () async {
    final empty = AppState();
    await empty.load();
    var notified = 0;
    empty.addListener(() => notified++);
    await empty.applyDateOverrides(<DateTime, DateOverride>{
      DateTime(2026, 10, 1): const DateOverride.cancelled(),
    });
    expect(notified, 0);
    expect(empty.currentTimetable, isNull);

    final state = await seeded();
    state.addListener(() => notified++);
    await state.applyDateOverrides(const <DateTime, DateOverride>{});
    expect(notified, 0);
    expect(state.currentConfig.overrides, isEmpty);
  });

  test('timetableId 指定写到另一张课表', () async {
    final state = await seeded();
    await state.addTimetable(
      Timetable(
        id: 'other',
        name: '另一张',
        config: ScheduleConfig(name: 'x', startDate: DateTime(2026, 9, 14)),
      ),
      switchTo: false,
    );
    await state.applyDateOverrides(<DateTime, DateOverride>{
      DateTime(2026, 10, 1): const DateOverride.cancelled(note: 'a'),
    }, timetableId: 'other');
    expect(state.currentTimetable!.id, 'tt');
    expect(state.currentConfig.overrides, isEmpty);
    final other = state.timetables.firstWhere((t) => t.id == 'other');
    expect(other.config.overrides.keys, <String>['2026-10-01']);
  });
}
