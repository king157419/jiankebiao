import 'dart:convert';

import '../../../core/presets.dart';
import '../../../models/course.dart';
import '../../../models/period_time.dart';
import '../../../models/timetable.dart';

/// 注入页面的 JS 回传消息所使用的 JavaScriptChannel 名字。
///
/// 页面脚本通过 `ShuImport.postMessage(JSON.stringify({...}))` 回传结果，
/// 因为 `runJavaScriptReturningResult` 拿不到 Promise（fetch）的结果。
const String importChannelName = 'ShuImport';

/// 一次导入过程中的阶段，用于进度文案与错误定位。
enum ImportStage {
  /// 正在读取课表查询页（拿学年/学期默认值，同时兼作登录检测）。
  indexPage,

  /// 正在读取首页文本（拿「第 N 周」）。
  week,

  /// 正在请求个人课表接口。
  schedule,

  /// 正在解析返回的数据。
  parse,

  /// 完成。
  done,
}

/// 阶段中文文案。
String importStageLabel(ImportStage stage) {
  switch (stage) {
    case ImportStage.indexPage:
      return '正在打开课表查询页…';
    case ImportStage.week:
      return '正在识别当前周次…';
    case ImportStage.schedule:
      return '正在请求个人课表…';
    case ImportStage.parse:
      return '正在解析课程数据…';
    case ImportStage.done:
      return '完成';
  }
}

/// 把脚本里回传的 stage 字符串映射成枚举；无法识别时返回 [ImportStage.parse]。
ImportStage importStageFromKey(Object? key) {
  switch (key) {
    case 'index':
      return ImportStage.indexPage;
    case 'week':
      return ImportStage.week;
    case 'kb':
    case 'schedule':
      return ImportStage.schedule;
    case 'done':
      return ImportStage.done;
    default:
      return ImportStage.parse;
  }
}

/// 通道消息的四种处理方式。
enum ChannelMessageKind {
  /// 不是我们认识的消息，忽略（通道对 WebView 里任意页面开放）。
  ignore,

  /// 进度消息，只更新文案。
  progress,

  /// 终态消息（`{ok:true|false, ...}`），结束等待。
  result,

  /// 诊断样本用的页面快照（`{diag:true, url, html}`），只在用户点
  /// 「导出诊断样本」时由我们自己注入的脚本发出。
  diagnostic,
}

/// 解析后的通道消息。
class ChannelMessage {
  final ChannelMessageKind kind;

  /// 进度消息携带的阶段；其它类型为 null。
  final ImportStage? stage;

  const ChannelMessage(this.kind, {this.stage});
}

/// 解析脚本通过 JavaScriptChannel 回传的一条消息。
///
/// **必须真的把 JSON 解出来判断**。早期版本用 `raw.contains('"progress"')`
/// 做判定，结果终态消息里只要有任何一门课的字段命中这个子串，
/// 整份课表数据就被当成进度消息丢掉，然后干等到 40 秒超时。
///
/// 通道对页面里的任意脚本开放，所以非 JSON、非对象、没有 `ok` 键的消息
/// 一律 [ChannelMessageKind.ignore]。
ChannelMessage parseChannelMessage(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const ChannelMessage(ChannelMessageKind.ignore);
  }
  if (decoded is! Map) return const ChannelMessage(ChannelMessageKind.ignore);
  if (decoded['diag'] == true) {
    return const ChannelMessage(ChannelMessageKind.diagnostic);
  }
  if (decoded['progress'] == true) {
    return ChannelMessage(
      ChannelMessageKind.progress,
      stage: importStageFromKey(decoded['stage']),
    );
  }
  if (!decoded.containsKey('ok')) {
    return const ChannelMessage(ChannelMessageKind.ignore);
  }
  return const ChannelMessage(ChannelMessageKind.result);
}

/// 导入失败。[message] 直接展示给用户，[suggestion] 是下一步建议。
class ImportException implements Exception {
  final String message;
  final ImportStage stage;
  final String? suggestion;

  const ImportException(
    this.message, {
    this.stage = ImportStage.parse,
    this.suggestion,
  });

  /// 会话失效 / 未登录。
  const ImportException.notLoggedIn({this.stage = ImportStage.schedule})
    : message = '未登录或登录会话已失效（教务系统返回了登录页）。',
      suggestion = '请在上方页面重新完成统一身份认证登录，回到教务首页后再点「一键导入课表」。';

  @override
  String toString() => 'ImportException($message)';
}

/// 一次导入的解析结果。
class ImportResult {
  /// 可以写进课表网格的课程。
  final List<Course> courses;

  /// 无固定上课时间的课程（正方的 `sjkList`）。不进网格，只在预览页展示。
  final List<Course> unscheduled;

  /// 规范化后的学期名，例如 `2026-2027 秋`。
  final String? termName;

  /// 教务系统原样给出的学期文本，例如 `2026-2027学年 第一学期`。
  final String? rawTermName;

  /// 学年学期代码，例如 `2026-2027-1`（写进 `Timetable.termCode`）。
  final String? termCode;

  /// 学生姓名（`xsxx.XM`），用于在预览页确认「导的是我的课表」。
  final String? studentName;

  /// 推断出的开学日期（第 1 周周一）。识别不到周次时为 null，
  /// 由预览页按学校校历给默认值、或问用户「现在是第几周？」（v1.5.0，`resolveTermStart`）。
  final DateTime? detectedStartDate;

  /// 从教务页面文本识别到的当前周次。
  final int? detectedCurrentWeek;

  /// 从教务页面识别出的作息（很多 HTML 课表表头写着「第1节 08:00-08:45」）。
  /// 拿不到时为 null，预览页按「当前课表作息 ?? 用户选模板」兜底。
  final List<PeriodTime>? detectedPeriods;

  /// 学校 id（[SchoolAdapter.id]）。
  final String? schoolId;

  /// 教务系统类型（[SchoolAdapter.systemType]）。
  final String? systemType;

  /// 解析过程中跳过 / 猜测 / 需要用户确认的事项。
  final List<String> warnings;

  const ImportResult({
    this.courses = const <Course>[],
    this.unscheduled = const <Course>[],
    this.termName,
    this.rawTermName,
    this.termCode,
    this.studentName,
    this.detectedStartDate,
    this.detectedCurrentWeek,
    this.detectedPeriods,
    this.schoolId,
    this.systemType,
    this.warnings = const <String>[],
  });

  bool get isEmpty => courses.isEmpty && unscheduled.isEmpty;

  /// 课程来源标记 `'<systemType>-<schoolId>'`，和 `Timetable.sourceTag` 同一规则。
  String? get sourceTag => (systemType != null && schoolId != null)
      ? Timetable.sourceTagOf(systemType!, schoolId!)
      : null;

  @override
  String toString() =>
      'ImportResult(${courses.length} 门课, ${unscheduled.length} 门无固定时间, '
      'term=$termName, week=$detectedCurrentWeek)';
}

/// 抓取方式。
enum CaptureMode {
  /// 已知接口地址，在登录后的页面里注入脚本主动 `fetch`（正方新版）。
  fetch,

  /// 用户自己点到课表页，App 解析当前页面 DOM（强智 / 树维 / 青果等，**尚未实现**）。
  currentPage,
}

/// 一个学校教务系统的适配器。
abstract class SchoolAdapter {
  /// 稳定 id，例如 `shu`。
  String get id;

  /// 展示名，例如 `某某大学`。
  String get name;

  /// 教务系统类型，例如 `zfsoft`。和 [id] 一起组成课程来源标记。
  String get systemType;

  /// 课程来源标记 `'<systemType>-<id>'`（`Timetable.sourceTagOf`）。
  String get sourceTag => Timetable.sourceTagOf(systemType, id);

  /// WebView 首次打开的地址（通常是教务门户，会自动跳统一身份认证）。
  String get loginUrl;

  /// 登录成功后应当回到的教务首页，失败时提示用户手动回到这里。
  String get homeUrl;

  /// 一句话说明，展示在学校列表里。
  String get description;

  /// 允许注入抓取脚本 / 判定为「已登录」的 host 列表（小写，不含端口）。
  List<String> get allowedHosts;

  /// WebView 使用的 User-Agent；null = 系统默认。
  String? get userAgent;

  /// 这所学校的学期预设（`schools.json` 里的校历），可空。没识别到周次时，预览页把
  /// 覆盖「今天」的那一期当作默认开学日期（和 `holidays.json` 的学校学期一起，
  /// 后者优先；v1.5.0，`resolveTermStart`）。
  List<TermPreset>? get presets;

  /// 作息模板 id（`periodTemplates`），可空。
  String? get periodProfileId;

  /// 抓取方式。目前只实现了 [CaptureMode.fetch]。
  CaptureMode get captureMode;

  /// 根据 WebView 当前 URL 判断是否已经登录进教务系统。
  bool isLoggedIn(String currentUrl);

  /// [url] 的 host 是否在 [allowedHosts] 里。
  bool isAllowedHost(String url) {
    final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
    return host.isNotEmpty && allowedHosts.contains(host);
  }

  /// 注入到页面里的抓取脚本。脚本通过 [importChannelName] 通道回传 JSON。
  String get scrapeScript;

  /// 解析脚本回传的 JSON。失败抛 [ImportException]。
  ImportResult parse(String rawJsonFromPage, {DateTime? now});
}
