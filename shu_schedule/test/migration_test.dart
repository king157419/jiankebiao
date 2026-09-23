import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/models/app_settings.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

/// v1.3.0 Phase A：1.2.0 → 1.3.0 覆盖安装 / 旧备份导入必须零数据丢失。
///
/// fixture 在 `test/fixtures/v1_2_0/`，是按 1.2.0 的 `toJson` 手写的真实格式：
/// - `backup_v1.json`：1.2.0 「导出备份」的文件（version 1）；
/// - `timetables.json` / `settings.json`：1.2.0 写在应用文档目录里的两份存档。
void main() {
  const fixtureDir = 'test/fixtures/v1_2_0';
  String fixture(String name) => File('$fixtureDir/$name').readAsStringSync();

  const importedId = '8f1c2d7e-6a0b-4d8e-9c55-2b7c1f0a9e31';
  const manualId = '2b0e7c9a-manual-table';

  /// 1.2.0 的数据在新模型里一个字段都不能少。
  void expectLegacyDataIntact(List<Timetable> timetables) {
    expect(timetables.length, 2);
    final imported = timetables.firstWhere((t) => t.id == importedId);
    final manual = timetables.firstWhere((t) => t.id == manualId);

    expect(imported.name, '2026-2027 秋');
    expect(imported.config.startDate, DateTime(2026, 9, 14));
    expect(imported.config.totalWeeks, 18);
    expect(imported.config.periodCount, 12);
    expect(imported.courses.length, 3);
    final math = imported.courses.firstWhere((c) => c.id == 'zf-0-08305001-01');
    expect(math.name, '高等数学 A(一)');
    expect(math.teacher, '张伟');
    expect(math.location, '东区 J-101');
    expect(math.day, 1);
    expect(math.startPeriod, 1);
    expect(math.endPeriod, 2);
    expect(math.weeks, <int>[for (var w = 1; w <= 16; w++) w]);
    expect(math.colorIndex, 3);
    expect(math.note, '宝山校区');
    expect(math.source, 'zfsoft-shu');
    final club = imported.courses.firstWhere((c) => c.id == 'c0d9b0f2-manual');
    expect(club.teacher, isNull);
    expect(club.colorIndex, 7);
    expect(club.note, '自己加的');
    expect(club.weeks, <int>[2, 4, 6]);

    expect(manual.name, '考研自习');
    expect(manual.config.name, '自定义');
    // 2026-09-16 是周三，1.2.0 读进来时就已对齐到周一。
    expect(manual.config.startDate, DateTime(2026, 9, 14));
    expect(manual.config.totalWeeks, 20);
    expect(manual.config.showWeekend, isFalse);
    expect(
      manual.config.periods.map((p) => '${p.start}-${p.end}').toList(),
      <String>['07:30-09:00', '09:10-10:40', '14:00-15:30'],
    );
    expect(manual.courses.single.name, '数学复习');

    // 新字段：默认值。
    for (final t in timetables) {
      expect(t.config.overrides, isEmpty);
      expect(t.config.breakAfter, isNull, reason: '休息带默认自动推导');
      expect(t.termCode, isNull);
      expect(t.importedAt, isNull);
      for (final c in t.courses) {
        expect(c.groupId, isNull);
        expect(c.externalKey, isNull);
      }
    }
    // 从旧来源标记推断出学校与教务类型；手动课表不乱标。
    expect(imported.schoolId, 'shu');
    expect(imported.systemType, 'zfsoft');
    expect(imported.sourceTag, 'zfsoft-shu');
    expect(manual.schoolId, isNull);
    expect(manual.systemType, isNull);
    expect(manual.sourceTag, isNull);
  }

  group('备份 v1 → v2', () {
    test('1.2.0 导出的备份（version 1）导入后数据完整', () {
      final snap = Storage.importJson(fixture('backup_v1.json'));
      expectLegacyDataIntact(snap.timetables);
      expect(snap.settings.currentTimetableId, manualId);
      expect(snap.settings.themeId, 'sakura');
      expect(snap.settings.showNonCurrentWeekCourses, isTrue);
      expect(
        snap.settings.showTimeInGrid,
        isTrue,
        reason: '1.2.0 的设置已经是 settingsVersion 2，用户的选择要保留',
      );
      expect(snap.settings.settingsVersion, AppSettings.currentVersion);
      expect(snap.warnings, isEmpty);
    });

    test('migrateBackupV1ToV2 是纯函数：不改入参，输出 version 2', () {
      final v1 = jsonDecode(fixture('backup_v1.json')) as Map<String, dynamic>;
      final before = jsonEncode(v1);
      final v2 = Storage.migrateBackupV1ToV2(v1);
      expect(jsonEncode(v1), before, reason: '入参不能被改');
      expect(v2['version'], 2);
      expect(v2['exportedAt'], v1['exportedAt']);
      final tts = (v2['timetables'] as List).cast<Map<String, dynamic>>();
      expect(tts[0]['schoolId'], 'shu');
      expect(tts[0]['systemType'], 'zfsoft');
      expect(tts[1].containsKey('schoolId'), isFalse);
      expect((v2['settings'] as Map)['settingsVersion'], 2);
    });

    test('1.0.x 的备份：settings 没有 settingsVersion → 走一次性设置迁移', () {
      final v1 = jsonDecode(fixture('backup_v1.json')) as Map<String, dynamic>;
      final settings = Map<String, dynamic>.from(v1['settings'] as Map)
        ..remove('settingsVersion');
      v1['settings'] = settings;
      final v2 = Storage.migrateBackupV1ToV2(v1);
      expect((v2['settings'] as Map)['settingsVersion'], 1);

      final snap = Storage.importJson(jsonEncode(v1));
      expect(snap.settings.showTimeInGrid, isFalse, reason: 'v1 设置的一次性迁移');
      expect(snap.settings.themeId, 'sakura');
      expect(snap.settings.settingsVersion, AppSettings.currentVersion);
    });

    test('缺 version 字段的备份按 v1 处理', () {
      final v1 = jsonDecode(fixture('backup_v1.json')) as Map<String, dynamic>
        ..remove('version');
      expect(Storage.backupVersionOf(v1), 1);
      expectLegacyDataIntact(Storage.importJson(jsonEncode(v1)).timetables);
      expect(Storage.backupVersionOf(<String, dynamic>{'version': '2'}), 2);
      expect(Storage.backupVersionOf(<String, dynamic>{'version': 0}), 1);
    });

    test('比当前还新的备份：不拒收，尽量读并给 warning', () {
      final v1 = jsonDecode(fixture('backup_v1.json')) as Map<String, dynamic>;
      final future = Storage.migrateBackupV1ToV2(v1)..['version'] = 99;
      final snap = Storage.importJson(jsonEncode(future));
      expect(snap.timetables.length, 2);
      expect(snap.warnings.any((w) => w.contains('更新版本')), isTrue);
    });

    test('exportJson 写 version 2，新字段完整往返', () {
      final tt = Timetable(
        id: 't1',
        name: '新格式',
        config: ScheduleConfig(
          name: '2026-2027 秋',
          startDate: DateTime(2026, 9, 14),
          breakAfter: <int>[5, 9],
          overrides: <String, DateOverride>{
            '2026-10-01': const DateOverride.cancelled(note: '国庆'),
            '2026-10-10': const DateOverride.actAs(week: 3, weekday: 1),
          },
        ),
        courses: <Course>[
          Course(
            id: 'c1',
            name: '高数',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1, 2],
            groupId: 'g-math',
            externalKey: '08305001|高数-01',
            source: 'zfsoft-shu',
          ),
        ],
        schoolId: 'shu',
        systemType: 'zfsoft',
        termCode: '2026-2027-1',
        importedAt: DateTime(2026, 9, 20, 21, 14, 3),
      );
      final text = Storage.exportJson(<Timetable>[
        tt,
      ], AppSettings(currentTimetableId: 't1'));
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      expect(decoded['version'], Storage.backupVersion);
      expect(Storage.backupVersion, 2);
      expect((decoded['settings'] as Map)['settingsVersion'], 2);

      final back = Storage.importJson(text).timetables.single;
      expect(back.schoolId, 'shu');
      expect(back.systemType, 'zfsoft');
      expect(back.termCode, '2026-2027-1');
      expect(back.importedAt, DateTime(2026, 9, 20, 21, 14, 3));
      expect(back.config.breakAfter, <int>[5, 9]);
      expect(back.config.overrides, tt.config.overrides);
      expect(back.courses.single.groupId, 'g-math');
      expect(back.courses.single.externalKey, '08305001|高数-01');
    });
  });

  group('Timetable / Course / ScheduleConfig 旧 JSON 兼容', () {
    test('migrateLegacyJson 幂等：新格式带了 schoolId 键（哪怕是 null）就不再推断', () {
      final json = <String, dynamic>{
        'id': 't',
        'name': 'n',
        'schoolId': null,
        'systemType': null,
        'courses': <dynamic>[
          <String, dynamic>{'name': 'x', 'source': 'zfsoft-shu'},
        ],
      };
      expect(Timetable.migrateLegacyJson(json), same(json));
      expect(Timetable.fromJson(json).schoolId, isNull);
    });

    test('新写出的 JSON 再读一遍，推断不会重复发生', () {
      final tt = Timetable.fromJson(<String, dynamic>{
        'id': 't',
        'name': 'n',
        'courses': <dynamic>[
          <String, dynamic>{'name': 'x', 'source': 'manual'},
        ],
      });
      expect(tt.schoolId, isNull);
      // 用户后来在这张手动课表里……（假设有人把来源改成了 zfsoft-shu）
      tt.courses.first.source = 'zfsoft-shu';
      final again = Timetable.fromJson(
        jsonDecode(jsonEncode(tt.toJson())) as Map<String, dynamic>,
      );
      expect(again.schoolId, isNull, reason: '新格式里 schoolId 键已存在');
    });

    test('Course 旧 JSON 没有 groupId / externalKey → null；新 JSON 往返', () {
      final old = Course.fromJson(<String, dynamic>{
        'id': 'c',
        'name': '旧课',
        'day': 2,
        'startPeriod': 1,
        'endPeriod': 2,
        'weeks': <int>[1],
      });
      expect(old.groupId, isNull);
      expect(old.externalKey, isNull);
      final c = old.copyWith(groupId: 'g', externalKey: 'k');
      final back = Course.fromJson(
        jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>,
      );
      expect(back.groupId, 'g');
      expect(back.externalKey, 'k');
      expect(back.copyWith(clearGroupId: true).groupId, isNull);
      expect(back.copyWith(clearExternalKey: true).externalKey, isNull);
      expect(back.copyWith(name: 'm').groupId, 'g', reason: 'copyWith 默认保留');
    });

    test('Timetable 导入元数据：脏值容错，copyWith 可清空', () {
      final tt = Timetable.fromJson(<String, dynamic>{
        'id': 't',
        'name': 'n',
        'schoolId': 42,
        'systemType': '  ',
        'termCode': '2026-2027-1',
        'importedAt': 'not-a-date',
      });
      expect(tt.schoolId, isNull);
      expect(tt.systemType, isNull);
      expect(tt.termCode, '2026-2027-1');
      expect(tt.importedAt, isNull);
      final withMeta = tt.copyWith(schoolId: 'shu', systemType: 'zfsoft');
      expect(withMeta.termCode, '2026-2027-1');
      expect(withMeta.sourceTag, 'zfsoft-shu');
      final cleared = withMeta.copyWith(clearImportMeta: true);
      expect(cleared.schoolId, isNull);
      expect(cleared.termCode, isNull);
    });

    test('AppSettings：settingsVersion 显式为 1 也按 v1 迁移', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'showTimeInGrid': true,
        'settingsVersion': 1,
      });
      expect(s.showTimeInGrid, isFalse);
      expect(AppSettings.versionOf(<String, dynamic>{}), 1);
      expect(AppSettings.versionOf(<String, dynamic>{'settingsVersion': 2}), 2);
    });
  });

  group('覆盖安装：1.2.0 的本地存档', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('shu_migration_test');
      Storage.overrideDirectory = dir;
      final sep = Platform.pathSeparator;
      await File('${dir.path}$sep${Storage.timetablesFileName}')
          .writeAsString(fixture('timetables.json'));
      await File('${dir.path}$sep${Storage.settingsFileName}')
          .writeAsString(fixture('settings.json'));
    });

    tearDown(() async {
      Storage.overrideDirectory = null;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test(
      'Storage.load 读 1.2.0 的 timetables.json / settings.json 零丢失',
      () async {
        final snap = await Storage.load();
        expect(snap.warnings, isEmpty);
        expectLegacyDataIntact(snap.timetables);
        expect(snap.settings.currentTimetableId, manualId);
        expect(snap.settings.showTimeInGrid, isTrue);
      },
    );

    test('AppState 读入 → 改一下 → 落盘 → 再读，数据完整且带上新字段', () async {
      final state = AppState();
      await state.load();
      await state.switchTimetable(importedId);
      await state.setDateOverride(
        DateTime(2026, 10, 1),
        const DateOverride.cancelled(),
      );
      await Storage.flushPendingWrites();

      final raw = jsonDecode(
        await File(
          '${dir.path}${Platform.pathSeparator}'
          '${Storage.timetablesFileName}',
        ).readAsString(),
      ) as List;
      final first = (raw.first as Map).cast<String, dynamic>();
      expect(first.containsKey('schoolId'), isTrue);
      expect(first['schoolId'], 'shu');
      expect((first['config'] as Map).containsKey('overrides'), isTrue);
      expect((first['config'] as Map)['breakAfter'], isNull);

      final reread = AppState();
      await reread.load();
      expectLegacyDataIntact(
        reread.timetables
            .map(
              (t) => t.copyWith(
                config: t.config.copyWith(
                  overrides: const <String, DateOverride>{},
                ),
              ),
            )
            .toList(),
      );
      expect(
        reread.timetables
            .firstWhere((t) => t.id == importedId)
            .config
            .overrideOn(DateTime(2026, 10, 1))
            ?.cancelled,
        isTrue,
      );
    });
  });
}
