import '../../core/presets.dart';
import '../../models/course.dart';
import '../../models/schedule_config.dart';
import '../../models/timetable.dart';

/// 一份写死的通用示例课表（6 门课），只给「推送示例数据到小组件」自测用。
///
/// Phase 3 重写 `main.dart` 之后这个文件可以删掉，或者留着当小组件的调试入口。
Timetable buildDemoTimetable() {
  final preset = exampleTermPresets.first; // 示例学期：2026-09-14 开学，18 周
  final allWeeks = List<int>.generate(16, (i) => i + 1);
  final oddWeeks = allWeeks.where((w) => w.isOdd).toList();

  return Timetable(
    id: 'demo-widget',
    name: '示例课表',
    config: ScheduleConfig(
      name: preset.name,
      startDate: preset.startDate,
      totalWeeks: preset.totalWeeks,
      periods: List.of(defaultPeriods),
    ),
    courses: <Course>[
      Course(
        id: 'demo-1',
        name: '高等数学 A(一)',
        teacher: '张伟',
        location: '东区 J-101',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: allWeeks,
        colorIndex: 0,
        source: 'manual',
      ),
      Course(
        id: 'demo-2',
        name: '大学英语（三）',
        teacher: '李敏',
        location: '东区 E-305',
        day: 2,
        startPeriod: 3,
        endPeriod: 4,
        weeks: allWeeks,
        colorIndex: 1,
        source: 'manual',
      ),
      Course(
        id: 'demo-3',
        name: '线性代数',
        teacher: '王强',
        location: '东区 J-204',
        day: 3,
        startPeriod: 1,
        endPeriod: 2,
        weeks: oddWeeks,
        colorIndex: 2,
        source: 'manual',
      ),
      Course(
        id: 'demo-4',
        name: '数据结构',
        teacher: '陈海',
        location: '计算机楼 A-301',
        day: 3,
        startPeriod: 5,
        endPeriod: 6,
        weeks: allWeeks,
        colorIndex: 3,
        source: 'manual',
      ),
      Course(
        id: 'demo-5',
        name: '大学物理（一）',
        teacher: '刘芳',
        location: '理科楼 B-102',
        day: 4,
        startPeriod: 3,
        endPeriod: 4,
        weeks: allWeeks,
        colorIndex: 4,
        source: 'manual',
      ),
      Course(
        id: 'demo-6',
        name: '体育（羽毛球）',
        teacher: '赵磊',
        location: '体育馆二楼',
        day: 5,
        startPeriod: 7,
        endPeriod: 8,
        weeks: allWeeks,
        colorIndex: 5,
        source: 'manual',
      ),
    ],
  );
}
