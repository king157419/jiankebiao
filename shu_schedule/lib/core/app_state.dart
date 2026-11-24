import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/course.dart';
import '../models/period_time.dart';
import '../models/schedule_config.dart';
import '../models/timetable.dart';
import 'presets.dart';
import 'schedule_utils.dart';
import 'storage.dart';

/// 全局应用状态。所有写操作都会在变更后自动 [save]。
class AppState extends ChangeNotifier {
  static const Uuid _uuid = Uuid();

  List<Timetable> _timetables = <Timetable>[];
  AppSettings _settings = AppSettings.defaults();
  bool _loaded = false;
  List<String> _warnings = <String>[];

  /// 是否已完成首次加载。
  bool get isLoaded => _loaded;

  /// 加载时遇到并已自动修复的问题。
  List<String> get warnings => List<String>.unmodifiable(_warnings);

  List<Timetable> get timetables => List<Timetable>.unmodifiable(_timetables);

  AppSettings get settings => _settings;

  /// 当前课表；一张都没有时返回 null。
  Timetable? get currentTimetable {
    if (_timetables.isEmpty) return null;
    for (final t in _timetables) {
      if (t.id == _settings.currentTimetableId) return t;
    }
    return _timetables.first;
  }

  /// 当前课表的配置；没有课表时返回按今天所在周周一暂定的空配置。
  ScheduleConfig get currentConfig =>
      currentTimetable?.config ??
      ScheduleConfig(
        name: '我的课表',
        startDate: ScheduleUtils.mondayOf(DateTime.now()),
      );

  /// 「刚导入完，请首页弹一次校历建议面板」（PLAN-1.5 D9 触发点 (a)）：值是课表 id。
  /// 导入预览页写入成功、退回首页后调用 [requestCalendarPrompt]；`HomeShell` 监听它，
  /// 处理时先把它清回 null。不写盘、不参与 [notifyListeners]。
  final ValueNotifier<String?> pendingCalendarPromptFor =
      ValueNotifier<String?>(null);

  /// 请首页给课表 [timetableId] 弹一次校历建议面板（见 [pendingCalendarPromptFor]）。
  /// 先清成 null 再设值：同一张课表连着导入两次也能再触发一次。
  void requestCalendarPrompt(String timetableId) {
    pendingCalendarPromptFor.value = null;
    pendingCalendarPromptFor.value = timetableId;
  }

  @override
  void dispose() {
    pendingCalendarPromptFor.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ 加载 / 保存

  Future<void> load() async {
    final snapshot = await Storage.load();
    _timetables = snapshot.timetables;
    _settings = snapshot.settings;
    _warnings = snapshot.warnings;
    _loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    await Storage.save(_timetables, _settings);
  }

  Future<void> _commit() async {
    notifyListeners();
    await save();
  }

  // -------------------------------------------------------------- 课表管理

  /// 新建一张空课表并切换过去，返回新课表。
  ///
  /// 没传 [config] 时按 [today]（默认 [DateTime.now]）所在周周一暂定开学日期；
  /// [confirmTermStart] 为 true 时同时记入 `AppSettings.termStartConfirmed`。
  Future<Timetable> createTimetable({
    String name = '我的课表',
    ScheduleConfig? config,
    bool confirmTermStart = false,
    DateTime? today,
  }) async {
    final tt = Timetable(
      id: _uuid.v4(),
      name: name,
      config:
          config ??
          ScheduleConfig(
            name: name,
            startDate: ScheduleUtils.mondayOf(today ?? DateTime.now()),
          ),
    );
    _timetables.add(tt);
    _settings.currentTimetableId = tt.id;
    if (confirmTermStart) {
      _settings.termStartConfirmed[tt.id] = ScheduleConfig.dateKey(
        tt.config.startDate,
      );
    }
    await _commit();
    return tt;
  }

  /// 直接加入一张已经构造好的课表（导入 / 备份恢复用）。
  Future<void> addTimetable(Timetable timetable, {bool switchTo = true}) async {
    _timetables.add(timetable);
    if (switchTo) _settings.currentTimetableId = timetable.id;
    await _commit();
  }

  Future<void> renameTimetable(String id, String name) async {
    final tt = _byId(id);
    if (tt == null) return;
    tt.name = name;
    await _commit();
  }

  Future<void> deleteTimetable(String id) async {
    _timetables.removeWhere((t) => t.id == id);
    _settings.calendarSuggestionDismissed.remove(id);
    _settings.termStartConfirmed.remove(id);
    if (_settings.currentTimetableId == id) {
      _settings.currentTimetableId = _timetables.isEmpty
          ? ''
          : _timetables.first.id;
    }
    await _commit();
  }

  Future<void> switchTimetable(String id) async {
    if (_byId(id) == null) return;
    _settings.currentTimetableId = id;
    await _commit();
  }

  /// 把一次教务导入写进课表，只保存一次。
  ///
  /// [overwriteId] 指向一张存在的课表时覆盖它：换掉课程、配置和导入元数据，
  /// **保留 `Timetable.name`**（用户起的名字）；否则新建一张名为 [name] 的课表并切换过去。
  /// [confirmTermStart] 为 true 时同时把开学日期记进 `AppSettings.termStartConfirmed`。
  Future<Timetable> applyImport({
    String? overwriteId,
    required String name,
    required List<Course> courses,
    required ScheduleConfig config,
    String? schoolId,
    String? systemType,
    String? termCode,
    DateTime? importedAt,
    bool confirmTermStart = false,
  }) async {
    final existing = overwriteId == null ? null : _byId(overwriteId);
    final Timetable tt;
    if (existing != null) {
      existing
        ..courses = List<Course>.from(courses)
        ..config = config
        ..schoolId = schoolId
        ..systemType = systemType
        ..termCode = termCode
        ..importedAt = importedAt;
      tt = existing;
    } else {
      tt = Timetable(
        id: _uuid.v4(),
        name: name,
        config: config,
        courses: List<Course>.from(courses),
        schoolId: schoolId,
        systemType: systemType,
        termCode: termCode,
        importedAt: importedAt,
      );
      _timetables.add(tt);
      _settings.currentTimetableId = tt.id;
    }
    if (confirmTermStart) {
      _settings.termStartConfirmed[tt.id] = ScheduleConfig.dateKey(
        tt.config.startDate,
      );
    }
    await _commit();
    return tt;
  }

  /// 用新的课程列表整体覆盖某张课表（导入「覆盖当前课表」用）。
  Future<void> replaceCourses(String timetableId, List<Course> courses) async {
    final tt = _byId(timetableId);
    if (tt == null) return;
    tt.courses = List<Course>.from(courses);
    await _commit();
  }

  // -------------------------------------------------------------- 课程管理

  /// 添加一门课；未指定 id 时自动生成。
  ///
  /// 一张课表都没有时会自动新建一张默认课表再放进去
  /// —— 冷启动空状态的「手动添加」走的就是这条路，
  /// 不自动建表的话用户点了保存却什么都不会发生（课程被静默丢弃）。
  Future<Course?> addCourse(Course course, {String? timetableId}) async {
    var tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    tt ??= await createTimetable();
    final withId = course.id.isEmpty ? course.copyWith(id: _uuid.v4()) : course;
    tt.courses.add(withId);
    await _commit();
    return withId;
  }

  /// 一次加入多门课、只保存一次（「复制到其他星期」用）。
  ///
  /// 没有 id 的课自动生成；一张课表都没有时和 [addCourse] 一样先建一张默认课表。
  Future<List<Course>> addCourses(
    List<Course> courses, {
    String? timetableId,
  }) async {
    if (courses.isEmpty) return const <Course>[];
    var tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    tt ??= await createTimetable();
    final added = <Course>[
      for (final c in courses) c.id.isEmpty ? c.copyWith(id: _uuid.v4()) : c,
    ];
    tt.courses.addAll(added);
    await _commit();
    return added;
  }

  /// 更新一门课。
  ///
  /// [syncGroupColor] 为 true（默认）且这门课有 [Course.groupId] 时，
  /// 颜色改动会同步到同组（同一门课的其他时段）的所有课程。
  Future<void> updateCourse(
    Course course, {
    String? timetableId,
    bool syncGroupColor = true,
  }) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    final index = tt.courses.indexWhere((c) => c.id == course.id);
    if (index < 0) return;
    final previous = tt.courses[index];
    tt.courses[index] = course;
    final group = course.groupId;
    if (syncGroupColor &&
        group != null &&
        previous.colorIndex != course.colorIndex) {
      for (var i = 0; i < tt.courses.length; i++) {
        final c = tt.courses[i];
        if (i != index && c.groupId == group) {
          tt.courses[i] = c.copyWith(colorIndex: course.colorIndex);
        }
      }
    }
    await _commit();
  }

  /// 同一张课表里和 [groupId] 同组的所有课程（同一门课的各个时段）。
  List<Course> coursesInGroup(String groupId, {String? timetableId}) {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return const <Course>[];
    return tt.courses.where((c) => c.groupId == groupId).toList();
  }

  Future<void> deleteCourse(String courseId, {String? timetableId}) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    tt.courses.removeWhere((c) => c.id == courseId);
    await _commit();
  }

  /// 生成一个新的课程 id（供 UI 在构造 Course 时使用）。
  String newId() => _uuid.v4();

  // -------------------------------------------------------------- 配置管理

  Future<void> updateConfig(
    ScheduleConfig config, {
    String? timetableId,
    bool confirmTermStart = false,
  }) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    tt.config = config;
    if (confirmTermStart) {
      _settings.termStartConfirmed[tt.id] = ScheduleConfig.dateKey(
        tt.config.startDate,
      );
    }
    await _commit();
  }

  /// 撤销一次配置修改（校历建议「一键套用」、学期设置「学校校历」的「撤销」），
  /// 同时把 `termStartConfirmed` 和（可选）`calendarSuggestionDismissed` 还原回修改前的值。
  Future<void> restoreTimetableConfig(
    String timetableId,
    ScheduleConfig previousConfig, {
    required String? previousConfirmedStart,
    bool restoreDismissed = false,
    String? previousDismissedKey,
  }) async {
    final tt = _byId(timetableId);
    if (tt == null) return;
    tt.config = previousConfig;
    if (previousConfirmedStart == null) {
      _settings.termStartConfirmed.remove(timetableId);
    } else {
      _settings.termStartConfirmed[timetableId] = previousConfirmedStart;
    }
    if (restoreDismissed) {
      if (previousDismissedKey == null) {
        _settings.calendarSuggestionDismissed.remove(timetableId);
      } else {
        _settings.calendarSuggestionDismissed[timetableId] =
            previousDismissedKey;
      }
    }
    await _commit();
  }

  /// 设置（[value] 非 null）或删除（[value] 为 null）某一天的调休 / 停课。
  Future<void> setDateOverride(
    DateTime date,
    DateOverride? value, {
    String? timetableId,
  }) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    tt.config = tt.config.withOverride(date, value);
    await _commit();
  }

  /// 一次写入多天的调休 / 停课（「套用节假日安排」），只保存一次。
  ///
  /// 只覆盖 [values] 里的日期，其余已有设置原样保留。
  Future<void> applyDateOverrides(
    Map<DateTime, DateOverride> values, {
    String? timetableId,
  }) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null || values.isEmpty) return;
    final next = Map<String, DateOverride>.from(tt.config.overrides);
    values.forEach((date, value) {
      next[ScheduleConfig.dateKey(date)] = value;
    });
    tt.config = tt.config.copyWith(overrides: next);
    await _commit();
  }

  /// 校历建议「一键套用」（v1.5.0，PLAN-1.5 D9）：[startDate] 非 null 时改开学日期，
  /// 再写入 [overrides] 里的调休 / 停课（其余已有设置原样保留），同时确认开学日期、
  /// （给了 [termKey] 时）记录本学期指纹，只保存一次。
  ///
  /// 返回套用前的配置；课表不存在返回 null。
  Future<ScheduleConfig?> applyCalendarSuggestion(
    String timetableId, {
    DateTime? startDate,
    Map<DateTime, DateOverride> overrides = const <DateTime, DateOverride>{},
    String? termKey,
  }) async {
    final tt = _byId(timetableId);
    if (tt == null) return null;
    final previous = tt.config;
    final next = Map<String, DateOverride>.from(previous.overrides);
    overrides.forEach((date, value) {
      next[ScheduleConfig.dateKey(date)] = value;
    });
    tt.config = previous.copyWith(startDate: startDate, overrides: next);
    _settings.termStartConfirmed[timetableId] = ScheduleConfig.dateKey(
      tt.config.startDate,
    );
    if (termKey != null) {
      _settings.calendarSuggestionDismissed[timetableId] = termKey;
    }
    await _commit();
    return previous;
  }

  /// 校历建议面板点了「先不用」：记下学期内容指纹 `termKey`，
  /// 同一学校同一学期的条目没变时启动不再弹（`AppSettings.calendarSuggestionDismissed`）。
  Future<void> dismissCalendarSuggestion(String timetableId, String key) async {
    _settings.calendarSuggestionDismissed[timetableId] = key;
    await _commit();
  }

  /// 修改休息带：null = 按作息自动推导，列表 = 手动指定（[PeriodTime.index]）。
  Future<void> setBreakAfter(
    List<int>? breakAfter, {
    String? timetableId,
  }) async {
    final tt =
        _byId(timetableId ?? _settings.currentTimetableId) ?? currentTimetable;
    if (tt == null) return;
    tt.config = breakAfter == null
        ? tt.config.copyWith(clearBreakAfter: true)
        : tt.config.copyWith(breakAfter: breakAfter);
    await _commit();
  }

  /// 修改作息表。
  Future<void> updatePeriods(List<PeriodTime> periods) async {
    final tt = currentTimetable;
    if (tt == null) return;
    tt.config.periods = List<PeriodTime>.from(periods)
      ..sort((a, b) => a.index.compareTo(b.index));
    await _commit();
  }

  /// 一键恢复内置的 12 节示例作息。
  Future<void> resetPeriodsToDefault() async {
    await updatePeriods(List<PeriodTime>.from(defaultPeriods));
  }

  // -------------------------------------------------------------- 设置管理

  Future<void> updateSettings(AppSettings settings) async {
    _settings = settings;
    await _commit();
  }

  Future<void> setThemeId(String themeId) async {
    _settings.themeId = themeId;
    await _commit();
  }

  Future<void> setShowNonCurrentWeekCourses(bool value) async {
    _settings.showNonCurrentWeekCourses = value;
    await _commit();
  }

  Future<void> setShowTimeInGrid(bool value) async {
    _settings.showTimeInGrid = value;
    await _commit();
  }

  Future<void> setRememberEduLogin(bool value) async {
    _settings.rememberEduLogin = value;
    await _commit();
  }

  /// 记录一次检查更新的时间（每天最多自动查一次靠它）。
  Future<void> setLastUpdateCheck(DateTime time) async {
    _settings.lastUpdateCheck = time;
    await _commit();
  }

  /// 记录一次联网刷新假日表的时间（24 小时节流靠它，v1.4.0）。
  Future<void> setLastHolidayRefresh(DateTime time) async {
    _settings.lastHolidayRefresh = time;
    await _commit();
  }

  /// 修改上课提醒偏好（v1.4.0）。提醒的重新排程由 `ReminderService`
  /// 监听 AppState 变化完成，这里只负责存。
  Future<void> setReminderSettings(ReminderSettings value) async {
    if (_settings.reminders == value) return;
    _settings.reminders = value;
    await _commit();
  }

  /// 备份恢复：整体替换所有数据。
  ///
  /// 覆盖前会把现有 `timetables.json` 另存一份
  /// （`timetables.json.before-restore-<时间戳>`），恢复错了还能手工捞回来；
  /// 路径只打到 debugPrint，不进 [warnings]。
  /// 同时修掉备份里可能存在的重复/缺失 id，并保证 `currentTimetableId` 不悬空。
  Future<void> restoreFrom(StorageSnapshot snapshot) async {
    final restoreWarnings = <String>[...snapshot.warnings];
    final backup = await Storage.backupBeforeRestore();
    // 旧数据的备份路径只写日志，不进 warnings：它会变成设置页顶部的红卡
    // 「读取数据时发现问题」，对学生是噪音（PLAN-1.5 任务 E）。
    if (backup != null) debugPrint('恢复前的旧数据已备份到 $backup');

    final restored = List<Timetable>.from(snapshot.timetables);
    Storage.normalizeIds(restored, restoreWarnings);

    // 检查更新时间 / 假日表刷新时间是「这台手机上的这个 App」的状态，
    // 不跟着备份走：恢复一份旧备份不应该重置每天一次的节流。
    // 上课提醒偏好（reminders）是用户偏好，跟着备份走（旧备份没有 → 关闭）；
    // 通知权限状态本来就不存。
    final keepLastCheck = _settings.lastUpdateCheck;
    final keepHolidayRefresh = _settings.lastHolidayRefresh;
    _timetables = restored;
    _settings = snapshot.settings;
    _settings.lastUpdateCheck = keepLastCheck ?? _settings.lastUpdateCheck;
    _settings.lastHolidayRefresh =
        keepHolidayRefresh ?? _settings.lastHolidayRefresh;
    if (_timetables.isEmpty) {
      _settings.currentTimetableId = '';
    } else if (!_timetables.any((t) => t.id == _settings.currentTimetableId)) {
      _settings.currentTimetableId = _timetables.first.id;
    }
    _warnings = restoreWarnings;
    await _commit();
  }

  Timetable? _byId(String id) {
    if (id.isEmpty) return null;
    for (final t in _timetables) {
      if (t.id == id) return t;
    }
    return null;
  }
}
