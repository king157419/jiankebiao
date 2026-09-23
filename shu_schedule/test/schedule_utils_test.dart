import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/period_time.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

ScheduleConfig _config({
  DateTime? start,
  int totalWeeks = 18,
  List<PeriodTime>? periods,
}) {
  return ScheduleConfig(
    name: '测试学期',
    startDate: start ?? DateTime(2026, 9, 14),
    totalWeeks: totalWeeks,
    periods: periods,
  );
}

Course _course({
  String id = 'c1',
  String name = '测试课',
  int day = 1,
  int startPeriod = 1,
  int endPeriod = 2,
  List<int> weeks = const <int>[1, 2, 3],
}) {
  return Course(
    id: id,
    name: name,
    day: day,
    startPeriod: startPeriod,
    endPeriod: endPeriod,
    weeks: weeks,
  );
}

void main() {
  group('parseWeeksText — PLAN §0.1 列出的 zcd 格式', () {
    test('1-16周 → 连续 1..16', () {
      expect(
        ScheduleUtils.parseWeeksText('1-16周'),
        List<int>.generate(16, (i) => i + 1),
      );
    });

    test('1-15周(单) → 单周', () {
      expect(ScheduleUtils.parseWeeksText('1-15周(单)'), <int>[
        1,
        3,
        5,
        7,
        9,
        11,
        13,
        15,
      ]);
    });

    test('2-16周(双) → 双周', () {
      expect(ScheduleUtils.parseWeeksText('2-16周(双)'), <int>[
        2,
        4,
        6,
        8,
        10,
        12,
        14,
        16,
      ]);
    });

    test('1-8周,10-16周 → 两段并集', () {
      expect(ScheduleUtils.parseWeeksText('1-8周,10-16周'), <int>[
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        10,
        11,
        12,
        13,
        14,
        15,
        16,
      ]);
    });

    test('3周 → 单个周次', () {
      expect(ScheduleUtils.parseWeeksText('3周'), <int>[3]);
    });

    test('1,3,5周 → 逗号分隔的单周次', () {
      expect(ScheduleUtils.parseWeeksText('1,3,5周'), <int>[1, 3, 5]);
    });

    test('1-4周,6-8周(双) → 单双标记只作用于自己那一段', () {
      expect(ScheduleUtils.parseWeeksText('1-4周,6-8周(双)'), <int>[
        1,
        2,
        3,
        4,
        6,
        8,
      ]);
    });

    test('空串与 null → 空列表', () {
      expect(ScheduleUtils.parseWeeksText(''), isEmpty);
      expect(ScheduleUtils.parseWeeksText('   '), isEmpty);
      expect(ScheduleUtils.parseWeeksText(null), isEmpty);
    });

    test('带「第」前缀的变体', () {
      expect(ScheduleUtils.parseWeeksText('第1-5周'), <int>[1, 2, 3, 4, 5]);
      expect(ScheduleUtils.parseWeeksText('第1-9周(单)'), <int>[1, 3, 5, 7, 9]);
      expect(ScheduleUtils.parseWeeksText('第1-4周,第7周'), <int>[1, 2, 3, 4, 7]);
    });

    test('全角逗号 / 全角括号 / 波浪号 / 空格', () {
      expect(ScheduleUtils.parseWeeksText('1-4周，6-8周'), <int>[
        1,
        2,
        3,
        4,
        6,
        7,
        8,
      ]);
      expect(ScheduleUtils.parseWeeksText('1-5周（单）'), <int>[1, 3, 5]);
      expect(ScheduleUtils.parseWeeksText('1~4周'), <int>[1, 2, 3, 4]);
      expect(ScheduleUtils.parseWeeksText('  1 - 4 周 '), <int>[1, 2, 3, 4]);
      expect(ScheduleUtils.parseWeeksText('1-5周单'), <int>[1, 3, 5]);
      expect(ScheduleUtils.parseWeeksText('1-6周 双周'), <int>[2, 4, 6]);
    });

    test('结果去重且升序', () {
      expect(ScheduleUtils.parseWeeksText('5周,1-3周,2周'), <int>[1, 2, 3, 5]);
    });

    test('脏数据不崩溃：超大范围被裁剪、非法文本被忽略', () {
      expect(
        ScheduleUtils.parseWeeksText('1-9999周').last,
        ScheduleUtils.maxWeek,
      );
      expect(ScheduleUtils.parseWeeksText('无固定周次'), isEmpty);
      expect(ScheduleUtils.parseWeeksText('0周'), isEmpty);
      expect(ScheduleUtils.parseWeeksText('8-5周'), <int>[5, 6, 7, 8]);
    });
  });

  group('formatWeeksText', () {
    test('连续段被压缩', () {
      expect(ScheduleUtils.formatWeeksText(<int>[1, 2, 3, 5]), '1-3,5周');
      expect(ScheduleUtils.formatWeeksText(<int>[2, 4, 6]), '2,4,6周');
      expect(ScheduleUtils.formatWeeksText(<int>[]), '');
    });

    test('与 parseWeeksText 互逆', () {
      final weeks = ScheduleUtils.parseWeeksText('1-8周,10-16周');
      expect(
        ScheduleUtils.parseWeeksText(ScheduleUtils.formatWeeksText(weeks)),
        weeks,
      );
    });
  });

  group('weekOf / rawWeekOf 边界', () {
    final config = _config(start: DateTime(2026, 9, 14), totalWeeks: 18);

    test('开学当天是第 1 周', () {
      expect(ScheduleUtils.rawWeekOf(DateTime(2026, 9, 14), config), 1);
    });

    test('第 1 周周日仍是第 1 周，下周一进入第 2 周', () {
      expect(ScheduleUtils.rawWeekOf(DateTime(2026, 9, 20), config), 1);
      expect(ScheduleUtils.rawWeekOf(DateTime(2026, 9, 21), config), 2);
    });

    test('最后一周（第 18 周）与其后一天', () {
      // 第 18 周周一 = 开学 + 17*7 = 2027-01-11，周日 = 2027-01-17。
      expect(ScheduleUtils.rawWeekOf(DateTime(2027, 1, 11), config), 18);
      expect(ScheduleUtils.rawWeekOf(DateTime(2027, 1, 17), config), 18);
      expect(ScheduleUtils.rawWeekOf(DateTime(2027, 1, 18), config), 19);
    });

    test('开学前：raw 为 0 或负，weekOf 裁剪到 1', () {
      expect(ScheduleUtils.rawWeekOf(DateTime(2026, 9, 13), config), 0);
      expect(ScheduleUtils.rawWeekOf(DateTime(2026, 9, 7), config), 0);
      expect(ScheduleUtils.rawWeekOf(DateTime(2026, 9, 6), config), -1);
      expect(ScheduleUtils.weekOf(DateTime(2026, 9, 6), config), 1);
    });

    test('学期结束后 weekOf 裁剪到 totalWeeks', () {
      expect(ScheduleUtils.weekOf(DateTime(2027, 3, 1), config), 18);
    });

    test('isDuringTerm', () {
      expect(
        ScheduleUtils.isDuringTerm(DateTime(2026, 9, 13), config),
        isFalse,
      );
      expect(ScheduleUtils.isDuringTerm(DateTime(2026, 9, 14), config), isTrue);
      expect(ScheduleUtils.isDuringTerm(DateTime(2027, 1, 17), config), isTrue);
      expect(
        ScheduleUtils.isDuringTerm(DateTime(2027, 1, 18), config),
        isFalse,
      );
    });

    test('开学日期被自动对齐到当周周一', () {
      // 2026-09-16 是周三 → 对齐到 2026-09-14。
      final c = _config(start: DateTime(2026, 9, 16));
      expect(c.startDate, DateTime(2026, 9, 14));
    });

    test('跨夏令时也不会错位（回归测试）', () {
      // 本机时区若有夏令时（如 Mountain Standard Time），
      // 用 Duration 做日期加减会得到 2027-01-10 23:00 这种结果。
      // 所有日期运算必须走日历加减 / UTC 归一化。
      for (var w = 1; w <= 18; w++) {
        for (var d = 1; d <= 7; d++) {
          final date = ScheduleUtils.dateOf(config, w, d);
          expect(date.hour, 0, reason: '第$w周星期$d 的时分被夏令时污染了');
          expect(date.weekday, d == 7 ? DateTime.sunday : d);
          expect(ScheduleUtils.rawWeekOf(date, config), w);
        }
      }
    });

    test('dateOf / mondayOfWeek', () {
      expect(ScheduleUtils.dateOf(config, 1, 1), DateTime(2026, 9, 14));
      expect(ScheduleUtils.dateOf(config, 1, 7), DateTime(2026, 9, 20));
      expect(ScheduleUtils.dateOf(config, 2, 1), DateTime(2026, 9, 21));
      expect(ScheduleUtils.mondayOfWeek(config, 18), DateTime(2027, 1, 11));
      // 越界参数被裁剪而不是崩溃。
      expect(ScheduleUtils.dateOf(config, 0, 0), DateTime(2026, 9, 14));
      expect(ScheduleUtils.dateOf(config, 1, 99), DateTime(2026, 9, 20));
    });
  });

  group('periodRange', () {
    final config = _config();

    test('SHU 默认作息的单节与跨节', () {
      expect(ScheduleUtils.periodRange(config, 1, 1), (
        start: '08:00',
        end: '08:45',
      ));
      expect(ScheduleUtils.periodRange(config, 1, 2), (
        start: '08:00',
        end: '09:40',
      ));
      expect(ScheduleUtils.periodRange(config, 3, 4), (
        start: '10:00',
        end: '11:40',
      ));
      expect(ScheduleUtils.periodRange(config, 11, 12), (
        start: '20:00',
        end: '21:40',
      ));
    });

    test('start > end 时自动交换', () {
      expect(ScheduleUtils.periodRange(config, 4, 1), (
        start: '08:00',
        end: '11:40',
      ));
    });

    test('越界被裁剪到已有节次', () {
      expect(ScheduleUtils.periodRange(config, 0, 1), (
        start: '08:00',
        end: '08:45',
      ));
      expect(ScheduleUtils.periodRange(config, 11, 99), (
        start: '20:00',
        end: '21:40',
      ));
      expect(ScheduleUtils.periodRange(config, 50, 60), (
        start: '20:55',
        end: '21:40',
      ));
    });

    test('作息表为空时返回空串而不是崩溃', () {
      final empty = ScheduleConfig(
        name: 'x',
        startDate: DateTime(2026, 9, 14),
        periods: <PeriodTime>[],
      );
      // fromJson/构造器都会兜底成默认作息，所以这里直接改字段模拟脏状态。
      empty.periods = <PeriodTime>[];
      expect(ScheduleUtils.periodRange(empty, 1, 2), (start: '', end: ''));
    });

    test('自定义不连续节次索引不崩溃', () {
      final custom = _config(
        periods: const <PeriodTime>[
          PeriodTime(index: 1, start: '09:00', end: '09:45'),
          PeriodTime(index: 5, start: '14:00', end: '14:45'),
        ],
      );
      expect(ScheduleUtils.periodRange(custom, 1, 5), (
        start: '09:00',
        end: '14:45',
      ));
      expect(ScheduleUtils.periodRange(custom, 3, 3), (
        start: '09:00',
        end: '09:45',
      ));
    });
  });

  group('coursesOn / coursesInWeek / nextCourse', () {
    Timetable buildTimetable() {
      return Timetable(
        id: 't1',
        name: '测试课表',
        config: _config(),
        courses: <Course>[
          _course(
            id: 'a',
            name: '高数',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1, 2, 3],
          ),
          _course(
            id: 'b',
            name: '英语',
            day: 1,
            startPeriod: 5,
            endPeriod: 6,
            weeks: <int>[1, 3],
          ),
          _course(
            id: 'c',
            name: '体育',
            day: 3,
            startPeriod: 3,
            endPeriod: 4,
            weeks: <int>[1, 2],
          ),
          _course(
            id: 'd',
            name: '周末课',
            day: 6,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1],
          ),
        ],
      );
    }

    test('coursesOn 按星期 + 周次过滤并按节次排序', () {
      final tt = buildTimetable();
      // 2026-09-14 = 第 1 周周一。
      final monday = ScheduleUtils.coursesOn(DateTime(2026, 9, 14), tt);
      expect(monday.map((c) => c.id), <String>['a', 'b']);
      // 第 2 周周一只有高数。
      final week2Monday = ScheduleUtils.coursesOn(DateTime(2026, 9, 21), tt);
      expect(week2Monday.map((c) => c.id), <String>['a']);
      // 周六有课。
      expect(
        ScheduleUtils.coursesOn(DateTime(2026, 9, 19), tt).map((c) => c.id),
        <String>['d'],
      );
      // 开学前没有课。
      expect(ScheduleUtils.coursesOn(DateTime(2026, 9, 7), tt), isEmpty);
    });

    test('coursesInWeek 按星期再按节次排序', () {
      final tt = buildTimetable();
      expect(ScheduleUtils.coursesInWeek(1, tt).map((c) => c.id), <String>[
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(ScheduleUtils.coursesInWeek(3, tt).map((c) => c.id), <String>[
        'a',
        'b',
      ]);
      expect(ScheduleUtils.coursesInWeek(9, tt), isEmpty);
    });

    test('nextCourse 跳过已开始的课并能跨天查找', () {
      final tt = buildTimetable();
      // 第 1 周周一 07:00 → 高数（08:00 开始）。
      expect(ScheduleUtils.nextCourse(DateTime(2026, 9, 14, 7), tt)?.id, 'a');
      // 09:00 时高数已开始 → 英语（13:00）。
      expect(ScheduleUtils.nextCourse(DateTime(2026, 9, 14, 9), tt)?.id, 'b');
      // 周一晚上 22:00 → 周三体育。
      expect(ScheduleUtils.nextCourse(DateTime(2026, 9, 14, 22), tt)?.id, 'c');
      // 学期最后一周之后没有课。
      expect(ScheduleUtils.nextCourse(DateTime(2027, 5, 1), tt), isNull);
    });
  });

  group('findConflicts', () {
    test('同天同周节次重叠会被检出', () {
      final tt = Timetable(
        id: 't',
        name: 'n',
        config: _config(),
        courses: <Course>[
          _course(
            id: 'a',
            day: 2,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1, 2],
          ),
          _course(
            id: 'b',
            day: 2,
            startPeriod: 2,
            endPeriod: 3,
            weeks: <int>[2, 3],
          ),
          _course(
            id: 'c',
            day: 2,
            startPeriod: 5,
            endPeriod: 6,
            weeks: <int>[1, 2],
          ),
          _course(
            id: 'd',
            day: 2,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[7],
          ),
        ],
      );
      final conflicts = ScheduleUtils.findConflicts(tt);
      expect(conflicts.length, 1);
      expect(conflicts.first.$1.id, 'a');
      expect(conflicts.first.$2.id, 'b');
    });
  });

  group('SHU 预设常量', () {
    test('12 节作息与官方时间一致', () {
      expect(defaultPeriods.length, 12);
      expect(defaultPeriods.first.start, '08:00');
      expect(defaultPeriods[3].end, '11:40');
      expect(defaultPeriods[4].start, '13:00');
      expect(defaultPeriods[8].start, '18:00');
      expect(defaultPeriods.last.end, '21:40');
      for (var i = 0; i < defaultPeriods.length; i++) {
        expect(defaultPeriods[i].index, i + 1);
      }
    });

    test('学期预设的开学日期都是周一', () {
      expect(exampleTermPresets.length, 2);
      for (final p in exampleTermPresets) {
        expect(p.startDate.weekday, DateTime.monday);
        expect(p.totalWeeks, 18);
      }
      expect(exampleTermPresets[0].startDate, DateTime(2026, 9, 14));
      expect(exampleTermPresets[1].startDate, DateTime(2027, 2, 22));
    });
  });
}
