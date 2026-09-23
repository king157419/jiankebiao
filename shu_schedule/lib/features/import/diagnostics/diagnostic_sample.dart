import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../settings/about_page.dart' show appVersion;
import 'redact.dart';

/// 生成诊断样本需要的原料。所有字段都可以为空，写文件前统一脱敏。
class DiagnosticInput {
  final String? schoolId;
  final String? schoolName;
  final String? systemType;

  /// 验证状态标签（已验证 / 社区 / 实验）。
  final String? status;

  /// 导出时 WebView 所在的地址。
  final String? url;

  /// 出错的阶段 / 错误信息（成功导入时为 null）。
  final String? stage;
  final String? error;

  /// 抓取脚本回传的原始消息（含课表接口响应；出错时含 `sample`）。
  final String? response;

  /// 当前页面的 HTML 快照（可选）。
  final String? pageHtml;

  /// 额外要抹掉的字面量，例如解析出来的学生姓名。
  final List<String> secrets;

  const DiagnosticInput({
    this.schoolId,
    this.schoolName,
    this.systemType,
    this.status,
    this.url,
    this.stage,
    this.error,
    this.response,
    this.pageHtml,
    this.secrets = const <String>[],
  });

  /// 有没有任何值得导出的原始数据。
  bool get hasPayload =>
      (response?.isNotEmpty ?? false) || (pageHtml?.isNotEmpty ?? false);
}

/// 诊断样本：生成（纯函数）+ 写临时文件并调起系统分享。
class DiagnosticSample {
  DiagnosticSample._();

  /// 每段原始数据最多保留的字节数（UTF-8）。
  static const int maxSectionBytes = 200 * 1024;

  /// 生成脱敏后的样本文本。先脱敏再截断，截断处不会漏出半个学号。
  static String build(
    DiagnosticInput input, {
    required DateTime now,
    String version = appVersion,
  }) {
    String clean(String? s) =>
        s == null ? '' : redactSensitive(s, extraSecrets: input.secrets);
    String section(String? s) => truncateUtf8(clean(s), maxSectionBytes);

    final b = StringBuffer()
      ..writeln('# 课表导入诊断样本')
      ..writeln('# 已在本机脱敏：8~12 位数字、11 位手机号、姓名字段替换为 $redactedMark。')
      ..writeln('# 每段原始数据最多保留前 ${maxSectionBytes ~/ 1024}KB。发送前可以先打开检查。')
      ..writeln('app: $version')
      ..writeln('time: ${now.toIso8601String()}')
      ..writeln(
        'school: ${clean(input.schoolId)} ${clean(input.schoolName)}'
            .trimRight(),
      )
      ..writeln('system: ${clean(input.systemType)}')
      ..writeln('status: ${clean(input.status)}')
      ..writeln('url: ${clean(input.url)}')
      ..writeln('stage: ${clean(input.stage)}')
      ..writeln('error: ${clean(input.error)}')
      ..writeln()
      ..writeln('----- response -----')
      ..writeln(section(input.response))
      ..writeln()
      ..writeln('----- page -----')
      ..writeln(section(input.pageHtml));
    return b.toString();
  }

  /// 样本文件名（只用 ASCII，避免个别分享目标处理不了中文文件名）。
  static String fileNameFor(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'import-diagnostic-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.txt';
  }

  /// 写到临时目录并调起系统分享面板。返回写出的文件路径。
  static Future<String> exportAndShare(DiagnosticInput input) async {
    final now = DateTime.now();
    final content = build(input, now: now);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}${fileNameFor(now)}',
    );
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: 'text/plain')],
        subject: '课表导入诊断样本',
        text: '课表导入诊断样本（已在本机脱敏，发送前可以先打开检查）',
      ),
    );
    return file.path;
  }
}
