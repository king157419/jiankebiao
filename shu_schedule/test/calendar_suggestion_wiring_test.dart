import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/app.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/holiday_repository.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/features/import/adapters/zfsoft_adapter.dart';
import 'package:shu_schedule/features/import/pages/import_preview_page.dart';
import 'package:shu_schedule/features/settings/calendar_suggestion_sheet.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/fake_holiday_repository.dart';
import 'helpers/harness.dart';

/// v1.5.0（PLAN-1.5 D9）：校历建议面板的三个触发点，都挂在 `HomeShell` 上——
/// (a) 导入完成、退回首页后；(b) 启动时；(c) 假日表联网更新带来新建议时
/// （SnackBar「假期表有更新」→「查看」）。没有底部导航了：首页就是周视图，
/// 面板弹出前 `popUntil(isFirst)`。
///
/// 今天固定 2026-10-08 10:00（9月14日开学的第 4 周周四）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = TempStorage();
  setUp(() => storage.setUp('calendar_suggestion_wiring'));
  tearDown(storage.tearDown);

  DateTime clock() => DateTime(2026, 10, 8, 10);

  Map<dynamic, dynamic> holidaysJson() =>
      jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map;
  final bundled = HolidayPresets.fromJson(holidaysJson());

  final sheet = find.byKey(const ValueKey<String>('calendar-suggestion-sheet'));
  final termLine = find.byKey(
    const ValueKey<String>('calendar-suggestion-term'),
  );
  final pendingLine = find.byKey(
    const ValueKey<String>('calendar-suggestion-pending'),
  );
  final applyButton = find.byKey(
    const ValueKey<String>('calendar-suggestion-apply'),
  );
  final laterButton = find.byKey(
    const ValueKey<String>('calendar-suggestion-later'),
  );

  Timetable timetable({
    required DateTime start,
    String? schoolId = 'shu',
    String name = '我的课表',
  }) => Timetable(
    id: 'tt',
    name: name,
    schoolId: schoolId,
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
  );

  Future<(AppState, ThemeController)> seeded(
    WidgetTester tester, {
    required Timetable tt,
    Map<String, String>? dismissed,
    bool checkedToday = true,
  }) => loadState(
    tester,
    seed: (s) async {
      await s.addTimetable(tt);
      if (dismissed != null) {
        for (final e in dismissed.entries) {
          await s.dismissCalendarSuggestion(e.key, e.value);
        }
      }
      // 今天已经自动检查过更新：启动流程不会去联网（触发点 (c) 的用例除外）。
      if (checkedToday) await s.setLastUpdateCheck(DateTime(2026, 10, 8, 8));
    },
  );

  Future<void> pumpShell(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
    HolidayRepository repo, {
    UpdateChecker? checker,
  }) async {
    await pumpApp(
      tester,
      state,
      controller,
      HomeShell(clock: clock, holidayRepository: repo, updateChecker: checker),
    );
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
  }

  /// 卸载（停掉周视图的分钟计时器）。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settleWithRealIo(tester, rounds: 5);
  }

  int pageWeek(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller!.page!.round() +
      1;

  // ------------------------------------------------------------ (b) 启动时

  testWidgets('(b) 启动：开学日期错设成本周（10/5）→ 弹面板；一键套用 → 9/14 + 13 条，周视图回到第 4 周，可撤销', (
    tester,
  ) async {
    final (state, controller) = await seeded(
      tester,
      tt: timetable(start: DateTime(2026, 10, 5)),
    );
    final repo = FakeHolidayRepository(data: bundled);
    await pumpShell(tester, state, controller, repo);

    expect(sheet, findsOneWidget);
    expect(find.text('按上海大学校历'), findsOneWidget);
    expect(tester.widget<Text>(termLine).data, '开学日期：9月14日（现在第 4 周）');
    expect(find.text('现在课表显示的是第 1 周'), findsOneWidget);
    expect(tester.widget<Text>(pendingLine).data, '放假 / 调休 13 条');
    // R1-8：今天（10/8）及以后的条目逐条列出（日期「10月10日 周六」，只显示一种描述），过去的 11 条折叠。
    expect(find.text('10月10日 周六'), findsOneWidget);
    expect(find.text('国庆调休，上 10 月 7 日（周三）的课'), findsOneWidget);
    expect(find.text('1月1日 周五'), findsOneWidget);
    expect(find.text('2026-09-20 周日'), findsNothing);
    expect(find.text('9月20日 周日'), findsNothing, reason: '已过去的条目折叠显示');
    expect(find.text('另有 11 条已经过去的，也会一起补上'), findsOneWidget);
    expect(find.text('第 1 周'), findsOneWidget, reason: '面板后面的周视图还按 10/5 算');

    await tester.tap(applyButton);
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    final config = state.currentConfig;
    expect(config.startDate, DateTime(2026, 9, 14));
    expect(config.overrides, hasLength(13));
    expect(config.overrideOn(DateTime(2026, 9, 20))!.actAsWeek, 4);
    expect(config.overrideOn(DateTime(2026, 10, 10))!.actAsWeekday, 3);
    for (var d = 1; d <= 7; d++) {
      expect(config.overrideOn(DateTime(2026, 10, d))!.cancelled, isTrue);
    }
    expect(find.text('第 4 周'), findsOneWidget);
    expect(pageWeek(tester), 4);
    expect(find.text('已按校历设置'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
    expect(state.currentConfig.startDate, DateTime(2026, 10, 5));
    expect(state.currentConfig.overrides, isEmpty);
    await unmount(tester);
  });

  testWidgets('(b) 「先不用」→ 记下 termKey；顶层 updatedAt 变不打扰，本校本学期条目变了再提示', (
    tester,
  ) async {
    final (state, controller) = await seeded(
      tester,
      tt: timetable(start: DateTime(2026, 10, 5)),
    );
    final repo = FakeHolidayRepository(data: bundled);
    await pumpShell(tester, state, controller, repo);
    expect(sheet, findsOneWidget);

    await tester.tap(laterButton);
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    final savedKey = state.settings.calendarSuggestionDismissed['tt'];
    expect(savedKey, startsWith('shu|2026-09-14|'));
    expect(state.currentConfig.startDate, DateTime(2026, 10, 5));
    expect(state.currentConfig.overrides, isEmpty);

    // 重启：同一份假期表 → 不弹。
    await unmount(tester);
    await pumpShell(tester, state, controller, repo);
    expect(repo.loads, 2);
    expect(sheet, findsNothing);

    // 顶层 updatedAt 变到 2026-11-02，但本校本学期条目没变 → 仍不弹。
    repo.data = HolidayPresets.fromJson(
      holidaysJson()..['updatedAt'] = '2026-11-02',
      source: HolidayDataSource.remote,
    );
    await unmount(tester);
    await pumpShell(tester, state, controller, repo);
    expect(sheet, findsNothing);

    // 本校本学期新增了一条停课 → termKey 变化，再次弹出建议面板。
    final changedJson = holidaysJson()..['updatedAt'] = '2026-11-03';
    final shuTerms =
        ((changedJson['schools'] as Map)['shu'] as Map)['terms'] as List;
    ((shuTerms.first as Map)['entries'] as List).add(<String, dynamic>{
      'date': '2026-11-15',
      'cancelled': true,
      'note': '校庆停课',
    });
    repo.data = HolidayPresets.fromJson(
      changedJson,
      source: HolidayDataSource.remote,
    );
    await unmount(tester);
    await pumpShell(tester, state, controller, repo);
    expect(sheet, findsOneWidget);
    expect(find.text('11月15日 周日'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('(b) 一键套用后删掉其中一条调休 → 重启不再弹面板', (tester) async {
    final (state, controller) = await seeded(
      tester,
      tt: timetable(start: DateTime(2026, 10, 5)),
    );
    final repo = FakeHolidayRepository(data: bundled);
    await pumpShell(tester, state, controller, repo);
    expect(sheet, findsOneWidget);

    await tester.tap(applyButton);
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
    expect(state.currentConfig.overrides, hasLength(13));

    // 用户自己把 10/10 补课删掉。
    await tester.runAsync(
      () => state.setDateOverride(DateTime(2026, 10, 10), null),
    );
    expect(state.currentConfig.overrides, hasLength(12));

    // 重启：因为一键套用已记下本学期的 termKey，不会再弹出来推翻用户的删除。
    await unmount(tester);
    await pumpShell(tester, state, controller, repo);
    expect(sheet, findsNothing);
    await unmount(tester);
  });

  testWidgets('(b) 周视图校正周次到第 3 周（开学 9/21）→ 重启不弹 termFix', (tester) async {
    final (state, controller) = await seeded(
      tester,
      tt: timetable(start: DateTime(2026, 9, 14)),
    );
    final repo = FakeHolidayRepository(data: bundled);
    await pumpShell(tester, state, controller, repo);
    // 先把 13 条放假调休一键套用。
    await tester.tap(applyButton);
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();

    // 在周视图点「第 4 周」→「本周不是第 4 周？点这里校正」→ 改选第 3 周（开学 9/21）。
    await tester.tap(find.text('第 4 周'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('week-picker-fix')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('week-number-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('week-number-confirm')));
    await settleUntil(tester, find.text('已把本周设为第 3 周'));
    await tester.pumpAndSettle();
    expect(state.currentConfig.startDate, DateTime(2026, 9, 21));
    expect(state.settings.termStartConfirmed['tt'], '2026-09-21');

    // 重启：不弹 termFix（且面板整体不弹）。
    await unmount(tester);
    await pumpShell(tester, state, controller, repo);
    expect(termLine, findsNothing);
    expect(sheet, findsNothing);
    await unmount(tester);
  });

  testWidgets('(b) 课表没有 schoolId → 不读假日表，不弹', (tester) async {
    final (state, controller) = await seeded(
      tester,
      tt: timetable(start: DateTime(2026, 10, 5), schoolId: null),
    );
    final repo = FakeHolidayRepository(data: bundled);
    await pumpShell(tester, state, controller, repo);
    expect(repo.loads, 0);
    expect(sheet, findsNothing);
    await unmount(tester);
  });

  // ------------------------------------------------------------ (a) 导入完成

  testWidgets('(a) 教务识别第 3 周导入（开学 9/21，不预置任何标记）→ 弹放假/调休面板但不含 termFix；'
      '重启后也不弹 termFix', (tester) async {
    // 初始放一张无关的无 schoolId 空课表，不预置任何 dismissed 或 termStartConfirmed。
    final (state, controller) = await seeded(
      tester,
      tt: timetable(start: DateTime(2026, 9, 14), schoolId: null, name: '旧课表'),
    );
    final repo = FakeHolidayRepository(data: bundled);
    await pumpShell(tester, state, controller, repo);
    expect(sheet, findsNothing);

    // 教务页面写着「当前第 3 周」（10/8）→ 开学 9/21，和校历（9/14）不同。
    final adapter = ZfsoftAdapter(
      id: 'shu',
      name: '上海大学',
      baseUrl: 'https://jwxt.shu.edu.cn/jwglxt',
      homeUrl: 'https://jwxt.shu.edu.cn/',
    );
    final result = adapter.parse(
      File('test/import/fixtures/shu_kb_envelope.json')
          .readAsStringSync(encoding: utf8),
      now: DateTime(2026, 10, 8),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ImportPreviewPage(
              result: result,
              schoolName: '上海大学',
              today: DateTime(2026, 10, 8),
              holidayPresets: bundled,
            ),
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('9月21日（周一）　教务系统显示当前第 3 周'), findsOneWidget);

    await tester.tap(find.text('确认导入（8 门）'));
    await settleWithRealIo(tester, rounds: 40);
    await tester.pumpAndSettle();

    expect(find.byType(ImportPreviewPage), findsNothing);
    expect(state.timetables, hasLength(1), reason: '覆盖当前课表');
    expect(state.currentConfig.startDate, DateTime(2026, 9, 21));
    expect(state.settings.termStartConfirmed['tt'], '2026-09-21');
    expect(state.pendingCalendarPromptFor.value, isNull, reason: '首页处理完清掉');
    expect(sheet, findsOneWidget);
    expect(find.text('已导入 8 门课'), findsOneWidget);
    expect(termLine, findsNothing, reason: '刚导入完不建议改开学日期');
    // 按 9/21 开学：9/20 不在学期内，剩 12 条。
    expect(tester.widget<Text>(pendingLine).data, '放假 / 调休 12 条');
    expect(find.text('第 3 周'), findsOneWidget);

    // 直接点空白处关掉面板（不套用、也不点「先不用」），模拟下次冷启动：仍不得弹 termFix！
    await tester.tapAt(const Offset(450, 20));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    await unmount(tester);
    await pumpShell(tester, state, controller, repo);
    expect(sheet, findsOneWidget, reason: '放假/调休还没套用，仍会提示');
    expect(termLine, findsNothing, reason: '教务确认过的 9/21 重启后也不得弹 termFix');

    await tester.tap(applyButton);
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
    expect(state.currentConfig.startDate, DateTime(2026, 9, 21));
    expect(state.currentConfig.overrides, hasLength(12));
    expect(
      state.currentConfig.overrideOn(DateTime(2026, 10, 10))!.actAsWeek,
      3,
    );

    // 套用后再重启：整张面板都不弹。
    await unmount(tester);
    await pumpShell(tester, state, controller, repo);
    expect(sheet, findsNothing);
    await unmount(tester);
  });

  // ------------------------------------------------------------ (c) 假日表更新

  UpdateChecker checker() => UpdateChecker(
    sources: const <String>['https://updates.example/latest.json'],
    fetch: (_, _) async => jsonEncode(<String, dynamic>{
      'versionCode': 7,
      'versionName': '1.4.0',
      'holidays': <String, dynamic>{'sha256': 'a' * 64},
    }),
    currentVersionCode: () async => 7,
  );

  FakeHolidayRepository updatingRepo() => FakeHolidayRepository(
    data: HolidayPresets.empty,
    afterUpdate: bundled,
    onRefresh: (_) =>
        HolidayRefreshResult(HolidayRefreshStatus.updated, presets: bundled),
  );

  testWidgets('(c) 自动检查更新顺带下载到新假日表 → SnackBar「假期表有更新」→「查看」弹面板', (tester) async {
    final (state, controller) = await seeded(
      tester,
      tt: timetable(start: DateTime(2026, 9, 14)),
      checkedToday: false,
    );
    final repo = updatingRepo();
    await pumpShell(tester, state, controller, repo, checker: checker());

    expect(repo.calls, hasLength(1));
    expect(find.text('假期表有更新'), findsOneWidget);
    expect(sheet, findsNothing, reason: '先只给 SnackBar');

    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    expect(termLine, findsNothing);
    expect(tester.widget<Text>(pendingLine).data, '放假 / 调休 13 条');

    await tester.tap(applyButton);
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();
    expect(state.currentConfig.overrides, hasLength(13));
    await unmount(tester);
  });

  testWidgets('(c) 新假日表带来的建议已经点过「先不用」，或顶层 updatedAt 变但本校条目没变 → 不出 SnackBar', (
    tester,
  ) async {
    final baseTt = timetable(start: DateTime(2026, 9, 14));
    final termKey = buildCalendarSuggestion(
      tt: baseTt,
      presets: bundled,
      today: DateTime(2026, 10, 8),
    )!.termKey;
    final (state, controller) = await seeded(
      tester,
      tt: baseTt,
      dismissed: <String, String>{'tt': termKey},
      checkedToday: false,
    );
    // 场景 1：顶层 updatedAt 更新了，但本校条目和旧数据完全一样 → oldKey == newKey，不出 SnackBar。
    final newerSameEntries = HolidayPresets.fromJson(
      holidaysJson()..['updatedAt'] = '2026-11-02',
      source: HolidayDataSource.remote,
    );
    final repoSame = FakeHolidayRepository(
      data: bundled,
      afterUpdate: newerSameEntries,
      onRefresh: (_) => HolidayRefreshResult(
        HolidayRefreshStatus.updated,
        presets: newerSameEntries,
      ),
    );
    await pumpShell(tester, state, controller, repoSame, checker: checker());
    expect(repoSame.calls, hasLength(1));
    expect(find.text('假期表有更新'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('calendar-holidays-updated')),
      findsNothing,
    );
    expect(sheet, findsNothing);
    await unmount(tester);

    // 场景 2：从空表更新到 bundled，但该 termKey 已点过「先不用」→ 也不出 SnackBar。
    await tester.runAsync(
      () => state.setLastUpdateCheck(DateTime(2026, 10, 7)),
    );
    final repoDismissed = updatingRepo();
    await pumpShell(
      tester,
      state,
      controller,
      repoDismissed,
      checker: checker(),
    );
    expect(repoDismissed.calls, hasLength(1));
    expect(find.text('假期表有更新'), findsNothing);
    expect(sheet, findsNothing);
    await unmount(tester);
  });
}
