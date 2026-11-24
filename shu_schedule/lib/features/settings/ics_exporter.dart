import '../../core/app_brand.dart';
import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../models/course.dart';
import '../../models/timetable.dart';

/// 学期里实际要上的一节课（调休 / 停课已经展开），也就是 .ics 里的一个 VEVENT。
class IcsSession {
  /// 上课的日历日（时分秒为 0）。
  final DateTime date;

  /// 这一天按哪一周、星期几上课（调休展开后的结果）。
  final EffectiveDay day;

  final Course course;

  /// 开始 / 结束的「当天分钟数」（来自作息表）。
  final int startMinutes;
  final int endMinutes;

  const IcsSession({
    required this.date,
    required this.day,
    required this.course,
    required this.startMinutes,
    required this.endMinutes,
  });
}

/// 把一张课表展开成 iCalendar（RFC 5545）文本，给「导出到日历（.ics）」用。
///
/// 纯 Dart，不碰 IO。规则（2026-10-07 对照 rfc-editor.org/rfc/rfc5545 核对）：
/// - §3.1：每行以 CRLF 结束；一行不超过 75 个**字节**（不含换行），超长的行
///   在两个字符之间插入「CRLF + 一个空格」折行。这里按 Unicode 码点切，
///   所以永远不会把一个 UTF-8 多字节字符切成两半。
/// - §3.3.11：TEXT 值里反斜杠、分号、逗号前加反斜杠，换行写成 `\n`；
///   冒号不转义。TEXT 不允许控制字符，除换行外的控制字符直接去掉。
/// - §3.6.1：VEVENT 里 UID、DTSTAMP 必须且只能出现一次；DTEND 和 DURATION 不能同时出现。
/// - §3.8.7.2：DTSTAMP 必须是 UTC（`Z` 结尾）。
/// - §3.6.5：引用了 `TZID=Asia/Shanghai` 就附一个 VTIMEZONE；中国不实行夏令时，
///   所以只有一个 STANDARD 段（+0800 → +0800，DTSTART 用不带 Z 的本地时间）。
/// - §3.3.5 FORM #1：手机当前不在 UTC+8（交换生、海外分校）时改用**浮动本地时间**
///   （不带 TZID、不附 VTIMEZONE），日历按导入那台设备的时区显示，和 App 里的
///   提醒、小组件、周视图一致（v1.4.0 修复轮，review-G P3-11）。
/// - §3.6.6 / §3.8.6.3：DISPLAY 提醒必须有 ACTION、DESCRIPTION、TRIGGER；
///   `TRIGGER:-PT15M` = 开始前 15 分钟（默认相对开始时间）。
///
/// 日期只用 [ScheduleUtils.addDays] 逐日前进、读本地日期字段格式化（开发机时区有夏令时，
/// NOTES.md §2.1），不做任何跨天的毫秒运算。
class IcsExporter {
  IcsExporter._();

  /// 事件时间引用的时区。
  static const String tzid = 'Asia/Shanghai';

  /// [tzid] 的 UTC 偏移。设备当前偏移等于它时才写 TZID + VTIMEZONE。
  static const Duration shanghaiOffset = Duration(hours: 8);

  /// 设备当前的 UTC 偏移是不是 +08:00（决定写 TZID 还是浮动时间）。
  static bool usesShanghaiTime(Duration utcOffset) =>
      utcOffset == shanghaiOffset;

  /// 分享时的 MIME 类型。
  static const String mimeType = 'text/calendar';

  /// UID 的域名部分（App 包名）。
  static const String uidDomain = 'cn.shu.schedule';

  /// 一行最多多少字节（RFC 5545 §3.1，不含 CRLF）。
  static const int maxLineOctets = 75;

  /// 底部弹窗里可选的「提前多少分钟提醒」（另有「无」）。
  static const List<int> alarmChoices = <int>[10, 15, 30];

  /// 上课提醒的提前分钟数不在 [alarmChoices] 里时，默认选这个。
  static const int defaultAlarmMinutes = 15;

  /// 底部弹窗的默认提醒：上课提醒设置的提前分钟数在可选项里就用它，否则 15 分钟。
  static int defaultAlarmFor(int leadMinutes) =>
      alarmChoices.contains(leadMinutes) ? leadMinutes : defaultAlarmMinutes;

  /// 文件名：`jiankebiao-timetable-yyyyMMdd.ics`（ASCII，有些网盘 / 电脑端对中文名不友好）。
  static String fileNameFor(DateTime date) =>
      '${AppBrand.slug}-timetable-${_ymd(date)}.ics';

  /// 学期内（第 1 周周一到第 totalWeeks 周周日）每一节实际要上的课，按日期、节次排好。
  ///
  /// 逐日 [ScheduleUtils.effectiveDayOf] + [ScheduleUtils.coursesOnEffective]：
  /// 停课日自然为空，调休日按目标星期（和周次）出课；实际按的周不在
  /// `1..totalWeeks` 里时没有课（和小组件快照、提醒规划器同一条规则）。
  /// 作息表里取不到时间的课跳过。
  static List<IcsSession> sessionsOf(Timetable timetable) {
    final config = timetable.config;
    final totalDays = config.totalWeeks * 7;
    final out = <IcsSession>[];
    for (var i = 0; i < totalDays; i++) {
      final date = ScheduleUtils.addDays(config.startDate, i);
      final day = ScheduleUtils.effectiveDayOf(date, config);
      if (day.week < 1 || day.week > config.totalWeeks) continue;
      final courses = List<Course>.from(
        ScheduleUtils.coursesOnEffective(day, timetable),
      )..sort(_byPeriodThenId);
      for (final c in courses) {
        final span = ScheduleUtils.periodRange(
          config,
          c.startPeriod,
          c.endPeriod,
        );
        final start = _minutesOf(span.start);
        final end = _minutesOf(span.end);
        if (start == null || end == null) continue;
        out.add(
          IcsSession(
            date: day.date,
            day: day,
            course: c,
            startMinutes: start,
            endMinutes: end,
          ),
        );
      }
    }
    return out;
  }

  /// 生成整份 .ics 文本（CRLF 换行、已折行）。
  ///
  /// [alarmMinutes] 为 null 时不带提醒；否则每个事件附一个开始前 N 分钟的
  /// DISPLAY 提醒。[now] 只用来写 DTSTAMP（转成 UTC）。
  ///
  /// [utcOffset] 是设备当前的 UTC 偏移（调用方传 `DateTime.now().timeZoneOffset`）：
  /// +08:00 时写 `TZID=Asia/Shanghai` + VTIMEZONE，否则写浮动本地时间。
  /// 默认按 +08:00（纯函数、不读机器时区，测试注入别的值）。
  static String build({
    required Timetable timetable,
    int? alarmMinutes,
    required DateTime now,
    Duration utcOffset = shanghaiOffset,
  }) {
    final zoned = usesShanghaiTime(utcOffset);
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//${AppBrand.name}//$appVersion//CN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${escapeText(_calendarName(timetable))}',
      if (zoned) ...<String>[
        'X-WR-TIMEZONE:$tzid',
        'BEGIN:VTIMEZONE',
        'TZID:$tzid',
        'BEGIN:STANDARD',
        'DTSTART:19700101T000000',
        'TZOFFSETFROM:+0800',
        'TZOFFSETTO:+0800',
        'TZNAME:CST',
        'END:STANDARD',
        'END:VTIMEZONE',
      ],
    ];
    // 带时区：`DTSTART;TZID=Asia/Shanghai:`；浮动时间：`DTSTART:`（同样不带 Z）。
    final tzParam = zoned ? ';TZID=$tzid' : '';

    final stamp = _utcStamp(now);
    final alarm = (alarmMinutes != null && alarmMinutes >= 0)
        ? alarmMinutes
        : null;
    final seen = <String>{};
    for (final s in sessionsOf(timetable)) {
      final uid = uidFor(timetable, s.course, s.date);
      // 同一门课同一天同一节只能有一个事件（UID 在一份日历里必须唯一）。
      if (!seen.add(uid)) continue;
      final summary = _summaryOf(s.course);
      final location = (s.course.location ?? '').trim();
      lines
        ..add('BEGIN:VEVENT')
        ..add('UID:${escapeText(uid)}')
        ..add('DTSTAMP:$stamp')
        ..add('DTSTART$tzParam:${_local(s.date, s.startMinutes)}');
      // 结束不晚于开始（作息表填错）时不写 DTEND：按 §3.6.1，
      // 只有 DATE-TIME 型 DTSTART 的事件在开始那一刻结束。
      if (s.endMinutes > s.startMinutes) {
        lines.add('DTEND$tzParam:${_local(s.date, s.endMinutes)}');
      }
      lines.add('SUMMARY:${escapeText(summary)}');
      if (location.isNotEmpty) lines.add('LOCATION:${escapeText(location)}');
      lines
        ..add('DESCRIPTION:${escapeText(descriptionOf(s))}')
        ..add('CATEGORIES:课程');
      if (alarm != null) {
        lines
          ..add('BEGIN:VALARM')
          ..add('ACTION:DISPLAY')
          ..add(
            'DESCRIPTION:${escapeText(location.isEmpty ? summary : '$summary · $location')}',
          )
          ..add('TRIGGER:-PT${alarm}M')
          ..add('END:VALARM');
      }
      lines.add('END:VEVENT');
    }
    lines.add('END:VCALENDAR');

    final buffer = StringBuffer();
    for (final line in lines) {
      buffer
        ..write(foldLine(line))
        ..write('\r\n');
    }
    return buffer.toString();
  }

  /// 稳定 UID：`jkb-{课表 id}-{课程 id}-{yyyyMMdd}-{起始节}@cn.shu.schedule`。
  /// 同一张课表重新导出时同一节课的 UID 不变，日历 App 可以据此更新而不是重复添加。
  static String uidFor(Timetable timetable, Course course, DateTime date) =>
      'jkb-${timetable.id}-${course.id}-${_ymd(date)}-${course.startPeriod}'
      '@$uidDomain';

  /// 事件说明（未转义，多行用 `\n` 分隔）：教师 / 第 s-e 节 / 第 N 周 周X / 调休说明。
  static String descriptionOf(IcsSession s) {
    final teacher = (s.course.teacher ?? '').trim();
    final lines = <String>[
      if (teacher.isNotEmpty) '教师：$teacher',
      _periodText(s.course),
      '第 ${s.day.calendarWeek} 周 ${weekdayNamesCn[s.date.weekday]}',
    ];
    final adjusted = s.day.description;
    if (adjusted != null && !s.day.cancelled) {
      final note = (s.day.override?.note ?? '').trim();
      lines.add(note.isEmpty ? adjusted : '$adjusted（$note）');
    }
    return lines.join('\n');
  }

  /// RFC 5545 §3.3.11 TEXT 转义：`\` → `\\`，`;` → `\;`，`,` → `\,`，
  /// 换行（CRLF / CR / LF）→ `\n`；其余控制字符去掉（TEXT 只允许 HTAB 这一个）。
  static String escapeText(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final out = StringBuffer();
    for (final rune in normalized.runes) {
      switch (rune) {
        case 0x5C: // \
          out.write(r'\\');
        case 0x3B: // ;
          out.write(r'\;');
        case 0x2C: // ,
          out.write(r'\,');
        case 0x0A: // LF
          out.write(r'\n');
        default:
          // HTAB 保留；其余 C0 控制字符和 DEL 不允许出现在 TEXT 里。
          if (rune == 0x09 || (rune >= 0x20 && rune != 0x7F)) {
            out.writeCharCode(rune);
          }
      }
    }
    return out.toString();
  }

  /// RFC 5545 §3.1 折行：每段不超过 [maxLineOctets] 字节（续行开头的空格也算），
  /// 只在两个 Unicode 码点之间断开，不会切断 UTF-8 多字节序列。
  /// 返回值里的断点是 `\r\n `；整行的结尾 CRLF 由调用方加。
  static String foldLine(String line) {
    final out = StringBuffer();
    var octets = 0;
    for (final rune in line.runes) {
      final size = _utf8Length(rune);
      if (octets + size > maxLineOctets) {
        out.write('\r\n ');
        octets = 1;
      }
      out.writeCharCode(rune);
      octets += size;
    }
    return out.toString();
  }

  // ------------------------------------------------------------------ 内部

  static int _byPeriodThenId(Course a, Course b) {
    final s = a.startPeriod.compareTo(b.startPeriod);
    if (s != 0) return s;
    final e = a.endPeriod.compareTo(b.endPeriod);
    return e != 0 ? e : a.id.compareTo(b.id);
  }

  static String _calendarName(Timetable timetable) {
    final name = timetable.name.trim();
    return name.isEmpty ? AppBrand.name : name;
  }

  static String _summaryOf(Course course) {
    final name = course.name.trim();
    return name.isEmpty ? '课程' : name;
  }

  static String _periodText(Course c) => c.startPeriod == c.endPeriod
      ? '第 ${c.startPeriod} 节'
      : '第 ${c.startPeriod}-${c.endPeriod} 节';

  /// "HH:mm" → 当天分钟数；格式不对返回 null（作息表为空时 periodRange 给空串）。
  static int? _minutesOf(String hhmm) {
    final m = RegExp(r'^\s*(\d{1,2}):(\d{1,2})\s*$').firstMatch(hhmm);
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return h * 60 + mi;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  /// 本地日期字段 + 当天分钟数 → `yyyyMMddTHHmmss`（配合 `TZID=Asia/Shanghai`，或作为浮动时间）。
  static String _local(DateTime date, int minutes) =>
      '${_ymd(date)}T${_two(minutes ~/ 60)}${_two(minutes % 60)}00';

  /// DTSTAMP：UTC，`yyyyMMddTHHmmssZ`。
  static String _utcStamp(DateTime now) {
    final u = now.toUtc();
    return '${_ymd(u)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
  }

  static int _utf8Length(int rune) {
    if (rune < 0x80) return 1;
    if (rune < 0x800) return 2;
    if (rune < 0x10000) return 3;
    return 4;
  }
}
