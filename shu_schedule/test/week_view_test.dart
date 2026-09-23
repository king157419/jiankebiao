import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/features/timetable/today_page.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

/// 注意：`testWidgets` 的函数体跑在 fakeAsync 里，真正的磁盘 / asset I/O
/// 必须包在 `tester.runAsync` 里，否则 `await` 永远不返回。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shu_week_view_test');
    Storage.overrideDirectory = tempDir;
  });

  tearDown(() async {
    Storage.overrideDirectory = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 构造一个「今天正好落在第 1 周」的课表 + 已加载主题。
  Future<(AppState, ThemeController)> buildState({
    List<Course>? courses,
  }) async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final state = AppState();
    await state.load();
    await state.addTimetable(
      Timetable(
        id: 'tt-1',
        name: '测试课表',
        config: ScheduleConfig(
          name: '2026-2027 秋',
          startDate: monday,
          totalWeeks: 18,
        ),
        courses:
            courses ??
            <Course>[
              Course(
                id: 'c1',
                name: '高等数学 A(一)',
                teacher: '张老师',
                location: 'J101',
                day: now.weekday,
                startPeriod: 1,
                endPeriod: 2,
                weeks: <int>[for (var w = 1; w <= 18; w++) w],
                colorIndex: 3,
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

  testWidgets('周视图渲染出课程名、地点、教师和周次', (tester) async {
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      (state, controller) = await buildState();
    });
    await pumpPage(tester, state, controller, const WeekViewPage());

    expect(find.text('高等数学 A(一)'), findsOneWidget);
    expect(find.text('J101'), findsOneWidget);
    expect(find.text('张老师'), findsOneWidget);
    expect(find.text('第 1 周'), findsOneWidget);
    expect(find.text('测试课表'), findsOneWidget);
    // 左侧节次列：第 1 节起止时间。
    expect(find.text('08:00'), findsWidgets);
    // 午间 / 晚间分隔带。
    expect(find.text('午间休息'), findsOneWidget);
    expect(find.text('晚间休息'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('非本周课程默认隐藏，打开开关后显示', (tester) async {
    final now = DateTime.now();
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      (state, controller) = await buildState(
        courses: <Course>[
          Course(
            id: 'c-other',
            name: '只在第 5 周的课',
            day: now.weekday,
            startPeriod: 3,
            endPeriod: 4,
            weeks: const <int>[5],
          ),
        ],
      );
    });
    await pumpPage(tester, state, controller, const WeekViewPage());

    expect(find.text('只在第 5 周的课'), findsNothing);

    await tester.runAsync(() => state.setShowNonCurrentWeekCourses(true));
    await tester.pump();
    expect(find.text('只在第 5 周的课'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('没有课程时显示引导空状态', (tester) async {
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      (state, controller) = await buildState(courses: <Course>[]);
    });
    await pumpPage(tester, state, controller, const WeekViewPage());

    expect(find.text('新学期，从第一门课开始。'), findsOneWidget);
    expect(find.text('从教务导入'), findsOneWidget);
    expect(find.text('手动添加'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('超长课程名在窄格子里多行换行而不是只显示一行', (tester) async {
    const longCn = '大学英语综合课程与跨文化交际（三）';
    const longEn = 'Introduction to Computational Thinking and Programming';
    final now = DateTime.now();
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      (state, controller) = await buildState(
        courses: <Course>[
          Course(
            id: 'long-2',
            name: longCn,
            teacher: '王老师',
            location: '宝山校区东区 J-101',
            day: now.weekday,
            startPeriod: 1,
            endPeriod: 2, // 2 节高
            weeks: <int>[for (var w = 1; w <= 18; w++) w],
            colorIndex: 1,
          ),
          Course(
            id: 'long-4',
            name: longEn,
            teacher: 'Prof. Zhang',
            location: '计算机楼 A-301',
            day: now.weekday,
            startPeriod: 5,
            endPeriod: 8, // 4 节高
            weeks: <int>[for (var w = 1; w <= 18; w++) w],
            colorIndex: 2,
          ),
        ],
      );
    });
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPage(tester, state, controller, const WeekViewPage());

    // 渲染期间不能有 overflow 之类的异常。
    expect(tester.takeException(), isNull);

    final cn = tester.widget<Text>(find.text(longCn));
    expect(cn.maxLines, isNotNull);
    expect(cn.maxLines!, greaterThanOrEqualTo(2));
    expect(cn.overflow, TextOverflow.ellipsis);

    // 「多行」还不够，得「完整显示」：实际排版要几行就得给几行，
    // 否则末尾照样吃掉一个省略号（这就是 v1.0.2 之后用户报的问题）。
    final cnWidth = tester.getSize(find.text(longCn)).width;
    final cnPainter = TextPainter(
      text: TextSpan(text: longCn, style: cn.style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: cnWidth);
    final cnNeeded = cnPainter.computeLineMetrics().length;
    cnPainter.dispose();
    expect(cnNeeded, lessThanOrEqualTo(cn.maxLines!));

    final en = tester.widget<Text>(find.text(longEn));
    expect(en.maxLines!, greaterThanOrEqualTo(2));
    // 4 节高的块比 2 节高的块能排更多行。
    expect(en.maxLines!, greaterThan(cn.maxLines!));

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('今日页列出今天的课程、周次与时间', (tester) async {
    late AppState state;
    late ThemeController controller;
    await tester.runAsync(() async {
      (state, controller) = await buildState();
    });
    await pumpPage(tester, state, controller, const TodayPage());

    expect(find.text('高等数学 A(一)'), findsOneWidget);
    expect(find.textContaining('第 1 周'), findsOneWidget);
    expect(find.textContaining('08:00-09:40'), findsOneWidget);
    expect(find.textContaining('J101'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
