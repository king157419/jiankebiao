import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/features/import/adapters/school_adapter.dart';
import 'package:shu_schedule/features/import/adapters/zfsoft_adapter.dart';
import 'package:shu_schedule/features/import/pages/import_preview_page.dart';
import 'package:shu_schedule/models/period_time.dart';

/// 预览页 + AppState 的接线测试：确认「覆盖」与「新建」两条路径真的写进了状态。
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
            ),
          ),
        );
    await tester.pumpAndSettle();
  }

  /// 点按钮 → 放行真实文件 IO → 把回调 pump 出来。
  Future<void> tapAndSettleWithRealIo(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pump();
    // `_confirm` 里有好几跳真实文件 IO（replaceCourses → save → updateConfig → save），
    // 每跳都要「让出真实时间 + flush 一次 fake async 的微任务队列」。
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('预览页展示学期、周次、课程与折叠区', (tester) async {
    await pumpPreview(tester);
    expect(find.text('2026-2027 秋'), findsOneWidget);
    expect(find.textContaining('2026-09-14'), findsOneWidget);
    expect(find.textContaining('当前第 3 周'), findsOneWidget);
    expect(find.text('高等数学(一)'), findsOneWidget);
    expect(find.text('马克思主义基本原理'), findsOneWidget);
    expect(find.text('确认导入（8 门）'), findsOneWidget);
    // 4 条脏数据 warning + 1 条无固定时间的课。
    expect(find.textContaining('4 条提醒'), findsOneWidget);
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
    expect(find.textContaining('已导入 8 门课程'), findsOneWidget);
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

  testWidgets('没识别到周次：默认最近的周一，确认时先问一句再导入', (tester) async {
    // 2026-10-01 是周四 → 最近的周一是 2026-09-28。
    await pumpPreview(
      tester,
      result: loadResultWithoutWeek(),
      today: DateTime(2026, 10, 1),
    );
    expect(find.textContaining('2026-09-28'), findsOneWidget);
    expect(find.textContaining('请选择本学期第一周的周一'), findsWidgets);
    expect(find.textContaining('未识别到周次，请确认'), findsOneWidget);
    // 不再出现任何学校的校历日期。
    expect(find.textContaining('2026-09-14'), findsNothing);

    await tester.tap(find.text('确认导入（8 门）'));
    await tester.pumpAndSettle();
    expect(find.text('确认开学日期'), findsOneWidget);
    await tapAndSettleWithRealIo(tester, find.text('对，导入'));

    final tt = appState.currentTimetable!;
    expect(tt.config.startDate, DateTime(2026, 9, 28));
    expect(tt.courses.length, 8);
  });

  testWidgets('没识别到周次：学校有校历预设时给快捷选项，点了就不用再确认', (tester) async {
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
    await tester.tap(find.text('2026-2027 秋 · 2026-09-14'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已手动选择'), findsOneWidget);

    await tapAndSettleWithRealIo(tester, find.text('确认导入（8 门）'));
    expect(find.text('确认开学日期'), findsNothing);
    final tt = appState.currentTimetable!;
    expect(tt.config.startDate, DateTime(2026, 9, 14));
    expect(tt.config.totalWeeks, 20);
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

    test('开学日期：识别到 → 推断值（对齐周一）；没识别到 → 最近的周一，需要确认', () {
      final withWeek = loadResult();
      expect(
        ImportPreviewDefaults.startDate(withWeek, DateTime(2027, 1, 1)),
        DateTime(2026, 9, 14),
      );
      expect(ImportPreviewDefaults.startDateNeedsConfirm(withWeek), isFalse);

      final noWeek = loadResultWithoutWeek();
      expect(ImportPreviewDefaults.startDateNeedsConfirm(noWeek), isTrue);
      expect(
        ImportPreviewDefaults.startDate(noWeek, DateTime(2026, 10, 1)),
        DateTime(2026, 9, 28),
      );
      expect(
        ImportPreviewDefaults.startDate(noWeek, DateTime(2026, 10, 2)),
        DateTime(2026, 10, 5),
        reason: '周五离下周一更近',
      );
    });

    test('nearestMonday / mondayOf：一周七天 + 跨月 / 跨年 / 夏令时附近', () {
      final starts = <DateTime>[
        DateTime(2026, 9, 14),
        DateTime(2026, 12, 28),
        DateTime(2027, 3, 8),
        DateTime(2027, 3, 22),
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 26),
      ];
      for (final monday in starts) {
        for (var i = 0; i < 7; i++) {
          final d = ScheduleUtils.addDays(monday, i);
          final expected = i <= 3 ? monday : ScheduleUtils.addDays(monday, 7);
          final got = ScheduleUtils.nearestMonday(d);
          expect(got, expected, reason: '$d');
          expect(got.weekday, DateTime.monday);
          expect(got.hour, 0);
          expect(ScheduleUtils.mondayOf(d), monday, reason: '$d');
        }
      }
    });
  });
}
