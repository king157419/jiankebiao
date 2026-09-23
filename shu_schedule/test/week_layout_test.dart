import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/features/timetable/week_layout.dart';
import 'package:shu_schedule/models/period_time.dart';
import 'package:shu_schedule/models/schedule_config.dart';

/// v1.3.0 Phase A：休息带从作息推导（>= 40 分钟画带），`breakAfter` 手动覆盖。
void main() {
  /// 「上午 5 节」的学校：午休在第 5 节后，晚休在第 9 节后。
  const fiveMorning = <PeriodTime>[
    PeriodTime(index: 1, start: '08:00', end: '08:45'),
    PeriodTime(index: 2, start: '08:55', end: '09:40'),
    PeriodTime(index: 3, start: '10:00', end: '10:45'), // 课间 20 分钟，不画
    PeriodTime(index: 4, start: '10:55', end: '11:40'),
    PeriodTime(index: 5, start: '11:50', end: '12:35'),
    PeriodTime(index: 6, start: '14:00', end: '14:45'), // 午休 85 分钟
    PeriodTime(index: 7, start: '14:55', end: '15:40'),
    PeriodTime(index: 8, start: '16:00', end: '16:45'),
    PeriodTime(index: 9, start: '16:55', end: '17:40'),
    PeriodTime(index: 10, start: '19:00', end: '19:45'), // 晚休 80 分钟
    PeriodTime(index: 11, start: '19:55', end: '20:40'),
  ];

  ScheduleConfig configOf(List<PeriodTime> periods, {List<int>? breakAfter}) =>
      ScheduleConfig(
        name: 'x',
        startDate: DateTime(2026, 9, 14),
        periods: List.of(periods),
        breakAfter: breakAfter,
      );

  group('ScheduleUtils.breakAfterIndices（自动推导）', () {
    test('上大 12 节推导出第 4、8 节后，与 v1.2.0 写死的一致', () {
      expect(ScheduleUtils.breakAfterIndices(configOf(defaultPeriods)), <int>[
        4,
        8,
      ]);
    });

    test('上午 5 节：第 5、9 节后', () {
      expect(ScheduleUtils.breakAfterIndices(configOf(fiveMorning)), <int>[
        5,
        9,
      ]);
    });

    test('阈值：间隔 39 分钟不画、40 分钟画', () {
      const periods = <PeriodTime>[
        PeriodTime(index: 1, start: '08:00', end: '08:45'),
        PeriodTime(index: 2, start: '09:24', end: '10:09'), // 39
        PeriodTime(index: 3, start: '10:49', end: '11:30'), // 40
      ];
      expect(ScheduleUtils.autoBreakAfterIndices(periods), <int>[2]);
      expect(ScheduleUtils.autoBreakMinGapMinutes, 40);
    });

    test('作息表乱序也按 index 排好再算', () {
      final shuffled = List<PeriodTime>.from(fiveMorning.reversed);
      expect(ScheduleUtils.autoBreakAfterIndices(shuffled), <int>[5, 9]);
    });

    test('0 / 1 节、时间写反的作息不崩溃', () {
      expect(
        ScheduleUtils.breakAfterIndices(configOf(const <PeriodTime>[])),
        isEmpty,
      );
      expect(
        ScheduleUtils.breakAfterIndices(configOf(fiveMorning.sublist(0, 1))),
        isEmpty,
      );
      const reversed = <PeriodTime>[
        PeriodTime(index: 1, start: '10:00', end: '10:45'),
        PeriodTime(index: 2, start: '08:00', end: '08:45'),
      ];
      expect(ScheduleUtils.autoBreakAfterIndices(reversed), isEmpty);
    });
  });

  group('ScheduleConfig.breakAfter（手动覆盖）', () {
    test('手动值优先；不存在的节次 / 最后一节被丢掉', () {
      final cfg = configOf(fiveMorning, breakAfter: <int>[2, 11, 99, 2]);
      expect(cfg.breakAfter, <int>[2, 11, 99], reason: '构造时去重升序');
      expect(ScheduleUtils.breakAfterIndices(cfg), <int>[2]);
    });

    test('空列表 = 一条都不画；null = 自动', () {
      expect(
        ScheduleUtils.breakAfterIndices(
          configOf(fiveMorning, breakAfter: <int>[]),
        ),
        isEmpty,
      );
      final auto = configOf(fiveMorning);
      expect(auto.hasManualBreaks, isFalse);
      expect(ScheduleUtils.breakAfterIndices(auto), <int>[5, 9]);
    });

    test('JSON 往返区分 null 与 []；旧 JSON 缺字段 → null', () {
      ScheduleConfig roundTrip(ScheduleConfig c) => ScheduleConfig.fromJson(
        jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>,
      );
      expect(roundTrip(configOf(fiveMorning)).breakAfter, isNull);
      expect(
        roundTrip(configOf(fiveMorning, breakAfter: <int>[])).breakAfter,
        isEmpty,
      );
      expect(
        roundTrip(configOf(fiveMorning, breakAfter: <int>[5])).breakAfter,
        <int>[5],
      );
      final dirty = ScheduleConfig.fromJson(<String, dynamic>{
        'name': 'x',
        'startDate': '2026-09-14',
        'breakAfter': <dynamic>['4', 8.0, null, 'x', -1],
      });
      expect(dirty.breakAfter, <int>[4, 8]);
    });

    test('copyWith 保留 / 清除手动休息带', () {
      final cfg = configOf(fiveMorning, breakAfter: <int>[5]);
      expect(cfg.copyWith(name: 'y').breakAfter, <int>[5]);
      expect(cfg.copyWith(clearBreakAfter: true).breakAfter, isNull);
    });
  });

  group('WeekLayout：上午 5 节 fixture', () {
    final layout = WeekLayout.of(configOf(fiveMorning));

    test('休息带位置（position = index - 1）', () {
      expect(layout.breakAfterPositions, <int>[4, 8]);
      expect(layout.hasBreakAfter(3), isFalse, reason: '不再写死第 4 节后');
      expect(layout.hasBreakAfter(4), isTrue);
      expect(layout.hasBreakAfter(7), isFalse, reason: '不再写死第 8 节后');
      expect(layout.hasBreakAfter(8), isTrue);
    });

    test('休息带种类与文字按时间判断', () {
      expect(layout.breakKindAfter(4), BreakKind.noon);
      expect(layout.breakLabelAfter(4), '午间休息');
      expect(layout.breakKindAfter(8), BreakKind.evening);
      expect(layout.breakLabelAfter(8), '晚间休息');
      expect(layout.breakKindAfter(0), isNull);
      expect(layout.breakLabelAfter(0), isNull);
      expect(layout.breakHeightAfter(4), layout.noonBreakHeight);
      expect(layout.breakHeightAfter(8), layout.eveningBreakHeight);
      expect(layout.breakHeightAfter(3), 0);
    });

    test('topOf / totalHeight', () {
      final h = layout.periodHeight;
      expect(layout.topOf(4), 4 * h, reason: '第 5 节前面没有休息带');
      expect(layout.topOf(5), 5 * h + layout.noonBreakHeight);
      expect(
        layout.topOf(9),
        9 * h + layout.noonBreakHeight + layout.eveningBreakHeight,
      );
      expect(
        layout.totalHeight,
        11 * h + layout.noonBreakHeight + layout.eveningBreakHeight,
      );
    });

    test('segmentsOf 按新的休息带拆分', () {
      // 1-5 节整个上午：不拆（旧规则会在第 4 节后拆开）。
      expect(layout.segmentsOf(0, 4), <(int, int)>[(0, 4)]);
      // 4-6 节跨午休：拆成 4-5 / 6。
      expect(layout.segmentsOf(3, 5), <(int, int)>[(3, 4), (5, 5)]);
      // 8-11 节跨晚休：拆成 8-9 / 10-11。
      expect(layout.segmentsOf(7, 10), <(int, int)>[(7, 8), (9, 10)]);
      // 5-10 节跨两条带。
      expect(layout.segmentsOf(4, 9), <(int, int)>[(4, 4), (5, 8), (9, 9)]);
    });

    test('当前时刻线落在午休带里', () {
      final noon = layout.currentTimeOffset(13 * 60)!; // 12:35 ~ 14:00 之间
      expect(noon, greaterThan(layout.topOf(4) + layout.periodHeight));
      expect(noon, lessThan(layout.topOf(5)));
    });
  });

  group('WeekLayout：其他情况', () {
    test('手动 breakAfter 覆盖自动推导', () {
      final layout = WeekLayout.of(configOf(fiveMorning, breakAfter: <int>[2]));
      expect(layout.breakAfterPositions, <int>[1]);
      expect(layout.segmentsOf(0, 4), <(int, int)>[(0, 1), (2, 4)]);
      // 08:55 前后（上午课间）的带：种类是 other，文字「休息」。
      expect(layout.breakKindAfter(1), BreakKind.other);
      expect(layout.breakLabelAfter(1), '休息');
      expect(layout.breakHeightAfter(1), layout.eveningBreakHeight);
    });

    test('手动空列表：一整天不拆', () {
      final layout = WeekLayout.of(configOf(fiveMorning, breakAfter: <int>[]));
      expect(layout.breakAfterPositions, isEmpty);
      expect(layout.segmentsOf(0, 10), <(int, int)>[(0, 10)]);
      expect(layout.totalHeight, 11 * layout.periodHeight);
    });

    test('直接构造（不给 breakAfterIndices）时按作息自动推导', () {
      final layout = WeekLayout(periods: fiveMorning, periodHeight: 40);
      expect(layout.breakAfterPositions, <int>[4, 8]);
      final shu = WeekLayout(periods: defaultPeriods);
      expect(shu.breakAfterPositions, <int>[3, 7]);
      expect(shu.breakLabelAfter(3), '午间休息');
      expect(shu.breakLabelAfter(7), '晚间休息');
    });

    test('index 不从 1 开始 / 不连续时也按 position 对齐', () {
      const periods = <PeriodTime>[
        PeriodTime(index: 3, start: '08:00', end: '08:45'),
        PeriodTime(index: 7, start: '10:00', end: '10:45'), // 75 分钟
        PeriodTime(index: 9, start: '10:55', end: '11:40'),
      ];
      final layout = WeekLayout.of(configOf(periods));
      expect(ScheduleUtils.breakAfterIndices(configOf(periods)), <int>[3]);
      expect(layout.breakAfterPositions, <int>[0]);
    });
  });
}
