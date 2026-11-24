import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/features/settings/ics_export_sheet.dart';
import 'package:shu_schedule/features/settings/ics_exporter.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';
import 'package:shu_schedule/features/settings/system_share.dart';
import 'package:shu_schedule/features/settings/timetable_manage_page.dart';
import 'package:shu_schedule/models/reminder_settings.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/harness.dart';
import 'helpers/reminder_fixtures.dart';

/// v1.4.0 任务 D：「导出到日历（.ics）」入口、底部弹窗与分享钩子。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = TempStorage();
  setUp(() => storage.setUp('ics_sheet'));
  tearDown(() async {
    IcsShare.resetIo();
    await storage.tearDown();
  });

  ValueKey<String> k(String s) => ValueKey<String>(s);

  /// 收下分享请求，不真的调系统面板。
  List<ShareFileRequest> captureShares() {
    final shared = <ShareFileRequest>[];
    IcsShare.shareFile = (r) async => shared.add(r);
    return shared;
  }

  Future<(AppState, ThemeController)> seeded(
    WidgetTester tester, {
    int? leadMinutes,
    List<Timetable>? extra,
  }) => loadState(
    tester,
    seed: (s) async {
      for (final t in extra ?? const <Timetable>[]) {
        await s.addTimetable(t, switchTo: false);
      }
      await s.addTimetable(buildTimetable(overrides: octoberOverrides()));
      if (leadMinutes != null) {
        await s.setReminderSettings(ReminderSettings(leadMinutes: leadMinutes));
      }
    },
  );

  Future<void> pumpSettings(
    WidgetTester tester,
    AppState state,
    ThemeController controller,
  ) async {
    await pumpApp(
      tester,
      state,
      controller,
      SettingsPage(updateChecker: UpdateChecker(sources: const <String>[])),
    );
    final tile = find.byKey(k('settings-export-ics'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
  }

  bool selected(WidgetTester tester, String key) =>
      tester.widget<ChoiceChip>(find.byKey(k(key))).selected;

  Future<void> tapAndSettle(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(k(key)));
    await tester.tap(find.byKey(k(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('设置「课表」分组有入口，打开底部弹窗：说明、课次、默认 15 分钟', (tester) async {
    final (state, controller) = await seeded(tester);
    await pumpApp(
      tester,
      state,
      controller,
      SettingsPage(updateChecker: UpdateChecker(sources: const <String>[])),
    );
    final tile = find.byKey(k('settings-export-ics'));
    expect(tile, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.text('导出到日历（.ics）')),
      findsOneWidget,
    );
    // v1.5.0：「课表」分组的最后一条——「上课提醒」之后、「显示」分组标题之前。
    final y = tester.getTopLeft(tile).dy;
    expect(y, greaterThan(tester.getTopLeft(find.text('作息时间')).dy));
    expect(
      y,
      greaterThan(tester.getTopLeft(find.byKey(k('settings-reminders'))).dy),
    );
    expect(y, lessThan(tester.getTopLeft(find.text('显示')).dy));

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byKey(k('ics-sheet')), findsOneWidget);
    expect(
      find.text('iPhone：微信/AirDrop 打开后选「添加全部」；电脑：Outlook / Google 日历导入'),
      findsOneWidget,
    );
    // P2-4：重新导入删不掉旧事件，说明要先清空单独的那个日历。
    expect(
      tester.widget<Text>(find.byKey(k('ics-reimport-note'))).data,
      '建议导入到一个单独的日历；课表或调休有变化时，先清空那个日历再重新导入，'
      '日历不会自动删除已取消的课。',
    );
    expect(find.textContaining('“'), findsNothing, reason: 'P3-3：引号统一为「」');
    final count = IcsExporter.sessionsOf(state.currentTimetable!).length;
    expect(count, greaterThan(0));
    expect(
      tester.widget<Text>(find.byKey(k('ics-summary'))).data,
      contains('共 $count 节课'),
    );
    // 默认上课提醒是 15 分钟 → 15 分钟选中。
    expect(selected(tester, 'ics-alarm-15'), isTrue);
    for (final key in <String>['ics-alarm-0', 'ics-alarm-10', 'ics-alarm-30']) {
      expect(selected(tester, key), isFalse);
    }
    expect(find.byKey(k('ics-share')), findsOneWidget);
  });

  testWidgets('切换提醒后「生成并分享」：钩子收到 .ics、text/calendar、对应 TRIGGER，弹窗关闭', (
    tester,
  ) async {
    final shared = captureShares();
    final (state, controller) = await seeded(tester);
    await pumpSettings(tester, state, controller);

    await tapAndSettle(tester, 'ics-alarm-30');
    expect(selected(tester, 'ics-alarm-30'), isTrue);
    expect(selected(tester, 'ics-alarm-15'), isFalse);

    await tapAndSettle(tester, 'ics-share');
    expect(shared.length, 1);
    final r = shared.single;
    expect(r.fileName, matches(RegExp(r'^jiankebiao-timetable-\d{8}\.ics$')));
    expect(r.mimeType, 'text/calendar');
    expect(r.content, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(r.content, contains('X-WR-CALNAME:测试课表\r\n'));
    expect(r.content, contains('TRIGGER:-PT30M\r\n'));
    expect(r.content.contains('TRIGGER:-PT15M'), isFalse);
    final events = 'BEGIN:VEVENT'.allMatches(r.content).length;
    expect(events, IcsExporter.sessionsOf(state.currentTimetable!).length);
    expect(find.byKey(k('ics-sheet')), findsNothing);
  });

  testWidgets('上课提醒提前 10 分钟 → 默认 10；选「无」→ 不带 VALARM', (tester) async {
    final shared = captureShares();
    final (state, controller) = await seeded(tester, leadMinutes: 10);
    await pumpSettings(tester, state, controller);
    expect(selected(tester, 'ics-alarm-10'), isTrue);

    await tapAndSettle(tester, 'ics-alarm-0');
    expect(selected(tester, 'ics-alarm-0'), isTrue);
    expect(selected(tester, 'ics-alarm-10'), isFalse);
    await tapAndSettle(tester, 'ics-share');
    expect(shared.single.content.contains('BEGIN:VALARM'), isFalse);
  });

  testWidgets('设备时区不是 UTC+8：弹窗提示按手机时区导出，文件是浮动时间（P3-11）', (tester) async {
    final shared = captureShares();
    final (state, controller) = await seeded(tester);
    await pumpApp(
      tester,
      state,
      controller,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showIcsExportSheet(
            context,
            timetable: state.currentTimetable!,
            utcOffset: () => const Duration(hours: -6),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(k('ics-local-time-note')), findsOneWidget);
    expect(find.text(icsLocalTimeNote), findsOneWidget);
    await tapAndSettle(tester, 'ics-share');
    expect(shared.single.content.contains('TZID'), isFalse);
  });

  testWidgets('设备时区是 UTC+8：不提示，文件带 TZID=Asia/Shanghai', (tester) async {
    final shared = captureShares();
    final (state, controller) = await seeded(tester);
    await pumpApp(
      tester,
      state,
      controller,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showIcsExportSheet(
            context,
            timetable: state.currentTimetable!,
            utcOffset: () => const Duration(hours: 8),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(k('ics-local-time-note')), findsNothing);
    await tapAndSettle(tester, 'ics-share');
    expect(shared.single.content, contains('DTSTART;TZID=Asia/Shanghai:'));
  });

  testWidgets('上课提醒提前 20 分钟（不在 无/10/15/30 里）→ 默认 15', (tester) async {
    final (state, controller) = await seeded(tester, leadMinutes: 20);
    await pumpSettings(tester, state, controller);
    expect(selected(tester, 'ics-alarm-15'), isTrue);
  });

  testWidgets('分享失败：提示「导出失败」，弹窗留着可以重试', (tester) async {
    IcsShare.shareFile = (_) async => throw const FileSystemException('磁盘满');
    final (state, controller) = await seeded(tester);
    await pumpSettings(tester, state, controller);
    await tapAndSettle(tester, 'ics-share');
    expect(find.textContaining('导出失败'), findsOneWidget);
    expect(find.byKey(k('ics-sheet')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(k('ics-share'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('学期内没有课：说明「没有可导出的内容」，按钮不可点', (tester) async {
    final (state, controller) = await seeded(tester);
    await tester.runAsync(
      () => state.addTimetable(Timetable.empty(id: 'blank', name: '空课表')),
    );
    await pumpSettings(tester, state, controller);
    expect(
      tester.widget<Text>(find.byKey(k('ics-summary'))).data,
      contains('没有可导出的内容'),
    );
    expect(
      tester.widget<FilledButton>(find.byKey(k('ics-share'))).onPressed,
      isNull,
    );
  });

  testWidgets('课表管理页菜单「导出到日历（.ics）」：导出被点的那一张', (tester) async {
    final shared = captureShares();
    final other = buildTimetable()
      ..id = 'other'
      ..name = '另一张';
    final (state, controller) = await seeded(tester, extra: <Timetable>[other]);
    expect(state.currentTimetable!.id, 't');
    await pumpApp(tester, state, controller, const TimetableManagePage());

    await tester.tap(find.byKey(k('timetable-menu-other')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出到日历（.ics）'));
    await tester.pumpAndSettle();
    expect(find.byKey(k('ics-sheet')), findsOneWidget);

    await tapAndSettle(tester, 'ics-share');
    expect(shared.single.content, contains('X-WR-CALNAME:另一张\r\n'));
    expect(shared.single.content, contains('UID:jkb-other-math-'));
    expect(shared.single.mimeType, 'text/calendar');
  });
}
