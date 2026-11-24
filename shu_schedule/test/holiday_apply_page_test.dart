import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/holiday_repository.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/features/settings/holiday_apply_page.dart';
import 'package:shu_schedule/features/settings/term_settings_page.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/fake_holiday_repository.dart';
import 'helpers/harness.dart';

/// v1.3.1：「套用节假日安排」页面。
void main() {
  final storage = TempStorage();
  setUp(() => storage.setUp('holiday_apply_page_test'));
  tearDown(storage.tearDown);

  final presets = HolidayPresets.fromJson(
    jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map,
  );

  /// 同一份数据，假装是 2026-11-02 联网更新下来的。
  final remote = HolidayPresets.fromJson(
    (jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map)
      ..['updatedAt'] = '2026-11-02',
    source: HolidayDataSource.remote,
  );

  Future<void> Function(AppState) seed({
    String? schoolId = 'shu',
    DateTime? start,
    Map<String, DateOverride>? overrides,
  }) =>
      (s) => s.addTimetable(
        Timetable(
          id: 'tt',
          name: '秋季',
          schoolId: schoolId,
          config: ScheduleConfig(
            name: '2026 秋',
            startDate: start ?? DateTime(2026, 9, 14),
            totalWeeks: 18,
            overrides: overrides,
          ),
        ),
      );

  Finder item(String key) => find.byKey(ValueKey<String>('holiday-item-$key'));
  final applyButton = find.byKey(const ValueKey<String>('holiday-apply'));

  Future<void> pumpPage(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
  ) => pumpApp(tester, state, controller, HolidayApplyPage(presets: presets));

  testWidgets('上大：13 行，取消一行后套用 → 12 条写进 AppState，返回并提示', (tester) async {
    final (state, controller) = await loadState(tester, seed: seed());
    await pumpApp(
      tester,
      state,
      controller,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => HolidayApplyPage(presets: presets),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('上海大学 · 2026-2027 学年秋季学期'), findsOneWidget);
    expect(find.text('查看来源'), findsOneWidget);
    expect(find.textContaining('以学校教务通知为准'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(13));
    expect(find.text('套用 13 条'), findsOneWidget);
    expect(find.text('按第 4 周周二上课 · 国庆调休，上 10 月 6 日（周二）的课'), findsOneWidget);

    await tester.ensureVisible(item('2027-01-01'));
    await tester.tap(item('2027-01-01'));
    await tester.pump();
    expect(find.text('套用 12 条'), findsOneWidget);

    await tester.tap(applyButton);
    await tester.pumpAndSettle();
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();

    final overrides = state.currentConfig.overrides;
    expect(overrides, hasLength(12));
    expect(overrides.containsKey('2027-01-01'), isFalse);
    expect(overrides['2026-10-10'], isNotNull);
    expect(find.byType(HolidayApplyPage), findsNothing);
    expect(find.text('已套用 12 条调休 / 停课'), findsOneWidget);
  });

  testWidgets('冲突行默认不勾、显示「将覆盖」；已设置的行禁用且不计数', (tester) async {
    final (state, controller) = await loadState(
      tester,
      seed: seed(
        overrides: <String, DateOverride>{
          '2026-09-25': const DateOverride.cancelled(note: '中秋节放假'),
          '2026-10-02': const DateOverride.cancelled(note: '运动会'),
        },
      ),
    );
    await pumpPage(tester, state, controller);
    await tester.pumpAndSettle();

    final conflict = tester.widget<CheckboxListTile>(item('2026-10-02'));
    expect(conflict.value, isFalse);
    expect(conflict.onChanged, isNotNull);
    expect(find.text('将覆盖：停课 · 运动会'), findsOneWidget);

    final applied = tester.widget<CheckboxListTile>(item('2026-09-25'));
    expect(applied.value, isTrue);
    expect(applied.onChanged, isNull);
    expect(find.text('已设置'), findsOneWidget);

    // 13 - 已设置 1 - 冲突 1。
    expect(find.text('套用 11 条'), findsOneWidget);

    // 勾上冲突行 → 12 条，套用后覆盖旧设置。
    await tester.ensureVisible(item('2026-10-02'));
    await tester.tap(item('2026-10-02'));
    await tester.pump();
    expect(find.text('套用 12 条'), findsOneWidget);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();
    await settleWithRealIo(tester);
    expect(
      state.currentConfig.overrides['2026-10-02'],
      const DateOverride.cancelled(note: '国庆节放假'),
    );
    expect(state.currentConfig.overrides, hasLength(13));
  });

  testWidgets('没有学校的课表 → 国家安排：需要确认的行没有勾选框', (tester) async {
    final (state, controller) = await loadState(
      tester,
      seed: seed(schoolId: null),
    );
    await pumpPage(tester, state, controller);
    await tester.pumpAndSettle();

    expect(find.text('国家法定节假日（2026）'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(10));
    expect(find.text('套用 10 条'), findsOneWidget);
    for (final key in <String>['2026-09-20', '2026-10-10']) {
      expect(item(key), findsOneWidget);
      expect(tester.widget(item(key)), isA<ListTile>());
    }
    expect(find.byIcon(Icons.info_outline), findsNWidgets(2));
    expect(find.textContaining('国家调休上班'), findsNWidgets(2));
  });

  testWidgets('学期对不上任何数据 → 空状态，按钮不出现', (tester) async {
    final (state, controller) = await loadState(
      tester,
      seed: seed(schoolId: null, start: DateTime(2030, 9, 2)),
    );
    await pumpPage(tester, state, controller);
    await tester.pumpAndSettle();
    expect(find.text('没有找到适用于当前学期的节假日安排'), findsOneWidget);
    expect(applyButton, findsNothing);
  });

  testWidgets('全部取消勾选 → 按钮禁用', (tester) async {
    final (state, controller) = await loadState(
      tester,
      seed: seed(schoolId: null),
    );
    await pumpPage(tester, state, controller);
    await tester.pumpAndSettle();
    final keys = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .map((w) => w.key!)
        .toList();
    for (final k in keys) {
      await tester.ensureVisible(find.byKey(k));
      await tester.tap(find.byKey(k));
      await tester.pump();
    }
    expect(find.text('套用 0 条'), findsOneWidget);
    expect(tester.widget<FilledButton>(applyButton).onPressed, isNull);
  });

  testWidgets('学期设置页：「套用节假日安排」入口在「添加调休 / 停课」上方', (tester) async {
    final (state, controller) = await loadState(tester, seed: seed());
    await pumpApp(tester, state, controller, const TermSettingsPage());
    final tile = find.byKey(const ValueKey<String>('override-apply-holidays'));
    expect(tile, findsOneWidget);
    expect(find.text('套用节假日安排'), findsOneWidget);
    expect(find.text('内置国家假期表和已收录学校的放假 / 补课通知'), findsOneWidget);
    final add = find.byKey(const ValueKey<String>('override-add'));
    expect(tester.getTopLeft(tile).dy, lessThan(tester.getTopLeft(add).dy));
    expect(tester.widget<ListTile>(tile).enabled, isTrue);
  });

  testWidgets('没有课表时入口禁用', (tester) async {
    final (state, controller) = await loadState(tester);
    await pumpApp(tester, state, controller, const TermSettingsPage());
    final tile = find.byKey(const ValueKey<String>('override-apply-holidays'));
    expect(tester.widget<ListTile>(tile).enabled, isFalse);
  });

  // ------------------------------------------------------------ v1.4.0：数据版本与刷新

  final refreshButton = find.byKey(const ValueKey<String>('holiday-refresh'));
  final dataVersion = find.byKey(
    const ValueKey<String>('holiday-data-version'),
  );

  testWidgets('仓库未配置更新源时：头部显示「内置」日期，不显示「联网更新假期表」按钮', (tester) async {
    final (state, controller) = await loadState(tester, seed: seed());
    await pumpPage(tester, state, controller);
    await tester.pumpAndSettle();
    expect(refreshButton, findsNothing);
    expect(find.byTooltip('联网更新假期表'), findsNothing);
    expect(tester.widget<Text>(dataVersion).data, '假期表 · 内置 2026-10-06');
    expect(find.byType(CheckboxListTile), findsNWidgets(13));
  });

  testWidgets('注入 fake repository：用它的数据，头部显示「已更新」日期，进入时静默刷新一次（非强制）', (
    tester,
  ) async {
    final (state, controller) = await loadState(tester, seed: seed());
    final repo = FakeHolidayRepository(data: remote);
    await pumpApp(
      tester,
      state,
      controller,
      HolidayApplyPage(repository: repo),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(dataVersion).data, '假期表 · 已更新 2026-11-02');
    expect(find.text('上海大学 · 2026-2027 学年秋季学期'), findsOneWidget);
    expect(repo.loads, 1);
    expect(repo.calls, hasLength(1));
    expect(repo.calls.single.force, isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('进入时静默刷新拿到更新 → 自动重新读取，不弹提示', (tester) async {
    final (state, controller) = await loadState(tester, seed: seed());
    final repo = FakeHolidayRepository(
      data: presets,
      afterUpdate: remote,
      onRefresh: (_) =>
          HolidayRefreshResult(HolidayRefreshStatus.updated, presets: remote),
    );
    await pumpApp(
      tester,
      state,
      controller,
      HolidayApplyPage(repository: repo),
    );
    await tester.pumpAndSettle();
    expect(repo.loads, 2);
    expect(tester.widget<Text>(dataVersion).data, '假期表 · 已更新 2026-11-02');
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('点刷新：强制刷新；updated → 重新读取并提示新日期', (tester) async {
    final (state, controller) = await loadState(tester, seed: seed());
    final repo = FakeHolidayRepository(
      data: presets,
      afterUpdate: remote,
      onRefresh: (call) => call.force
          ? HolidayRefreshResult(HolidayRefreshStatus.updated, presets: remote)
          : const HolidayRefreshResult(HolidayRefreshStatus.throttled),
    );
    await pumpApp(
      tester,
      state,
      controller,
      HolidayApplyPage(repository: repo),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(dataVersion).data, '假期表 · 内置 2026-10-06');

    await tester.tap(refreshButton);
    await tester.pumpAndSettle();
    expect(repo.calls.map((c) => c.force).toList(), <bool>[false, true]);
    expect(tester.widget<Text>(dataVersion).data, '假期表 · 已更新 2026-11-02');
    expect(find.text('假期表已更新（2026-11-02）'), findsOneWidget);
  });

  testWidgets('点刷新：失败 / 已是最新 都有提示，数据不变', (tester) async {
    final (state, controller) = await loadState(tester, seed: seed());
    var next = const HolidayRefreshResult(
      HolidayRefreshStatus.failed,
      errors: <String>['cdn.jsdelivr.net：超时'],
    );
    final repo = FakeHolidayRepository(
      data: presets,
      onRefresh: (call) => call.force
          ? next
          : const HolidayRefreshResult(HolidayRefreshStatus.throttled),
    );
    await pumpApp(
      tester,
      state,
      controller,
      HolidayApplyPage(repository: repo),
    );
    await tester.pumpAndSettle();
    await tester.tap(refreshButton);
    await tester.pumpAndSettle();
    expect(find.text('假期表这次没更新成功，稍后会再试'), findsOneWidget);

    next = HolidayRefreshResult(
      HolidayRefreshStatus.unchanged,
      presets: presets,
    );
    await tester.tap(refreshButton);
    await tester.pumpAndSettle();
    expect(find.text('假期表已是最新'), findsOneWidget);
    expect(repo.loads, 1);
    expect(tester.widget<Text>(dataVersion).data, '假期表 · 内置 2026-10-06');
  });

  testWidgets('空状态也有数据版本；配置更新源时显示刷新按钮，未配置时隐藏', (tester) async {
    final (state, controller) = await loadState(
      tester,
      seed: seed(schoolId: null, start: DateTime(2030, 9, 2)),
    );
    await pumpPage(tester, state, controller);
    await tester.pumpAndSettle();
    expect(find.text('没有找到适用于当前学期的节假日安排'), findsOneWidget);
    expect(refreshButton, findsNothing);
    expect(tester.widget<Text>(dataVersion).data, '假期表 · 内置 2026-10-06');

    final repo = FakeHolidayRepository(data: presets);
    await pumpApp(
      tester,
      state,
      controller,
      HolidayApplyPage(
        key: const ValueKey<String>('configured'),
        repository: repo,
      ),
    );
    await tester.pumpAndSettle();
    expect(refreshButton, findsOneWidget);
  });

  test('describeHolidayRefresh / holidayDataVersionText 文案（白话错误提示）', () {
    expect(describeHolidayRefresh(null), '假期表这次没更新成功，稍后会再试');
    expect(
      describeHolidayRefresh(
        const HolidayRefreshResult(HolidayRefreshStatus.notConfigured),
      ),
      '更新源未配置',
    );
    expect(
      describeHolidayRefresh(
        const HolidayRefreshResult(HolidayRefreshStatus.failed),
      ),
      '假期表这次没更新成功，稍后会再试',
    );
    expect(
      describeHolidayRefresh(
        const HolidayRefreshResult(
          HolidayRefreshStatus.failed,
          errors: <String>[
            'gitee.com：HTTP 404',
            'cdn.jsdelivr.net：超时',
            'raw.githubusercontent.com：连不上服务器',
          ],
        ),
      ),
      '假期表这次没更新成功，稍后会再试',
    );
    expect(holidayDataVersionText(HolidayPresets.empty), '假期表 · 内置');
    expect(holidayDataVersionText(remote), '假期表 · 已更新 2026-11-02');
  });
}
