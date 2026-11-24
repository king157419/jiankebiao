import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../core/app_brand.dart';
import '../../core/app_state.dart';
import '../../core/storage.dart';
import '../../models/timetable.dart';
import 'system_share.dart';

/// 备份导出 / 恢复（设置 →「备份与恢复」，v1.5.0 合并成一个入口）。
///
/// 导出：写一个临时文件再交给系统分享面板（share_plus）。
/// 恢复：file_picker 选文件 → `Storage.importJson` 校验 → 覆盖或合并。
/// 1.3 / 1.4 的「分享此课表」单表文件也是同一种格式（没有 settings），
/// 可以用「合并」读进来。
class BackupService {
  BackupService._();

  /// 选文件（测试替换）：返回文件文本，用户取消返回 null。
  @visibleForTesting
  static Future<String?> Function() pickText = _pickTextWithFilePicker;

  /// 分享文件（测试替换）：返回分享面板是否成功打开。
  @visibleForTesting
  static Future<bool> Function(ShareFileRequest request) shareFile =
      shareFileWithSystemSheet;

  /// 恢复默认的文件选择 / 分享实现（测试 tearDown 用）。
  @visibleForTesting
  static void resetIo() {
    pickText = _pickTextWithFilePicker;
    shareFile = shareFileWithSystemSheet;
  }

  /// 完整备份的文件名：`jiankebiao-backup-<时间戳>.json`（用 ASCII 短名，
  /// 有些网盘 / 电脑端对中文文件名不友好）。
  static String backupFileName(String stamp) =>
      '${AppBrand.slug}-backup-$stamp.json';

  /// 要分享的备份文件（[now] 只决定文件名里的时间戳）。
  static ShareFileRequest requestFor(AppState appState, {DateTime? now}) {
    final json = Storage.exportJson(appState.timetables, appState.settings);
    final stamp = (now ?? DateTime.now())
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    return ShareFileRequest(
      fileName: backupFileName(stamp),
      content: json,
      mimeType: 'application/json',
      subject: '${AppBrand.name}备份',
      text: '${AppBrand.name}数据备份（${appState.timetables.length} 张课表）',
    );
  }

  /// 导出并调起系统分享。返回分享面板是否成功打开。
  ///
  /// 写临时文件 + 分享面板走共用的 [shareFileWithSystemSheet]
  /// （和「导出到日历」同一份代码）。
  static Future<bool> exportAndShare(AppState appState, {DateTime? now}) =>
      shareFile(requestFor(appState, now: now));

  /// 选择并解析一个备份文件。
  ///
  /// 用户取消返回 null；文件非法抛 [FormatException]。
  static Future<StorageSnapshot?> pickAndParse() async {
    final text = await pickText();
    if (text == null) return null;
    return Storage.importJson(text);
  }

  /// 合并导入：保留现有课表，把备份里的课表追加进来。
  ///
  /// id 冲突时给一个新 id 并在名字后加「（导入）」，不覆盖现有数据。
  static Future<int> mergeInto(
    AppState appState,
    StorageSnapshot snapshot,
  ) async {
    var added = 0;
    for (final tt in snapshot.timetables) {
      final clash = appState.timetables.any((t) => t.id == tt.id);
      final Timetable toAdd = clash
          ? tt.copyWith(id: appState.newId(), name: '${tt.name}（导入）')
          : tt;
      await appState.addTimetable(toAdd, switchTo: false);
      added++;
    }
    return added;
  }

  static Future<String?> _pickTextWithFilePicker() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择备份文件',
      type: FileType.any,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}
