import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_brand.dart';
import '../../core/app_state.dart';
import '../../core/holiday_repository.dart';
import '../../core/presets.dart';
import '../../core/schedule_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../models/course.dart';
import '../../models/schedule_config.dart';
import '../../models/timetable.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/themed_background.dart';
import '../settings/settings_page.dart';
import '../settings/week_number_sheet.dart';
import 'course_detail_sheet.dart';
import 'course_editor_page.dart';
import 'day_override_sheet.dart';
import 'timetable_empty_state.dart';
import 'week_layout.dart';

export 'timetable_empty_state.dart' show importRouteName;

/// 周课表页。
///
/// v1.4.0：长按列头（key `weekday-<yyyy-MM-dd>`）弹出调休 / 停课面板；
/// 列头角标「休」/「补」；隐藏周末时，某一周的周六 / 周日有课或有调休就单独显示出来。
///
/// v1.5.0：[showCurrentWeekSignal] 每变一次就回到本周（`HomeShell` 点通知时用）。
/// 周视图就是首页（没有底部导航栏）：头部右上角「更多 ⋮」左边的齿轮
/// （key `week-settings`）`push` 打开设置页。头部在空状态下也在，所以没有课时
/// 同样能进设置。
///
/// 点「第 N 周」弹出的「选择周次」面板底部有一行「本周不是第 N 周？点这里校正」
/// （key `week-picker-fix`）→「现在是第几周？」面板 → 改开学日期、回到本周（PLAN-1.5 D8）。
class WeekViewPage extends StatefulWidget {
  /// 长按面板「假期表建议」的数据源（测试注入）；不传时用默认仓库。
  final HolidayRepository? holidayRepository;

  /// 测试用时钟；不传时用 [DateTime.now]。
  final DateTime Function()? clock;

  /// 「回到本周」触发器：值每变一次，按 [clock] 的「现在」跳到本周。
  final ValueListenable<int>? showCurrentWeekSignal;

  const WeekViewPage({
    super.key,
    this.holidayRepository,
    this.clock,
    this.showCurrentWeekSignal,
  });

  @override
  State<WeekViewPage> createState() => _WeekViewPageState();
}

class _WeekViewPageState extends State<WeekViewPage> {
  static const double _timeColumnWidth = 48;

  late PageController _pageController;
  final ScrollController _vScroll = ScrollController();
  Timer? _ticker;
  late DateTime _now;
  late DateTime _seenStartDate;
  String? _seenTimetableId;
  int _viewWeek = 1;
  int _pagesWeeks = 1;

  DateTime _clockNow() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _now = _clockNow();
    final appState = context.read<AppState>();
    final config = appState.currentConfig;
    _seenTimetableId = appState.currentTimetable?.id;
    _seenStartDate = config.startDate;
    _pagesWeeks = config.totalWeeks;
    _viewWeek = ScheduleUtils.weekOf(_now, config);
    _pageController = PageController(initialPage: _viewWeek - 1);
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() => _now = _clockNow());
    });
    widget.showCurrentWeekSignal?.addListener(_showCurrentWeek);
  }

  @override
  void didUpdateWidget(WeekViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showCurrentWeekSignal != widget.showCurrentWeekSignal) {
      oldWidget.showCurrentWeekSignal?.removeListener(_showCurrentWeek);
      widget.showCurrentWeekSignal?.addListener(_showCurrentWeek);
    }
  }

  @override
  void dispose() {
    widget.showCurrentWeekSignal?.removeListener(_showCurrentWeek);
    _ticker?.cancel();
    _pageController.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final theme = context.watch<ThemeController>().current;
    final timetable = appState.currentTimetable;
    final config = appState.currentConfig;
    final timetableChanged = _seenTimetableId != timetable?.id;
    final startDateChanged =
        ScheduleUtils.daysBetween(_seenStartDate, config.startDate) != 0;
    if (timetableChanged || startDateChanged) {
      _seenTimetableId = timetable?.id;
      _seenStartDate = config.startDate;
      _now = _clockNow();
      _viewWeek = ScheduleUtils.weekOf(_now, config);
    }

    // 总周数变了（切课表 / 改设置）时重建 PageController；
    // 开学日期或课表变了（总周数没变）时在下一帧跳到新的本周。
    if (_pagesWeeks != config.totalWeeks) {
      _pagesWeeks = config.totalWeeks;
      if (_viewWeek > _pagesWeeks) _viewWeek = _pagesWeeks;
      final old = _pageController;
      _pageController = PageController(initialPage: _viewWeek - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } else if (timetableChanged || startDateChanged) {
      final targetPage = _viewWeek - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(targetPage);
        }
      });
    }

    final currentWeek = ScheduleUtils.weekOf(_now, config);
    final layout = WeekLayout.of(config);

    return ThemedBackground(
      theme: theme,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              _header(theme, appState, config, currentWeek),
              _weekdayBar(theme, config, timetable),
              Expanded(
                child: timetable == null || timetable.courses.isEmpty
                    ? _emptyGuide(theme)
                    : _grid(theme, timetable, config, layout, currentWeek),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 顶部

  Widget _header(
    AppTheme theme,
    AppState appState,
    ScheduleConfig config,
    int currentWeek,
  ) {
    final colors = theme.colors;
    final monday = ScheduleUtils.mondayOfWeek(config, _viewWeek);
    final sunday = ScheduleUtils.addDays(monday, 6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      appState.currentTimetable?.name ?? AppBrand.name,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: colors.headerText,
                        fontFamily: theme.titleFontFamily,
                      ),
                    ),
                    Text(
                      config.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey<String>('week-settings'),
                tooltip: '设置',
                icon: Icon(Icons.settings_outlined, color: colors.headerText),
                onPressed: _openSettings,
              ),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: Icon(Icons.more_vert, color: colors.headerText),
                onSelected: (value) => _onMenu(value),
                itemBuilder: (_) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'import',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cloud_download_outlined),
                      title: Text('从教务导入'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'add',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.add),
                      title: Text('新建课程'),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'week',
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.calendar_month_outlined),
                      title: Text('选择 / 校正周次'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: '上一周',
                onPressed: _viewWeek > 1
                    ? () => _goToWeek(_viewWeek - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
                color: colors.headerText,
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _showWeekPicker(config, currentWeek),
                  borderRadius: BorderRadius.circular(theme.cornerRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: <Widget>[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              '第 $_viewWeek 周',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w600,
                                color: colors.headerText,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.expand_more,
                              size: 16,
                              color: colors.headerText,
                            ),
                          ],
                        ),
                        Text(
                          '${_md(monday)} - ${_md(sunday)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '下一周',
                onPressed: _viewWeek < config.totalWeeks
                    ? () => _goToWeek(_viewWeek + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                color: colors.headerText,
              ),
              if (_viewWeek != currentWeek)
                TextButton(
                  onPressed: () => _goToWeek(currentWeek),
                  child: const Text('回到本周'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weekdayBar(
    AppTheme theme,
    ScheduleConfig config,
    Timetable? timetable,
  ) {
    final colors = theme.colors;
    final days = _visibleDays(config, timetable, _viewWeek);
    final monday = ScheduleUtils.mondayOfWeek(config, _viewWeek);
    return Container(
      height: 52,
      color: colors.surface.withValues(alpha: 0.92),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _timeColumnWidth,
            child: Center(
              child: Text(
                '${monday.month}月',
                style: TextStyle(fontSize: 11, color: colors.timeColumnText),
              ),
            ),
          ),
          for (final d in days)
            Expanded(
              child: _weekdayCell(
                theme,
                config,
                monday,
                d,
                canEdit: timetable != null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _weekdayCell(
    AppTheme theme,
    ScheduleConfig config,
    DateTime monday,
    int day, {
    required bool canEdit,
  }) {
    final colors = theme.colors;
    final date = ScheduleUtils.addDays(monday, day - 1);
    final isToday = _isSameDay(date, _now);
    // 调休 / 停课：日期下面一个小圆角角标「休」/「补」，这一列的课已经按调休展开
    // （见 _dayColumn）。小组件仍用「停课」/「调休」（EffectiveDay.label）。
    final effective = ScheduleUtils.effectiveDayOf(date, config);
    final badge = effective.badge;
    final overrideText = badge == null ? '' : ' ${effective.description}';
    return Semantics(
      label:
          '${weekdayNamesCn[day]} ${date.month}月${date.day}日'
          '${isToday ? ' 今天' : ''}$overrideText',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey<String>('weekday-${ScheduleUtils.dateKey(date)}'),
          // 长按列头：设这一天的调休 / 停课（没有课表时没有地方存，不响应）。
          onLongPress: canEdit ? () => _onLongPressDay(date) : null,
          child: Ink(
            color: isToday ? colors.todayHighlight : Colors.transparent,
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      weekdayNamesCn[day],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.headerText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // 日期和角标并排：列头只有 52 高，叠成三行在 CJK 字体下会顶到底边。
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isToday
                                ? colors.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isToday
                                  ? colors.onPrimary
                                  : colors.onSurfaceMuted,
                            ),
                          ),
                        ),
                        if (badge != null)
                          Container(
                            key: ValueKey<String>(
                              'override-${ScheduleUtils.dateKey(date)}',
                            ),
                            margin: const EdgeInsets.only(left: 1),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              // 休：灰；补：主题强调色。
                              color: effective.cancelled
                                  ? colors.onSurfaceMuted.withValues(
                                      alpha: 0.75,
                                    )
                                  : colors.accent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 9,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: colors.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onLongPressDay(DateTime date) =>
      showDayOverrideSheet(context, date, holidays: widget.holidayRepository);

  // ------------------------------------------------------------------ 网格

  Widget _grid(
    AppTheme theme,
    Timetable timetable,
    ScheduleConfig config,
    WeekLayout layout,
    int currentWeek,
  ) {
    if (layout.count == 0) {
      return EmptyState(
        theme: theme,
        emoji: theme.decor.emoji,
        title: '作息表是空的',
        message: '请到「设置 → 作息时间」里添加节次。',
      );
    }
    return SingleChildScrollView(
      controller: _vScroll,
      child: SizedBox(
        height: layout.totalHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _timeColumn(
              theme,
              layout,
              _viewWeek == currentWeek &&
                  ScheduleUtils.isDuringTerm(_now, config),
            ),
            Expanded(
              child: PageView.builder(
                key: ValueKey<int>(config.totalWeeks),
                controller: _pageController,
                itemCount: config.totalWeeks,
                onPageChanged: (i) => setState(() => _viewWeek = i + 1),
                itemBuilder: (_, i) =>
                    _weekPage(theme, timetable, config, layout, i + 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeColumn(AppTheme theme, WeekLayout layout, bool showNowLabel) {
    final colors = theme.colors;
    final children = <Widget>[];
    for (var i = 0; i < layout.count; i++) {
      final p = layout.periods[i];
      children.add(
        SizedBox(
          height: layout.periodHeight,
          width: _timeColumnWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // FittedBox：字体放大 / 时间文字较宽时缩放而不是溢出。
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${p.index}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.timeColumnText,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  p.start,
                  maxLines: 1,
                  style: TextStyle(fontSize: 10, color: colors.timeColumnText),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  p.end,
                  maxLines: 1,
                  style: TextStyle(fontSize: 10, color: colors.timeColumnText),
                ),
              ),
            ],
          ),
        ),
      );
      if (layout.hasBreakAfter(i)) {
        children.add(SizedBox(height: layout.breakHeightAfter(i)));
      }
    }
    final nowOffset = showNowLabel
        ? layout.currentTimeOffset(_now.hour * 60 + _now.minute)
        : null;
    return Container(
      width: _timeColumnWidth,
      color: colors.surface.withValues(alpha: 0.92),
      child: Stack(
        children: <Widget>[
          Column(children: children),
          // 「现在」标签放在时间列这条空白边缘，不遮挡课程名（DESIGN.md §4）。
          if (nowOffset != null)
            Positioned(
              left: 2,
              right: 2,
              top: (nowOffset - 7).clamp(0.0, layout.totalHeight - 14),
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${_now.hour.toString().padLeft(2, '0')}:'
                    '${_now.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(fontSize: 9, color: colors.onPrimary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _weekPage(
    AppTheme theme,
    Timetable timetable,
    ScheduleConfig config,
    WeekLayout layout,
    int week,
  ) {
    // 每一页（每一周）自己算显示哪几天：隐藏周末时，这一周的周六 / 周日有课或有调休
    // 就多出一列，列宽按这一页的列数分（和列头 _weekdayBar 用同一个 _visibleDays）。
    final days = _visibleDays(config, timetable, week);
    final monday = ScheduleUtils.mondayOfWeek(config, week);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 同一周里只要有一门课在默认字号下放不下，整周一起用紧凑档，
        // 免得相邻格子一个大一个小（Codex 设计稿 §任务 2）。
        final colWidth = days.isEmpty
            ? 0.0
            : constraints.maxWidth / days.length;
        final compact = _weekNeedsCompact(
          context,
          timetable,
          layout,
          week,
          colWidth,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final d in days)
              Expanded(
                child: _dayColumn(
                  theme,
                  timetable,
                  config,
                  layout,
                  week,
                  d,
                  ScheduleUtils.addDays(monday, d - 1),
                  compact,
                ),
              ),
          ],
        );
      },
    );
  }

  /// 这一周需不需要整周降到紧凑字号。结果按「周 + 列宽 + 文字缩放」缓存，
  /// 每分钟刷新时不会重复测量。
  final Map<String, bool> _compactCache = <String, bool>{};

  bool _weekNeedsCompact(
    BuildContext context,
    Timetable timetable,
    WeekLayout layout,
    int week,
    double colWidth,
  ) {
    if (colWidth <= 0) return false;
    final scaler = MediaQuery.textScalerOf(context);
    final showTime = context.read<AppState>().settings.showTimeInGrid;
    // 课程名 / 节次改了也要重算，所以 key 里带一个便宜的内容指纹。
    var fingerprint = timetable.courses.length;
    for (final c in timetable.courses) {
      fingerprint =
          fingerprint ^ c.name.hashCode ^ (c.startPeriod * 31 + c.endPeriod);
    }
    // 调休改了也要重算（某天换成了别的星期的课）。
    timetable.config.overrides.forEach((k, v) {
      fingerprint = fingerprint ^ Object.hash(k, v);
    });
    final key =
        '${timetable.id}|$fingerprint|$week|'
        '${colWidth.toStringAsFixed(1)}|${scaler.scale(100).round()}|$showTime';
    final cached = _compactCache[key];
    if (cached != null) return cached;

    // 块的内容宽度：列宽 - 外边距(1.5×2) - 内边距(_kBlockPadH×2)。
    final contentWidth = colWidth - 3 - _kBlockPadH * 2;
    var needs = false;
    // 按调休展开后这一周真正画出来的课（和 _dayColumn 同一个来源）。
    final monday = ScheduleUtils.mondayOfWeek(timetable.config, week);
    final shown = <Course>[
      for (final d in _visibleDays(timetable.config, timetable, week))
        ...ScheduleUtils.coursesOn(
          ScheduleUtils.addDays(monday, d - 1),
          timetable,
        ),
    ];
    for (final c in shown) {
      final startPos = layout.positionOfIndex(c.startPeriod);
      final endPos = layout.positionOfIndex(c.endPeriod);
      if (startPos < 0) continue;
      final segments = layout.segmentsOf(
        startPos,
        endPos < 0 ? startPos : endPos,
      );
      for (final (a, b) in segments) {
        final h = layout.heightOfSpan(a, b) - 3 - _kBlockPadV * 2;
        final lines = _blockLines(
          name: c.name,
          nameStyle: const TextStyle(
            fontSize: _kNameSize,
            height: _kNameHeight,
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
          ),
          maxWidth: contentWidth,
          available: h,
          scaler: scaler,
          hasLocation: (c.location ?? '').trim().isNotEmpty,
          hasTeacher: (c.teacher ?? '').trim().isNotEmpty,
          hasTime: showTime,
        );
        // 只有「降到紧凑档就能装下」才值得让整周跟着降；
        // 个别怎么都装不下的超长名属于异类，让它自己再小一档就行，
        // 否则一门课就能把全周的字都拖小。
        if (lines.nameSize == _kNameSizeCompact && lines.fitted) {
          needs = true;
          break;
        }
      }
      if (needs) break;
    }
    if (_compactCache.length > 64) _compactCache.clear();
    _compactCache[key] = needs;
    return needs;
  }

  Widget _dayColumn(
    AppTheme theme,
    Timetable timetable,
    ScheduleConfig config,
    WeekLayout layout,
    int week,
    int day,
    DateTime date,
    bool compact,
  ) {
    final colors = theme.colors;
    final isToday = _isSameDay(date, _now);
    final showOther = context
        .read<AppState>()
        .settings
        .showNonCurrentWeekCourses;

    // 调休 / 停课在这里展开：停课的一天什么都不画；按别的星期 / 周次上课的一天
    // 画那一天的课。和小组件、上课提醒一样走 ScheduleUtils，三处结果一致。
    final effective = ScheduleUtils.effectiveDayOf(date, config);
    final inWeek = ScheduleUtils.coursesOnEffective(effective, timetable);
    final otherWeek = <Course>[];
    if (showOther && !effective.cancelled) {
      for (final c in timetable.courses) {
        if (c.day == effective.weekday && !inWeek.contains(c)) {
          otherWeek.add(c);
        }
      }
    }
    final blocks = _groupBlocks(inWeek);
    final ghosts = showOther
        ? _groupBlocks(otherWeek)
              .where((g) => !blocks.any((b) => _overlaps(b, g)))
              .toList()
        : const <_BlockGroup>[];

    final children = <Widget>[
      _cellBackground(theme, layout, day, isToday),
      for (final g in ghosts)
        ..._positionedBlocks(theme, layout, g, faded: true, compact: compact),
      for (final g in blocks)
        ..._positionedBlocks(
          theme,
          layout,
          g,
          isToday: isToday,
          compact: compact,
        ),
    ];

    return Container(
      color: isToday
          ? colors.todayHighlight.withValues(alpha: 0.55)
          : Colors.transparent,
      child: Stack(children: children),
    );
  }

  /// 底层网格线 + 长按新建课程的热区。
  Widget _cellBackground(
    AppTheme theme,
    WeekLayout layout,
    int day,
    bool isToday,
  ) {
    final colors = theme.colors;
    final children = <Widget>[];
    for (var i = 0; i < layout.count; i++) {
      final periodIndex = layout.periods[i].index;
      children.add(
        SizedBox(
          height: layout.periodHeight,
          child: InkWell(
            key: ValueKey<String>('cell-$day-$periodIndex'),
            onLongPress: () => _newCourseAt(day, periodIndex),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: colors.gridLine, width: 0.5),
                  bottom: BorderSide(color: colors.gridLine, width: 0.5),
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      if (layout.hasBreakAfter(i)) {
        children.add(
          Container(
            height: layout.breakHeightAfter(i),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceVariant.withValues(alpha: 0.6),
              border: Border(
                right: BorderSide(color: colors.gridLine, width: 0.5),
              ),
            ),
            child: day == 1
                ? Text(
                    layout.breakLabelAfter(i) ?? '',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.onSurfaceMuted,
                    ),
                  )
                : null,
          ),
        );
      }
    }
    return Column(children: children);
  }

  List<Widget> _positionedBlocks(
    AppTheme theme,
    WeekLayout layout,
    _BlockGroup group, {
    bool faded = false,
    bool isToday = false,
    bool compact = false,
  }) {
    final course = group.primary;
    final startPos = layout.positionOfIndex(course.startPeriod);
    final endPos = layout.positionOfIndex(course.endPeriod);
    if (startPos < 0) return const <Widget>[];
    final segments = layout.segmentsOf(
      startPos,
      endPos < 0 ? startPos : endPos,
    );
    final widgets = <Widget>[];
    final nowMinutes = _now.hour * 60 + _now.minute;
    for (var i = 0; i < segments.length; i++) {
      final (s, e) = segments[i];
      // 「正在上的课」：今天 + 此刻落在这一段的起止时间之内。
      final segStart = layout.periods[s].startMinutes;
      final segEnd = layout.periods[e].endMinutes;
      final ongoing =
          isToday && !faded && nowMinutes >= segStart && nowMinutes <= segEnd;
      final progress = ongoing && segEnd > segStart
          ? ((nowMinutes - segStart) / (segEnd - segStart)).clamp(0.0, 1.0)
          : 0.0;
      widgets.add(
        Positioned(
          left: 0,
          right: 0,
          top: layout.topOf(s),
          height: layout.heightOfSpan(s, e),
          child: _CourseBlock(
            theme: theme,
            group: group,
            faded: faded,
            ongoing: ongoing,
            progress: progress,
            compact: compact,
            showTime: context.read<AppState>().settings.showTimeInGrid,
            timeText: ScheduleUtils.periodRange(
              context.read<AppState>().currentConfig,
              layout.periods[s].index,
              layout.periods[e].index,
            ).start,
            continued: i > 0,
            onTap: () => showCourseDetailSheet(context, courses: group.all),
          ),
        ),
      );
    }
    return widgets;
  }

  // ------------------------------------------------------------------ 空状态

  Widget _emptyGuide(AppTheme theme) {
    return TimetableEmptyState(
      theme: theme,
      keyPrefix: 'week-empty',
      title: '新学期，从第一门课开始。',
      message: '可以从教务系统一键导入，也可以手动添加。',
      clock: widget.clock,
    );
  }

  // ------------------------------------------------------------------ 交互

  void _onMenu(String value) {
    switch (value) {
      case 'import':
        _openImport();
      case 'add':
        _newCourseAt(1, 1);
      case 'week':
        final config = context.read<AppState>().currentConfig;
        _showWeekPicker(config, ScheduleUtils.weekOf(_now, config));
    }
  }

  /// 打开导入流程。
  ///
  /// 路由 [importRouteName] 由 Phase 3 在 `lib/app.dart` 的 `routes` 里注册；
  /// 还没注册时会落到 `ShuScheduleApp` 的 `onUnknownRoute`，显示「尚未接入」页，
  /// 不会白屏或崩溃。
  void _openImport() {
    Navigator.of(context).pushNamed(importRouteName);
  }

  /// 右上角齿轮：打开设置页（普通页面，AppBar 自带返回键）。
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          holidayRepository: widget.holidayRepository,
          clock: widget.clock,
        ),
      ),
    );
  }

  Future<void> _newCourseAt(int day, int periodIndex) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CourseEditorPage(
          initialDay: day,
          initialStartPeriod: periodIndex,
          clock: widget.clock,
        ),
      ),
    );
  }

  /// 回到本周（[WeekViewPage.showCurrentWeekSignal] 触发）。先刷新「现在」，
  /// 不等分钟计时器（刚跨过周日午夜时，差一分钟就差一周）。
  void _showCurrentWeek() {
    if (!mounted) return;
    _now = _clockNow();
    _goToWeek(
      ScheduleUtils.weekOf(_now, context.read<AppState>().currentConfig),
    );
  }

  void _goToWeek(int week) {
    final target = week.clamp(1, _pagesWeeks);
    setState(() => _viewWeek = target);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        target - 1,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  /// 「选择周次」面板里「本周不是第 N 周？」那一行 pop 出来的值（真实周次都 >= 1）。
  static const int _fixCurrentWeek = 0;

  Future<void> _showWeekPicker(ScheduleConfig config, int currentWeek) async {
    final theme = context.read<ThemeController>().current;
    final hasTimetable = context.read<AppState>().currentTimetable != null;
    // 不裁剪的周次：开学前 / 学期结束后不说「本周不是第 1 周」这种话。
    final rawWeek = ScheduleUtils.rawWeekOf(_clockNow(), config);
    final inTerm = rawWeek >= 1 && rawWeek <= config.totalWeeks;
    // 周次多、屏幕矮时周次那一块自己滚动，底部「本周不是第 N 周？」那一行始终露在外面。
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: Padding(
          // 底部留出手势条 / 导航栏的位置（useSafeArea 只管顶部）。
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '选择周次',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (var w = 1; w <= config.totalWeeks; w++)
                        ChoiceChip(
                          label: Text(w == currentWeek ? '$w（本周）' : '$w'),
                          selected: w == _viewWeek,
                          onSelected: (_) => Navigator.of(sheetContext).pop(w),
                        ),
                    ],
                  ),
                ),
              ),
              if (hasTimetable) ...<Widget>[
                const SizedBox(height: 12),
                TextButton.icon(
                  key: const ValueKey<String>('week-picker-fix'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colors.accent,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(_fixCurrentWeek),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: Text(
                    inTerm ? '本周不是第 $rawWeek 周？点这里校正' : '现在是第几周？点这里校正',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == _fixCurrentWeek) {
      await _fixCurrentWeekNumber();
      return;
    }
    _goToWeek(picked);
  }

  /// 「本周不是第 N 周？」：选好「现在是第几周」后改开学日期，SnackBar 提示，回到本周。
  Future<void> _fixCurrentWeekNumber() async {
    final start = await correctCurrentWeek(context, today: _clockNow());
    if (start == null || !mounted) return;
    _showCurrentWeek();
  }

  // ------------------------------------------------------------------ 工具

  /// 第 [week] 周要画哪几天（1..7）。
  ///
  /// 显示周末时总是七天；隐藏周末时是周一到周五，再加上这一周里**有课**
  /// （调休展开后，例如周六补周一的课）、**有调休设置**、或**停课但原本有课**的
  /// 周六 / 周日——这样补课的周六能看到、能长按列头。原本就没课的周末停课
  /// （套用国家假日表时 10/3、10/4 这类）不单独出列（v1.4.0 修复轮，review-G P3-1）。
  /// 列头、网格、紧凑字号的测量都用它，所以同一周的列数一致；相邻两周可以一周 5 列、一周 7 列。
  static List<int> _visibleDays(
    ScheduleConfig config,
    Timetable? timetable,
    int week,
  ) {
    if (config.showWeekend) return const <int>[1, 2, 3, 4, 5, 6, 7];
    final monday = ScheduleUtils.mondayOfWeek(config, week);
    final days = <int>[1, 2, 3, 4, 5];
    for (final d in const <int>[6, 7]) {
      final effective = ScheduleUtils.effectiveDayOf(
        ScheduleUtils.addDays(monday, d - 1),
        config,
      );
      final bool show;
      if (effective.cancelled) {
        show = timetable != null && _wouldHaveClasses(effective, timetable);
      } else {
        show =
            effective.isOverridden ||
            (timetable != null &&
                ScheduleUtils.coursesOnEffective(
                  effective,
                  timetable,
                ).isNotEmpty);
      }
      if (show) days.add(d);
    }
    return days;
  }

  /// 不考虑调休 / 停课时，这一天原本有没有课（和提醒规划器的同名判断一致）。
  static bool _wouldHaveClasses(EffectiveDay day, Timetable timetable) {
    final plain = EffectiveDay(
      date: day.date,
      calendarWeek: day.calendarWeek,
      week: day.calendarWeek,
      weekday: day.date.weekday,
      cancelled: false,
    );
    return ScheduleUtils.coursesOnEffective(plain, timetable).isNotEmpty;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _md(DateTime d) => '${d.month}/${d.day}';

  /// 把同一天里节次重叠的课程归成一组（冲突显示角标，详情里列全部）。
  static List<_BlockGroup> _groupBlocks(List<Course> courses) {
    final sorted = List<Course>.from(courses)
      ..sort((a, b) {
        final s = a.startPeriod.compareTo(b.startPeriod);
        return s != 0 ? s : b.periodSpan.compareTo(a.periodSpan);
      });
    final groups = <_BlockGroup>[];
    for (final c in sorted) {
      _BlockGroup? hit;
      for (final g in groups) {
        if (c.startPeriod <= g.endPeriod && g.startPeriod <= c.endPeriod) {
          hit = g;
          break;
        }
      }
      if (hit == null) {
        groups.add(_BlockGroup(c));
      } else {
        hit.others.add(c);
      }
    }
    return groups;
  }

  static bool _overlaps(_BlockGroup a, _BlockGroup b) =>
      a.startPeriod <= b.endPeriod && b.startPeriod <= a.endPeriod;
}

/// 同一格里重叠的一组课程；[primary] 是画出来的那一门。
class _BlockGroup {
  final Course primary;
  final List<Course> others = <Course>[];

  _BlockGroup(this.primary);

  int get startPeriod => primary.startPeriod;

  int get endPeriod => primary.endPeriod;

  List<Course> get all => <Course>[primary, ...others];
}

/// 课程块里每一行怎么排。见 [_blockLines]。
class _BlockLines {
  /// 课程名最多排几行。
  final int name;

  /// 课程名实际用的字号：排不下时会自动缩一档，换取完整显示。
  final double nameSize;

  /// 名字是否完整排下了（false 时调用方会收紧上下留白再算一次）。
  final bool fitted;

  final bool location;
  final bool teacher;
  final bool time;

  const _BlockLines({
    required this.name,
    required this.nameSize,
    required this.location,
    required this.teacher,
    required this.time,
    this.fitted = true,
  });
}

/// 课程名在 [maxWidth] 宽度下、用 [size] 字号自然要排几行。
int _measureNameLines(
  String text,
  TextStyle style,
  double size,
  double maxWidth,
  TextScaler scaler,
) {
  if (text.isEmpty || maxWidth <= 0 || !maxWidth.isFinite) return 1;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: style.copyWith(fontSize: size, height: _nameLineHeight(size)),
    ),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout(maxWidth: maxWidth);
  final lines = painter.computeLineMetrics().length;
  painter.dispose();
  return lines < 1 ? 1 : lines;
}

/// 课程名可以缩到哪几档字号（从大到小）。
/// 第二档是「紧凑档」，同一周里只要有一门课放不下，整周一起用，
/// 避免相邻格子忽大忽小；最后一档留给「1 节高 + 超长名」的极端情况。
const double _kNameSizeCompact = 10.5;
const List<double> _kNameSizeSteps = <double>[
  _kNameSize,
  _kNameSizeCompact,
  9.5,
  9,
];

/// 行高：紧凑档以下收紧一点，1 节高的格子才塞得下长名字。
double _nameLineHeight(double size) =>
    size >= _kNameSizeCompact ? _kNameHeight : 1.08;

/// 冲突角标（右上角 `+N`）要占掉的宽度。有角标时课程名整体让出这点宽度，
/// 否则第一行的字会被角标盖住。
const double _kBadgeWidth = 18;

/// 按块的实际尺寸决定：课程名用多大字号、最多几行，教室/教师/时间画不画。
///
/// 行高直接用 `fontSize * height`（几个 TextStyle 都写死了 `height`，
/// 所以这个值就是 Flutter 排出来的行高）；课程名要几行用 [TextPainter] 量。
///
/// 规则是「课程名优先」：
/// 1. 先用最大字号配尽量多的附加行；名字排不完就依次砍掉时间、教师、教室；
/// 2. 附加行全砍掉还排不完，就把字号缩一档再来一遍（12 → 11 → 10）；
/// 3. 还是排不完（窄格子里的超长英文名），用最小字号把整块高度都给名字。
///
/// 附加行按「时间 → 教师 → 教室」的顺序退让：教师和上课时间点开详情都看得到，
/// 教室是上课当下要用的，所以最后才砍。
_BlockLines _blockLines({
  required String name,
  required TextStyle nameStyle,
  required double maxWidth,
  required double available,
  required TextScaler scaler,
  required bool hasLocation,
  required bool hasTeacher,
  required bool hasTime,
  bool compact = false,
}) {
  if (!available.isFinite || available <= 0) {
    // 高度不受限：不限行，全画。
    return _BlockLines(
      name: 99,
      nameSize: _kNameSize,
      location: hasLocation,
      teacher: hasTeacher,
      time: hasTime,
    );
  }
  final locationLine = scaler.scale(_kLocationSize) * _kMetaHeight;
  final metaLine = scaler.scale(_kTeacherSize) * _kMetaHeight;
  // 留一点余量，避免浮点误差 / 字体度量差异让最后一行擦出边界。
  final total = available - 0.5;
  // 整周紧凑档：直接从第二档字号起步。
  final steps = compact ? _kNameSizeSteps.sublist(1) : _kNameSizeSteps;

  for (final double size in steps) {
    final lineH = scaler.scale(size) * _nameLineHeight(size);
    final needed = _measureNameLines(name, nameStyle, size, maxWidth, scaler);
    for (var drop = 0; drop <= 3; drop++) {
      final time = hasTime && drop < 1;
      final teacher = hasTeacher && drop < 2;
      final location = hasLocation && drop < 3;
      final anyExtra = time || teacher || location;
      final extras =
          (time ? metaLine : 0) +
          (teacher ? metaLine : 0) +
          (location ? locationLine : 0) +
          (anyExtra ? _kMetaGap : 0);
      if (total - extras >= needed * lineH) {
        return _BlockLines(
          name: needed,
          nameSize: size,
          location: location,
          teacher: teacher,
          time: time,
        );
      }
    }
  }

  // 兜底：最小字号，整块高度全给课程名。
  final smallest = steps.last;
  final lineH = scaler.scale(smallest) * _nameLineHeight(smallest);
  final lines = (total / lineH).floor();
  return _BlockLines(
    name: lines < 1 ? 1 : lines,
    nameSize: smallest,
    location: false,
    teacher: false,
    time: false,
    fitted: false,
  );
}

const double _kNameSize = 11.5;
const double _kNameHeight = 1.22;
const double _kLocationSize = 9.5;
const double _kTeacherSize = 9.5;
const double _kMetaHeight = 1.16;
const double _kBlockPadH = 3;
const double _kBlockPadV = 5;

/// 课程名和下面「教室 / 教师」之间的固定间距。
const double _kMetaGap = 4;

/// 名字怎么都排不下时改用的上下留白：把最后一点空间也让给文字。
const double _kBlockPadVTight = 1;

class _CourseBlock extends StatelessWidget {
  final AppTheme theme;
  final _BlockGroup group;
  final bool faded;
  final bool showTime;
  final String timeText;
  final bool continued;

  /// 这一段正好是「此刻在上的课」：加一圈描边和右侧进度槽。
  final bool ongoing;

  /// 这节课已经上了多少（0~1），只在 [ongoing] 时有意义。
  final double progress;

  /// 整周统一用紧凑字号。
  final bool compact;
  final VoidCallback onTap;

  const _CourseBlock({
    required this.theme,
    required this.group,
    required this.showTime,
    required this.timeText,
    required this.onTap,
    this.faded = false,
    this.continued = false,
    this.ongoing = false,
    this.progress = 0,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final course = group.primary;
    final textColor = theme.courseTextOnBlock;
    final location = (course.location ?? '').trim();
    final teacher = (course.teacher ?? '').trim();
    final nameText = continued ? '${course.name}（续）' : course.name;
    final nameStyle = TextStyle(
      fontSize: _kNameSize,
      height: _kNameHeight,
      letterSpacing: 0,
      fontWeight: FontWeight.w600,
      color: textColor,
    );
    final radius = BorderRadius.circular(theme.cornerRadius);
    final block = Padding(
      padding: const EdgeInsets.all(1.5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: ongoing
              ? Border.all(
                  color: theme.colors.accent.withValues(alpha: 0.7),
                  width: 1.5,
                )
              : null,
        ),
        child: Material(
          color: theme.courseBlockColor(course.colorIndex),
          borderRadius: radius,
          child: InkWell(
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            onTap: onTap,
            child: Stack(
              children: <Widget>[
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    // 有冲突角标时，课程名整体往左让出角标的宽度。
                    final badgeGap = group.others.isEmpty ? 0.0 : _kBadgeWidth;
                    final bounded = constraints.maxHeight.isFinite;
                    final scaler = MediaQuery.textScalerOf(context);
                    _BlockLines measure(double padV) => _blockLines(
                      name: nameText,
                      nameStyle: nameStyle,
                      maxWidth:
                          constraints.maxWidth - _kBlockPadH * 2 - badgeGap,
                      available: bounded
                          ? constraints.maxHeight - padV * 2
                          : double.infinity,
                      scaler: scaler,
                      hasLocation: location.isNotEmpty,
                      hasTeacher: teacher.isNotEmpty,
                      hasTime: showTime && timeText.isNotEmpty,
                    );
                    var padV = _kBlockPadV;
                    var lines = measure(padV);
                    if (!lines.fitted && bounded) {
                      // 排不下就把上下留白收到最紧再试一次，常常正好多出一行。
                      padV = _kBlockPadVTight;
                      lines = measure(padV);
                    }
                    // 名字 + 教室 + 教师是一个连续的信息组，整组靠上；
                    // 多出来的留白集中在组的下方，所有格子的首行起点一致。
                    final nameWidget = Padding(
                      padding: EdgeInsets.only(right: badgeGap),
                      child: Text(
                        nameText,
                        maxLines: lines.name,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle.copyWith(
                          fontSize: lines.nameSize,
                          height: _nameLineHeight(lines.nameSize),
                        ),
                      ),
                    );
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: _kBlockPadH,
                        vertical: padV,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Flexible(child: nameWidget),
                          if (lines.location || lines.teacher || lines.time)
                            const SizedBox(height: _kMetaGap),
                          if (lines.location)
                            Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: _kLocationSize,
                                height: _kMetaHeight,
                                letterSpacing: 0,
                                fontWeight: FontWeight.w500,
                                color: textColor.withValues(alpha: 0.82),
                              ),
                            ),
                          if (lines.teacher)
                            Text(
                              teacher,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: _kTeacherSize,
                                height: _kMetaHeight,
                                letterSpacing: 0,
                                color: textColor.withValues(alpha: 0.66),
                              ),
                            ),
                          if (lines.time)
                            Text(
                              timeText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: _kTeacherSize,
                                height: _kMetaHeight,
                                letterSpacing: 0,
                                color: textColor.withValues(alpha: 0.66),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                // 正在上的课：右边缘一条细进度槽，显示这节课已经过了多少。
                // 画在内边距里，不挤占文字宽度，上课那一刻不会重新换行。
                if (ongoing)
                  Positioned(
                    right: 1,
                    top: 6,
                    bottom: 6,
                    width: 2.5,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: FractionallySizedBox(
                            widthFactor: 1,
                            heightFactor: progress.clamp(0.02, 1.0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: theme.colors.accent.withValues(
                                  alpha: 0.85,
                                ),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (group.others.isNotEmpty)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colors.danger,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+${group.others.length}',
                        style: TextStyle(
                          fontSize: 9,
                          color: theme.colors.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final semanticsLabel = <String>[
      weekdayNamesCn[course.day.clamp(1, 7)],
      '第 ${course.startPeriod}-${course.endPeriod} 节',
      course.name,
      if (course.location != null) course.location!,
      if (course.teacher != null) course.teacher!,
      if (faded) '非本周',
    ].join('，');

    return Semantics(
      label: semanticsLabel,
      button: true,
      child: faded ? Opacity(opacity: 0.38, child: block) : block,
    );
  }
}
