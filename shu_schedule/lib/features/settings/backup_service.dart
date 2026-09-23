import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_brand.dart';
import '../../core/app_state.dart';
import '../../core/storage.dart';
import '../../models/timetable.dart';

/// 备份导出 / 导入。
///
/// 导出：写一个临时 JSON 文件再交给系统分享面板（share_plus）。
/// 导入：file_picker 选文件 → `Storage.importJson` 校验 → 覆盖或合并。
class BackupService {
  BackupService._();

  /// 完整备份的文件名：`jiankebiao-backup-<时间戳>.json`（用 ASCII 短名，
  /// 有些网盘 / 电脑端对中文文件名不友好）。
  static String backupFileName(String stamp) =>
      '${AppBrand.slug}-backup-$stamp.json';

  /// 导出并调起系统分享。返回分享面板是否成功打开。
  static Future<bool> exportAndShare(AppState appState) async {
    final json = Storage.exportJson(appState.timetables, appState.settings);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final file = File(
      '${dir.path}${Platform.pathSeparator}${backupFileName(stamp)}',
    );
    await file.writeAsString(json, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'application/json')],
        subject: '${AppBrand.name}备份',
        text: '${AppBrand.name}数据备份（${appState.timetables.length} 张课表）',
      ),
    );
    return result.status != ShareResultStatus.unavailable;
  }

  /// 选择并解析一个备份文件。
  ///
  /// 用户取消返回 null；文件非法抛 [FormatException]。
  static Future<StorageSnapshot?> pickAndParse() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择备份 JSON 文件',
      type: FileType.any,
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return Storage.importJson(text);
  }

  /// 合并导入：保留现有课表，把备份里的课表追加进来。
  ///
  /// id 冲突时给一个新 id 并在名字后加「(导入)」，不覆盖现有数据。
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
}
