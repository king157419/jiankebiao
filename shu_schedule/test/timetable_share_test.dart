import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/features/settings/timetable_manage_page.dart';
import 'package:shu_schedule/features/settings/timetable_share.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/harness.dart';

/// v1.3.0 Phase C.3：单张课表分享与「从文件导入课表」。
void main() {
  Timetable sample({String id = 'tt1', String name = '2026 秋'}) => Timetable(
    id: id,
    name: name,
    config: ScheduleConfig(
      name: '2026-2027 秋',
      startDate: DateTime(2026, 9, 14),
      totalWeeks: 18,
      overrides: <String, DateOverride>{
        '2026-10-10': DateOverride.actAs(weekday: 1, note: '国庆调休'),
        '2026-10-01': const DateOverride.cancelled(),
      },
    ),
    courses: <Course>[
      Course(
        id: 'c1',
        name: '高等数学',
        teacher: '张老师',
        location: 'A101',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: <int>[1, 2, 3],
        colorIndex: 3,
        groupId: 'g-math',
        source: 'zfsoft-shu',
        externalKey: 'k1',
      ),
      Course(
        id: 'c2',
        name: '高等数学',
        day: 3,
        startPeriod: 3,
        endPeriod: 4,
        weeks: <int>[1, 2, 3],
        colorIndex: 3,
        groupId: 'g-math',
      ),
    ],
    schoolId: 'shu',
    systemType: 'zfsoft',
    termCode: '2026-2027-1',
    importedAt: DateTime(2026, 9, 20, 10),
  );

  group('导出格式', () {
    test(
      '单表 JSON 是备份 v2 的子集：version 2 / kind timetable / 一张课表 / 不带 settings',
      () {
        final json = jsonDecode(
          TimetableShare.exportJson(sample(), now: DateTime(2026, 9, 23)),
        ) as Map<String, dynamic>;
        expect(json['version'], Storage.backupVersion);
        expect(json['kind'], 'timetable');
        expect(json['app'], '简课表');
        expect(json.containsKey('settings'), isFalse);
        expect((json['timetables'] as List).length, 1);
      },
    );

    test('文件名：简课表-<课表名>-yyyyMMdd.json，非法字符换掉', () {
      expect(
        TimetableShare.fileNameFor(sample(), DateTime(2026, 9, 3)),
        '简课表-2026 秋-20260903.json',
      );
      expect(TimetableShare.safeFileName('a/b:c*?"<>|d'), 'a_b_c______d');
      expect(TimetableShare.safeFileName('  ..  '), '课表');
      expect(TimetableShare.safeFileName('x' * 60).length, 40);
    });

    test('uniqueName：冲突时加（2）（3）', () {
      expect(TimetableShare.uniqueName('A', <String>['B']), 'A');
      expect(TimetableShare.uniqueName('A', <String>['A']), 'A（2）');
      expect(TimetableShare.uniqueName('A', <String>['A', 'A（2）']), 'A（3）');
      expect(TimetableShare.uniqueName('  ', <String>[]), '导入的课表');
    });

    test('导出 → 解析往返：课程、分组、调休、导入元数据都在', () {
      final snap = TimetableShare.parse(TimetableShare.exportJson(sample()));
      final tt = snap.timetables.single;
      expect(tt.name, '2026 秋');
      expect(tt.courses.length, 2);
      expect(tt.courses.map((c) => c.groupId).toSet(), <String?>{'g-math'});
      expect(tt.courses.first.externalKey, 'k1');
      expect(tt.config.overrides.length, 2);
      expect(tt.config.overrides['2026-10-10']!.actAsWeekday, 1);
      expect(tt.config.overrides['2026-10-10']!.note, '国庆调休');
      expect(tt.config.overrides['2026-10-01']!.cancelled, isTrue);
      expect(tt.schoolId, 'shu');
      expect(tt.systemType, 'zfsoft');
      expect(tt.termCode, '2026-2027-1');
      expect(tt.importedAt, DateTime(2026, 9, 20, 10));
    });

    test('不是课表文件：抛 FormatException', () {
      expect(() => TimetableShare.parse('not json'), throwsFormatException);
      expect(() => TimetableShare.parse('[]'), throwsFormatException);
      expect(
        () => TimetableShare.parse('{"version":2,"timetables":[]}'),
        throwsFormatException,
      );
    });
  });

  group('导入写入 AppState', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('phase_c_share'));
    tearDown(storage.tearDown);

    test('新建（不覆盖）、名字冲突加后缀、课程 id 重新生成、切换过去', () async {
      final state = AppState();
      await state.load();
      await state.addTimetable(sample());
      final before = state.timetables.single;

      final snap = TimetableShare.parse(TimetableShare.exportJson(sample()));
      final created = await TimetableShare.importInto(state, snap);

      expect(state.timetables.length, 2);
      expect(created.single.name, '2026 秋（2）');
      expect(created.single.id, isNot(before.id));
      expect(state.currentTimetable!.id, created.single.id);
      // 原表原封不动。
      expect(state.timetables.first.courses.map((c) => c.id), <String>[
        'c1',
        'c2',
      ]);
      final ids = created.single.courses.map((c) => c.id).toSet();
      expect(ids.length, 2);
      expect(ids.intersection(<String>{'c1', 'c2'}), isEmpty);
      expect(created.single.courses.map((c) => c.groupId).toSet(), <String?>{
        'g-math',
      });
      expect(created.single.config.overrides.length, 2);

      // 同一个文件再导一次 → （3）。
      final again = await TimetableShare.importInto(state, snap);
      expect(again.single.name, '2026 秋（3）');
    });

    test('1.2.0 导出的旧备份（v1、带 settings）也能当课表文件导入，只取课表不动设置', () async {
      final state = AppState();
      await state.load();
      await state.setThemeId('mint');
      final text = File('test/fixtures/v1_2_0/backup_v1.json')
          .readAsStringSync();
      final snap = TimetableShare.parse(text);
      final created = await TimetableShare.importInto(state, snap);
      expect(created, isNotEmpty);
      expect(state.settings.themeId, 'mint');
      // v1 → v2 迁移：旧来源标记 zfsoft-shu 推断出学校。
      final migrated = created.firstWhere(
        (t) => t.courses.any((c) => c.source == 'zfsoft-shu'),
      );
      expect(migrated.name, '2026-2027 秋');
      expect(migrated.schoolId, 'shu');
      expect(migrated.systemType, 'zfsoft');
      expect(migrated.courses.first.name, '高等数学 A(一)');
    });

    test('v1 格式的单表 JSON（没有 version / 新字段）也能导', () async {
      final state = AppState();
      await state.load();
      final legacy = jsonEncode(<String, dynamic>{
        'timetables': <dynamic>[
          <String, dynamic>{
            'id': 'old',
            'name': '老课表',
            'config': <String, dynamic>{
              'name': '2025 秋',
              'startDate': '2025-09-08',
              'totalWeeks': 16,
            },
            'courses': <dynamic>[
              <String, dynamic>{
                'id': 'x',
                'name': '旧课',
                'day': 2,
                'startPeriod': 1,
                'endPeriod': 2,
                'weeks': <int>[1, 2],
                'source': 'zfsoft-shu',
              },
            ],
          },
        ],
      });
      final created = await TimetableShare.importInto(
        state,
        TimetableShare.parse(legacy),
      );
      final tt = created.single;
      expect(tt.name, '老课表');
      expect(tt.courses.single.name, '旧课');
      expect(tt.config.overrides, isEmpty);
      expect(tt.schoolId, 'shu');
    });
  });

  group('课表管理页', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('phase_c_share_ui'));
    tearDown(() async {
      TimetableShare.resetIo();
      await storage.tearDown();
    });

    testWidgets('菜单「分享此课表」：只导出这一张，文件名带课表名', (tester) async {
      final shared = <SharedTimetableFile>[];
      TimetableShare.shareFile = (f) async => shared.add(f);
      final (state, controller) = await loadState(
        tester,
        seed: (s) async {
          await s.addTimetable(sample());
          await s.addTimetable(sample(id: 'tt2', name: '另一张'));
        },
      );
      await pumpApp(tester, state, controller, const TimetableManagePage());

      await tester.tap(
        find.byKey(const ValueKey<String>('timetable-menu-tt1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享此课表'));
      await tester.pumpAndSettle();

      expect(shared.length, 1);
      expect(shared.single.fileName, startsWith('简课表-2026 秋-'));
      expect(shared.single.fileName, endsWith('.json'));
      final json = jsonDecode(shared.single.json) as Map<String, dynamic>;
      final tts = json['timetables'] as List;
      expect(tts.length, 1);
      expect((tts.single as Map)['name'], '2026 秋');
    });

    testWidgets('右上角「从文件导入课表」：选到的文件新建成一张课表并提示', (tester) async {
      final text = TimetableShare.exportJson(sample(name: '同学的课表'));
      TimetableShare.pickText = () async => text;
      final (state, controller) = await loadState(
        tester,
        seed: (s) => s.addTimetable(sample()),
      );
      await pumpApp(tester, state, controller, const TimetableManagePage());

      await tester.tap(
        find.byKey(const ValueKey<String>('import-timetable-file')),
      );
      await settleWithRealIo(tester, rounds: 40);
      await tester.pump(const Duration(milliseconds: 300));

      expect(state.timetables.length, 2);
      expect(state.currentTimetable!.name, '同学的课表');
      expect(find.textContaining('已导入「同学的课表」，共 2 门课'), findsOneWidget);
    });

    testWidgets('选到坏文件：提示「这不是有效的课表文件」，不新建', (tester) async {
      TimetableShare.pickText = () async => '{"hello":1}';
      final (state, controller) = await loadState(
        tester,
        seed: (s) => s.addTimetable(sample()),
      );
      await pumpApp(tester, state, controller, const TimetableManagePage());
      await tester.tap(
        find.byKey(const ValueKey<String>('import-timetable-file')),
      );
      await settleWithRealIo(tester, rounds: 5);
      expect(state.timetables.length, 1);
      expect(find.textContaining('这不是有效的课表文件'), findsOneWidget);
    });
  });
}
