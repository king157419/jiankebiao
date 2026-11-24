import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 要交给系统分享面板的一个文本文件。
class ShareFileRequest {
  /// 文件名（写进临时目录用的名字，也是对方收到的名字）。
  final String fileName;

  /// 文件内容，按 UTF-8 写出（不带 BOM）。
  final String content;

  /// MIME 类型，例如 `application/json`、`text/calendar`。
  final String mimeType;

  /// 分享标题（邮件主题等）；null = 用文件名。
  final String? subject;

  /// 附带的一段说明文字，可空。
  final String? text;

  const ShareFileRequest({
    required this.fileName,
    required this.content,
    required this.mimeType,
    this.subject,
    this.text,
  });
}

/// 把 [request] 写到临时目录，再调起系统分享面板（share_plus）。
///
/// 「导出到日历」（`IcsShare`）和「备份与恢复 → 导出备份文件」
/// （`BackupService.exportAndShare`）共用，两者的 `shareFile` 测试钩子默认都走这里。
/// 返回分享面板是否成功打开。
Future<bool> shareFileWithSystemSheet(ShareFileRequest request) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}${request.fileName}');
  await file.writeAsString(request.content, flush: true);
  final result = await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[XFile(file.path, mimeType: request.mimeType)],
      subject: request.subject ?? request.fileName,
      text: request.text,
    ),
  );
  return result.status != ShareResultStatus.unavailable;
}
