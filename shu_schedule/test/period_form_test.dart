import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/features/settings/period_form.dart';
import 'package:shu_schedule/features/timetable/week_layout.dart';
import 'package:shu_schedule/models/period_time.dart';

void main() {
  final shu = List<PeriodTime>.from(defaultPeriods);

  group('PeriodForm.validateEdit', () {
    test('合法修改返回 null', () {
      expect(PeriodForm.validateEdit(shu, 0, '08:10', '08:55'), isNull);
    });

    test('结束不晚于开始要报错', () {
      expect(PeriodForm.validateEdit(shu, 0, '09:00', '08:00'), isNotNull);
      expect(PeriodForm.validateEdit(shu, 0, '08:00', '08:00'), isNotNull);
    });

    test('与上一节重叠要报错', () {
      // 第 2 节原本 08:55 开始，上一节 08:45 结束。
      expect(PeriodForm.validateEdit(shu, 1, '08:40', '09:40'), isNotNull);
      expect(PeriodForm.validateEdit(shu, 1, '08:45', '09:40'), isNull);
    });

    test('与下一节重叠要报错', () {
      // 第 1 节的下一节 08:55 开始。
      expect(PeriodForm.validateEdit(shu, 0, '08:00', '09:00'), isNotNull);
      expect(PeriodForm.validateEdit(shu, 0, '08:00', '08:55'), isNull);
    });

    test('越界位置返回错误而不是崩溃', () {
      expect(PeriodForm.validateEdit(shu, -1, '08:00', '08:45'), isNotNull);
      expect(PeriodForm.validateEdit(shu, 99, '08:00', '08:45'), isNotNull);
    });
  });

  group('PeriodForm 增删节次', () {
    test('append 接在最后一节之后，时长沿用', () {
      final next = PeriodForm.appendPeriod(shu);
      expect(next.length, 13);
      expect(next.last.index, 13);
      expect(next.last.start, '21:50'); // 20:55-21:40 之后 10 分钟
      expect(next.last.end, '22:35');
      expect(
        PeriodForm.validateEdit(next, 12, next.last.start, next.last.end),
        isNull,
      );
    });

    test('append 到空列表时给一个默认节次', () {
      final next = PeriodForm.appendPeriod(const <PeriodTime>[]);
      expect(next.length, 1);
      expect(next.first.index, 1);
    });

    test('removeLast 保底留一节', () {
      expect(PeriodForm.removeLast(shu).length, 11);
      final one = <PeriodTime>[shu.first];
      expect(PeriodForm.removeLast(one).length, 1);
    });

    test('renumber 把 index 排成 1..n', () {
      final messy = <PeriodTime>[
        const PeriodTime(index: 5, start: '08:00', end: '08:45'),
        const PeriodTime(index: 9, start: '09:00', end: '09:45'),
      ];
      expect(PeriodForm.renumber(messy).map((p) => p.index).toList(), <int>[
        1,
        2,
      ]);
    });

    test('formatMinutes 补零并裁剪', () {
      expect(PeriodForm.formatMinutes(0), '00:00');
      expect(PeriodForm.formatMinutes(8 * 60 + 5), '08:05');
      expect(PeriodForm.formatMinutes(99999), '23:59');
    });
  });

  group('WeekLayout', () {
    final layout = WeekLayout(periods: shu, periodHeight: 50);

    test('第 4 / 8 节后插入休息带', () {
      expect(layout.topOf(0), 0);
      expect(layout.topOf(4), 4 * 50 + layout.noonBreakHeight);
      expect(
        layout.topOf(8),
        8 * 50 + layout.noonBreakHeight + layout.eveningBreakHeight,
      );
      expect(
        layout.totalHeight,
        12 * 50 + layout.noonBreakHeight + layout.eveningBreakHeight,
      );
    });

    test('跨休息带的课程被拆成多段', () {
      expect(layout.segmentsOf(0, 1), <(int, int)>[(0, 1)]);
      expect(layout.segmentsOf(2, 5), <(int, int)>[(2, 3), (4, 5)]);
      expect(layout.segmentsOf(2, 9), <(int, int)>[(2, 3), (4, 7), (8, 9)]);
    });

    test('positionOfIndex 与 heightOfSpan', () {
      expect(layout.positionOfIndex(1), 0);
      expect(layout.positionOfIndex(12), 11);
      expect(layout.positionOfIndex(99), -1);
      expect(layout.heightOfSpan(0, 1), 100);
    });

    test('当前时刻线：课前和放学后不画，课中按比例插值', () {
      expect(layout.currentTimeOffset(7 * 60), isNull); // 07:00 第一节课前
      expect(layout.currentTimeOffset(23 * 60 + 30), isNull); // 全部结束后
      // 08:00 正好第 1 节开始。
      expect(layout.currentTimeOffset(8 * 60), 0);
      // 08:45 第 1 节结束。
      expect(layout.currentTimeOffset(8 * 60 + 45), 50);
      // 08:50 落在第 1、2 节之间，这里没有休息带，线正好压在两节交界上。
      expect(layout.currentTimeOffset(8 * 60 + 50), 50);
      // 12:00 落在第 4 节（11:40 结束）与第 5 节（13:00 开始）之间的午间带里。
      final noon = layout.currentTimeOffset(12 * 60)!;
      expect(noon, greaterThan(layout.topOf(3) + 50));
      expect(noon, lessThan(layout.topOf(4)));
    });

    test('空作息表不崩溃', () {
      final empty = WeekLayout(periods: const <PeriodTime>[]);
      expect(empty.totalHeight, 0);
      expect(empty.segmentsOf(0, 3), isEmpty);
      expect(empty.currentTimeOffset(600), isNull);
    });
  });
}
