import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_brand.dart';
import '../../core/app_state.dart';
import '../../core/storage.dart';
import '../../models/course.dart';
import '../../models/timetable.dart';

/// 分享出去的单张课表文件（给同学用）。
class SharedTimetableFile {
  final String fileName;
  final String json;

  const SharedTimetableFile({required this.fileName, required this.json});
}

/// 从文件导入课表的结果。
class TimetableImportOutcome {
  /// 新建出来的课表（已经写进 AppState，最后一张是当前课表）。
  final List<Timetable> created;

  /// 读文件时发现并已自动修复的问题。
  final List<String> warnings;

  const TimetableImportOutcome({required this.created, required this.warnings});
}

/// 单张课表的分享与导入（REVIEW-2 §4 的「同学之间离线分享」）。
///
/// 文件格式就是备份格式 v2 的子集：`{version: 2, kind: "timetable",
/// exportedAt, app, timetables: [一张]}`，**不带 settings**（主题、当前课表这些
/// 是分享者自己的偏好）。所以：
/// - 旧版（1.2.0 及以前）的完整备份、v1 格式的单表，都能用「从文件导入课表」读进来
///   （走 `Storage.importJson` 的 v1 → v2 迁移）；
/// - 反过来，这里导出的单表文件也能用「导入备份 → 合并」读。
class TimetableShare {
  TimetableShare._();

  /// 文件里 `kind` 字段的值。
  static const String kind = 'timetable';

  /// 选文件（测试替换）：返回文件文本，用户取消返回 null。
  @visibleForTesting
  static Future<String?> Function() pickText = _pickTextWithFilePicker;

  /// 分享文件（测试替换）。
  @visibleForTesting
  static Future<void> Function(SharedTimetableFile file) shareFile =
      _shareWithSystemSheet;

  /// 恢复默认的文件选择 / 分享实现（测试 tearDown 用）。
  @visibleForTesting
  static void resetIo() {
    pickText = _pickTextWithFilePicker;
    shareFile = _shareWithSystemSheet;
  }

  // ------------------------------------------------------------------ 导出

  /// 单表 JSON（纯函数）。
  static String exportJson(Timetable timetable, {DateTime? now}) {
    return const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'version': Storage.backupVersion,
      'kind': kind,
      'app': AppBrand.name,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'timetables': <dynamic>[timetable.toJson()],
    });
  }

  /// 文件名：`简课表-<课表名>-yyyyMMdd.json`（课表名里文件系统不允许的字符换成 `_`）。
  static String fileNameFor(Timetable timetable, DateTime date) {
    final ymd =
        '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    return '${AppBrand.name}-${safeFileName(timetable.name)}-$ymd.json';
  }

  /// 去掉文件名里的非法字符：`\ / : * ? " < > |` 和控制字符换成 `_`，
  /// 首尾空白与点去掉，最长 40 个字符；清完是空的就叫「课表」。
  static String safeFileName(String raw) {
    var s = raw.replaceAll(RegExp(r'[\/:*?"<>|\x00-\x1F]'), '_').trim();
    s = s.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    if (s.runes.length > 40) s = String.fromCharCodes(s.runes.take(40));
    return s.isEmpty ? '课表' : s;
  }

  /// 生成文件并调起系统分享。
  static Future<SharedTimetableFile> share(Timetable timetable) async {
    final now = DateTime.now();
    final file = SharedTimetableFile(
      fileName: fileNameFor(timetable, now),
      json: exportJson(timetable, now: now),
    );
    await shareFile(file);
    return file;
  }

  // ------------------------------------------------------------------ 导入

  /// 解析一个课表文件（单表文件 / 任意版本的完整备份都行），返回里面的课表。
  ///
  /// 格式不对抛 [FormatException]；一张课表都没有也算格式不对。
  static StorageSnapshot parse(String text) {
    final snapshot = Storage.importJson(text);
    if (snapshot.timetables.isEmpty) {
      throw const FormatException('文件里没有课表');
    }
    return snapshot;
  }

  /// 名字冲突时加后缀：`课表` → `课表（2）` → `课表（3）`……
  static String uniqueName(String name, Iterable<String> existing) {
    final base = name.trim().isEmpty ? '导入的课表' : name.trim();
    final taken = existing.toSet();
    if (!taken.contains(base)) return base;
    for (var i = 2; ; i++) {
      final candidate = '$base（$i）';
      if (!taken.contains(candidate)) return candidate;
    }
  }

  /// 把解析出的课表逐张**新建**进 [appState]（永远不覆盖现有课表），
  /// 名字冲突自动加后缀，最后一张成为当前课表。
  ///
  /// 课程 id 重新生成（同一个文件导两次也不会有两张课表共用课程 id）；
  /// `groupId` / `externalKey` / 导入元数据原样保留。
  static Future<List<Timetable>> importInto(
    AppState appState,
    StorageSnapshot snapshot,
  ) async {
    final created = <Timetable>[];
    for (final tt in snapshot.timetables) {
      final name = uniqueName(tt.name, appState.timetables.map((t) => t.name));
      final result = await appState.applyImport(
        overwriteId: null,
        name: name,
        courses: <Course>[
          for (final c in tt.courses) c.copyWith(id: appState.newId()),
        ],
        config: tt.config,
        schoolId: tt.schoolId,
        systemType: tt.systemType,
        termCode: tt.termCode,
        importedAt: tt.importedAt,
      );
      created.add(result);
    }
    return created;
  }

  /// 选文件 → 校验 → 新建。用户取消返回 null；文件不对抛 [FormatException]。
  static Future<TimetableImportOutcome?> pickAndImport(
    AppState appState,
  ) async {
    final text = await pickText();
    if (text == null) return null;
    final snapshot = parse(text);
    final created = await importInto(appState, snapshot);
    return TimetableImportOutcome(
      created: created,
      warnings: snapshot.warnings,
    );
  }

  // ------------------------------------------------------------ 默认 I/O

  static Future<String?> _pickTextWithFilePicker() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择课表文件（.json）',
      type: FileType.any,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<void> _shareWithSystemSheet(SharedTimetableFile shared) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${shared.fileName}');
    await file.writeAsString(shared.json, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/json')],
        subject: shared.fileName,
        text:
            '这是我在「${AppBrand.name}」里的课表。'
            '安装${AppBrand.name}后，在「设置 → 课表管理 → 从文件导入课表」里选这个文件即可。',
      ),
    );
  }
}
