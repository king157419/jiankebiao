import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/holiday_presets.dart';
import 'package:shu_schedule/core/presets.dart';
import 'package:shu_schedule/core/schedule_utils.dart';
import 'package:shu_schedule/features/settings/calendar_suggestion_sheet.dart';
import 'package:shu_schedule/models/schedule_config.dart';
import 'package:shu_schedule/models/timetable.dart';

import 'helpers/harness.dart';

/// v1.5.0（PLAN-1.5 D9）：校历建议的纯函数 + AppState 的「一键套用」/「先不用」。
///
/// 内置假日表：上海大学 2026-09-14 开学、18 周；本学期 13 条——9/20 调休（上 10/6 周二）、
/// 9/25–27 中秋、10/1–10/7 国庆、10/10 调休（上 10/7 周三）、2027-01-01 元旦。
/// 今天固定 2026-10-08（第 4 周周四）。
void main() {
  final bundled = HolidayPresets.fromJson(
    jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map,
  );
  final today = DateTime(2026, 10, 8);

  Timetable tt({
    DateTime? start,
    String? schoolId = 'shu',
    Map<String, DateOverride>? overrides,
    int totalWeeks = 18,
  }) => Timetable(
    id: 'tt',
    name: '我的课表',
    schoolId: schoolId,
    config: ScheduleConfig(
      name: '2026-2027 秋',
      startDate: start ?? DateTime(2026, 9, 14),
      totalWeeks: totalWeeks,
      overrides: overrides,
    ),
  );

  List<String> dates(CalendarSuggestion s) =>
      s.pending.map((p) => ScheduleUtils.dateKey(p.date)).toList();

  group('buildCalendarSuggestion', () {
    test('开学日期错设成本周（10/5）→ termFix 9/14、现在第 4 周；放假 / 调休按修正后的日期算出 13 条', () {
      final s = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 10, 5)),
        presets: bundled,
        today: today,
      )!;
      expect(s.timetableId, 'tt');
      expect(s.schoolName, '上海大学');
      expect(s.termFix?.startDate, DateTime(2026, 9, 14));
      expect(s.currentStartDate, DateTime(2026, 10, 5));
      expect(s.currentWeek, 4);
      expect(dates(s), <String>[
        '2026-09-20',
        '2026-09-25',
        '2026-09-26',
        '2026-09-27',
        '2026-10-01',
        '2026-10-02',
        '2026-10-03',
        '2026-10-04',
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
        '2026-10-10',
        '2027-01-01',
      ]);
      final o = s.overrides;
      expect(o, hasLength(13));
      // 调休的「第几周」按 9/14 开学算，不是按错的 10/5。
      expect(o[DateTime(2026, 9, 20)]!.actAsWeek, 4);
      expect(o[DateTime(2026, 9, 20)]!.actAsWeekday, 2);
      expect(o[DateTime(2026, 10, 10)]!.actAsWeek, 4);
      expect(o[DateTime(2026, 10, 10)]!.actAsWeekday, 3);
      expect(o[DateTime(2026, 10, 1)]!.cancelled, isTrue);
      expect(s.pending.every((p) => p.fromSchool && !p.conflicts), isTrue);
      expect(s.termKey, startsWith('shu|2026-09-14|'));
      expect(s.dismissKey, s.termKey);
    });

    test('开学日期正确、一条都没套用 → 没有 termFix，13 条', () {
      final s = buildCalendarSuggestion(
        tt: tt(),
        presets: bundled,
        today: today,
      )!;
      expect(s.termFix, isNull);
      expect(s.pending, hasLength(13));
      expect(s.currentWeek, 4);
      expect(s.termKey, startsWith('shu|2026-09-14|'));
    });

    test('全部已套用 → null；套用了一部分 → 只剩没套用的', () {
      final all = buildCalendarSuggestion(
        tt: tt(),
        presets: bundled,
        today: today,
      )!.overrides;
      Map<String, DateOverride> keyed(Map<DateTime, DateOverride> m) =>
          <String, DateOverride>{
            for (final e in m.entries) ScheduleUtils.dateKey(e.key): e.value,
          };
      expect(
        buildCalendarSuggestion(
          tt: tt(overrides: keyed(all)),
          presets: bundled,
          today: today,
        ),
        isNull,
      );

      final mid = Map<DateTime, DateOverride>.from(all)
        ..removeWhere((d, _) => d.month != 10);
      final s = buildCalendarSuggestion(
        tt: tt(overrides: keyed(mid)),
        presets: bundled,
        today: today,
      )!;
      expect(dates(s), <String>[
        '2026-09-20',
        '2026-09-25',
        '2026-09-26',
        '2026-09-27',
        '2027-01-01',
      ]);
    });

    test('目标日期上有不同的手动设置 → 仍然建议，并标出会覆盖', () {
      final s = buildCalendarSuggestion(
        tt: tt(
          overrides: <String, DateOverride>{
            '2026-09-25': const DateOverride.actAs(weekday: 1, note: '手动'),
          },
        ),
        presets: bundled,
        today: today,
      )!;
      final mid = s.pending.firstWhere((p) => p.date == DateTime(2026, 9, 25));
      expect(mid.conflicts, isTrue);
      expect(mid.override!.cancelled, isTrue);
    });

    test('课表没有 schoolId / 学校没有校历 → null', () {
      expect(
        buildCalendarSuggestion(
          tt: tt(schoolId: null, start: DateTime(2026, 10, 5)),
          presets: bundled,
          today: today,
        ),
        isNull,
      );
      expect(
        buildCalendarSuggestion(
          tt: tt(schoolId: 'nope', start: DateTime(2026, 10, 5)),
          presets: bundled,
          today: today,
        ),
        isNull,
        reason: '国家安排的条目不进校历建议',
      );
    });

    test('allowTermFix = false（刚导入完）→ 不改开学日期，放假 / 调休按原日期算', () {
      final s = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 10, 5)),
        presets: bundled,
        today: today,
        allowTermFix: false,
      )!;
      expect(s.termFix, isNull);
      expect(s.currentWeek, 1);
      expect(dates(s), <String>[
        '2026-10-05',
        '2026-10-06',
        '2026-10-07',
        '2026-10-10',
        '2027-01-01',
      ]);
      expect(s.overrides[DateTime(2026, 10, 10)]!.actAsWeek, 1);
    });

    test('提前导入的下学期 / 还在用的上学期课表：开学日期不动', () {
      // 学校清单里的春季学期开学日（已知学期）。
      final spring = <TermPreset>[
        TermPreset(
          id: 's',
          name: '2026-2027 春',
          startDate: DateTime(2027, 2, 22),
          totalWeeks: 18,
        ),
      ];
      expect(
        buildCalendarSuggestion(
          tt: tt(start: DateTime(2027, 2, 22)),
          presets: bundled,
          today: today,
          schoolPresets: spring,
        ),
        isNull,
      );
      // 没拿到学校清单也一样：课表的学期和「今天」所在学期不重叠。
      expect(
        buildCalendarSuggestion(
          tt: tt(start: DateTime(2027, 2, 22)),
          presets: bundled,
          today: today,
        ),
        isNull,
      );
      // 上学期（2026 春）的课表。
      expect(
        buildCalendarSuggestion(
          tt: tt(start: DateTime(2026, 3, 2)),
          presets: bundled,
          today: today,
        ),
        isNull,
      );
    });

    test('寒假里（今天不在任何学期）→ 不改开学日期，只给本学期没套用的', () {
      final s = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 9, 21)),
        presets: bundled,
        today: DateTime(2027, 2, 1),
      )!;
      expect(s.termFix, isNull);
      expect(s.pending.first.date, DateTime(2026, 9, 25));
    });

    test('学校名：假日表里没有这所学校时用传进来的', () {
      final s = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 10, 5)),
        presets: HolidayPresets.empty,
        today: today,
        schoolPresets: <TermPreset>[
          TermPreset(
            id: 'a',
            name: '秋',
            startDate: DateTime(2026, 9, 14),
            totalWeeks: 18,
          ),
        ],
        schoolName: '某某大学',
      )!;
      expect(s.schoolName, '某某大学');
      expect(s.termFix?.startDate, DateTime(2026, 9, 14));
      expect(s.pending, isEmpty);
      expect(
        s.termKey,
        startsWith('shu|2026-09-14|'),
        reason: '没有假日表条目也能生成学期指纹',
      );
    });

    test('termStartConfirmed：已确认当前开学日期时不再给 termFix，只给放假 / 调休', () {
      final s = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 9, 21)),
        presets: bundled,
        today: today,
        termStartConfirmed: const <String, String>{'tt': '2026-09-21'},
      )!;
      expect(s.termFix, isNull);
      expect(s.pending, hasLength(12), reason: '9/20 在 9/21 开学前，剩 12 条');
      // 换了别的开学日期但没确认新的日期 → 照常给 termFix。
      final unconfirmed = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 10, 5)),
        presets: bundled,
        today: today,
        termStartConfirmed: const <String, String>{'tt': '2026-09-21'},
      )!;
      expect(unconfirmed.termFix?.startDate, DateTime(2026, 9, 14));
    });
  });

  group('学期内容指纹 termKey（「先不用」与「一键套用」共用）', () {
    test('顶层 updatedAt 或课表开学日期变化不影响 termKey；本校本学期条目变了才算新建议', () {
      final s = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 10, 5)),
        presets: bundled,
        today: today,
      )!;
      expect(s.isDismissedIn(const <String, String>{}), isFalse);
      expect(s.isDismissedIn(<String, String>{'tt': s.termKey}), isTrue);
      expect(s.isDismissedIn(<String, String>{'other': s.termKey}), isFalse);

      // 顶层 updatedAt 变了、国家表或别的学校变了，但本校本学期条目没变 → termKey 相同，仍视为已处理。
      final raw =
          jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map;
      raw['updatedAt'] = '2026-11-02';
      (raw['schools'] as Map)['other_uni'] = <String, dynamic>{
        'name': '别的大学',
        'terms': <dynamic>[],
      };
      final newerSameSchool = HolidayPresets.fromJson(raw);
      final s2 = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 10, 5)),
        presets: newerSameSchool,
        today: today,
      )!;
      expect(s2.termKey, s.termKey);
      expect(s2.isDismissedIn(<String, String>{'tt': s.termKey}), isTrue);

      // 课表自己的开学日期从 10/5 改成 9/28 → 仍属于同一校历学期，termKey 相同。
      final s3 = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 9, 28)),
        presets: bundled,
        today: today,
      )!;
      expect(s3.termKey, s.termKey);

      // 本校本学期新增了一条停课（例如 2026-11-15 校庆停课）→ termKey 变化，重新提示。
      final changedRaw =
          jsonDecode(File('assets/holidays.json').readAsStringSync()) as Map;
      final shuTerms =
          ((changedRaw['schools'] as Map)['shu'] as Map)['terms'] as List;
      ((shuTerms.first as Map)['entries'] as List).add(<String, dynamic>{
        'date': '2026-11-15',
        'cancelled': true,
        'note': '校庆停课',
      });
      final changedSchool = HolidayPresets.fromJson(changedRaw);
      final s4 = buildCalendarSuggestion(
        tt: tt(start: DateTime(2026, 10, 5)),
        presets: changedSchool,
        today: today,
      )!;
      expect(s4.termKey, isNot(s.termKey));
      expect(s4.isDismissedIn(<String, String>{'tt': s.termKey}), isFalse);
    });
  });

  group('AppState', () {
    final storage = TempStorage();
    setUp(() => storage.setUp('calendar_suggestion_state'));
    tearDown(storage.tearDown);

    test(
      'applyCalendarSuggestion：改开学日期 + 写 13 条，只通知 / 保存一次，返回旧配置可撤销',
      () async {
        final state = AppState();
        await state.load();
        await state.addTimetable(
          tt(
            start: DateTime(2026, 10, 5),
            overrides: <String, DateOverride>{
              '2026-12-25': const DateOverride.cancelled(note: '手动'),
            },
          ),
        );
        final s = buildCalendarSuggestion(
          tt: state.currentTimetable!,
          presets: bundled,
          today: today,
        )!;
        var notified = 0;
        state.addListener(() => notified++);
        final previous = await state.applyCalendarSuggestion(
          'tt',
          startDate: s.termFix!.startDate,
          overrides: s.overrides,
        );
        expect(notified, 1);
        final config = state.currentConfig;
        expect(config.startDate, DateTime(2026, 9, 14));
        expect(config.overrides, hasLength(14), reason: '13 条 + 原来手动的 1 条');
        expect(config.overrideOn(DateTime(2026, 12, 25))!.note, '手动');
        expect(
          buildCalendarSuggestion(
            tt: state.currentTimetable!,
            presets: bundled,
            today: today,
          ),
          isNull,
          reason: '套用完就没有建议了',
        );

        // 写盘了：重新读一遍还在。
        final reloaded = AppState();
        await reloaded.load();
        expect(reloaded.currentConfig.startDate, DateTime(2026, 9, 14));
        expect(reloaded.currentConfig.overrides, hasLength(14));

        // 撤销 = 整个配置换回去。
        expect(previous!.startDate, DateTime(2026, 10, 5));
        await state.updateConfig(previous, timetableId: 'tt');
        expect(state.currentConfig.startDate, DateTime(2026, 10, 5));
        expect(state.currentConfig.overrides.keys, <String>['2026-12-25']);

        expect(
          await state.applyCalendarSuggestion(
            'missing',
            overrides: s.overrides,
          ),
          isNull,
        );
      },
    );

    test('dismissCalendarSuggestion：记下标记并写盘', () async {
      final state = AppState();
      await state.load();
      await state.addTimetable(tt());
      await state.dismissCalendarSuggestion('tt', '2026-10-06|2026-09-14');
      expect(state.settings.calendarSuggestionDismissed, <String, String>{
        'tt': '2026-10-06|2026-09-14',
      });
      final reloaded = AppState();
      await reloaded.load();
      expect(reloaded.settings.calendarSuggestionDismissed, <String, String>{
        'tt': '2026-10-06|2026-09-14',
      });
    });

    test('requestCalendarPrompt：同一张课表连着请求两次也会通知', () {
      final state = AppState();
      final seen = <String?>[];
      state.pendingCalendarPromptFor.addListener(
        () => seen.add(state.pendingCalendarPromptFor.value),
      );
      state.requestCalendarPrompt('tt');
      state.pendingCalendarPromptFor.value = null; // 首页处理完清掉
      state.requestCalendarPrompt('tt');
      state.requestCalendarPrompt('tt');
      expect(seen.where((v) => v == 'tt'), hasLength(3));
      state.dispose();
    });
  });
}
