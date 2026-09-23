import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/features/settings/date_override_editor.dart';
import 'package:shu_schedule/features/settings/term_settings_page.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/harness.dart';

/// v1.3.0 Phase C.4：学期设置里的「调休 / 停课」编辑 UI。
void main() {
  final day = DateTime(2026, 10, 10); // 周六

  group('DateOverrideDraft（纯数据）', () {
    test('停课：忽略星期 / 周次，备注去空白', () {
      final o = DateOverrideDraft(
        date: day,
        weekday: 1,
        week: 3,
        note: '  运动会 ',
      ).toOverride();
      expect(o, const DateOverride.cancelled(note: '运动会'));
    });

    test('按某个星期上课：星期必填，周次可选', () {
      final draft = DateOverrideDraft(date: day, mode: OverrideMode.weekday);
      expect(draft.validate(), isNotNull);
      expect(
        draft.copyWith(weekday: 1).toOverride(),
        DateOverride.actAs(weekday: 1),
      );
      expect(
        draft.copyWith(weekday: 1, week: 5, note: '').toOverride(),
        DateOverride.actAs(weekday: 1, week: 5),
      );
    });

    test('指定周次：周次必填，星期可选', () {
      final draft = DateOverrideDraft(date: day, mode: OverrideMode.week);
      expect(draft.validate(), isNotNull);
      expect(draft.copyWith(week: 7).validate(), isNull);
      expect(draft.copyWith(week: 7).toOverride(), DateOverride.actAs(week: 7));
    });

    test('from：从已有规则还原模式', () {
      expect(
        DateOverrideDraft.from(day, const DateOverride.cancelled()).mode,
        OverrideMode.cancelled,
      );
      final both = DateOverrideDraft.from(
        day,
        DateOverride.actAs(week: 2, weekday: 3, note: 'x'),
      );
      expect(both.mode, OverrideMode.weekday);
      expect(both.week, 2);
      expect(both.weekday, 3);
      expect(both.note, 'x');
      expect(
        DateOverrideDraft.from(day, DateOverride.actAs(week: 4)).mode,
        OverrideMode.week,
      );
      // 往返不丢信息。
      final o = DateOverride.actAs(week: 2, weekday: 3, note: 'x');
      expect(DateOverrideDraft.from(day, o).toOverride(), o);
    });

    test('describeDateOverride / formatOverrideDate', () {
      expect(describeDateOverride(const DateOverride.cancelled()), '停课');
      expect(
        describeDateOverride(DateOverride.actAs(week: 5, weekday: 1)),
        '按第 5 周周一上课',
      );
      expect(describeDateOverride(DateOverride.actAs(weekday: 1)), '按周一的课上');
      expect(
        describeDateOverride(DateOverride.actAs(week: 5)),
        '按第 5 周的课上（星期不变）',
      );
      expect(formatOverrideDate(day), '2026-10-10 周六');
    });
  });

  group('学期设置页', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('phase_c_override_ui'));
    tearDown(storage.tearDown);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    Future<void> seed(AppState s, {Map<String, DateOverride>? overrides}) =>
        s.addTimetable(
          Timetable(
            id: 'tt',
            name: '调休',
            config: ScheduleConfig(
              name: '学期',
              startDate: ScheduleUtils.mondayOf(today),
              totalWeeks: 18,
              overrides: overrides,
            ),
          ),
        );

    Future<void> openAdd(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('override-add')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('override-add')));
      await tester.pumpAndSettle();
      expect(find.byType(DateOverrideEditorPage), findsOneWidget);
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('override-save')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('override-save')));
      await tester.pumpAndSettle();
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('添加停课（带备注）：写进 AppState，列表里显示日期、类型、备注', (tester) async {
      final (state, controller) = await loadState(tester, seed: seed);
      await pumpApp(tester, state, controller, const TermSettingsPage());
      expect(find.text('调休 / 停课'), findsOneWidget);

      await openAdd(tester);
      // 默认是今天、停课。
      expect(find.text(formatOverrideDate(today)), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey<String>('override-note')),
        '运动会',
      );
      await tester.pump();
      await save(tester);

      final o = state.currentConfig.overrideOn(today);
      expect(o, const DateOverride.cancelled(note: '运动会'));
      expect(find.byType(DateOverrideEditorPage), findsNothing);
      final key = ScheduleUtils.dateKey(today);
      expect(
        find.byKey(ValueKey<String>('override-item-$key')),
        findsOneWidget,
      );
      expect(find.text('停课 · 运动会'), findsOneWidget);
    });

    testWidgets('添加「按某个星期上课」并同时指定周次（组合 weekday + week）', (tester) async {
      final (state, controller) = await loadState(tester, seed: seed);
      await pumpApp(tester, state, controller, const TermSettingsPage());
      await openAdd(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('override-mode-weekday')),
      );
      await tester.pumpAndSettle();
      // 星期没选就保存 → 提示，不关页面。
      await tester.tap(find.byKey(const ValueKey<String>('override-save')));
      await tester.pumpAndSettle();
      expect(find.text('请选择按星期几的课上'), findsOneWidget);
      expect(find.byType(DateOverrideEditorPage), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('override-weekday')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('周一').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('override-week')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 3 周').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('按第 3 周周一上课'), findsOneWidget);
      await save(tester);

      expect(
        state.currentConfig.overrideOn(today),
        DateOverride.actAs(weekday: 1, week: 3),
      );
      expect(find.text('按第 3 周周一上课'), findsOneWidget);
    });

    testWidgets('添加「指定周次」', (tester) async {
      final (state, controller) = await loadState(tester, seed: seed);
      await pumpApp(tester, state, controller, const TermSettingsPage());
      await openAdd(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('override-mode-week')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('override-week')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 7 周').last);
      await tester.pumpAndSettle();
      await save(tester);
      expect(
        state.currentConfig.overrideOn(today),
        DateOverride.actAs(week: 7),
      );
    });

    testWidgets('编辑已有的一条：改成停课；删除后可撤销', (tester) async {
      final key = ScheduleUtils.dateKey(day);
      final (state, controller) = await loadState(
        tester,
        seed: (s) => seed(
          s,
          overrides: <String, DateOverride>{
            key: DateOverride.actAs(weekday: 1, note: '国庆调休'),
          },
        ),
      );
      await pumpApp(tester, state, controller, const TermSettingsPage());
      expect(find.text('2026-10-10 周六'), findsOneWidget);
      expect(find.text('按周一的课上 · 国庆调休'), findsOneWidget);

      await tester.tap(find.byKey(ValueKey<String>('override-item-$key')));
      await tester.pumpAndSettle();
      expect(find.text('编辑调休 / 停课'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('override-mode-cancelled')),
      );
      await tester.pumpAndSettle();
      await save(tester);
      expect(
        state.currentConfig.overrideOn(day),
        const DateOverride.cancelled(note: '国庆调休'),
      );

      await tester.tap(find.byKey(ValueKey<String>('override-delete-$key')));
      await settleWithRealIo(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.currentConfig.overrideOn(day), isNull);
      expect(find.text('撤销'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await settleWithRealIo(tester);
      expect(
        state.currentConfig.overrideOn(day),
        const DateOverride.cancelled(note: '国庆调休'),
      );
    });
  });
}
