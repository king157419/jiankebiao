import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_brand.dart';
import 'package:shu_schedule/features/settings/ics_exporter.dart';
import 'package:shu_schedule/models/course.dart';
import 'package:shu_schedule/models/period_time.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

/// v1.4.0 任务 D：IcsExporter（纯 Dart）。
///
/// 学期：第 1 周周一 2026-09-14，18 周（最后一天 2027-01-17 周日），内置 12 节作息。
/// 本机时区有夏令时（2026-11-01 美国山地时间回拨），所以专门看 11 月以后的钟点不漂。
void main() {
  final all = <int>[for (var w = 1; w <= 18; w++) w];

  Timetable fixture({
    String name = '2026 秋',
    Map<String, DateOverride>? overrides,
    List<Course>? courses,
    List<PeriodTime>? periods,
  }) => Timetable(
    id: 'tt1',
    name: name,
    config: ScheduleConfig(
      name: '2026-2027 秋',
      startDate: DateTime(2026, 9, 14),
      totalWeeks: 18,
      periods: periods,
      overrides:
          overrides ??
          <String, DateOverride>{
            // 第 3 周周四：停课（体育没了）。
            '2026-10-01': const DateOverride.cancelled(note: '国庆'),
            // 第 4 周周三：停课（英语没了）。
            '2026-10-07': const DateOverride.cancelled(),
            // 第 4 周周六：按周一上课（多一节高数）。
            '2026-10-10': const DateOverride.actAs(weekday: 1, note: '国庆调休'),
            // 第 15 周周六：按「第 19 周」周二上课——超出 18 周，什么都不该出。
            '2026-12-26': const DateOverride.actAs(week: 19, weekday: 2),
          },
    ),
    courses:
        courses ??
        <Course>[
          Course(
            id: 'math',
            name: '高等数学',
            teacher: '张老师',
            location: 'A101',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: all,
          ),
          Course(
            id: 'eng',
            name: '大学英语',
            location: 'B202',
            day: 3,
            startPeriod: 3,
            endPeriod: 4,
            weeks: all,
          ),
          Course(
            id: 'pe',
            name: '体育',
            day: 4,
            startPeriod: 5,
            endPeriod: 5,
            weeks: all,
          ),
          // 第 18 周周日：学期最后一天，必须导出。
          Course(
            id: 'sun',
            name: '周日讲座',
            day: 7,
            startPeriod: 9,
            endPeriod: 10,
            weeks: const <int>[18],
          ),
          // 周次超过总周数（导入数据里常见）：一节都不该出。
          Course(
            id: 'far',
            name: '超周课',
            day: 2,
            startPeriod: 1,
            endPeriod: 2,
            weeks: const <int>[19, 20],
          ),
        ],
  );

  final now = DateTime.utc(2026, 10, 7, 4, 5, 6);

  test('事件数 = 学期内有效课次（手算 54），sessionsOf 与之一致', () {
    final tt = fixture();
    final ics = IcsExporter.build(timetable: tt, now: now);
    final events = parseEvents(ics);
    // 高数 18 + 调休 1 = 19；英语 18 - 停课 1 = 17；体育 18 - 停课 1 = 17；周日讲座 1；超周课 0。
    expect(events.length, 54);
    expect(IcsExporter.sessionsOf(tt).length, 54);
    int countOf(String name) =>
        events.where((e) => e['SUMMARY'] == name).length;
    expect(countOf('高等数学'), 19);
    expect(countOf('大学英语'), 17);
    expect(countOf('体育'), 17);
    expect(countOf('周日讲座'), 1);
    expect(countOf('超周课'), 0);
  });

  test('停课日没有事件', () {
    final events = parseEvents(
      IcsExporter.build(timetable: fixture(), now: now),
    );
    final days = events.map((e) => e['DTSTART']!.substring(0, 8)).toSet();
    expect(days, isNot(contains('20261001')));
    expect(days, isNot(contains('20261007')));
    // 前后一周同一天照常有课。
    expect(days, containsAll(<String>['20260924', '20261008', '20260930']));
  });

  test('调休日按目标星期出课，说明里带调休与备注', () {
    final events = parseEvents(
      IcsExporter.build(timetable: fixture(), now: now),
    );
    final sat = events.where((e) => e['DTSTART']!.startsWith('20261010'));
    expect(sat.length, 1);
    final e = sat.single;
    expect(e['SUMMARY'], '高等数学');
    expect(e['UID'], 'jkb-tt1-math-20261010-1@cn.shu.schedule');
    expect(e['DTSTART'], '20261010T080000');
    expect(e['DTEND'], '20261010T094000');
    final desc = unescape(e['DESCRIPTION']!);
    expect(desc, contains('教师：张老师'));
    expect(desc, contains('第 1-2 节'));
    expect(desc, contains('第 4 周 周六'));
    expect(desc, contains('调休，按周一上课（国庆调休）'));
    // 普通日子没有调休行。
    final mon = events.firstWhere((x) => x['DTSTART']!.startsWith('20260914'));
    expect(unescape(mon['DESCRIPTION']!), '教师：张老师\n第 1-2 节\n第 1 周 周一');
  });

  test('实际按的周 > 总周数：没有事件（调休到第 19 周也不行）', () {
    final events = parseEvents(
      IcsExporter.build(timetable: fixture(), now: now),
    );
    expect(events.where((e) => e['DTSTART']!.startsWith('20261226')), isEmpty);
    expect(events.where((e) => e['UID']!.contains('-far-')), isEmpty);
  });

  test('范围：第 1 周周一到第 18 周周日；夏令时切换后钟点不漂', () {
    final events = parseEvents(
      IcsExporter.build(timetable: fixture(), now: now),
    );
    final starts = events.map((e) => e['DTSTART']!).toList();
    expect(starts.first, '20260914T080000');
    expect(starts.last, '20270117T180000');
    // 美国山地时间 2026-11-01 回拨之后：仍然是 08:00 / 第 18 周周一。
    expect(starts, contains('20261102T080000'));
    expect(starts, contains('20270111T080000'));
    // 按日期升序。
    final sorted = List<String>.from(starts)..sort();
    expect(starts, sorted);
  });

  test('PRODID 跟着 appVersion 走（P3-11）', () {
    final lines = unfold(IcsExporter.build(timetable: fixture(), now: now));
    expect(lines[2], 'PRODID:-//${AppBrand.name}//$appVersion//CN');
    expect(appVersion, '1.5.0');
  });

  test('设备不在 UTC+8 → 浮动本地时间：没有 TZID、没有 VTIMEZONE（P3-11）', () {
    final zoned = IcsExporter.build(
      timetable: fixture(),
      now: now,
      utcOffset: const Duration(hours: 8),
    );
    final floating = IcsExporter.build(
      timetable: fixture(),
      now: now,
      utcOffset: const Duration(hours: -6), // 例如美国山地夏令时
    );
    expect(zoned, contains('BEGIN:VTIMEZONE'));
    expect(zoned, contains('DTSTART;TZID=Asia/Shanghai:20260914T080000'));
    for (final bad in <String>['TZID', 'VTIMEZONE', 'X-WR-TIMEZONE']) {
      expect(floating, isNot(contains(bad)), reason: bad);
    }
    final lines = unfold(floating);
    expect(lines, contains('DTSTART:20260914T080000'));
    expect(lines, contains('DTEND:20260914T094000'));
    expect(
      lines
          .where((l) => l.startsWith('DTSTART'))
          .every((l) => !l.endsWith('Z')),
      isTrue,
      reason: '浮动时间不带 Z',
    );
    // 事件数和带时区时一样，只是时间写法不同。
    expect(
      'BEGIN:VEVENT'.allMatches(floating).length,
      'BEGIN:VEVENT'.allMatches(zoned).length,
    );
    expect(IcsExporter.usesShanghaiTime(const Duration(hours: 8)), isTrue);
    expect(
      IcsExporter.usesShanghaiTime(const Duration(hours: 8, minutes: 30)),
      isFalse,
    );
    expect(IcsExporter.usesShanghaiTime(Duration.zero), isFalse);
  });

  test('头部、VTIMEZONE、属性格式', () {
    final ics = IcsExporter.build(
      timetable: fixture(name: 'A,B;C'),
      now: now,
    );
    final lines = unfold(ics);
    expect(lines.take(16).toList(), <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//简课表//$appVersion//CN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      r'X-WR-CALNAME:A\,B\;C',
      'X-WR-TIMEZONE:Asia/Shanghai',
      'BEGIN:VTIMEZONE',
      'TZID:Asia/Shanghai',
      'BEGIN:STANDARD',
      'DTSTART:19700101T000000',
      'TZOFFSETFROM:+0800',
      'TZOFFSETTO:+0800',
      'TZNAME:CST',
      'END:STANDARD',
      'END:VTIMEZONE',
    ]);
    expect(lines.last, 'END:VCALENDAR');
    expect(
      lines.where((l) => l.startsWith('DTSTART')).skip(1),
      everyElement(startsWith('DTSTART;TZID=Asia/Shanghai:')),
    );
    expect(
      lines.where((l) => l.startsWith('DTEND')),
      everyElement(startsWith('DTEND;TZID=Asia/Shanghai:')),
    );
    expect(lines.where((l) => l.startsWith('CATEGORIES')).toSet(), <String>{
      'CATEGORIES:课程',
    });
    // 每个事件 UID、DTSTAMP 恰好各一个。
    final events = parseEventBlocks(ics);
    for (final block in events) {
      expect(block.where((l) => l.startsWith('UID:')).length, 1);
      expect(block.where((l) => l.startsWith('DTSTAMP:')).length, 1);
      expect(block.where((l) => l.startsWith('DURATION')), isEmpty);
    }
    // 没有地点的课不写 LOCATION。
    final pe = parseEvents(ics).firstWhere((e) => e['SUMMARY'] == '体育');
    expect(pe.containsKey('LOCATION'), isFalse);
  });

  test('DTSTAMP 是 UTC（Z 结尾），本地时间的 now 也会先转 UTC', () {
    final ics = IcsExporter.build(timetable: fixture(), now: now);
    final stamps = unfold(ics).where((l) => l.startsWith('DTSTAMP:')).toSet();
    expect(stamps, <String>{'DTSTAMP:20261007T040506Z'});

    final local = DateTime(2026, 10, 7, 12, 30, 15);
    final u = local.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final expected =
        'DTSTAMP:${u.year}${two(u.month)}${two(u.day)}'
        'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
    final stamps2 = unfold(IcsExporter.build(timetable: fixture(), now: local))
        .where((l) => l.startsWith('DTSTAMP:'))
        .toSet();
    expect(stamps2, <String>{expected});
    expect(expected, endsWith('Z'));
  });

  test('UID 稳定：两次导出（不同时刻）UID 完全一样且互不重复', () {
    final a = parseEvents(IcsExporter.build(timetable: fixture(), now: now));
    final b = parseEvents(
      IcsExporter.build(
        timetable: fixture(),
        alarmMinutes: 10,
        now: DateTime.utc(2027, 1, 1, 9),
      ),
    );
    final uidsA = a.map((e) => e['UID']!).toList();
    final uidsB = b.map((e) => e['UID']!).toList();
    expect(uidsA, uidsB);
    expect(uidsA.toSet().length, uidsA.length);
    expect(uidsA.first, 'jkb-tt1-math-20260914-1@cn.shu.schedule');
    expect(a.first['DTSTAMP'], isNot(b.first['DTSTAMP']));
  });

  test('CRLF：每行都以 CRLF 结尾，没有单独的 CR / LF', () {
    final ics = IcsExporter.build(
      timetable: fixture(),
      alarmMinutes: 15,
      now: now,
    );
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    final bare = ics.replaceAll('\r\n', '');
    expect(bare.contains('\r'), isFalse);
    expect(bare.contains('\n'), isFalse);
  });

  test('长中文 SUMMARY / DESCRIPTION：每行 ≤ 75 字节、不切断 UTF-8，展开后原样还原', () {
    final longName = '数据结构与算法分析（荣誉课程，含上机实验；第二学期续）' * 4;
    final longTeacher = '欧阳某某;司马某某\\诸葛某某,' * 6;
    final longLocation = 'A楼🏫一〇一教室🎓' * 8; // 混入 4 字节字符
    final tt = fixture(
      overrides: <String, DateOverride>{},
      courses: <Course>[
        Course(
          id: 'long',
          name: longName,
          teacher: longTeacher,
          location: longLocation,
          day: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: const <int>[1],
        ),
      ],
    );
    final ics = IcsExporter.build(timetable: tt, alarmMinutes: 30, now: now);
    final bytes = utf8.encode(ics);

    // 按 CRLF 切字节：每一段 ≤ 75 字节，并且单独拿出来也是合法 UTF-8。
    final segments = splitCrlf(bytes);
    var folded = 0;
    for (final seg in segments) {
      expect(seg.length, lessThanOrEqualTo(75));
      expect(() => utf8.decode(seg), returnsNormally);
      if (seg.isNotEmpty && seg.first == 0x20) folded++;
    }
    expect(folded, greaterThan(10));

    // 按 RFC 5545 §3.1 展开后，还原出原来的文字。
    final e = parseEvents(ics).single;
    expect(unescape(e['SUMMARY']!), longName);
    expect(unescape(e['LOCATION']!), longLocation);
    expect(unescape(e['DESCRIPTION']!), contains('教师：$longTeacher'));
    expect(e['DESCRIPTION'], contains(r'\;'));
    expect(e['DESCRIPTION'], contains(r'\\'));
  });

  test('foldLine：ASCII 按 75 / 74+1 字节塞满；中文按整字断开', () {
    final ascii = IcsExporter.foldLine('X' * 200).split('\r\n');
    expect(ascii.map((l) => l.length).toList(), <int>[75, 75, 52]);
    expect(ascii.skip(1), everyElement(startsWith(' ')));

    final cjk = IcsExporter.foldLine('中' * 50).split('\r\n');
    expect(cjk.map((l) => utf8.encode(l).length).toList(), <int>[75, 73, 4]);
    expect(cjk.join().replaceAll(' ', ''), '中' * 50);

    final emoji = IcsExporter.foldLine('😀' * 30).split('\r\n');
    for (final l in emoji) {
      expect(utf8.encode(l).length, lessThanOrEqualTo(75));
    }
    expect(emoji.first.runes.length, 18); // 18 × 4 = 72，再加一个就 76

    expect(IcsExporter.foldLine('SHORT:ok'), 'SHORT:ok');
  });

  test('TEXT 转义：\\ ; , 换行；冒号不转义；控制字符去掉', () {
    expect(
      IcsExporter.escapeText('a\\b;c,d\ne\r\nf\rg:h\u0001i\tj'),
      r'a\\b\;c\,d\ne\nf\ng:hi'
      '\tj',
    );
    final tt = fixture(
      overrides: <String, DateOverride>{},
      courses: <Course>[
        Course(
          id: 'x',
          name: r'C;D,E\F',
          location: '一楼\n二楼',
          day: 1,
          startPeriod: 1,
          endPeriod: 1,
          weeks: const <int>[1],
        ),
      ],
    );
    final lines = unfold(IcsExporter.build(timetable: tt, now: now));
    expect(lines, contains(r'SUMMARY:C\;D\,E\\F'));
    expect(lines, contains(r'LOCATION:一楼\n二楼'));
  });

  test('VALARM：只在要求时出现，TRIGGER 对、带 ACTION / DESCRIPTION', () {
    final none = IcsExporter.build(timetable: fixture(), now: now);
    expect(none.contains('BEGIN:VALARM'), isFalse);
    expect(none.contains('TRIGGER'), isFalse);

    final ics = IcsExporter.build(
      timetable: fixture(),
      alarmMinutes: 30,
      now: now,
    );
    final blocks = parseEventBlocks(ics);
    expect(blocks.length, 54);
    for (final block in blocks) {
      final start = block.indexOf('BEGIN:VALARM');
      final end = block.indexOf('END:VALARM');
      expect(start, greaterThan(0));
      final alarm = block.sublist(start + 1, end);
      expect(alarm, contains('ACTION:DISPLAY'));
      expect(alarm, contains('TRIGGER:-PT30M'));
      expect(alarm.where((l) => l.startsWith('DESCRIPTION:')).length, 1);
    }
    final math = blocks.firstWhere((b) => b.contains('SUMMARY:高等数学'));
    expect(math, contains('DESCRIPTION:高等数学 · A101'));
  });

  test('默认提醒：10 / 15 / 30 沿用上课提醒，其余 15', () {
    expect(IcsExporter.defaultAlarmFor(10), 10);
    expect(IcsExporter.defaultAlarmFor(15), 15);
    expect(IcsExporter.defaultAlarmFor(30), 30);
    expect(IcsExporter.defaultAlarmFor(5), 15);
    expect(IcsExporter.defaultAlarmFor(20), 15);
  });

  test('文件名：ASCII jiankebiao-timetable-yyyyMMdd.ics', () {
    expect(
      IcsExporter.fileNameFor(DateTime(2026, 10, 7, 23, 59)),
      'jiankebiao-timetable-20261007.ics',
    );
    expect(
      IcsExporter.fileNameFor(DateTime(2027, 1, 2)),
      'jiankebiao-timetable-20270102.ics',
    );
  });

  test('脏数据：作息表为空 → 没有事件但仍是完整日历；结束不晚于开始 → 不写 DTEND', () {
    final empty = fixture(periods: const <PeriodTime>[]);
    final ics = IcsExporter.build(timetable: empty, now: now);
    expect(parseEvents(ics), isEmpty);
    expect(IcsExporter.sessionsOf(empty), isEmpty);
    expect(unfold(ics).last, 'END:VCALENDAR');

    final bad = fixture(
      overrides: <String, DateOverride>{},
      periods: const <PeriodTime>[
        PeriodTime(index: 1, start: '09:00', end: '08:00'),
      ],
      courses: <Course>[
        Course(
          id: 'b',
          name: '倒挂',
          day: 1,
          startPeriod: 1,
          endPeriod: 1,
          weeks: const <int>[1],
        ),
      ],
    );
    final e = parseEvents(IcsExporter.build(timetable: bad, now: now)).single;
    expect(e['DTSTART'], '20260914T090000');
    expect(e.containsKey('DTEND'), isFalse);
  });

  // v1.5.0：隐私说明换成白话短文，不再逐项列出分享出口（导出到日历不联网，
  // 文件由用户自己通过系统分享面板发出去），这里只保留 README 的检查。
  test('文档：根 README 不再说「App 里没有 ICS 导出」', () {
    final readme = File('../README.md');
    if (readme.existsSync()) {
      final text = readme.readAsStringSync();
      expect(text.contains('App 里没有 ICS 导出'), isFalse);
      expect(text.contains('没有 ICS 导出'), isFalse);
    }
  });
}

// ---------------------------------------------------------------- 解析工具

/// RFC 5545 §3.1 展开：去掉「CRLF + 一个空格 / HTAB」，再按 CRLF 切行。
List<String> unfold(String ics) {
  final text = ics.replaceAll('\r\n ', '').replaceAll('\r\n\t', '');
  final lines = text.split('\r\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// 每个 VEVENT 的展开后各行（不含 BEGIN / END:VEVENT）。
List<List<String>> parseEventBlocks(String ics) {
  final out = <List<String>>[];
  List<String>? cur;
  for (final line in unfold(ics)) {
    if (line == 'BEGIN:VEVENT') {
      cur = <String>[];
    } else if (line == 'END:VEVENT') {
      out.add(cur!);
      cur = null;
    } else {
      cur?.add(line);
    }
  }
  return out;
}

/// 每个 VEVENT 的属性名 → 值（不含 VALARM 里的属性；参数丢掉）。
List<Map<String, String>> parseEvents(String ics) {
  final out = <Map<String, String>>[];
  for (final block in parseEventBlocks(ics)) {
    final map = <String, String>{};
    var inAlarm = false;
    for (final line in block) {
      if (line == 'BEGIN:VALARM') inAlarm = true;
      if (line == 'END:VALARM') {
        inAlarm = false;
        continue;
      }
      if (inAlarm) continue;
      final colon = line.indexOf(':');
      final head = line.substring(0, colon);
      final name = head.split(';').first;
      map[name] = line.substring(colon + 1);
    }
    out.add(map);
  }
  return out;
}

/// TEXT 反转义（\n \N \\ \; \,）。
String unescape(String v) {
  final out = StringBuffer();
  for (var i = 0; i < v.length; i++) {
    final c = v[i];
    if (c == r'\' && i + 1 < v.length) {
      final n = v[++i];
      out.write(n == 'n' || n == 'N' ? '\n' : n);
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

/// 按 CRLF 把字节切成段（最后的空段丢掉）。
List<List<int>> splitCrlf(List<int> bytes) {
  final out = <List<int>>[];
  var start = 0;
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0x0D && bytes[i + 1] == 0x0A) {
      out.add(bytes.sublist(start, i));
      start = i + 2;
      i++;
    }
  }
  if (start < bytes.length) out.add(bytes.sublist(start));
  return out;
}
