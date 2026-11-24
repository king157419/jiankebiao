import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/features/import/adapters/school_adapter.dart';
import 'package:shu_schedule/features/import/adapters/zfsoft_adapter.dart';
import 'package:shu_schedule/features/import/pages/import_preview_page.dart';
import 'package:shu_schedule/models/period_time.dart';

/// 预览页 + AppState 的接线测试：确认「覆盖」与「新建」两条路径真的写进了状态。
///
/// v1.5.0（PLAN-1.5 D8，2026-10-08 下午修订）：开学日期三种来源——教务识别（直接用）、
/// 学校校历（默认值 + 确认导入时弹一次「现在是第几周？」预选校历周次）、
/// 都没有（同一个面板不预选，不选不能导入）。
///
/// 注意：`testWidgets` 跑在 fake async 区里，而 `Storage` 写的是真实文件，
/// 所以点完确认按钮后要用 [settleWithRealIo] 放行一次真实 IO 再 pump。
void main() {
  late Directory tempDir;
  late AppState appState;

  final adapter = ZfsoftAdapter(
    id: 'shu',
    name: '上海大学',
    baseUrl: 'https://jwxt.shu.edu.cn/jwglxt',
    homeUrl: 'https://jwxt.shu.edu.cn/',
  );

  String fixture() =>
      File('test/import/fixtures/shu_kb_envelope.json')
          .readAsStringSync(encoding: utf8);

  ImportResult loadResult() =>
      adapter.parse(fixture(), now: DateTime(2026, 10, 1));

  /// 同一份 fixture，但去掉 currentWeek（教务页面没识别到「第 N 周」）。
  ImportResult loadResultWithoutWeek() {
    final envelope = jsonDecode(fixture()) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(envelope['data'] as Map)
      ..remove('currentWeek');
    envelope['data'] = data;
    return adapter.parse(jsonEncode(envelope), now: DateTime(2026, 10, 1));
  }

  /// 打包进 App 的假日表（学校校历：2026-09-14 开学、18 周）。
  final bundledHolidays = HolidayPresets.fromJson(
    jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map,
  );

  final startText = find.byKey(
    const ValueKey<String>('import-start-date-text'),
  );
  final changeButton = find.byKey(
    const ValueKey<String>('import-start-date-change'),
  );
  final weekSheet = find.byKey(const ValueKey<String>('week-number-sheet'));
  final weekSheetConfirm = find.byKey(
    const ValueKey<String>('week-number-confirm'),
  );
  Finder weekChip(int w) => find.byKey(ValueKey<String>('week-number-$w'));

  String shownStartText(WidgetTester tester) =>
      tester.widget<Text>(startText).data!;
  String sheetTitle(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('week-number-title')))
      .data!;
  bool chipSelected(WidgetTester tester, int w) =>
      tester.widget<ChoiceChip>(weekChip(w)).selected;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shu_import_test');
    Storage.overrideDirectory = tempDir;
    appState = AppState();
    await appState.load();
  });

  tearDown(() async {
    Storage.overrideDirectory = null;
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows 上偶尔还有未关闭的句柄，留给系统清理临时目录。
    }
  });

  /// 铺一个「首页 → 预览页」的导航栈，并把测试窗口调高，
  /// 免得 ListView 把课程懒加载在视口外。
  Future<void> pumpPreview(
    WidgetTester tester, {
    ImportResult? result,
    ZfsoftAdapter? withAdapter,
    Future<void> Function()? onImported,
    DateTime? today,
    HolidayPresets? holidayPresets,
  }) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: appState,
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Text('首页占位'))),
        ),
      ),
    );
    // 用 Navigator 推进预览页，这样 popUntil(isFirst) 有得可退。
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push<void>(
          MaterialPageRoute<void>(
            builder: (_) => ImportPreviewPage(
              result: result ?? loadResult(),
              schoolName: '上海大学',
              adapter: withAdapter,
              onImported: onImported,
              today: today,
              holidayPresets: holidayPresets,
            ),
          ),
        );
    await tester.pumpAndSettle();
  }

  /// `_confirm` 里有好几跳真实文件 IO（replaceCourses → save → updateConfig → save），
  /// 每跳都要「让出真实时间 + flush 一次 fake async 的微任务队列」。
  Future<void> settleRealIo(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// 点按钮 → 放行真实文件 IO → 把回调 pump 出来。
  Future<void> tapAndSettleWithRealIo(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pump();
    await settleRealIo(tester);
  }

  testWidgets('预览页展示学期、周次、课程与折叠区', (tester) async {
    await pumpPreview(tester);
    expect(find.text('2026-2027 秋'), findsOneWidget);
    expect(find.textContaining('9月14日（周一）'), findsOneWidget);
    expect(find.textContaining('当前第 3 周'), findsOneWidget);
    expect(shownStartText(tester), '9月14日（周一）　教务系统显示当前第 3 周');
    expect(changeButton, findsOneWidget, reason: '教务识别的也能「改」');
    expect(find.text('高等数学(一)'), findsOneWidget);
    expect(find.text('马克思主义基本原理'), findsOneWidget);
    expect(find.text('确认导入（8 门）'), findsOneWidget);
    // 2 条合并后的白话提醒 + 1 条无固定时间的课。
    expect(find.textContaining('2 条提醒'), findsOneWidget);
    expect(find.textContaining('1 门没有固定时间的课'), findsOneWidget);
    // 无固定时间的课默认折叠，不会出现在课程勾选列表里。
    expect(find.text('创新创业实践'), findsNothing);
  });

  testWidgets('没有课表时强制走「新建」，写入 8 门课与 SHU 默认作息', (tester) async {
    expect(appState.timetables, isEmpty);
    await pumpPreview(tester);
    await tapAndSettleWithRealIo(tester, find.text('确认导入（8 门）'));

    expect(appState.timetables.length, 1);
    final tt = appState.currentTimetable!;
    expect(tt.name, '2026-2027 秋');
    expect(tt.courses.length, 8);
    expect(tt.config.name, '2026-2027 秋');
    expect(tt.config.startDate, DateTime(2026, 9, 14));
    expect(tt.config.totalWeeks, 18);
    expect(tt.config.periods.length, 12);
    expect(appState.settings.termStartConfirmed[tt.id], '2026-09-14');
    expect(find.text('已导入 8 门课'), findsOneWidget);
    expect(find.text('首页占位'), findsOneWidget, reason: '应当退回首页');
  });

  testWidgets('覆盖当前课表：换掉课程与学期设置，保留自定义作息', (tester) async {
    late final String existingId;
    await tester.runAsync(() async {
      final existing = await appState.createTimetable(name: '旧课表');
      existingId = existing.id;
      await appState.updatePeriods(<PeriodTime>[
        const PeriodTime(index: 1, start: '07:30', end: '08:15'),
        const PeriodTime(index: 2, start: '08:25', end: '09:10'),
      ]);
    });
    expect(appState.currentTimetable!.config.periods.length, 2);

    await pumpPreview(tester);
    await tapAndSettleWithRealIo(tester, find.text('确认导入（8 门）'));

    expect(appState.timetables.length, 1, reason: '覆盖不应新建课表');
    final tt = appState.currentTimetable!;
    expect(tt.id, existingId);
    expect(tt.courses.length, 8);
    expect(tt.name, '旧课表', reason: 'Timetable.name 不变，只改 config.name');
    expect(tt.config.name, '2026-2027 秋');
    expect(tt.config.startDate, DateTime(2026, 9, 14));
    expect(tt.config.totalWeeks, 18);
    expect(
      tt.config.periods.length,
      2,
      reason: '覆盖只改 name/startDate/totalWeeks，作息表必须保留',
    );
  });

  testWidgets('取消勾选后只导入被选中的课程', (tester) async {
    await pumpPreview(tester);
    // 初始是全选状态，按钮文案为「全不选」。
    await tester.tap(find.text('全不选'));
    await tester.pumpAndSettle();
    expect(find.text('确认导入（0 门）'), findsOneWidget);

    await tester.tap(find.text('高等数学(一)'));
    await tester.pumpAndSettle();
    expect(find.text('确认导入（1 门）'), findsOneWidget);

    await tapAndSettleWithRealIo(tester, find.text('确认导入（1 门）'));
    expect(appState.currentTimetable!.courses.length, 1);
    expect(appState.currentTimetable!.courses.single.name, '高等数学(一)');
  });

  testWidgets('导入写入课表元数据，课程来源 = systemType-schoolId，成功后回调清理登录态', (
    tester,
  ) async {
    var cleaned = 0;
    await pumpPreview(tester, onImported: () async => cleaned++);
    await tapAndSettleWithRealIo(tester, find.text('确认导入（8 门）'));

    final tt = appState.currentTimetable!;
    expect(tt.schoolId, 'shu');
    expect(tt.systemType, 'zfsoft');
    expect(tt.sourceTag, 'zfsoft-shu');
    expect(tt.termCode, '2026-2027-1');
    expect(tt.importedAt, isNotNull);
    expect(tt.courses.every((c) => c.source == 'zfsoft-shu'), isTrue);
    expect(tt.courses.every((c) => c.externalKey != null), isTrue);
    expect(cleaned, 1);
  });

  testWidgets('教务识别到周次：优先于校历，确认导入直接写入、不弹面板，并请首页弹校历建议', (tester) async {
    await pumpPreview(
      tester,
      today: DateTime(2026, 10, 8),
      holidayPresets: bundledHolidays,
    );
    expect(shownStartText(tester), '9月14日（周一）　教务系统显示当前第 3 周');
    expect(find.textContaining('校历'), findsNothing);
    await tester.tap(find.text('确认导入（8 门）'));
    await tester.pump();
    expect(weekSheet, findsNothing, reason: '教务识别的周次不再问');
    await settleRealIo(tester);

    final tt = appState.currentTimetable!;
    expect(tt.config.startDate, DateTime(2026, 9, 14));
    expect(tt.config.totalWeeks, 18);
    expect(appState.pendingCalendarPromptFor.value, tt.id);
  });

  testWidgets('验收（today=2026-10-08）：SHU 样例没有 currentWeek → 按校历 9月14日开学、现在第 4 周；'
      '确认导入时弹面板预选第 4 周，点「确定」才导入', (tester) async {
    await pumpPreview(
      tester,
      result: loadResultWithoutWeek(),
      today: DateTime(2026, 10, 8),
      holidayPresets: bundledHolidays,
    );
    expect(shownStartText(tester), '按上海大学校历 · 9月14日开学 · 现在第 4 周');
    expect(changeButton, findsOneWidget);
    expect(find.textContaining('还没确定'), findsNothing);
    expect(find.textContaining('请选择本学期第一周的周一'), findsNothing);
    // 识别不到周次不再算一条「提醒」。
    expect(find.textContaining('2 条提醒'), findsOneWidget);

    await tester.tap(find.text('确认导入（8 门）'));
    await tester.pumpAndSettle();
    expect(weekSheet, findsOneWidget);
    expect(sheetTitle(tester), '按上海大学校历，现在是第 4 周，对吗？');
    expect(chipSelected(tester, 4), isTrue);
    expect(find.text('将把 9月14日（周一）设为第一周'), findsOneWidget);
    expect(appState.timetables, isEmpty, reason: '点「确定」之前不导入');

    await tapAndSettleWithRealIo(tester, weekSheetConfirm);
    final tt = appState.currentTimetable!;
    expect(tt.config.startDate, DateTime(2026, 9, 14));
    expect(tt.config.totalWeeks, 18);
    expect(tt.schoolId, 'shu');
    expect(tt.courses.length, 8);
    expect(find.text('首页占位'), findsOneWidget);
    expect(appState.pendingCalendarPromptFor.value, tt.id);
  });

  testWidgets('校历来源：关掉面板 = 不导入，留在预览页；面板里改选第 5 周就按第 5 周导入', (tester) async {
    await pumpPreview(
      tester,
      result: loadResultWithoutWeek(),
      today: DateTime(2026, 10, 8),
      holidayPresets: bundledHolidays,
    );
    await tester.tap(find.text('确认导入（8 门）'));
    await tester.pumpAndSettle();
    expect(weekSheet, findsOneWidget);
    await tester.tapAt(const Offset(500, 20)); // 点面板外面关掉
    await tester.pumpAndSettle();
    expect(weekSheet, findsNothing);
    expect(appState.timetables, isEmpty);
    expect(find.text('确认导入（8 门）'), findsOneWidget, reason: '还在预览页');

    await tester.tap(find.text('确认导入（8 门）'));
    await tester.pumpAndSettle();
    await tester.tap(weekChip(5));
    await tester.pumpAndSettle();
    expect(find.text('将把 9月7日（周一）设为第一周'), findsOneWidget);
    await tapAndSettleWithRealIo(tester, weekSheetConfirm);
    expect(appState.currentTimetable!.config.startDate, DateTime(2026, 9, 7));
  });

  testWidgets('只有学校清单里的学期预设（适配器 presets）也算校历：总周数取校历的 20 周', (tester) async {
    final withPresets = ZfsoftAdapter(
      id: 'shu',
      name: '上海大学',
      baseUrl: 'https://jwxt.shu.edu.cn/jwglxt',
      homeUrl: 'https://jwxt.shu.edu.cn/',
      presets: <TermPreset>[
        TermPreset(
          id: 'a',
          name: '2026-2027 秋',
          startDate: DateTime(2026, 9, 14),
          totalWeeks: 20,
        ),
      ],
    );
    await pumpPreview(
      tester,
      result: loadResultWithoutWeek(),
      withAdapter: withPresets,
      today: DateTime(2026, 10, 1),
    );
    expect(shownStartText(tester), '按上海大学校历 · 9月14日开学 · 现在第 3 周');
    expect(
      tester
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .value,
      20,
    );

    await tester.tap(find.text('确认导入（8 门）'));
    await tester.pumpAndSettle();
    expect(sheetTitle(tester), '按上海大学校历，现在是第 3 周，对吗？');
    expect(chipSelected(tester, 3), isTrue);
    expect(weekChip(20), findsOneWidget);
    await tapAndSettleWithRealIo(tester, weekSheetConfirm);
    final tt = appState.currentTimetable!;
    expect(tt.config.startDate, DateTime(2026, 9, 14));
    expect(tt.config.totalWeeks, 20);
  });

  testWidgets('没有校历：「还没确定 · 点这里选」；确认按钮不禁用，点了弹不预选的面板，不选不能导入', (tester) async {
    await pumpPreview(
      tester,
      result: loadResultWithoutWeek(),
      today: DateTime(2026, 10, 8),
    );
    expect(shownStartText(tester), '还没确定 · 点这里选');
    expect(changeButton, findsNothing);
    final confirm = find.widgetWithText(FilledButton, '确认导入（8 门）');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(sheetTitle(tester), '现在是第几周？');
    for (var w = 1; w <= 18; w++) {
      expect(chipSelected(tester, w), isFalse, reason: '第 $w 周不该预选');
    }
    expect(find.text('选一个周次'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(weekSheetConfirm).onPressed,
      isNull,
      reason: '不选周次不能确定',
    );
    await tester.tapAt(const Offset(500, 20));
    await tester.pumpAndSettle();
    expect(appState.timetables, isEmpty, reason: '没选周次就没有导入');

    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(weekChip(4));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(weekSheetConfirm).onPressed, isNotNull);
    await tapAndSettleWithRealIo(tester, weekSheetConfirm);
    final tt = appState.currentTimetable!;
    expect(tt.config.startDate, DateTime(2026, 9, 14));
    expect(tt.config.totalWeeks, 18);
  });

  testWidgets('没有校历：先点「点这里选」选第 6 周 → 显示「已手动选择」，确认导入不再弹面板', (tester) async {
    await pumpPreview(
      tester,
      result: loadResultWithoutWeek(),
      today: DateTime(2026, 10, 8),
    );
    await tester.tap(startText);
    await tester.pumpAndSettle();
    expect(sheetTitle(tester), '现在是第几周？');
    await tester.tap(weekChip(6));
    await tester.pumpAndSettle();
    await tester.tap(weekSheetConfirm);
    await tester.pumpAndSettle();
    expect(shownStartText(tester), '8月31日开学 · 现在第 6 周 · 已手动选择');
    expect(changeButton, findsOneWidget);

    await tester.tap(find.text('确认导入（8 门）'));
    await tester.pump();
    expect(weekSheet, findsNothing);
    await settleRealIo(tester);
    expect(find.text('首页占位'), findsOneWidget);
    expect(appState.currentTimetable!.config.startDate, DateTime(2026, 8, 31));
  });

  testWidgets('「改」：教务识别的周次也能改（预选按识别结果算出的本周），改完按手动选的导入', (tester) async {
    await pumpPreview(tester, today: DateTime(2026, 10, 8));
    await tester.tap(changeButton);
    await tester.pumpAndSettle();
    expect(sheetTitle(tester), '现在是第几周？');
    expect(chipSelected(tester, 4), isTrue, reason: '9月14日开学，10月8日是第 4 周');
    await tester.tap(weekChip(2));
    await tester.pumpAndSettle();
    await tester.tap(weekSheetConfirm);
    await tester.pumpAndSettle();
    expect(shownStartText(tester), '9月28日开学 · 现在第 2 周 · 已手动选择');

    await tapAndSettleWithRealIo(tester, find.text('确认导入（8 门）'));
    expect(weekSheet, findsNothing);
    expect(appState.currentTimetable!.config.startDate, DateTime(2026, 9, 28));
  });

  testWidgets('新建课表时沿用当前课表的作息（当前课表作息 ?? 模板）', (tester) async {
    await tester.runAsync(() async {
      await appState.createTimetable(name: '旧课表');
      await appState.updatePeriods(<PeriodTime>[
        const PeriodTime(index: 1, start: '07:30', end: '08:15'),
        const PeriodTime(index: 2, start: '08:25', end: '09:10'),
      ]);
    });
    await pumpPreview(tester);
    expect(find.text('沿用当前课表作息（2 节）'), findsOneWidget);
    expect(find.textContaining('课程用到了第 12 节'), findsOneWidget);

    await tester.tap(find.text('新建课表'));
    await tester.pumpAndSettle();
    await tapAndSettleWithRealIo(tester, find.text('确认导入（8 门）'));
    expect(appState.timetables.length, 2);
    expect(appState.currentTimetable!.config.periods.length, 2);
  });

  testWidgets('作息可以改选模板', (tester) async {
    await tester.runAsync(() async {
      await appState.createTimetable(name: '旧课表');
      await appState.updatePeriods(<PeriodTime>[
        const PeriodTime(index: 1, start: '07:30', end: '08:15'),
      ]);
    });
    await pumpPreview(tester);
    await tester.tap(find.text('沿用当前课表作息（1 节）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模板：${periodTemplates.first.name}'));
    await tester.pumpAndSettle();
    expect(find.text('模板：${periodTemplates.first.name}'), findsOneWidget);
    expect(find.textContaining('课程用到了第'), findsNothing);

    await tapAndSettleWithRealIo(tester, find.text('确认导入（8 门）'));
    expect(appState.currentTimetable!.config.periods.length, 12);
  });

  testWidgets('开学前导入（today=2026-09-10）：按校历显示「还没开学」，确认面板默认选中「还没开学（9月14日开学）」', (
    tester,
  ) async {
    await pumpPreview(
      tester,
      result: loadResultWithoutWeek(),
      today: DateTime(2026, 9, 10),
      holidayPresets: bundledHolidays,
    );
    expect(shownStartText(tester), '按上海大学校历 · 9月14日开学 · 还没开学');
    expect(changeButton, findsOneWidget);

    await tester.tap(find.text('确认导入（8 门）'));
    await tester.pumpAndSettle();
    expect(weekSheet, findsOneWidget);
    expect(sheetTitle(tester), '按上海大学校历，9月14日开学，对吗？');
    final upcomingChip = find.byKey(
      const ValueKey<String>('week-number-upcoming'),
    );
    expect(upcomingChip, findsOneWidget);
    expect(find.text('还没开学（9月14日开学）'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(upcomingChip).selected, isTrue);

    await tapAndSettleWithRealIo(tester, weekSheetConfirm);
    final tt = appState.currentTimetable!;
    expect(tt.config.startDate, DateTime(2026, 9, 14));
    expect(appState.settings.termStartConfirmed[tt.id], '2026-09-14');
    expect(find.text('首页占位'), findsOneWidget);
  });

  testWidgets('schoolId 来源统一 + 同名同教师多时段门数去重：result 无 schoolId 时落回 adapter.id', (
    tester,
  ) async {
    final base = loadResultWithoutWeek();
    final extraSlot = base.courses.first.copyWith(id: 'extra-wed', day: 3);
    final noSchoolResult = ImportResult(
      courses: <dynamic>[...base.courses, extraSlot].cast(),
      termName: base.termName,
      termCode: base.termCode,
      systemType: base.systemType,
      schoolId: null,
    );
    await pumpPreview(
      tester,
      result: noSchoolResult,
      withAdapter: adapter,
      today: DateTime(2026, 10, 8),
      holidayPresets: bundledHolidays,
    );
    // 9 条时段记录，但高等数学(一)+王建国占 2 条 → 仍显示 8 门，导入后 SnackBar 写「8 门课（每周 9 节）」。
    expect(shownStartText(tester), '按上海大学校历 · 9月14日开学 · 现在第 4 周');
    expect(find.text('确认导入（8 门）'), findsOneWidget);

    await tester.tap(find.text('确认导入（8 门）'));
    await tester.pumpAndSettle();
    await tapAndSettleWithRealIo(tester, weekSheetConfirm);

    final tt = appState.currentTimetable!;
    expect(tt.schoolId, 'shu', reason: 'result.schoolId 为空时同样写入 adapter.id');
    expect(tt.courses, hasLength(9));
    expect(find.text('已导入 8 门课（每周 9 节）'), findsOneWidget);
  });

  group('ImportPreviewDefaults', () {
    test('作息优先级：识别出的 > 当前课表 > 模板', () {
      const detected = <PeriodTime>[
        PeriodTime(index: 1, start: '08:10', end: '08:55'),
      ];
      const current = <PeriodTime>[
        PeriodTime(index: 1, start: '07:30', end: '08:15'),
        PeriodTime(index: 2, start: '08:25', end: '09:10'),
      ];
      expect(
        ImportPreviewDefaults.periods(
          detected: detected,
          current: current,
        ).source,
        PeriodSource.detected,
      );
      final cur = ImportPreviewDefaults.periods(current: current);
      expect(cur.source, PeriodSource.current);
      expect(cur.periods.length, 2);
      final tpl = ImportPreviewDefaults.periods(
        detected: const <PeriodTime>[],
        periodProfileId: 'nope',
      );
      expect(tpl.source, PeriodSource.template);
      expect(tpl.template!.id, periodTemplates.first.id);
      expect(tpl.periods, defaultPeriods);
    });
  });
}
