import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/features/timetable/course_form.dart';
import 'package:shu_schedule/models/course.dart';

void main() {
  group('CourseForm.validate*', () {
    test('课程名必填', () {
      expect(CourseForm.validateName(null), isNotNull);
      expect(CourseForm.validateName('   '), isNotNull);
      expect(CourseForm.validateName('高等数学'), isNull);
      expect(CourseForm.validateName('课' * 41), isNotNull);
    });

    test('节次范围必须 1 <= start <= end <= periodCount', () {
      expect(CourseForm.validatePeriodRange(1, 2, 12), isNull);
      expect(CourseForm.validatePeriodRange(12, 12, 12), isNull);
      expect(CourseForm.validatePeriodRange(0, 2, 12), isNotNull);
      expect(CourseForm.validatePeriodRange(1, 13, 12), isNotNull);
      expect(CourseForm.validatePeriodRange(5, 3, 12), isNotNull);
      expect(CourseForm.validatePeriodRange(1, 1, 0), isNotNull);
    });

    test('星期与周次', () {
      expect(CourseForm.validateDay(0), isNotNull);
      expect(CourseForm.validateDay(8), isNotNull);
      expect(CourseForm.validateDay(7), isNull);
      expect(CourseForm.validateWeeks(const <int>[]), isNotNull);
      expect(CourseForm.validateWeeks(const <int>[1]), isNull);
    });

    test('validateAll 按顺序返回第一条错误', () {
      expect(
        CourseForm.validateAll(
          name: '',
          day: 9,
          startPeriod: 3,
          endPeriod: 1,
          periodCount: 12,
          weeks: const <int>[],
        ),
        '请填写课程名',
      );
      expect(
        CourseForm.validateAll(
          name: '大学物理',
          day: 1,
          startPeriod: 3,
          endPeriod: 1,
          periodCount: 12,
          weeks: const <int>[1],
        ),
        '结束节次不能早于起始节次',
      );
      expect(
        CourseForm.validateAll(
          name: '大学物理',
          day: 1,
          startPeriod: 1,
          endPeriod: 2,
          periodCount: 12,
          weeks: const <int>[1, 2, 3],
        ),
        isNull,
      );
    });
  });

  group('CourseForm 周次快捷方案', () {
    test('全部 / 单 / 双 / 前半 / 后半', () {
      expect(CourseForm.allWeeks(4), <int>[1, 2, 3, 4]);
      expect(CourseForm.oddWeeks(6), <int>[1, 3, 5]);
      expect(CourseForm.evenWeeks(6), <int>[2, 4, 6]);
      expect(CourseForm.firstHalfWeeks(18), <int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(CourseForm.secondHalfWeeks(18), <int>[
        10,
        11,
        12,
        13,
        14,
        15,
        16,
        17,
        18,
      ]);
      // 奇数周数时前半多一周，两半合起来仍然是全部。
      expect(<int>[
        ...CourseForm.firstHalfWeeks(17),
        ...CourseForm.secondHalfWeeks(17),
      ], CourseForm.allWeeks(17));
    });
  });

  group('CourseForm.defaultColorIndex', () {
    test('同名课程颜色稳定，且落在 0..9', () {
      final a = CourseForm.defaultColorIndex('高等数学 A(一)');
      final b = CourseForm.defaultColorIndex('高等数学 A(一)');
      expect(a, b);
      expect(a, inInclusiveRange(0, 9));
      expect(CourseForm.defaultColorIndex(''), 0);
      for (final name in <String>['大学英语', '线性代数', '体育', '程序设计']) {
        expect(CourseForm.defaultColorIndex(name), inInclusiveRange(0, 9));
      }
    });
  });

  group('CourseForm.normalize', () {
    test('纠正越界节次、星期、颜色并规范周次', () {
      final c = CourseForm.normalize(
        Course(
          id: 'x',
          name: '  体育  ',
          day: 9,
          startPeriod: 0,
          endPeriod: -3,
          weeks: <int>[3, 1, 1, 0, 2],
          colorIndex: 42,
        ),
        periodCount: 12,
      );
      expect(c.name, '体育');
      expect(c.day, 7);
      expect(c.startPeriod, 1);
      expect(c.endPeriod, 1);
      expect(c.weeks, <int>[1, 2, 3]);
      expect(c.colorIndex, 9);
    });

    test('节次超过作息表长度时裁剪', () {
      final c = CourseForm.normalize(
        Course(
          id: 'x',
          name: '实验',
          day: 1,
          startPeriod: 20,
          endPeriod: 22,
          weeks: <int>[1],
        ),
        periodCount: 12,
      );
      expect(c.startPeriod, 12);
      expect(c.endPeriod, 12);
    });
  });
}
