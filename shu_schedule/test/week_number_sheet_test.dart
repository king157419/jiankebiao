import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/features/settings/week_number_sheet.dart';

/// v1.5.0（PLAN-1.5 D8）：「现在是第几周？」面板。今天固定 2026-10-08（周四）。
void main() {
  final today = DateTime(2026, 10, 8);

  final sheet = find.byKey(const ValueKey<String>('week-number-sheet'));
  final confirm = find.byKey(const ValueKey<String>('week-number-confirm'));
  final preview = find.byKey(const ValueKey<String>('week-number-preview'));
  final pickDate = find.byKey(const ValueKey<String>('week-number-pick-date'));
  Finder chip(int w) => find.byKey(ValueKey<String>('week-number-$w'));

  group('firstMondayForWeek', () {
    test('现在第 4 周 → 今天所在周的周一往前 21 天', () {
      expect(firstMondayForWeek(today, 4), DateTime(2026, 9, 14));
      expect(firstMondayForWeek(today, 1), DateTime(2026, 10, 5));
      expect(
        firstMondayForWeek(DateTime(2026, 10, 11), 4),
        DateTime(2026, 9, 14),
      );
    });

    test('跨夏令时切换（开发机所在时区 11/1）仍是 0 点的周一', () {
      final d = firstMondayForWeek(DateTime(2026, 11, 3), 10);
      expect(d, DateTime(2026, 8, 31));
      expect(d.hour, 0);
      expect(d.weekday, DateTime.monday);
    });
  });

  /// 点按钮弹面板，面板关掉后把结果记进 [results]。
  Future<List<DateTime?>> pumpOpener(
    WidgetTester tester, {
    int totalWeeks = 18,
    int? initialWeek,
    DateTime? upcomingStart,
    String? title,
  }) async {
    final results = <DateTime?>[];
    await tester.pumpWidget(const SizedBox.shrink()); // 上一个面板一起扔掉
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => results.add(
                  await showWeekNumberSheet(
                    context,
                    today: today,
                    totalWeeks: totalWeeks,
                    initialWeek: initialWeek,
                    upcomingStart: upcomingStart,
                    title: title,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(sheet, findsOneWidget);
    return results;
  }

  bool selected(WidgetTester tester, int w) =>
      tester.widget<ChoiceChip>(chip(w)).selected;

  testWidgets('选第 4 周 → 返回 2026-09-14（今天所在周周一减 21 天）', (tester) async {
    final results = await pumpOpener(tester);
    expect(find.text('现在是第几周？'), findsOneWidget);
    expect(chip(1), findsOneWidget);
    expect(chip(18), findsOneWidget);
    expect(chip(19), findsNothing);
    expect(tester.widget<Text>(preview).data, '选一个周次');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.tap(chip(4));
    await tester.pumpAndSettle();
    expect(selected(tester, 4), isTrue);
    expect(tester.widget<Text>(preview).data, '将把 9月14日（周一）设为第一周');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(results, <DateTime?>[DateTime(2026, 9, 14)]);
  });

  testWidgets('initialWeek 预选 + 自定义标题：直接「确定」就过', (tester) async {
    final results = await pumpOpener(
      tester,
      initialWeek: 4,
      title: '按某某大学校历，现在是第 4 周，对吗？',
    );
    expect(find.text('按某某大学校历，现在是第 4 周，对吗？'), findsOneWidget);
    expect(find.text('现在是第几周？'), findsNothing);
    expect(selected(tester, 4), isTrue);
    expect(find.text('将把 9月14日（周一）设为第一周'), findsOneWidget);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(results, <DateTime?>[DateTime(2026, 9, 14)]);
  });

  testWidgets('initialWeek 不在 1..总周数里 → 不预选', (tester) async {
    for (final bad in <int>[0, -2, 19]) {
      await pumpOpener(tester, initialWeek: bad);
      for (var w = 1; w <= 18; w++) {
        expect(selected(tester, w), isFalse, reason: 'initialWeek=$bad 第 $w 周');
      }
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    }
  });

  testWidgets('关掉面板 → null', (tester) async {
    final results = await pumpOpener(tester, initialWeek: 4);
    await tester.tapAt(const Offset(450, 20));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(results, <DateTime?>[null]);
  });

  testWidgets('「我知道开学日期」→ 日期选择器，返回所选日期所在周的周一', (tester) async {
    final results = await pumpOpener(tester, initialWeek: 4);
    await tester.tap(pickDate);
    await tester.pumpAndSettle();
    expect(find.text('选择开学日期（第 1 周的任意一天）'), findsOneWidget);
    // 预选了第 4 周，日期选择器从 9月14日 开始；改选 9月23日（周三）。
    await tester.tap(find.text('23'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(results, <DateTime?>[DateTime(2026, 9, 21)]);
  });

  testWidgets('upcomingStart：顶部多出「还没开学（…开学）」并默认选中，点确定直接返回该周一；也可改选第 1 周', (
    tester,
  ) async {
    final upcomingChip = find.byKey(
      const ValueKey<String>('week-number-upcoming'),
    );
    final results = await pumpOpener(
      tester,
      upcomingStart: DateTime(2026, 10, 19),
      title: '按上海大学校历，10月19日开学，对吗？',
    );
    expect(find.text('按上海大学校历，10月19日开学，对吗？'), findsOneWidget);
    expect(upcomingChip, findsOneWidget);
    expect(find.text('还没开学（10月19日开学）'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(upcomingChip).selected, isTrue);
    expect(tester.widget<Text>(preview).data, '将把 10月19日（周一）设为第一周');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(results, <DateTime?>[DateTime(2026, 10, 19)]);

    final results2 = await pumpOpener(
      tester,
      upcomingStart: DateTime(2026, 10, 19),
    );
    await tester.tap(chip(1));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(upcomingChip).selected, isFalse);
    expect(selected(tester, 1), isTrue);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(results2, <DateTime?>[DateTime(2026, 10, 5)]);
  });
}
