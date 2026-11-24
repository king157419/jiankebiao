import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';
import 'package:shu_schedule/features/settings/timetable_manage_page.dart';
import 'package:shu_schedule/features/settings/week_number_sheet.dart';
import 'package:shu_schedule/features/timetable/week_view_page.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/fake_holiday_repository.dart';
import 'helpers/harness.dart';
import 'helpers/reminder_fixtures.dart';

/// v1.5.0 任务 B：设置页收敛成「课表 / 显示 / 桌面 / 其他」四组，
/// 备份合并成一个「备份与恢复」入口（D6），「从文件导入课表」删除（D5），
/// 课表管理页去掉右上角「选择文件」和菜单里的「分享此课表」（D5）。
///
/// 任务 A2：设置页不再是底部 tab，而是从周视图右上角齿轮 push 进来的普通页面，
/// AppBar 自动带返回键。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = TempStorage();
  setUp(() => storage.setUp('settings_page'));
  tearDown(storage.tearDown);

  ValueKey<String> k(String s) => ValueKey<String>(s);

  Future<void> pumpSettings(
    WidgetTester tester, {
    UpdateChecker? checker,
  }) async {
    final (state, controller) = await loadState(
      tester,
      seed: (s) => s.addTimetable(buildTimetable()),
    );
    await pumpApp(
      tester,
      state,
      controller,
      SettingsPage(
        updateChecker: checker ?? UpdateChecker(sources: const <String>[]),
      ),
      size: const Size(900, 4000),
    );
  }

  double y(WidgetTester tester, Finder f) {
    expect(f, findsOneWidget, reason: '$f');
    return tester.getTopLeft(f).dy;
  }

  testWidgets('四组的标题和组内条目按计划顺序排列（未配置更新源时隐藏「检查更新」，已配置时显示）', (tester) async {
    await pumpSettings(tester);
    expect(find.byKey(k('settings-check-update')), findsNothing);

    await pumpSettings(
      tester,
      checker: UpdateChecker(
        sources: const <String>['https://updates.example/latest.json'],
      ),
    );
    final order = <(String, Finder)>[
      ('组：课表', find.text('课表')),
      ('课表管理', find.text('课表管理')),
      ('学期设置', find.text('学期设置')),
      ('作息时间', find.text('作息时间')),
      ('上课提醒', find.byKey(k('settings-reminders'))),
      ('导出到日历', find.byKey(k('settings-export-ics'))),
      ('组：显示', find.text('显示')),
      ('显示非本周课程', find.text('显示非本周课程')),
      ('格子里显示时间', find.text('格子里显示时间')),
      ('主题', find.text('主题')),
      ('组：桌面', find.text('桌面')),
      ('添加桌面小组件', find.byKey(k('settings-add-widget'))),
      ('组：其他', find.text('其他')),
      ('记住教务登录', find.byKey(k('settings-remember-login'))),
      ('备份与恢复', find.byKey(k('settings-backup'))),
      ('检查更新', find.byKey(k('settings-check-update'))),
      ('关于简课表', find.byKey(k('settings-about'))),
      ('隐私说明', find.byKey(k('settings-privacy'))),
      ('反馈', find.byKey(k('settings-feedback'))),
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        y(tester, order[i].$2),
        greaterThan(y(tester, order[i - 1].$2)),
        reason: '「${order[i].$1}」应该在「${order[i - 1].$1}」下面',
      );
    }
    expect(
      find.descendant(
        of: find.byKey(k('settings-about')),
        matching: find.text('关于简课表'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('删掉的条目和旧分组标题都不在了', (tester) async {
    await pumpSettings(tester);
    for (final gone in <String>[
      '导出备份',
      '导入备份',
      '从文件导入课表',
      '教务导入',
      '备份',
      '关于',
      '桌面小组件',
    ]) {
      expect(find.text(gone), findsNothing, reason: '还有「$gone」');
    }
    expect(find.byKey(k('settings-import-timetable')), findsNothing);
    // 「上课提醒」只剩 tile 标题，不再单独成组。
    expect(find.text('上课提醒'), findsOneWidget);
  });

  testWidgets('副标题：桌面 / 备份与恢复 / 隐私说明', (tester) async {
    await pumpSettings(tester);
    Finder sub(String key, String text) =>
        find.descendant(of: find.byKey(k(key)), matching: find.text(text));
    expect(sub('settings-add-widget', '把课表放到桌面上，不打开 App 也能看'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(k('settings-add-widget')),
        matching: find.text('添加桌面小组件'),
      ),
      findsOneWidget,
    );
    expect(sub('settings-backup', '备份与恢复'), findsOneWidget);
    expect(sub('settings-backup', '换手机、重装前先导出一份'), findsOneWidget);
    expect(
      sub('settings-privacy', '课表只存在手机里；只在导入、检查更新、更新假期表时联网'),
      findsOneWidget,
    );
    expect(settingsAddWidgetSubtitle, '把课表放到桌面上，不打开 App 也能看');
    expect(settingsBackupSubtitle, '换手机、重装前先导出一份');
    expect(settingsPrivacySubtitle, '课表只存在手机里；只在导入、检查更新、更新假期表时联网');

    // R1-5：设置页「主题」副标题只显示主题名，所有主题 description 都不含色值 `#`。
    final themeTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '主题'),
    );
    expect((themeTile.subtitle! as Text).data, '经典蓝');
    final rawThemes = jsonDecode(
      File('assets/themes/themes.json').readAsStringSync(),
    ) as List;
    for (final t in rawThemes.cast<Map>()) {
      expect(
        t['description'] as String,
        isNot(contains('#')),
        reason: '${t['id']} 的 description 里还有 #',
      );
    }
  });

  testWidgets('页面上的文字没有技术术语', (tester) async {
    await pumpSettings(tester);
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join('\n');
    for (final bad in <String>[
      'JSON',
      'WebView',
      'SDK',
      'API',
      'USE_EXACT',
      'SHA',
      'Cookie',
      '精确闹钟',
      'Android 1',
    ]) {
      expect(texts, isNot(contains(bad)), reason: '设置页还有「$bad」');
    }
  });

  testWidgets('点「备份与恢复」弹出面板：导出备份文件 / 从备份文件恢复', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byKey(k('settings-backup')));
    await tester.pumpAndSettle();
    expect(find.byKey(k('backup-sheet')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(k('backup-export')),
        matching: find.text('导出备份文件'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(k('backup-restore')),
        matching: find.text('从备份文件恢复'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('JSON'), findsNothing);
    // 面板标题在上面，导出在恢复上面。
    expect(
      y(tester, find.byKey(k('backup-export'))),
      lessThan(y(tester, find.byKey(k('backup-restore')))),
    );
  });

  testWidgets('课表管理页：右上角没有按钮，菜单只剩导出到日历 / 重命名 / 删除', (tester) async {
    final (state, controller) = await loadState(
      tester,
      seed: (s) => s.addTimetable(buildTimetable()),
    );
    await pumpApp(tester, state, controller, const TimetableManagePage());
    expect(find.byKey(k('import-timetable-file')), findsNothing);
    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.byType(IconButton)),
      findsNothing,
    );

    await tester.tap(find.byKey(k('timetable-menu-t')));
    await tester.pumpAndSettle();
    final items = tester
        .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
        .map((i) => i.value)
        .toList();
    expect(items, <String>['ics', 'rename', 'delete']);
    expect(find.text('分享此课表'), findsNothing);
    expect(find.text('从文件导入课表'), findsNothing);
  });

  testWidgets('课表管理页（R1-2 / R1-13）：门数按同名+同教师去重；新建课表询问第几周，关掉面板给提示', (
    tester,
  ) async {
    final multiSlot = Timetable(
      id: 't1',
      name: '大三秋',
      config: ScheduleConfig(
        name: '2026-2027 秋',
        startDate: DateTime(2026, 9, 14),
      ),
      courses: <Course>[
        Course(
          id: 'c1',
          name: '马克思主义基本原理',
          teacher: '李老师',
          day: 5,
          startPeriod: 1,
          endPeriod: 2,
        ),
        Course(
          id: 'c2',
          name: '马克思主义基本原理',
          teacher: '李老师',
          day: 5,
          startPeriod: 3,
          endPeriod: 4,
        ),
        Course(
          id: 'c3',
          name: '高等数学',
          teacher: '张老师',
          day: 1,
          startPeriod: 1,
          endPeriod: 2,
        ),
      ],
    );
    final (state, controller) = await loadState(
      tester,
      seed: (s) => s.addTimetable(multiSlot),
    );
    await pumpApp(
      tester,
      state,
      controller,
      TimetableManagePage(clock: () => DateTime(2026, 10, 8, 10)),
    );
    expect(find.textContaining('2 门课（每周 3 节）'), findsOneWidget);

    // 路径 1a：新建课表 → 填名字 → 弹「现在是第几周？」→ 选第 4 周 → 9/14 开学且写入 termStartConfirmed。
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新课表A');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.byKey(k('week-number-sheet')), findsOneWidget);
    expect(find.text('现在是第几周？'), findsOneWidget);
    await tester.tap(find.byKey(k('week-number-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(k('week-number-confirm')));
    await settleWithRealIo(tester);
    await tester.pumpAndSettle();

    final createdA = state.timetables.firstWhere((t) => t.name == '新课表A');
    expect(createdA.config.startDate, DateTime(2026, 9, 14));
    expect(state.settings.termStartConfirmed[createdA.id], '2026-09-14');

    // 删除确认框同样使用去重后的 courseCountText。
    await tester.tap(find.byKey(k('timetable-menu-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('确定删除「大三秋」及其 2 门课（每周 3 节）吗？不可撤销。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 路径 1b：新建课表 → 填名字 → 直接关掉周次面板 → 仍建表（mondayOf(today)=10/5），不记 confirmed，弹 SnackBar。
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '未定周课表');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.byKey(k('week-number-sheet')), findsOneWidget);
    await tester.tapAt(const Offset(450, 20));
    await settleUntil(tester, find.text(unconfirmedTermStartHint));
    await tester.pumpAndSettle();

    final createdB = state.timetables.firstWhere((t) => t.name == '未定周课表');
    expect(createdB.config.startDate, DateTime(2026, 10, 5));
    expect(state.settings.termStartConfirmed.containsKey(createdB.id), isFalse);
    expect(find.text(unconfirmedTermStartHint), findsOneWidget);
  });

  testWidgets('从周视图齿轮进来：AppBar 自带返回键；每套主题下返回键都和标题、齿轮同色，在底色上看得清', (
    tester,
  ) async {
    final (state, controller) = await loadState(
      tester,
      seed: (s) => s.addTimetable(buildTimetable()),
    );
    final themes = controller.themes;
    expect(themes.length, greaterThan(1), reason: '主题表没读到');

    /// [of] 里第一段文字 / 第一个图标实际画出来的颜色。
    Color? drawn(Finder of) => tester
        .widget<RichText>(
          find.descendant(of: of, matching: find.byType(RichText)).first,
        )
        .text
        .style
        ?.color;
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    final gear = find.byKey(k('week-settings'));
    for (final theme in themes) {
      await tester.runAsync(() => controller.select(theme.id));
      await pumpApp(
        tester,
        state,
        controller,
        WeekViewPage(
          clock: () => DateTime(2026, 10, 7, 10),
          holidayRepository: FakeHolidayRepository(data: HolidayPresets.empty),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.current.id, theme.id);
      final header = theme.colors.headerText;
      expect(drawn(gear), header, reason: '${theme.id}：齿轮');

      await tester.tap(gear);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget, reason: theme.id);
      final back = find.byType(BackButton);
      expect(back, findsOneWidget, reason: '${theme.id}：没有返回键');
      expect(drawn(back), header, reason: '${theme.id}：返回键');
      expect(
        drawn(
          find.descendant(of: find.byType(AppBar), matching: find.text('设置')),
        ),
        header,
        reason: '${theme.id}：标题',
      );
      expect(
        contrast(header, theme.colors.background),
        greaterThanOrEqualTo(4.5),
        reason: '${theme.id}：返回键在底色上看不清',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing, reason: theme.id);
      expect(gear, findsOneWidget, reason: theme.id);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await settleWithRealIo(tester, rounds: 5);
  });
}
