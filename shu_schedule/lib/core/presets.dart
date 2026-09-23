import '../models/period_time.dart';

/// 通用示例作息：每天 12 节（1-4 上午，5-8 下午，9-12 晚上）。
///
/// 数据是一所已验证学校的真实作息（来源见 NOTES.md v1.3.0 Phase A），
/// 新建课表时作为起点，用户可在「作息时间」里改。
const List<PeriodTime> defaultPeriods = <PeriodTime>[
  PeriodTime(index: 1, start: '08:00', end: '08:45'),
  PeriodTime(index: 2, start: '08:55', end: '09:40'),
  PeriodTime(index: 3, start: '10:00', end: '10:45'),
  PeriodTime(index: 4, start: '10:55', end: '11:40'),
  PeriodTime(index: 5, start: '13:00', end: '13:45'),
  PeriodTime(index: 6, start: '13:55', end: '14:40'),
  PeriodTime(index: 7, start: '15:00', end: '15:45'),
  PeriodTime(index: 8, start: '15:55', end: '16:40'),
  PeriodTime(index: 9, start: '18:00', end: '18:45'),
  PeriodTime(index: 10, start: '18:55', end: '19:40'),
  PeriodTime(index: 11, start: '20:00', end: '20:45'),
  PeriodTime(index: 12, start: '20:55', end: '21:40'),
];

/// 学期预设（开学日期 = 第 1 周周一）。
class TermPreset {
  final String id;
  final String name;
  final DateTime startDate;
  final int totalWeeks;

  const TermPreset({
    required this.id,
    required this.name,
    required this.startDate,
    required this.totalWeeks,
  });
}

/// 内置的示例学期预设（新建课表时的默认学期）。
///
/// 数据取自一所已验证学校的 2026-2027 学年校历：两学期制，每学期 18 周 = 16 教学周 + 2 考试周。
final List<TermPreset> exampleTermPresets = <TermPreset>[
  TermPreset(
    id: 'shu-2026-autumn',
    name: '2026-2027 秋',
    startDate: DateTime(2026, 9, 14),
    totalWeeks: 18,
  ),
  TermPreset(
    id: 'shu-2027-spring',
    name: '2026-2027 春',
    startDate: DateTime(2027, 2, 22),
    totalWeeks: 18,
  ),
];

/// 一套作息模板（导入时教务没给出作息、又没有当前课表可沿用时让用户选）。
class PeriodTemplate {
  /// 稳定 id，`assets/schools.json` 里的 `periodProfileId` 指向它。
  final String id;

  /// 展示名。
  final String name;

  /// 一句话说明。
  final String description;

  final List<PeriodTime> periods;

  const PeriodTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.periods,
  });
}

/// 内置作息模板。目前只有一套，界面按列表写，以后加模板只改这里。
const List<PeriodTemplate> periodTemplates = <PeriodTemplate>[
  PeriodTemplate(
    id: 'default-12',
    name: '通用 12 节',
    description: '上午 4 节 · 下午 4 节 · 晚上 4 节，08:00 开始',
    periods: defaultPeriods,
  ),
];

/// 按 id 找作息模板；找不到（含 null）返回第一套。
PeriodTemplate periodTemplateById(String? id) {
  for (final t in periodTemplates) {
    if (t.id == id) return t;
  }
  return periodTemplates.first;
}

/// 星期中文名，索引 1..7。
const List<String> weekdayNamesCn = <String>[
  '',
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
];
