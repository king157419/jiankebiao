import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/schedule_config.dart';
import 'presets.dart';
import 'schedule_utils.dart';

/// 内置节假日数据（`assets/holidays.json`）与「一键套用」的建议生成（v1.3.1）。
///
/// 两类数据：
/// - `national`：国务院办公厅每年发布的放假 / 调休上班日期（按年份）；
/// - `schools`：已收录学校某个学期的放假 / 补课通知，按日期给出
///   「停课」或「按另一天的课上」（`actAsDate`）。
///
/// 当前课表有 `schoolId` 且该校有和当前学期对得上的学期时用学校数据，
/// 否则退回国家安排：放假日 → 停课；调休上班日只提示，不自动设置
/// （学校按哪天的课上各校不同，要看教务通知）。
///
/// v1.4.0：顶层多了 `version`（数据结构版本，只认 [schemaVersion]）和 `updatedAt`
/// （整份数据的更新日期）。同一份结构既打包在安装包里（[HolidayDataSource.bundled]），
/// 也可以由 `HolidayRepository` 从发布仓库下载（[HolidayDataSource.remote]）。
class HolidayPresets {
  /// 年份 → 国家安排。
  final Map<int, NationalYear> national;

  /// 学校 id → 学校数据。
  final Map<String, SchoolHolidays> schools;

  /// 顶层 `version`；没写为 0（旧数据 / 手写的测试数据，仍按当前结构读）。
  final int version;

  /// 顶层 `updatedAt`（整份数据的更新日期，只有日期）；没写 / 解析不了为 null。
  final DateTime? updatedAt;

  /// 这份数据从哪来：安装包内置，还是联网下载后缓存在本地的。
  final HolidayDataSource source;

  const HolidayPresets({
    required this.national,
    required this.schools,
    this.version = 0,
    this.updatedAt,
    this.source = HolidayDataSource.bundled,
  });

  static const HolidayPresets empty = HolidayPresets(
    national: <int, NationalYear>{},
    schools: <String, SchoolHolidays>{},
  );

  /// App 认识的数据结构版本。顶层写了别的版本号 → 整份视为无效（不去猜新结构）。
  static const int schemaVersion = 1;

  static const String assetPath = 'assets/holidays.json';

  /// 顶层明确写着 `version == 1`（[schemaVersion]）。
  bool get isValid => version == schemaVersion;

  /// 「内置 2026-10-06」/「已更新 2026-11-02」这类数据版本说明里的日期；没有为 null。
  String? get updatedAtText =>
      updatedAt == null ? null : ScheduleUtils.dateKey(updatedAt!);

  /// 远程下载 / 本地缓存用的严格解析：必须是对象、顶层 `version` 等于 [schemaVersion]、
  /// `updatedAt` 是合法日期；否则返回 null（调用方回退到内置数据）。
  static HolidayPresets? tryParseStrict(
    Object? decoded, {
    HolidayDataSource source = HolidayDataSource.remote,
  }) {
    if (decoded is! Map) return null;
    if (_version(decoded['version']) != schemaVersion) return null;
    if (ScheduleConfig.parseDate(decoded['updatedAt']) == null) return null;
    final parsed = HolidayPresets.fromJson(decoded, source: source);
    return parsed.isValid && parsed.updatedAt != null ? parsed : null;
  }

  static int? _version(Object? raw) {
    if (raw is int) return raw;
    if (raw is num && raw == raw.roundToDouble()) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static HolidayPresets? _cached;

  /// 读打包进 App 的 `assets/holidays.json`（读一次后缓存）。读不到 / 坏 JSON → [empty]。
  static Future<HolidayPresets> loadBundled({AssetBundle? bundle}) async {
    final cached = _cached;
    if (cached != null && bundle == null) return cached;
    try {
      final text = await (bundle ?? rootBundle).loadString(assetPath);
      final decoded = jsonDecode(text);
      final result = decoded is Map
          ? HolidayPresets.fromJson(decoded)
          : HolidayPresets.empty;
      if (bundle == null) _cached = result;
      return result;
    } catch (_) {
      return HolidayPresets.empty;
    }
  }

  /// 容错解析：缺字段 / 类型不对 / 日期解析不了的条目直接丢掉，不抛异常。
  ///
  /// 顶层 `version` 写了但不等于 [schemaVersion] → 返回不含任何条目的无效数据
  /// （[isValid] 为 false）；没写 `version` 时按当前结构读（[version] 记为 0）。
  factory HolidayPresets.fromJson(
    Map<dynamic, dynamic> json, {
    HolidayDataSource source = HolidayDataSource.bundled,
  }) {
    final rawVersion = json['version'];
    final version = rawVersion == null ? 0 : (_version(rawVersion) ?? -1);
    final updatedAt = ScheduleConfig.parseDate(json['updatedAt']);
    if (rawVersion != null && version != schemaVersion) {
      return HolidayPresets(
        national: const <int, NationalYear>{},
        schools: const <String, SchoolHolidays>{},
        version: version,
        updatedAt: updatedAt,
        source: source,
      );
    }
    final national = <int, NationalYear>{};
    final rawNational = json['national'];
    if (rawNational is Map) {
      rawNational.forEach((key, value) {
        final year = int.tryParse('$key'.trim());
        if (year == null || value is! Map) return;
        final parsed = NationalYear._fromJson(year, value);
        if (parsed != null) national[year] = parsed;
      });
    }
    final schools = <String, SchoolHolidays>{};
    final rawSchools = json['schools'];
    if (rawSchools is Map) {
      rawSchools.forEach((key, value) {
        if (key is! String || key.trim().isEmpty || value is! Map) return;
        final parsed = SchoolHolidays._fromJson(key.trim(), value);
        if (parsed != null) schools[parsed.id] = parsed;
      });
    }
    return HolidayPresets(
      national: national,
      schools: schools,
      version: version,
      updatedAt: updatedAt,
      source: source,
    );
  }

  /// [schoolId] 这所学校里「今天」所在的学期：`[startDate, startDate + totalWeeks * 7)`
  /// 包含 [today]（v1.5.0，导入预览和校历建议用它推开学日期）。没有返回 null。
  SchoolTerm? termCovering(String schoolId, DateTime today) {
    final school = schools[schoolId];
    if (school == null) return null;
    for (final t in school.terms) {
      final days = ScheduleUtils.daysBetween(t.startDate, today);
      if (days >= 0 && days < t.totalWeeks * 7) return t;
    }
    return null;
  }

  /// 当前学期的建议列表（见 [planFor]）。
  List<HolidaySuggestion> suggestionsFor({
    required ScheduleConfig config,
    String? schoolId,
  }) => planFor(config: config, schoolId: schoolId).items;

  /// 给 [config] 这个学期生成一份套用方案。
  ///
  /// 学期范围 = `[startDate, startDate + totalWeeks * 7 - 1]`，只返回范围内的日期，按日期排序。
  HolidayPlan planFor({required ScheduleConfig config, String? schoolId}) {
    final start = config.startDate;
    final weeks = config.totalWeeks < 1 ? 1 : config.totalWeeks;
    final end = ScheduleUtils.addDays(start, weeks * 7 - 1);

    final school = schoolId == null ? null : schools[schoolId];
    final term = school?.termFor(start, end);
    if (school != null && term != null) {
      return _schoolPlan(school, term, config, start, end);
    }
    return _nationalPlan(config, start, end);
  }

  HolidayPlan _schoolPlan(
    SchoolHolidays school,
    SchoolTerm term,
    ScheduleConfig config,
    DateTime start,
    DateTime end,
  ) {
    final items = <HolidaySuggestion>[];
    for (final e in term.entries) {
      if (!_within(e.date, start, end)) continue;
      final existing = config.overrideOn(e.date);
      final actAs = e.actAsDate;
      if (actAs == null) {
        items.add(
          HolidaySuggestion(
            date: e.date,
            override: DateOverride.cancelled(note: e.note),
            note: e.note,
            sourceLabel: school.name,
            fromSchool: true,
            existing: existing,
          ),
        );
        continue;
      }
      final week = ScheduleUtils.rawWeekOf(actAs, config);
      String? warning;
      if (week < 1 || week > config.totalWeeks) {
        warning =
            '${_monthDay(actAs)}（${weekdayNamesCn[actAs.weekday]}）不在本学期第 1-'
            '${config.totalWeeks} 周内，套用后这天可能没有课，请检查开学日期';
      }
      items.add(
        HolidaySuggestion(
          date: e.date,
          override: DateOverride.actAs(
            week: week,
            weekday: actAs.weekday,
            note: e.note,
          ),
          note: e.note,
          sourceLabel: school.name,
          fromSchool: true,
          warning: warning,
          existing: existing,
        ),
      );
    }
    items.sort((a, b) => a.date.compareTo(b.date));
    final sources = <String>[?term.noticeSource, ?term.calendarSource];
    final updated = term.updatedAt == null ? '' : '（${term.updatedAt} 更新）';
    return HolidayPlan(
      title: '${school.name} · ${term.name}',
      sourceText: sources.isEmpty
          ? '${school.name}$updated'
          : '${sources.join('；')}$updated',
      sourceUrl: term.noticeUrl ?? term.calendarUrl,
      items: items,
    );
  }

  HolidayPlan _nationalPlan(
    ScheduleConfig config,
    DateTime start,
    DateTime end,
  ) {
    final byKey = <String, HolidaySuggestion>{};
    final years = <NationalYear>[];
    for (var y = start.year; y <= end.year; y++) {
      final data = national[y];
      if (data == null) continue;
      var used = false;
      for (final h in data.holidays) {
        for (final d in h.off) {
          if (!_within(d, start, end)) continue;
          used = true;
          final note = '${h.name}放假（国家安排）';
          byKey.putIfAbsent(
            ScheduleUtils.dateKey(d),
            () => HolidaySuggestion(
              date: d,
              override: DateOverride.cancelled(note: note),
              note: note,
              sourceLabel: '国家安排',
              existing: config.overrideOn(d),
            ),
          );
        }
        for (final d in h.work) {
          if (!_within(d, start, end)) continue;
          used = true;
          byKey.putIfAbsent(
            ScheduleUtils.dateKey(d),
            () => HolidaySuggestion(
              date: d,
              note:
                  '${_monthDay(d)}（${weekdayNamesCn[d.weekday]}）国家调休上班，'
                  '学校按哪天的课上要看教务通知后手动设置',
              sourceLabel: '国家安排',
              needsConfirmation: true,
              existing: config.overrideOn(d),
            ),
          );
        }
      }
      if (used) years.add(data);
    }
    final items = byKey.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final yearText = years.isEmpty
        ? ''
        : '（${years.map((y) => y.year).join('、')}）';
    return HolidayPlan(
      title: '国家法定节假日$yearText',
      sourceText: years.isEmpty
          ? '国务院办公厅节假日安排通知'
          : years.map((y) => y.source).join('；'),
      sourceUrl: years.isEmpty ? null : years.first.sourceUrl,
      items: items,
    );
  }

  static bool _within(DateTime d, DateTime start, DateTime end) =>
      !d.isBefore(start) && !d.isAfter(end);

  static String _monthDay(DateTime d) => '${d.month}月${d.day}日';
}

/// 假日表数据的来源。
enum HolidayDataSource {
  /// 安装包内置的 `assets/holidays.json`。
  bundled,

  /// 从发布仓库下载、缓存在本地的 `holidays.remote.json`。
  remote,
}

/// 一份可套用的方案：标题、来源、建议列表。
class HolidayPlan {
  /// 「<校名> · <学期名>」/「国家法定节假日（2026）」。
  final String title;
  final String sourceText;
  final String? sourceUrl;
  final List<HolidaySuggestion> items;

  const HolidayPlan({
    required this.title,
    required this.sourceText,
    this.sourceUrl,
    required this.items,
  });

  bool get isEmpty => items.isEmpty;
}

/// 一条建议：某一天建议设置成 [override]。
class HolidaySuggestion {
  final DateTime date;

  /// 建议的规则；[needsConfirmation] 时为 null（只提示，不能直接套用）。
  final DateOverride? override;

  /// 说明文字（一般就是 override 的备注；需要确认的条目是完整提示）。
  final String? note;

  /// 学校名 /「国家安排」。
  final String sourceLabel;

  /// 来自学校通知（否则是国家安排）。
  final bool fromSchool;

  /// 国家调休上班日：学校怎么补课要看通知，需要用户手动设置。
  final bool needsConfirmation;

  /// 需要提醒用户的问题（例如被调换的那天不在学期内）。
  final String? warning;

  /// 这一天当前已有的设置。
  final DateOverride? existing;

  const HolidaySuggestion({
    required this.date,
    this.override,
    this.note,
    required this.sourceLabel,
    this.fromSchool = false,
    this.needsConfirmation = false,
    this.warning,
    this.existing,
  });

  /// 这一天已经是建议的设置了。
  bool get alreadyApplied => existing != null && existing == override;

  /// 这一天已有不同的设置，套用会覆盖它。
  bool get conflicts =>
      existing != null && override != null && existing != override;

  /// 能不能勾选套用。
  bool get applicable => override != null && !alreadyApplied;
}

/// 国家某一年的安排。
class NationalYear {
  final int year;
  final String source;
  final String? sourceUrl;
  final List<NationalHoliday> holidays;

  const NationalYear({
    required this.year,
    required this.source,
    this.sourceUrl,
    required this.holidays,
  });

  static NationalYear? _fromJson(int year, Map<dynamic, dynamic> json) {
    final rawHolidays = json['holidays'];
    if (rawHolidays is! List) return null;
    final holidays = <NationalHoliday>[];
    for (final h in rawHolidays) {
      if (h is! Map) continue;
      final name = _string(h['name']);
      if (name == null) continue;
      holidays.add(
        NationalHoliday(
          name: name,
          off: _dates(h['off']),
          work: _dates(h['work']),
        ),
      );
    }
    return NationalYear(
      year: year,
      source: _string(json['source']) ?? '国务院办公厅 $year 年节假日安排通知',
      sourceUrl: _httpUrl(json['sourceUrl']),
      holidays: holidays,
    );
  }
}

/// 一个节日：放假日期 + 调休上班日期。
class NationalHoliday {
  final String name;
  final List<DateTime> off;
  final List<DateTime> work;

  const NationalHoliday({
    required this.name,
    required this.off,
    required this.work,
  });
}

/// 一所学校的放假 / 补课数据。
class SchoolHolidays {
  final String id;
  final String name;
  final List<SchoolTerm> terms;

  const SchoolHolidays({
    required this.id,
    required this.name,
    required this.terms,
  });

  /// 和 `[start, end]` 这个学期对应的那一期：先找开学日期（对齐到周一）完全相同的，
  /// 再找日期范围有重叠的；都没有返回 null。
  SchoolTerm? termFor(DateTime start, DateTime end) {
    final key = ScheduleUtils.dateKey(start);
    for (final t in terms) {
      if (ScheduleUtils.dateKey(t.startDate) == key) return t;
    }
    for (final t in terms) {
      final tEnd = ScheduleUtils.addDays(t.startDate, t.totalWeeks * 7 - 1);
      if (!t.startDate.isAfter(end) && !tEnd.isBefore(start)) return t;
    }
    return null;
  }

  static SchoolHolidays? _fromJson(String id, Map<dynamic, dynamic> json) {
    final rawTerms = json['terms'];
    if (rawTerms is! List) return null;
    final terms = <SchoolTerm>[];
    for (final t in rawTerms) {
      if (t is! Map) continue;
      final parsed = SchoolTerm._fromJson(t);
      if (parsed != null) terms.add(parsed);
    }
    return SchoolHolidays(
      id: id,
      name: _string(json['name']) ?? id,
      terms: terms,
    );
  }
}

/// 学校某个学期的放假 / 补课安排。
class SchoolTerm {
  final String id;
  final String name;

  /// 第 1 周周一（已对齐到周一）。
  final DateTime startDate;
  final int totalWeeks;
  final String? calendarSource;
  final String? calendarUrl;
  final String? noticeSource;
  final String? noticeUrl;
  final String? updatedAt;
  final List<SchoolHolidayEntry> entries;

  const SchoolTerm({
    required this.id,
    required this.name,
    required this.startDate,
    required this.totalWeeks,
    this.calendarSource,
    this.calendarUrl,
    this.noticeSource,
    this.noticeUrl,
    this.updatedAt,
    required this.entries,
  });

  static SchoolTerm? _fromJson(Map<dynamic, dynamic> json) {
    final start = ScheduleConfig.parseDate(json['startDate']);
    final rawWeeks = json['totalWeeks'];
    final weeks = rawWeeks is num ? rawWeeks.toInt() : null;
    if (start == null || weeks == null || weeks < 1 || weeks > 60) return null;
    final entries = <SchoolHolidayEntry>[];
    final seen = <String>{};
    final rawEntries = json['entries'];
    if (rawEntries is List) {
      for (final e in rawEntries) {
        if (e is! Map) continue;
        final parsed = SchoolHolidayEntry._fromJson(e);
        if (parsed == null) continue;
        if (!seen.add(ScheduleUtils.dateKey(parsed.date))) continue;
        entries.add(parsed);
      }
    }
    final id = _string(json['id']) ?? ScheduleUtils.dateKey(start);
    return SchoolTerm(
      id: id,
      name: _string(json['name']) ?? id,
      startDate: ScheduleUtils.mondayOf(start),
      totalWeeks: weeks,
      calendarSource: _string(json['calendarSource']),
      calendarUrl: _httpUrl(json['calendarUrl']),
      noticeSource: _string(json['noticeSource']),
      noticeUrl: _httpUrl(json['noticeUrl']),
      updatedAt: _string(json['updatedAt']),
      entries: entries,
    );
  }
}

/// 学校通知里的一天：停课，或按 [actAsDate] 那天的课上。
class SchoolHolidayEntry {
  final DateTime date;
  final bool cancelled;
  final DateTime? actAsDate;
  final String? note;

  const SchoolHolidayEntry({
    required this.date,
    this.cancelled = false,
    this.actAsDate,
    this.note,
  });

  /// 必须有日期，且是停课或有合法的 `actAsDate`（两个都有时按停课）；否则丢掉。
  static SchoolHolidayEntry? _fromJson(Map<dynamic, dynamic> json) {
    final date = ScheduleConfig.parseDate(json['date']);
    if (date == null) return null;
    final note = _string(json['note']);
    if (json['cancelled'] == true) {
      return SchoolHolidayEntry(date: date, cancelled: true, note: note);
    }
    final actAs = ScheduleConfig.parseDate(json['actAsDate']);
    if (actAs == null) return null;
    return SchoolHolidayEntry(date: date, actAsDate: actAs, note: note);
  }
}

String? _string(Object? v) =>
    v is String && v.trim().isNotEmpty ? v.trim() : null;

String? _httpUrl(Object? v) {
  final s = _string(v);
  if (s == null) return null;
  final uri = Uri.tryParse(s);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return s;
}

List<DateTime> _dates(Object? raw) {
  if (raw is! List) return const <DateTime>[];
  final result = <DateTime>[];
  for (final v in raw) {
    final d = v is String ? ScheduleConfig.parseDate(v) : null;
    if (d != null) result.add(d);
  }
  return result;
}
