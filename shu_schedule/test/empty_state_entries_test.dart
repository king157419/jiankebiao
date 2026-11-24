import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';
import 'package:shu_schedule/features/settings/week_number_sheet.dart';
import 'package:shu_schedule/features/timetable/course_editor_page.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';
import 'package:shu_schedule/widgets/empty_state.dart';

import 'helpers/fake_holiday_repository.dart';
import 'helpers/harness.dart';

/// 周视图空状态的入口（v1.4.0 任务 E3 起；v1.5.0 删掉了今日页和第三个入口
/// 「打开同学分享的文件」，只剩「从教务导入」「手动添加」）。
///
/// v1.5.0 任务 A2：没有底部导航栏了，空状态下头部右上角的齿轮（`week-settings`）
/// 也必须在，否则没课的人进不了设置。
void main() {
  DateTime clock() => DateTime(2026, 10, 7, 10);

  Timetable emptyTable({String id = 'mine', String name = '我的课表'}) => Timetable(
    id: id,
    name: name,
    config: ScheduleConfig(name: '默认学期', startDate: DateTime(2026, 9, 14)),
  );

  Finder key(String k) => find.byKey(ValueKey<String>(k));

  /// 和 harness.pumpApp 一样，但注册了导入路由（点「从教务导入」要用）。
  Future<void> pumpWithRoutes(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
    Widget home,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: <ChangeNotifierProvider<ChangeNotifier>>[
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<ThemeController>.value(value: controller),
        ],
        child: MaterialApp(
          theme: controller.current.toThemeData(),
          home: home,
          routes: <String, WidgetBuilder>{
            importRouteName: (_) =>
                Scaffold(appBar: AppBar(title: const Text('导入流程页'))),
          },
        ),
      ),
    );
    await tester.pump();
  }

  Widget week() => WeekViewPage(
    clock: clock,
    holidayRepository: FakeHolidayRepository(data: HolidayPresets.empty),
  );

  group('EmptyState', () {
    testWidgets('keyPrefix 给两个按钮加 key；不给 keyPrefix 时没有 key，最多两个入口', (
      tester,
    ) async {
      final (state, controller) = await loadState(tester);
      final taps = <String>[];
      await pumpApp(
        tester,
        state,
        controller,
        Scaffold(
          body: EmptyState(
            theme: controller.current,
            emoji: '🌱',
            title: '标题',
            keyPrefix: 'demo',
            primaryLabel: '一',
            onPrimary: () => taps.add('1'),
            secondaryLabel: '二',
            onSecondary: () => taps.add('2'),
          ),
        ),
      );
      for (final slot in <String>['primary', 'secondary']) {
        await tester.tap(key('demo-$slot'));
      }
      expect(taps, <String>['1', '2']);
      expect(key('demo-tertiary'), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);

      await pumpApp(
        tester,
        state,
        controller,
        Scaffold(
          body: EmptyState(
            theme: controller.current,
            emoji: '🌱',
            title: '标题',
            primaryLabel: '一',
            onPrimary: () {},
          ),
        ),
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).key,
        isNull,
      );
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('周视图空状态两个入口', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('v140_empty_entries'));
    tearDown(storage.tearDown);

    testWidgets('课表为空：文案 + 两个按钮都在、都能点，没有「打开同学分享的文件」', (tester) async {
      final (state, controller) = await loadState(
        tester,
        seed: (s) => s.addTimetable(emptyTable()),
      );
      await pumpWithRoutes(tester, state, controller, week());

      expect(find.text('新学期，从第一门课开始。'), findsOneWidget);
      expect(find.text('可以从教务系统一键导入，也可以手动添加。'), findsOneWidget);
      expect(
        find.descendant(
          of: key('week-empty-primary'),
          matching: find.text('从教务导入'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: key('week-empty-secondary'),
          matching: find.text('手动添加'),
        ),
        findsOneWidget,
      );
      expect(key('week-empty-tertiary'), findsNothing);
      expect(find.text('打开同学分享的文件'), findsNothing);
      expect(key('week-settings').hitTestable(), findsOneWidget);

      await tester.tap(key('week-empty-primary'));
      await tester.pumpAndSettle();
      expect(find.text('导入流程页'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(key('week-empty-secondary'));
      await tester.pumpAndSettle();
      expect(find.byType(CourseEditorPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('一张课表都没有：同样两个入口', (tester) async {
      final (state, controller) = await loadState(tester);
      await pumpWithRoutes(tester, state, controller, week());
      expect(state.currentTimetable, isNull);
      for (final slot in <String>['primary', 'secondary']) {
        expect(key('week-empty-$slot'), findsOneWidget);
      }
      expect(key('week-empty-tertiary'), findsNothing);
      expect(key('week-settings').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('一张课表都没有：点右上角齿轮进设置页，返回键回到空状态', (tester) async {
      final (state, controller) = await loadState(tester);
      await pumpWithRoutes(tester, state, controller, week());
      expect(find.text('新学期，从第一门课开始。'), findsOneWidget);

      await tester.tap(key('week-settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('还没有课表'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.text('新学期，从第一门课开始。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('一张课表都没有 → 空状态点「手动添加」保存时问「现在是第几周？」：选第 4 周确认开学日期', (
      tester,
    ) async {
      final (state, controller) = await loadState(tester);
      await pumpWithRoutes(tester, state, controller, week());
      expect(state.currentTimetable, isNull);

      await tester.tap(key('week-empty-secondary'));
      await tester.pumpAndSettle();
      await tester.enterText(key('course-name'), '高等数学');
      await tester.ensureVisible(key('course-save'));
      await tester.tap(key('course-save'));
      await tester.pumpAndSettle();

      // 自动建表前先弹「现在是第几周？」（clock=2026-10-07 周三，第 4 周 → 9/14）。
      expect(key('week-number-sheet'), findsOneWidget);
      expect(find.text('现在是第几周？'), findsOneWidget);
      await tester.tap(key('week-number-4'));
      await tester.pumpAndSettle();
      await tester.tap(key('week-number-confirm'));
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();

      final tt = state.currentTimetable!;
      expect(tt.courses.single.name, '高等数学');
      expect(tt.config.startDate, DateTime(2026, 9, 14));
      expect(state.settings.termStartConfirmed[tt.id], '2026-09-14');
      expect(find.text(unconfirmedTermStartHint), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('一张课表都没有 → 空状态「手动添加」关掉周次面板：仍建表（mondayOf(today)）并弹 SnackBar', (
      tester,
    ) async {
      final (state, controller) = await loadState(tester);
      await pumpWithRoutes(tester, state, controller, week());

      await tester.tap(key('week-empty-secondary'));
      await tester.pumpAndSettle();
      await tester.enterText(key('course-name'), '线性代数');
      await tester.ensureVisible(key('course-save'));
      await tester.tap(key('course-save'));
      await tester.pumpAndSettle();

      expect(key('week-number-sheet'), findsOneWidget);
      await tester.tapAt(const Offset(450, 20));
      await settleUntil(tester, find.text(unconfirmedTermStartHint));
      await tester.pumpAndSettle();

      final tt = state.currentTimetable!;
      expect(tt.courses.single.name, '线性代数');
      expect(tt.config.startDate, DateTime(2026, 10, 5));
      expect(state.settings.termStartConfirmed.containsKey(tt.id), isFalse);
      expect(find.text(unconfirmedTermStartHint), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
