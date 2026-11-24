import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/app_settings.dart';
import '../models/timetable.dart';

/// 一次完整的持久化快照。
class StorageSnapshot {
  final List<Timetable> timetables;
  final AppSettings settings;

  /// 读取时发现并已自动修复的问题（损坏文件、非法字段等）。
  final List<String> warnings;

  const StorageSnapshot({
    required this.timetables,
    required this.settings,
    this.warnings = const <String>[],
  });
}

/// 应用文档目录下的 JSON 持久化。
///
/// 设计要点：任何损坏/半截/非法 JSON 都必须回退到默认值而不是抛异常，
/// 同时把损坏文件改名为 `*.corrupt-<时间戳>` 保留现场。
class Storage {
  Storage._();

  static const String timetablesFileName = 'timetables.json';
  static const String settingsFileName = 'settings.json';

  /// 数据损坏 / 自动恢复时给用户看的白话提示（文件名与异常详情只打到 [debugPrint]）。
  static const String recoveryWarningText = '读取课表时出了点问题，已经尽量恢复';

  static void _addRecoveryWarning(List<String> warnings, String detail) {
    debugPrint('[Storage] $detail');
    if (!warnings.contains(recoveryWarningText)) {
      warnings.add(recoveryWarningText);
    }
  }

  /// 测试可覆盖的根目录；为 null 时使用应用文档目录。
  static Directory? overrideDirectory;

  static const Uuid _uuid = Uuid();

  /// 写队列：所有落盘操作排队执行。
  ///
  /// `AppState._commit()` 没有串行化（一次导入会连着触发 3~4 次），
  /// 多个写同时进行会互相踩临时文件。这里把写串起来，
  /// 调用方无需关心并发。
  static Future<void> _writeQueue = Future<void>.value();

  /// 临时文件序号，保证并发写不会用到同一个 `.tmp`。
  static int _tmpSeq = 0;

  static Future<void> _serialized(Future<void> Function() op) {
    // **整段必须在 root zone 里跑**。Future 完成时，唤醒监听者的微任务是用
    // *future 自己创建时所在的 zone* 调度的：如果 gate 建在调用方的 zone 里
    // （比如 flutter_test 的 fakeAsync，测试结束后就不再被 pump），
    // 队列的下一环永远不会被唤醒，之后所有 save 都不落盘。
    return Zone.root.run<Future<void>>(() {
      final previous = _writeQueue;
      final gate = Completer<void>();
      _writeQueue = gate.future;
      // gate 永远正常 complete、不带错误：一次写失败不能让后续写全被拒绝。
      // 错误仍然通过返回的 future 抛给调用方。
      return previous
          .then<void>((_) => op())
          .whenComplete(() => gate.complete());
    });
  }

  /// 等当前排队的写全部落盘。给测试和「退出前确保保存」用。
  static Future<void> flushPendingWrites() => _writeQueue;

  static Future<Directory> _baseDir() async {
    final override = overrideDirectory;
    if (override != null) {
      if (!await override.exists()) {
        await override.create(recursive: true);
      }
      return override;
    }
    return getApplicationDocumentsDirectory();
  }

  /// App 数据目录（`timetables.json` / `settings.json` 所在的目录）。
  ///
  /// 测试里设置了 [overrideDirectory] 就用它（不存在会先创建）；否则是
  /// `getApplicationDocumentsDirectory()`。其他需要落盘的小缓存
  /// （例如远程假日表 `holidays.remote.json`，v1.4.0）也放这里，
  /// 这样「清除 App 数据 / 卸载」能一并删掉。
  static Future<Directory> dataDirectory() => _baseDir();

  static Future<File> _file(String name) async =>
      File('${(await _baseDir()).path}${Platform.pathSeparator}$name');

  /// 读取全部数据。任何失败都会回退到默认值。
  static Future<StorageSnapshot> load() async {
    final warnings = <String>[];
    final timetables = await _loadTimetables(warnings);
    final settings = await _loadSettings(warnings);

    // 保证 currentTimetableId 指向真实存在的课表。
    if (timetables.isNotEmpty &&
        !timetables.any((t) => t.id == settings.currentTimetableId)) {
      settings.currentTimetableId = timetables.first.id;
    }
    return StorageSnapshot(
      timetables: timetables,
      settings: settings,
      warnings: warnings,
    );
  }

  static Future<List<Timetable>> _loadTimetables(List<String> warnings) async {
    try {
      final file = await _file(timetablesFileName);
      await _recoverFromTmp(file, warnings);
      if (!await file.exists()) return <Timetable>[];
      final text = await file.readAsString();
      if (text.trim().isEmpty) return <Timetable>[];
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        _addRecoveryWarning(warnings, 'timetables.json 顶层不是数组，已重置。');
        await _quarantine(file);
        return <Timetable>[];
      }
      final result = <Timetable>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          result.add(Timetable.fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          _addRecoveryWarning(warnings, '跳过了一条无法解析的课表数据：$e');
        }
      }
      return result;
    } catch (e) {
      _addRecoveryWarning(warnings, 'timetables.json 读取失败（$e），已回退到空课表列表。');
      try {
        await _quarantine(await _file(timetablesFileName));
      } catch (_) {
        // 隔离失败不影响主流程。
      }
      return <Timetable>[];
    }
  }

  static Future<AppSettings> _loadSettings(List<String> warnings) async {
    try {
      final file = await _file(settingsFileName);
      await _recoverFromTmp(file, warnings);
      if (!await file.exists()) return AppSettings.defaults();
      final text = await file.readAsString();
      if (text.trim().isEmpty) return AppSettings.defaults();
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        _addRecoveryWarning(warnings, 'settings.json 顶层不是对象，已重置为默认设置。');
        await _quarantine(file);
        return AppSettings.defaults();
      }
      return AppSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      _addRecoveryWarning(warnings, 'settings.json 读取失败（$e），已回退到默认设置。');
      try {
        await _quarantine(await _file(settingsFileName));
      } catch (_) {
        // 忽略。
      }
      return AppSettings.defaults();
    }
  }

  /// 写入全部数据。先写临时文件再 rename，避免写一半留下半截 JSON。
  static Future<void> save(
    List<Timetable> timetables,
    AppSettings settings,
  ) async {
    await saveTimetables(timetables);
    await saveSettings(settings);
  }

  /// 进队列之前先把「写什么」和「写到哪」都定下来：
  /// - `jsonEncode` 要在排队前做，排队期间数据还会被继续改，
  ///   队列跑到时再序列化就不是这一次 save 想写的内容了；
  /// - 目录也要在排队前解析好，不能把 `getApplicationDocumentsDirectory()`
  ///   （平台通道）留在队列里跑，那样一旦通道不可用整条队列就永久卡住。
  static Future<void> saveTimetables(List<Timetable> timetables) async {
    final content = jsonEncode(timetables.map((t) => t.toJson()).toList());
    final file = await _file(timetablesFileName);
    return _serialized(() => _writeAtomic(file, content));
  }

  static Future<void> saveSettings(AppSettings settings) async {
    final content = jsonEncode(settings.toJson());
    final file = await _file(settingsFileName);
    return _serialized(() => _writeAtomic(file, content));
  }

  /// 写临时文件再 `rename` 覆盖。
  ///
  /// `rename` 在 POSIX 与 Windows 上都是原子覆盖，**不要先 delete**
  /// —— 先删会造出「旧文件没了、新文件还没就位」的窗口，
  /// 这时候进程被杀（或掉电）课表就归零了。
  /// 临时文件名带自增序号，并发写不会互相踩。
  static Future<void> _writeAtomic(File file, String content) async {
    final tmp = File('${file.path}.${_tmpSeq++}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
  }

  /// [_writeAtomic] 的公开版本（v1.4.0，给 `HolidayRepository` 写缓存用）：
  /// 写临时文件再 `rename` 覆盖；失败时尽量删掉临时文件，再把异常抛给调用方。
  /// 不走 [_serialized] 写队列（那条队列只管课表 / 设置），调用方自己保证同一文件不并发写。
  static Future<void> writeAtomic(File file, String content) async {
    final tmp = File('${file.path}.${_tmpSeq++}.tmp');
    try {
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {
        // 清理失败不影响结果。
      }
      rethrow;
    }
  }

  /// 主文件不在、但留着 `<name>.<n>.tmp` 时，把最新的一个改名回来。
  ///
  /// 对应「写到一半被杀」的现场：`rename` 没来得及执行。
  /// 只在主文件缺失时才恢复，绝不覆盖已有数据。
  static Future<void> _recoverFromTmp(File file, List<String> warnings) async {
    try {
      if (await file.exists()) return;
      final dir = file.parent;
      if (!await dir.exists()) return;
      final base = file.uri.pathSegments.last;
      final candidates = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('$base.') && name.endsWith('.tmp')) {
          candidates.add(entity);
        }
      }
      if (candidates.isEmpty) return;
      candidates.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );
      await candidates.last.rename(file.path);
      _addRecoveryWarning(warnings, '$base 上次写入被中断，已从临时文件恢复。');
    } catch (_) {
      // 恢复失败就当没有这个文件，走默认值分支。
    }
  }

  static Future<void> _quarantine(File file) async {
    if (!await file.exists()) return;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    await file.rename('${file.path}.corrupt-$stamp');
  }

  /// 覆盖式恢复备份前先把现有课表另存一份，出事还能手工捞回来。
  ///
  /// 返回备份文件路径；没有现有数据或备份失败时返回 null（不影响主流程）。
  static Future<String?> backupBeforeRestore() async {
    try {
      final file = await _file(timetablesFileName);
      if (!await file.exists()) return null;
      final target =
          '${file.path}.before-restore-'
          '${DateTime.now().millisecondsSinceEpoch}';
      await file.copy(target);
      return target;
    } catch (_) {
      return null;
    }
  }

  /// 保证课表 / 课程 id 非空且不重复；重复的重新分配 uuid。
  ///
  /// 备份文件可能是手工拼的、或者由老版本（用微秒时间戳兜底 id）导出，
  /// 重复 id 会让第二张课表永远编辑不了（`_byId` 只找得到第一张）。
  static void normalizeIds(List<Timetable> timetables, List<String> warnings) {
    final seenTimetables = <String>{};
    var fixed = 0;
    for (final tt in timetables) {
      if (tt.id.isEmpty || !seenTimetables.add(tt.id)) {
        tt.id = _uuid.v4();
        seenTimetables.add(tt.id);
        fixed++;
      }
      final seenCourses = <String>{};
      for (final c in tt.courses) {
        if (c.id.isEmpty || !seenCourses.add(c.id)) {
          c.id = _uuid.v4();
          seenCourses.add(c.id);
          fixed++;
        }
      }
    }
    if (fixed > 0) {
      _addRecoveryWarning(warnings, '修复了 $fixed 个重复或缺失的 id。');
    }
  }

  /// 当前备份格式版本。
  ///
  /// - v1（1.0.0 ~ 1.2.0）：`{version: 1, exportedAt, timetables, settings}`；
  /// - v2（1.3.0）：顶层结构不变，课表多了 `schoolId / systemType / termCode /
  ///   importedAt`，学期配置多了 `overrides / breakAfter`，课程多了
  ///   `groupId / externalKey`，设置里一定带 `settingsVersion`。
  static const int backupVersion = 2;

  /// 导出为一个可分享的备份 JSON 字符串。
  static String exportJson(List<Timetable> timetables, AppSettings settings) {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'version': backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'timetables': timetables.map((t) => t.toJson()).toList(),
      'settings': settings.toJson(),
    });
  }

  /// 读备份顶层的 `version`；缺失 / 类型不对当 v1（1.0.0 起就写了 1）。
  static int backupVersionOf(Map<dynamic, dynamic> decoded) {
    final v = decoded['version'];
    if (v is int && v >= 1) return v;
    if (v is num && v >= 1) return v.toInt();
    if (v is String) {
      final parsed = int.tryParse(v.trim());
      if (parsed != null && parsed >= 1) return parsed;
    }
    return 1;
  }

  /// 备份 v1 → v2（纯函数，返回新 Map，不改入参）。
  ///
  /// - 每张课表走 [Timetable.migrateLegacyJson]：从课程的旧来源标记
  ///   （`zfsoft-shu`）补出 `systemType / schoolId`；
  /// - 设置缺 `settingsVersion`（1.0.x 导出的）时明确标成 1，
  ///   交给 [AppSettings.fromJson] 走一次性迁移；
  /// - 其余新字段（调休、休息带、分组……）在模型 `fromJson` 里有默认值，
  ///   这里不用补。
  static Map<String, dynamic> migrateBackupV1ToV2(Map<String, dynamic> v1) {
    final result = Map<String, dynamic>.from(v1);
    final rawTimetables = v1['timetables'];
    if (rawTimetables is List) {
      result['timetables'] = <dynamic>[
        for (final item in rawTimetables)
          item is Map
              ? Timetable.migrateLegacyJson(Map<String, dynamic>.from(item))
              : item,
      ];
    }
    final rawSettings = v1['settings'];
    if (rawSettings is Map) {
      final settings = Map<String, dynamic>.from(rawSettings);
      settings.putIfAbsent('settingsVersion', () => 1);
      result['settings'] = settings;
    }
    result['version'] = 2;
    return result;
  }

  /// 把任意版本的备份迁移到 [backupVersion]。
  ///
  /// 比当前版本还新的备份（用新版 App 导出、在旧版里导入）不拒收，
  /// 按当前结构尽量读，并写一条 warning。
  static Map<String, dynamic> migrateBackup(
    Map<String, dynamic> decoded,
    List<String> warnings,
  ) {
    final version = backupVersionOf(decoded);
    if (version > backupVersion) {
      _addRecoveryWarning(warnings, '备份来自更新版本的 App（格式 v$version），部分新数据可能无法读取。');
      return decoded;
    }
    var data = decoded;
    // 逐级迁移：以后加 v3 就在后面接一句 `if (version <= 2) ...`。
    if (version <= 1) data = migrateBackupV1ToV2(data);
    return data;
  }

  /// 解析备份 JSON；格式不对时抛 [FormatException]。
  static StorageSnapshot importJson(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map) {
      throw const FormatException('备份文件顶层不是对象');
    }
    final warnings = <String>[];
    final decoded = migrateBackup(Map<String, dynamic>.from(raw), warnings);
    final rawTimetables = decoded['timetables'];
    if (rawTimetables is! List) {
      throw const FormatException('备份文件缺少 timetables 数组');
    }
    // 单条坏数据只跳过那一条 + 记 warning，与 `_loadTimetables` 保持一致，
    // 不能因为一张课表坏了就让整份备份作废。
    final timetables = <Timetable>[];
    for (var i = 0; i < rawTimetables.length; i++) {
      final item = rawTimetables[i];
      if (item is! Map) {
        _addRecoveryWarning(warnings, '备份里第 ${i + 1} 条课表不是对象，已跳过。');
        continue;
      }
      try {
        timetables.add(Timetable.fromJson(Map<String, dynamic>.from(item)));
      } catch (e) {
        _addRecoveryWarning(warnings, '备份里第 ${i + 1} 条课表无法解析（$e），已跳过。');
      }
    }
    if (timetables.isEmpty && rawTimetables.isNotEmpty) {
      throw const FormatException('备份文件里没有一条可用的课表');
    }
    normalizeIds(timetables, warnings);

    final rawSettings = decoded['settings'];
    final settings = rawSettings is Map
        ? AppSettings.fromJson(Map<String, dynamic>.from(rawSettings))
        : AppSettings.defaults();
    if (timetables.isNotEmpty &&
        !timetables.any((t) => t.id == settings.currentTimetableId)) {
      settings.currentTimetableId = timetables.first.id;
    }
    return StorageSnapshot(
      timetables: timetables,
      settings: settings,
      warnings: warnings,
    );
  }
}
