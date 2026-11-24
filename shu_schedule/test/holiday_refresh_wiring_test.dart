import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/app.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/holiday_repository.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';

import 'helpers/fake_holiday_repository.dart';
import 'helpers/harness.dart';

/// v1.4.0 A2 / A3：自动检查更新后顺带刷新假日表。
///
/// v1.5.0：没有首次启动的隐私同意框了，启动后直接自动检查（每天最多一次）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('自动检查更新 → 顺带刷新假日表', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('holiday_refresh_wiring'));
    tearDown(storage.tearDown);

    DateTime clock() => DateTime(2026, 10, 8, 9);

    UpdateChecker checker({bool fail = false}) => UpdateChecker(
      sources: const <String>['https://updates.example/latest.json'],
      fetch: (_, _) async {
        if (fail) throw Exception('断网');
        return jsonEncode(<String, dynamic>{
          'versionCode': 7,
          'versionName': '1.4.0',
          'holidays': <String, dynamic>{'sha256': 'a' * 64},
        });
      },
      currentVersionCode: () async => 7,
    );

    testWidgets('启动后：检查成功 → 非强制刷新一次，带上 latest.json 校验值', (tester) async {
      final (state, controller) = await loadState(tester);
      final repo = FakeHolidayRepository(data: HolidayPresets.empty);
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(
          updateChecker: checker(),
          holidayRepository: repo,
          clock: clock,
        ),
      );
      await tester.pump();
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();

      expect(repo.calls, hasLength(1));
      final call = repo.calls.single;
      expect(call.force, isFalse);
      expect(call.manifest?.holidaysSha256, 'a' * 64);
    });

    testWidgets('检查更新失败 → 不刷新假日表', (tester) async {
      final (state, controller) = await loadState(tester);
      final repo = FakeHolidayRepository(data: HolidayPresets.empty);
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(
          updateChecker: checker(fail: true),
          holidayRepository: repo,
          clock: clock,
        ),
      );
      await tester.pump();
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();
      expect(state.settings.lastUpdateCheck, clock());
      expect(repo.calls, isEmpty);
    });

    testWidgets('刷新抛异常也不影响启动流程', (tester) async {
      final (state, controller) = await loadState(tester);
      final repo = FakeHolidayRepository(
        data: HolidayPresets.empty,
        onRefresh: (_) => throw StateError('boom'),
      );
      await pumpApp(
        tester,
        state,
        controller,
        HomeShell(
          updateChecker: checker(),
          holidayRepository: repo,
          clock: clock,
        ),
      );
      await tester.pump();
      await settleWithRealIo(tester);
      await tester.pumpAndSettle();
      expect(repo.calls, hasLength(1));
      expect(tester.takeException(), isNull);
      expect(find.byType(WeekViewPage), findsOneWidget);
    });
  });

  group('设置页「隐私说明」入口', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('holiday_wiring_settings'));
    tearDown(storage.tearDown);

    testWidgets('设置页「隐私说明」副标题提到假期表（v1.5.0 白话）', (tester) async {
      final (state, controller) = await loadState(tester);
      await pumpApp(tester, state, controller, const SettingsPage());
      final tile = find.byKey(const ValueKey<String>('settings-privacy'));
      await tester.ensureVisible(tile);
      expect(
        find.descendant(
          of: tile,
          matching: find.text('课表只存在手机里；只在导入、检查更新、更新假期表时联网'),
        ),
        findsOneWidget,
      );
    });
  });

  test('HolidayRefreshResult.isUpdated', () {
    expect(
      const HolidayRefreshResult(HolidayRefreshStatus.updated).isUpdated,
      isTrue,
    );
    expect(
      const HolidayRefreshResult(HolidayRefreshStatus.unchanged).isUpdated,
      isFalse,
    );
  });
}
