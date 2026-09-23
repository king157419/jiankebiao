import 'date_override.dart';
import 'period_time.dart';
import '../core/presets.dart';

export 'date_override.dart';

/// 一张课表的学期配置：学期名、开学日期、总周数、作息表、调休 / 停课、休息带。
class ScheduleConfig {
  /// 学期名，例如 "2026-2027 秋"。
  String name;

  /// 第 1 周的周一（时间部分会被归一化为 00:00）。
  DateTime startDate;

  /// 总周数，例如 18。
  int totalWeeks;

  /// 作息表，按 index 升序，默认 [defaultPeriods]（12 节示例作息）。
  List<PeriodTime> periods;

  /// 是否显示周六/周日两列。
  bool showWeekend;

  /// 调休 / 停课：key 为 `yyyy-MM-dd`（见 [dateKey]）。
  ///
  /// v1.3.0 新增；旧 JSON 没有这个字段时为空表。
  Map<String, DateOverride> overrides;

  /// 手动指定「在哪几节之后画休息带」，元素是 [PeriodTime.index]（1 基）。
  ///
  /// - null：自动推导（相邻两节间隔 >= 40 分钟就画一条，见
  ///   `ScheduleUtils.breakAfterIndices`）；
  /// - 空列表：一条休息带都不画。
  ///
  /// v1.3.0 新增；旧 JSON 没有这个字段时为 null（自动）。
  List<int>? breakAfter;

  ScheduleConfig({
    required this.name,
    required DateTime startDate,
    this.totalWeeks = 18,
    List<PeriodTime>? periods,
    this.showWeekend = true,
    Map<String, DateOverride>? overrides,
    List<int>? breakAfter,
  }) : startDate = _mondayFloor(startDate),
       periods = periods ?? List<PeriodTime>.from(defaultPeriods),
       overrides = overrides == null
           ? <String, DateOverride>{}
           : Map<String, DateOverride>.from(overrides),
       breakAfter = breakAfter == null ? null : _normalizeBreaks(breakAfter);

  /// 内置默认配置：第一个示例学期 + 12 节示例作息。
  factory ScheduleConfig.defaults() {
    final preset = exampleTermPresets.first;
    return ScheduleConfig(
      name: preset.name,
      startDate: preset.startDate,
      totalWeeks: preset.totalWeeks,
      periods: List<PeriodTime>.from(defaultPeriods),
    );
  }

  /// 节数。
  int get periodCount => periods.length;

  /// 是否手动指定了休息带（否则自动推导）。
  bool get hasManualBreaks => breakAfter != null;

  ScheduleConfig copyWith({
    String? name,
    DateTime? startDate,
    int? totalWeeks,
    List<PeriodTime>? periods,
    bool? showWeekend,
    Map<String, DateOverride>? overrides,
    List<int>? breakAfter,
    bool clearBreakAfter = false,
  }) => ScheduleConfig(
    name: name ?? this.name,
    startDate: startDate ?? this.startDate,
    totalWeeks: totalWeeks ?? this.totalWeeks,
    periods: periods ?? List<PeriodTime>.from(this.periods),
    showWeekend: showWeekend ?? this.showWeekend,
    overrides: overrides ?? this.overrides,
    breakAfter: clearBreakAfter ? null : (breakAfter ?? this.breakAfter),
  );

  /// 按 index 取一节的时间；越界返回 null。
  PeriodTime? periodAt(int index) {
    for (final p in periods) {
      if (p.index == index) return p;
    }
    return null;
  }

  /// [date] 这一天的调休 / 停课规则；没有返回 null。
  DateOverride? overrideOn(DateTime date) => overrides[dateKey(date)];

  /// 返回一份在 [date] 上设置（[value] 非 null）或删除（[value] 为 null）
  /// 调休规则后的新配置，原对象不变。
  ScheduleConfig withOverride(DateTime date, DateOverride? value) {
    final next = Map<String, DateOverride>.from(overrides);
    if (value == null) {
      next.remove(dateKey(date));
    } else {
      next[dateKey(date)] = value;
    }
    return copyWith(overrides: next);
  }

  Map<String, dynamic> toJson() {
    final keys = overrides.keys.toList()..sort();
    return <String, dynamic>{
      'name': name,
      'startDate': dateKey(startDate),
      'totalWeeks': totalWeeks,
      'periods': periods.map((p) => p.toJson()).toList(),
      'showWeekend': showWeekend,
      'overrides': <String, dynamic>{
        for (final k in keys) k: overrides[k]!.toJson(),
      },
      'breakAfter': breakAfter,
    };
  }

  factory ScheduleConfig.fromJson(Map<String, dynamic> json) {
    final rawPeriods = json['periods'];
    List<PeriodTime> periods;
    if (rawPeriods is List && rawPeriods.isNotEmpty) {
      periods = rawPeriods
          .whereType<Map>()
          .map((e) => PeriodTime.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (periods.isEmpty) periods = List<PeriodTime>.from(defaultPeriods);
    } else {
      periods = List<PeriodTime>.from(defaultPeriods);
    }
    final weeks = json['totalWeeks'];
    return ScheduleConfig(
      name: json['name'] is String ? json['name'] as String : '未命名学期',
      startDate:
          parseDate(json['startDate']) ?? exampleTermPresets.first.startDate,
      totalWeeks: (weeks is num ? weeks.toInt() : 18).clamp(1, 60),
      periods: periods,
      showWeekend: json['showWeekend'] is bool
          ? json['showWeekend'] as bool
          : true,
      overrides: _parseOverrides(json['overrides']),
      breakAfter: _parseBreaks(json['breakAfter']),
    );
  }

  /// 容错解析调休表：key 必须是能解析的日期（会被归一化成 `yyyy-MM-dd`），
  /// value 必须是对象；其余条目直接丢掉。
  static Map<String, DateOverride> _parseOverrides(Object? raw) {
    final result = <String, DateOverride>{};
    if (raw is! Map) return result;
    raw.forEach((key, value) {
      final date = parseDate(key);
      if (date == null || value is! Map) return;
      result[dateKey(date)] = DateOverride.fromJson(
        Map<String, dynamic>.from(value),
      );
    });
    return result;
  }

  /// 缺字段 / 不是数组 → null（自动）；数组里的非法元素丢掉。
  static List<int>? _parseBreaks(Object? raw) {
    if (raw is! List) return null;
    final list = <int>[];
    for (final e in raw) {
      if (e is int) {
        list.add(e);
      } else if (e is num) {
        list.add(e.toInt());
      } else if (e is String) {
        final v = int.tryParse(e.trim());
        if (v != null) list.add(v);
      }
    }
    return list;
  }

  static List<int> _normalizeBreaks(Iterable<int> input) {
    final set = <int>{};
    for (final v in input) {
      if (v >= 1) set.add(v);
    }
    return set.toList()..sort();
  }

  /// 把任意日期向前对齐到当周周一，并清掉时分秒。
  ///
  /// 用日历加减（`DateTime(y, m, d - n)`）而不是 `subtract(Duration(days: n))`：
  /// Duration 是绝对时长，跨夏令时会得到 23:00/01:00 这种错位结果。
  static DateTime _mondayFloor(DateTime d) {
    final offset = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day - offset);
  }

  /// 解析 "yyyy-MM-dd" 或完整 ISO 串；失败返回 null。
  static DateTime? parseDate(Object? v) {
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is! String) return null;
    final parsed = DateTime.tryParse(v);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// 日期 → `yyyy-MM-dd`（[overrides] 的 key、小组件快照的日期都用这个格式）。
  static String dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  String toString() =>
      'ScheduleConfig($name, ${dateKey(startDate)}, $totalWeeks 周)';
}
