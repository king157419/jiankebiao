import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

/// v1.3.0 Phase A：同组课程改色同步、调休 / 休息带的 AppState 入口。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shu_app_state_group_test');
    Storage.overrideDirectory = dir;
  });

  tearDown(() async {
    Storage.overrideDirectory = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Course course(String id, {String? group, int color = 0, int day = 1}) =>
      Course(
        id: id,
        name: id,
        day: day,
        startPeriod: 1,
        endPeriod: 2,
        weeks: <int>[1],
        colorIndex: color,
        groupId: group,
      );

  Future<AppState> stateWith(List<Course> courses) async {
    final state = AppState();
    await state.load();
    await state.addTimetable(
      Timetable(
        id: 'tt',
        name: 'n',
        config: ScheduleConfig.defaults(),
        courses: courses,
      ),
    );
    return state;
  }

  int colorOf(AppState s, String id) =>
      s.currentTimetable!.courses.firstWhere((c) => c.id == id).colorIndex;

  test('改颜色：同组的其他时段一起改，别的组 / 无组不动', () async {
    final state = await stateWith(<Course>[
      course('a1', group: 'g', color: 1, day: 2),
      course('a2', group: 'g', color: 1, day: 4),
      course('b', group: 'h', color: 1),
      course('c', color: 1),
    ]);
    final a1 = state.currentTimetable!.courses.first;
    await state.updateCourse(a1.copyWith(colorIndex: 6));
    expect(colorOf(state, 'a1'), 6);
    expect(colorOf(state, 'a2'), 6);
    expect(colorOf(state, 'b'), 1);
    expect(colorOf(state, 'c'), 1);
    expect(state.coursesInGroup('g').map((c) => c.id), <String>['a1', 'a2']);

    // 落盘后 groupId 与同步后的颜色都在。
    final reread = AppState();
    await reread.load();
    expect(colorOf(reread, 'a2'), 6);
    expect(
      reread.currentTimetable!.courses.firstWhere((c) => c.id == 'a2').groupId,
      'g',
    );
  });

  test('只改别的字段不触发同步；syncGroupColor: false 可以单独改', () async {
    final state = await stateWith(<Course>[
      course('a1', group: 'g', color: 1),
      course('a2', group: 'g', color: 2),
    ]);
    final a1 = state.currentTimetable!.courses.first;
    await state.updateCourse(a1.copyWith(name: '改名'));
    expect(colorOf(state, 'a2'), 2, reason: '颜色没变就不去动同组');

    await state.updateCourse(
      state.currentTimetable!.courses.first.copyWith(colorIndex: 9),
      syncGroupColor: false,
    );
    expect(colorOf(state, 'a1'), 9);
    expect(colorOf(state, 'a2'), 2);
  });

  test('setDateOverride / setBreakAfter 改的是当前课表并落盘', () async {
    final state = await stateWith(<Course>[course('x')]);
    await state.setDateOverride(
      DateTime(2026, 10, 10),
      const DateOverride.actAs(weekday: 1, note: '补课'),
    );
    await state.setBreakAfter(<int>[4]);
    expect(
      state.currentConfig.overrideOn(DateTime(2026, 10, 10))!.actAsWeekday,
      1,
    );
    expect(state.currentConfig.breakAfter, <int>[4]);

    final reread = AppState();
    await reread.load();
    expect(reread.currentConfig.overrideOn(DateTime(2026, 10, 10))!.note, '补课');
    expect(reread.currentConfig.breakAfter, <int>[4]);

    await reread.setDateOverride(DateTime(2026, 10, 10), null);
    await reread.setBreakAfter(null);
    expect(reread.currentConfig.overrides, isEmpty);
    expect(reread.currentConfig.breakAfter, isNull);
  });
}
