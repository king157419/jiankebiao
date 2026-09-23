import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/features/timetable/course_editor_page.dart';
import 'package:shu_schedule/features/timetable/course_form.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/harness.dart';

/// v1.3.0 Phase C.2：手动录入提效——保存并继续添加、复制到其他星期、
/// 教师 / 教室历史补全、周视图空格子长按新建。
void main() {
  // ------------------------------------------------------------ 纯函数

  group('CourseForm.copiesToDays', () {
    final base = Course(
      id: 'base',
      name: '线性代数',
      teacher: '王老师',
      location: 'A101',
      day: 1,
      startPeriod: 3,
      endPeriod: 4,
      weeks: <int>[1, 2, 3],
      colorIndex: 5,
      source: 'zfsoft-shu',
      groupId: 'g1',
      externalKey: 'kch|jxb|1|3-4',
    );
    var seq = 0;
    String newId() => 'copy-${seq++}';

    test('副本共享同一个 groupId，其余字段照抄，externalKey 清空、来源改 manual', () {
      seq = 0;
      final copies = CourseForm.copiesToDays(
        base,
        <int>[3, 5],
        groupId: 'g1',
        newId: newId,
      );
      expect(copies.map((c) => c.day), <int>[3, 5]);
      expect(copies.map((c) => c.id), <String>['copy-0', 'copy-1']);
      for (final c in copies) {
        expect(c.groupId, 'g1');
        expect(c.name, '线性代数');
        expect(c.teacher, '王老师');
        expect(c.location, 'A101');
        expect(c.startPeriod, 3);
        expect(c.endPeriod, 4);
        expect(c.weeks, <int>[1, 2, 3]);
        expect(c.colorIndex, 5);
        expect(c.externalKey, isNull);
        expect(c.source, 'manual');
      }
    });

    test('跳过本课同一天、重复和越界的星期', () {
      final copies = CourseForm.copiesToDays(
        base,
        <int>[1, 2, 2, 0, 8, 7],
        groupId: 'g2',
        newId: newId,
      );
      expect(copies.map((c) => c.day), <int>[2, 7]);
      expect(copies.every((c) => c.groupId == 'g2'), isTrue);
    });
  });

  group('历史补全', () {
    final courses = <Course>[
      Course(
        id: '1',
        name: 'a',
        teacher: '张老师',
        location: 'A101',
        day: 1,
        startPeriod: 1,
        endPeriod: 1,
      ),
      Course(
        id: '2',
        name: 'b',
        teacher: ' 李老师 ',
        location: 'B202',
        day: 2,
        startPeriod: 1,
        endPeriod: 1,
      ),
      Course(
        id: '3',
        name: 'c',
        teacher: '李老师',
        location: 'A101',
        day: 3,
        startPeriod: 1,
        endPeriod: 1,
      ),
      Course(
        id: '4',
        name: 'd',
        teacher: '',
        day: 4,
        startPeriod: 1,
        endPeriod: 1,
      ),
    ];

    test('historyValues：去首尾空白后去重，出现次数多的在前，空值丢掉', () {
      expect(CourseForm.historyValues(courses, (c) => c.teacher), <String>[
        '李老师',
        '张老师',
      ]);
      expect(CourseForm.historyValues(courses, (c) => c.location), <String>[
        'A101',
        'B202',
      ]);
    });

    test('matchSuggestions：空输入不给候选；前缀优先；完全相同的不重复提示；忽略大小写', () {
      final options = <String>['A101', 'B-A1', 'a1 楼', 'C3'];
      expect(CourseForm.matchSuggestions(options, ''), isEmpty);
      expect(CourseForm.matchSuggestions(options, '  '), isEmpty);
      expect(CourseForm.matchSuggestions(options, 'a1'), <String>[
        'A101',
        'a1 楼',
        'B-A1',
      ]);
      expect(CourseForm.matchSuggestions(<String>['C3'], 'c3'), isEmpty);
      expect(
        CourseForm.matchSuggestions(<String>['x1', 'x2', 'x3'], 'x', limit: 2),
        <String>['x1', 'x2'],
      );
    });
  });

  // ------------------------------------------------------------ 编辑器

  final storage = TempStorage();
  setUp(() => storage.setUp('phase_c_course_entry'));
  tearDown(storage.tearDown);

  Future<void> seedTimetable(AppState s, {List<Course>? courses}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await s.addTimetable(
      Timetable(
        id: 'tt',
        name: '录入测试',
        config: ScheduleConfig(
          name: '学期',
          startDate: ScheduleUtils.mondayOf(today),
          totalWeeks: 16,
        ),
        courses: courses ?? <Course>[],
      ),
    );
  }

  Course? byName(AppState s, String name) {
    for (final c in s.currentTimetable!.courses) {
      if (c.name == name) return c;
    }
    return null;
  }

  testWidgets('保存并继续添加：留在本页，保留星期 / 节次 / 周次，清空课名教师教室，两门课不共享 groupId', (
    tester,
  ) async {
    final (state, controller) = await loadState(tester, seed: seedTimetable);
    await pumpApp(
      tester,
      state,
      controller,
      const CourseEditorPage(initialDay: 3, initialStartPeriod: 5),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('course-name')),
      '高等数学',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('course-teacher')),
        matching: find.byType(TextField),
      ),
      '张老师',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey<String>('course-location')),
        matching: find.byType(TextField),
      ),
      'A101',
    );
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('course-save-continue')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('course-save-continue')),
    );
    await settleWithRealIo(tester);

    // 仍在编辑器里，字段清空。
    expect(find.byType(CourseEditorPage), findsOneWidget);
    expect(find.textContaining('已添加「高等数学」'), findsOneWidget);
    final nameField = tester.widget<TextField>(
      find.byKey(const ValueKey<String>('course-name')),
    );
    expect(nameField.controller!.text, isEmpty);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    for (final f in fields) {
      expect(f.controller!.text, isEmpty);
    }

    final first = byName(state, '高等数学')!;
    expect(first.day, 3);
    expect(first.startPeriod, 5);
    expect(first.teacher, '张老师');
    expect(first.location, 'A101');
    expect(first.weeks.length, 16);

    // 第二门：只填课名，星期 / 节次沿用。
    await tester.enterText(
      find.byKey(const ValueKey<String>('course-name')),
      '大学英语',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('course-save-continue')),
    );
    await settleWithRealIo(tester);

    final second = byName(state, '大学英语')!;
    expect(second.day, 3);
    expect(second.startPeriod, 5);
    expect(second.endPeriod, 5);
    expect(second.weeks, first.weeks);
    expect(second.teacher, isNull);
    expect(second.id, isNot(first.id));
    expect(first.groupId, isNull);
    expect(second.groupId, isNull);
    expect(state.currentTimetable!.courses.length, 2);
  });

  testWidgets('复制到其他星期：一次生成 3 门课，共享同一个 groupId 与颜色；之后改色同组同步', (tester) async {
    final (state, controller) = await loadState(tester, seed: seedTimetable);
    await pumpApp(
      tester,
      state,
      controller,
      const CourseEditorPage(initialDay: 1, initialStartPeriod: 1),
    );

    await tester.enterText(
      find.byKey(const ValueKey<String>('course-name')),
      '体育',
    );
    await tester.pump();
    // 本课是周一，所以周一不在可选里。
    expect(find.byKey(const ValueKey<String>('copy-day-1')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('copy-day-3')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('copy-day-3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('copy-day-5')));
    await tester.pump();
    expect(find.textContaining('保存时会在周三、周五再各生成一门同样的课'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('course-save')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('course-save')));
    await settleWithRealIo(tester);

    final courses = state.currentTimetable!.courses;
    expect(courses.map((c) => c.day).toList()..sort(), <int>[1, 3, 5]);
    final groups = courses.map((c) => c.groupId).toSet();
    expect(groups.length, 1);
    expect(groups.single, isNotNull);
    expect(courses.map((c) => c.colorIndex).toSet().length, 1);
    expect(courses.map((c) => c.id).toSet().length, 3);
    expect(
      courses.every((c) => c.startPeriod == 1 && c.weeks.length == 16),
      isTrue,
    );

    // 改其中一门的颜色，同组一起变（Phase A 的 updateCourse 同步）。
    final monday = courses.firstWhere((c) => c.day == 1);
    await tester.runAsync(
      () => state.updateCourse(
        monday.copyWith(colorIndex: (monday.colorIndex + 1) % 10),
      ),
    );
    expect(
      state.currentTimetable!.courses.map((c) => c.colorIndex).toSet(),
      <int>{(monday.colorIndex + 1) % 10},
    );
  });

  testWidgets('编辑已有课程并复制到其他星期：原课被分到新组，副本同组', (tester) async {
    final existing = Course(
      id: 'c1',
      name: '物理',
      day: 2,
      startPeriod: 3,
      endPeriod: 4,
      weeks: <int>[1, 2],
      colorIndex: 2,
    );
    final (state, controller) = await loadState(
      tester,
      seed: (s) => seedTimetable(s, courses: <Course>[existing]),
    );
    await pumpApp(
      tester,
      state,
      controller,
      CourseEditorPage(course: existing),
    );
    // 编辑模式没有「保存并继续添加」。
    expect(
      find.byKey(const ValueKey<String>('course-save-continue')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('copy-day-4')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('copy-day-4')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('course-save')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('course-save')));
    await settleWithRealIo(tester);

    final courses = state.currentTimetable!.courses;
    expect(courses.length, 2);
    final original = courses.firstWhere((c) => c.id == 'c1');
    final copy = courses.firstWhere((c) => c.id != 'c1');
    expect(original.groupId, isNotNull);
    expect(copy.groupId, original.groupId);
    expect(copy.day, 4);
    expect(copy.colorIndex, 2);
  });

  testWidgets('教师输入框给出本课表已有值的补全候选，点选后填入', (tester) async {
    final (state, controller) = await loadState(
      tester,
      seed: (s) => seedTimetable(
        s,
        courses: <Course>[
          Course(
            id: 'x',
            name: '旧课',
            teacher: '张三丰',
            location: '东区 D301',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
          ),
        ],
      ),
    );
    await pumpApp(tester, state, controller, const CourseEditorPage());

    final teacherField = find.descendant(
      of: find.byKey(const ValueKey<String>('course-teacher')),
      matching: find.byType(TextField),
    );
    await tester.tap(teacherField);
    await tester.enterText(teacherField, '张');
    await tester.pumpAndSettle();
    expect(find.text('张三丰'), findsOneWidget);
    await tester.tap(find.text('张三丰'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(teacherField).controller!.text, '张三丰');

    final locationField = find.descendant(
      of: find.byKey(const ValueKey<String>('course-location')),
      matching: find.byType(TextField),
    );
    await tester.tap(locationField);
    await tester.enterText(locationField, 'd3');
    await tester.pumpAndSettle();
    expect(find.text('东区 D301'), findsOneWidget);
  });

  // ------------------------------------------------------------ 周视图长按

  testWidgets('周视图：长按空格子打开新建课程并带入星期与节次；长按已有课的格子不打开编辑器', (tester) async {
    final (state, controller) = await loadState(
      tester,
      seed: (s) => seedTimetable(
        s,
        courses: <Course>[
          Course(
            id: 'busy',
            name: '占位课',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[for (var w = 1; w <= 16; w++) w],
          ),
        ],
      ),
    );
    await pumpApp(tester, state, controller, const WeekViewPage());

    // 已有课的格子：课程块盖在上面，长按和以前一样（按下松开 = 点开详情），
    // 不会打开新建课程。
    await tester.longPress(find.text('占位课'));
    await tester.pumpAndSettle();
    expect(find.byType(CourseEditorPage), findsNothing);
    // 关掉详情 sheet。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 空格子：周三第 5 节。
    final cell = find.byKey(const ValueKey<String>('cell-3-5'));
    await tester.ensureVisible(cell);
    await tester.longPress(cell);
    await tester.pumpAndSettle();
    expect(find.byType(CourseEditorPage), findsOneWidget);
    final editor = tester.widget<CourseEditorPage>(
      find.byType(CourseEditorPage),
    );
    expect(editor.initialDay, 3);
    expect(editor.initialStartPeriod, 5);
    expect(editor.course, isNull);
    expect(find.text('新建课程'), findsOneWidget);
    expect(find.text('周三'), findsWidgets);
    expect(find.text('第 5 节'), findsNWidgets(2)); // 起始 + 结束
  });
}
