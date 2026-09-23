import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/storage.dart';
import 'package:shu_schedule/models/app_settings.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/period_time.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

void main() {
  group('模型 toJson / fromJson 往返', () {
    test('PeriodTime', () {
      const p = PeriodTime(index: 3, start: '10:00', end: '10:45');
      expect(PeriodTime.fromJson(p.toJson()), p);
      expect(p.startMinutes, 600);
      expect(p.endMinutes, 645);
    });

    test('Course', () {
      final c = Course(
        id: 'x',
        name: '高等数学',
        teacher: '张三',
        location: '东区J102',
        day: 2,
        startPeriod: 3,
        endPeriod: 4,
        weeks: <int>[3, 1, 1, 2],
        colorIndex: 5,
        source: 'zfsoft-shu',
      );
      expect(c.weeks, <int>[1, 2, 3]); // 构造时已去重升序
      expect(c.periodSpan, 2);
      expect(c.isInWeek(2), isTrue);
      expect(c.isInWeek(9), isFalse);
      final back = Course.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(back.name, c.name);
      expect(back.weeks, c.weeks);
      expect(back.teacher, '张三');
      expect(back.source, 'zfsoft-shu');
    });

    test('Course.copyWith 可清空可空字段', () {
      final c = Course(
        id: 'x',
        name: 'n',
        teacher: 't',
        day: 1,
        startPeriod: 1,
        endPeriod: 1,
      );
      expect(c.copyWith(clearTeacher: true).teacher, isNull);
      expect(c.copyWith(name: 'm').name, 'm');
      expect(c.copyWith(name: 'm').teacher, 't');
    });

    test('ScheduleConfig / Timetable', () {
      final tt = Timetable.empty(id: 't1', name: '我的课表');
      expect(tt.config.periodCount, 12);
      expect(tt.config.startDate, DateTime(2026, 9, 14));
      final back = Timetable.fromJson(jsonDecode(jsonEncode(tt.toJson())));
      expect(back.id, 't1');
      expect(back.config.periodCount, 12);
      expect(back.config.totalWeeks, 18);
      expect(back.courses, isEmpty);
    });

    test('AppSettings 默认值', () {
      final s = AppSettings.defaults();
      expect(s.themeId, 'default');
      // 默认不在格子里重复写时间（左侧时间列已经有了），v1.1.0 起改为 false。
      expect(s.showTimeInGrid, isFalse);
      expect(s.showNonCurrentWeekCourses, isFalse);
      final back = AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(back.themeId, 'default');
      expect(back.settingsVersion, AppSettings.currentVersion);
    });

    test('v1 存档（没有 settingsVersion）迁移一次：格子里不再重复写时间', () {
      final old = AppSettings.fromJson(<String, dynamic>{
        'currentTimetableId': 't1',
        'themeId': 'sakura',
        'showTimeInGrid': true, // v1 的出厂默认
      });
      expect(old.showTimeInGrid, isFalse, reason: '一次性迁移到新默认值');
      expect(old.settingsVersion, AppSettings.currentVersion);

      // 迁移之后，用户自己打开这个开关必须一直保留。
      final chosen = old.copyWith(showTimeInGrid: true);
      final back = AppSettings.fromJson(
        jsonDecode(jsonEncode(chosen.toJson())),
      );
      expect(back.showTimeInGrid, isTrue);
    });
  });

  group('脏 JSON 不崩溃', () {
    test('缺字段 / 类型不对 → 回退到默认值', () {
      final c = Course.fromJson(<String, dynamic>{
        'name': 123,
        'day': '9',
        'startPeriod': 'abc',
        'weeks': <dynamic>['1', 2, null, -3],
      });
      expect(c.name, '未命名课程');
      expect(c.day, 7); // 9 被裁剪到 7
      expect(c.startPeriod, 1);
      expect(c.endPeriod, greaterThanOrEqualTo(c.startPeriod));
      expect(c.weeks, <int>[1, 2]);
    });

    test('ScheduleConfig 缺 periods → SHU 默认 12 节', () {
      final cfg = ScheduleConfig.fromJson(<String, dynamic>{
        'name': 'x',
        'startDate': 'not-a-date',
        'totalWeeks': 'oops',
      });
      expect(cfg.periods.length, 12);
      expect(cfg.totalWeeks, 18);
      expect(cfg.startDate, DateTime(2026, 9, 14));
    });

    test('endPeriod < startPeriod 会被修正', () {
      final c = Course.fromJson(<String, dynamic>{
        'name': 'n',
        'startPeriod': 5,
        'endPeriod': 2,
      });
      expect(c.startPeriod, 5);
      expect(c.endPeriod, 5);
    });
  });

  group('Storage 读写与损坏恢复', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('shu_storage_test');
      Storage.overrideDirectory = dir;
    });

    tearDown(() async {
      Storage.overrideDirectory = null;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('首次运行：文件不存在 → 空列表 + 默认设置', () async {
      final snap = await Storage.load();
      expect(snap.timetables, isEmpty);
      expect(snap.settings.themeId, 'default');
      expect(snap.warnings, isEmpty);
    });

    test('save 后 load 能读回', () async {
      final tt = Timetable.empty(id: 't1', name: '大三上');
      tt.courses.add(
        Course(
          id: 'c1',
          name: '编译原理',
          day: 4,
          startPeriod: 1,
          endPeriod: 2,
          weeks: <int>[1, 2, 3],
        ),
      );
      final settings = AppSettings(currentTimetableId: 't1', themeId: 'sakura');
      await Storage.save(<Timetable>[tt], settings);

      final snap = await Storage.load();
      expect(snap.timetables.length, 1);
      expect(snap.timetables.first.name, '大三上');
      expect(snap.timetables.first.courses.single.name, '编译原理');
      expect(snap.settings.themeId, 'sakura');
      expect(snap.settings.currentTimetableId, 't1');
    });

    test('损坏的 timetables.json → 回退到空列表并留下 warning', () async {
      await File('${dir.path}/timetables.json')
          .writeAsString('{ this is not json');
      final snap = await Storage.load();
      expect(snap.timetables, isEmpty);
      expect(snap.warnings, isNotEmpty);
      // 损坏文件被隔离保留。
      final quarantined = dir
          .listSync()
          .where((e) => e.path.contains('.corrupt-'))
          .toList();
      expect(quarantined, isNotEmpty);
    });

    test('损坏的 settings.json → 回退到默认设置', () async {
      await File('${dir.path}/settings.json').writeAsString('[1,2,3]');
      final snap = await Storage.load();
      expect(snap.settings.themeId, 'default');
      expect(snap.warnings, isNotEmpty);
    });

    test('currentTimetableId 指向不存在的课表 → 自动修正', () async {
      final tt = Timetable.empty(id: 'real', name: 'n');
      await Storage.save(<Timetable>[
        tt,
      ], AppSettings(currentTimetableId: 'ghost'));
      final snap = await Storage.load();
      expect(snap.settings.currentTimetableId, 'real');
    });

    test('备份导出 / 导入往返', () {
      final tt = Timetable.empty(id: 't1', name: '备份测试');
      final json = Storage.exportJson(<Timetable>[
        tt,
      ], AppSettings(currentTimetableId: 't1'));
      final snap = Storage.importJson(json);
      expect(snap.timetables.single.name, '备份测试');
      expect(snap.settings.currentTimetableId, 't1');
    });

    test('导入非法备份抛 FormatException', () {
      expect(() => Storage.importJson('[]'), throwsFormatException);
      expect(
        () => Storage.importJson('{"settings":{}}'),
        throwsFormatException,
      );
    });

    // ---------------------------------------------------- REVIEW-1 C1 / M6 / L4

    test('并发 save 不会丢数据：写队列串行化，最后一次内容落盘', () async {
      // 同时发起 20 次写（不 await），模拟导入时连续触发的多次 _commit()。
      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        futures.add(
          Storage.saveTimetables(<Timetable>[
            Timetable.empty(id: 't$i', name: '课表$i'),
          ]),
        );
      }
      await Future.wait(futures);
      await Storage.flushPendingWrites();

      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${Storage.timetablesFileName}',
      );
      expect(await file.exists(), isTrue, reason: '主文件必须存在，不能被删掉');
      final decoded = jsonDecode(await file.readAsString());
      expect(decoded, isA<List>());
      expect((decoded as List).single['name'], '课表19');

      // 不留临时文件。
      final leftovers = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty, reason: '.tmp 应当已经 rename 掉');
    });

    test('并发 save 后还能正常读回来', () async {
      await Future.wait(<Future<void>>[
        Storage.saveTimetables(<Timetable>[Timetable.empty(id: 'a')]),
        Storage.saveSettings(AppSettings(currentTimetableId: 'a')),
        Storage.saveTimetables(<Timetable>[Timetable.empty(id: 'b')]),
        Storage.saveSettings(AppSettings(currentTimetableId: 'b')),
      ]);
      final snap = await Storage.load();
      expect(snap.timetables.single.id, 'b');
      expect(snap.settings.currentTimetableId, 'b');
    });

    test('主文件缺失但留着 .tmp 时自动恢复（写到一半被杀的现场）', () async {
      final tmp = File(
        '${dir.path}${Platform.pathSeparator}'
        '${Storage.timetablesFileName}.7.tmp',
      );
      await tmp.writeAsString(
        jsonEncode(<dynamic>[
          Timetable.empty(id: 'rescued', name: '抢救回来的').toJson(),
        ]),
      );
      final snap = await Storage.load();
      expect(snap.timetables.single.name, '抢救回来的');
      expect(snap.warnings.any((w) => w.contains('临时文件')), isTrue);
    });

    test('主文件存在时不会被 .tmp 覆盖', () async {
      await Storage.saveTimetables(<Timetable>[
        Timetable.empty(id: 'good', name: '正式数据'),
      ]);
      final tmp = File(
        '${dir.path}${Platform.pathSeparator}'
        '${Storage.timetablesFileName}.9.tmp',
      );
      await tmp.writeAsString(
        jsonEncode(<dynamic>[
          Timetable.empty(id: 'stale', name: '旧残留').toJson(),
        ]),
      );
      final snap = await Storage.load();
      expect(snap.timetables.single.name, '正式数据');
    });

    test('importJson：单条坏课表只跳过那一条并写 warning', () {
      final good = Timetable.empty(id: 't1', name: '好的').toJson();
      final text = jsonEncode(<String, dynamic>{
        'version': 1,
        'timetables': <dynamic>[
          good,
          'not-a-map',
          <String, dynamic>{'id': 42},
        ],
        'settings': <String, dynamic>{'currentTimetableId': 't1'},
      });
      final snap = Storage.importJson(text);
      expect(snap.timetables.length, 2, reason: '字符串那条跳过，{id:42} 靠模型容错活下来');
      expect(snap.warnings, isNotEmpty);
      expect(snap.settings.currentTimetableId, 't1');
    });

    test('importJson：一条都解析不出来才抛 FormatException', () {
      final text = jsonEncode(<String, dynamic>{
        'timetables': <dynamic>['x', 1, null],
      });
      expect(() => Storage.importJson(text), throwsFormatException);
    });

    test('normalizeIds：重复 / 空 id 会被重新分配', () {
      final a = Timetable.empty(id: 'dup', name: 'A');
      final b = Timetable.empty(id: 'dup', name: 'B');
      final c = Timetable.empty(id: '', name: 'C');
      final warnings = <String>[];
      Storage.normalizeIds(<Timetable>[a, b, c], warnings);
      expect(<String>{a.id, b.id, c.id}.length, 3);
      expect(a.id, 'dup', reason: '第一个保留原 id');
      expect(c.id, isNotEmpty);
      expect(warnings, isNotEmpty);
    });

    test('normalizeIds：课程重复 id 也会修掉', () {
      final tt = Timetable.empty(id: 't1');
      tt.courses.addAll(<Course>[
        Course(id: 'same', name: 'A', day: 1, startPeriod: 1, endPeriod: 2),
        Course(id: 'same', name: 'B', day: 2, startPeriod: 1, endPeriod: 2),
      ]);
      Storage.normalizeIds(<Timetable>[tt], <String>[]);
      expect(tt.courses[0].id == tt.courses[1].id, isFalse);
    });

    test('backupBeforeRestore：有数据时留一份副本', () async {
      await Storage.saveTimetables(<Timetable>[
        Timetable.empty(id: 't1', name: '恢复前'),
      ]);
      final path = await Storage.backupBeforeRestore();
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), contains('恢复前'));
    });

    test('backupBeforeRestore：没有数据时返回 null', () async {
      expect(await Storage.backupBeforeRestore(), isNull);
    });
  });

  group('AppState', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('shu_app_state_test');
      Storage.overrideDirectory = dir;
    });

    tearDown(() async {
      Storage.overrideDirectory = null;
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('一张课表都没有时 addCourse 会自动建表（冷启动「手动添加」）', () async {
      final state = AppState();
      await state.load();
      expect(state.timetables, isEmpty);

      final added = await state.addCourse(
        Course(id: '', name: '高等数学', day: 1, startPeriod: 1, endPeriod: 2),
      );

      expect(added, isNotNull, reason: '不能静默丢掉课程');
      expect(state.timetables.length, 1);
      expect(state.currentTimetable!.courses.single.name, '高等数学');
      expect(state.currentTimetable!.config.periodCount, 12);

      // 真的落盘了。
      final reread = AppState();
      await reread.load();
      expect(reread.currentTimetable!.courses.single.name, '高等数学');
    });

    test('restoreFrom：空备份时 currentTimetableId 不悬空', () async {
      final state = AppState();
      await state.load();
      await state.createTimetable(name: '旧的');
      await state.restoreFrom(
        StorageSnapshot(
          timetables: const <Timetable>[],
          settings: AppSettings(currentTimetableId: 'ghost'),
        ),
      );
      expect(state.timetables, isEmpty);
      expect(state.settings.currentTimetableId, '');
      expect(state.currentTimetable, isNull);
    });

    test('restoreFrom：覆盖前留了一份 before-restore 备份', () async {
      final state = AppState();
      await state.load();
      await state.createTimetable(name: '会被覆盖掉的');
      await Storage.flushPendingWrites();

      await state.restoreFrom(
        StorageSnapshot(
          timetables: <Timetable>[Timetable.empty(id: 'new', name: '恢复进来的')],
          settings: AppSettings(currentTimetableId: 'new'),
        ),
      );
      expect(state.currentTimetable!.name, '恢复进来的');

      final backups = dir
          .listSync()
          .where((e) => e.path.contains('.before-restore-'))
          .toList();
      expect(backups, isNotEmpty);
      expect(state.warnings.any((w) => w.contains('已备份')), isTrue);
    });

    test('restoreFrom：备份里的重复 id 会被修掉', () async {
      final state = AppState();
      await state.load();
      await state.restoreFrom(
        StorageSnapshot(
          timetables: <Timetable>[
            Timetable.empty(id: 'same', name: 'A'),
            Timetable.empty(id: 'same', name: 'B'),
          ],
          settings: AppSettings(currentTimetableId: 'same'),
        ),
      );
      final ids = state.timetables.map((t) => t.id).toSet();
      expect(ids.length, 2);
    });
  });
}
