import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/presets.dart';
import '../../../core/schedule_utils.dart';
import '../../../models/course.dart';
import 'school_adapter.dart';

/// 正方教务（zfsoft `jwglxt`）通用适配器。
///
/// 国内大量高校的「教学管理信息服务平台」就是这套系统（内置清单里已验证的学校见 assets/schools.json）。
/// 学校之间的差异（根路径、入口页、允许的域名……）全部来自构造参数，
/// 由 `assets/schools.json` 或「我的学校不在列表」的网址推断生成。
class ZfsoftAdapter extends SchoolAdapter {
  /// 系统类型标识，写进 `Timetable.systemType` 与课程来源标记。
  static const String type = 'zfsoft';

  @override
  final String id;

  @override
  final String name;

  /// 教务系统根路径，例如 `https://jwxt.shu.edu.cn/jwglxt`（结尾不带 `/`）。
  final String baseUrl;

  /// 登录后回到的教务首页，例如 `https://jwxt.shu.edu.cn/`。
  @override
  final String homeUrl;

  /// WebView 首次打开的地址；不给时等于 [homeUrl]。
  final String? entryUrl;

  @override
  final String description;

  @override
  final List<String> allowedHosts;

  @override
  final String? userAgent;

  @override
  final List<TermPreset>? presets;

  @override
  final String? periodProfileId;

  ZfsoftAdapter({
    required this.id,
    required this.name,
    required String baseUrl,
    required this.homeUrl,
    this.entryUrl,
    this.description = '正方教务系统（jwglxt）',
    List<String>? allowedHosts,
    this.userAgent,
    this.presets,
    this.periodProfileId,
  }) : baseUrl = _trimSlash(baseUrl),
       allowedHosts = List<String>.unmodifiable(
         _normalizeHosts(allowedHosts, _trimSlash(baseUrl)),
       );

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// 小写、去重；空列表时退回 [baseUrl] 的 host。
  static List<String> _normalizeHosts(List<String>? hosts, String baseUrl) {
    final out = <String>[];
    for (final h in hosts ?? const <String>[]) {
      final v = h.trim().toLowerCase();
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }
    if (out.isEmpty) {
      final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
      if (host.isNotEmpty) out.add(host);
    }
    return out;
  }

  @override
  String get systemType => type;

  @override
  CaptureMode get captureMode => CaptureMode.fetch;

  @override
  String get loginUrl => entryUrl ?? homeUrl;

  /// 期望的教务系统域名（[baseUrl] 的 host）。
  String get expectedHost => Uri.parse(baseUrl).host.toLowerCase();

  /// 教务系统的路径前缀，例如 `/jwglxt/`。
  String get pathMarker {
    final p = Uri.parse(baseUrl).path;
    if (p.isEmpty || p == '/') return '/';
    return p.endsWith('/') ? p.toLowerCase() : '${p.toLowerCase()}/';
  }

  // ------------------------------------------------------------------ 登录判定

  @override
  bool isLoggedIn(String currentUrl) {
    final uri = Uri.tryParse(currentUrl.trim());
    if (uri == null || !uri.hasScheme) return false;
    if (!allowedHosts.contains(uri.host.toLowerCase())) return false;
    final path = uri.path.toLowerCase();
    // `pathMarker` 带尾斜杠（`/jwglxt/`），但教务首页常常就是 `/jwglxt`（无尾斜杠），
    // 只用 contains 判定会漏掉它，「一键导入」按钮会莫名其妙地灰着。
    final marker = pathMarker;
    final bare = marker.length > 1
        ? marker.substring(0, marker.length - 1)
        : marker;
    if (path != bare && !path.contains(marker)) return false;
    if (path.contains('login')) return false;
    return true;
  }

  // ------------------------------------------------------------------ 注入脚本

  @override
  String get scrapeScript => _scrapeTemplate
      .replaceAll('__BASE__', _jsString(baseUrl))
      .replaceAll('__CHANNEL__', importChannelName);

  /// 把字符串转义成可以安全放进 JS 单引号里的形式。
  static String _jsString(String raw) => raw
      .replaceAll('\\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');

  // -------------------------------------------------------------------- 解析

  @override
  ImportResult parse(String rawJsonFromPage, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final trimmed = rawJsonFromPage.trim();
    if (trimmed.isEmpty) {
      throw const ImportException(
        '教务系统没有返回任何数据。',
        stage: ImportStage.schedule,
        suggestion: '请回到教务首页（我的课表页面）后重试。',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      if (looksLikeLoginHtml(trimmed)) {
        throw const ImportException.notLoggedIn();
      }
      throw const ImportException(
        '教务系统返回的内容看不懂，可能还没登录成功。',
        stage: ImportStage.schedule,
        suggestion: '请确认已登录教务系统；若反复失败，可能是学校改了接口，需要更新 App。',
      );
    }
    if (decoded is! Map) {
      throw const ImportException('教务系统返回的数据格式无法识别。', stage: ImportStage.parse);
    }

    final envelope = Map<String, dynamic>.from(decoded);
    final payload = _unwrap(envelope);
    final kb = _asMap(payload['kb']) ?? payload;

    final warnings = <String>[];
    final xsxx = _asMap(kb['xsxx']) ?? const <String, dynamic>{};

    // ------- 学期
    var xnm = _str(payload['xnm']) ?? _str(xsxx['XNM']);
    var xqm = _str(payload['xqm']) ?? _str(xsxx['XQM']);
    if (xnm == null) {
      xnm = fallbackXnm(at);
      warnings.add('未能读取教务系统的学年默认值，已按当前日期推断为 $xnm 学年，请确认学期信息。');
    }
    xqm ??= defaultXqm;
    final termName = termNameOf(xnm, xqm);
    final rawTermName = _joinNonEmpty([
      _str(payload['xnmText']) ?? _str(xsxx['XNMC']),
      _str(payload['xqmText']) ?? _str(xsxx['XQMC']),
    ]);

    // ------- 课程
    final courses = _parseKbList(kb['kbList'], warnings);
    final unscheduled = _parseSjkList(kb['sjkList'], warnings);
    if (courses.isEmpty && unscheduled.isEmpty) {
      warnings.add('这个学期没有解析到任何课程。可能是学期选错了，或者课表尚未发布。');
    }

    // ------- 周次 / 开学日期
    int? currentWeek = _int(payload['currentWeek']);
    if (currentWeek != null &&
        (currentWeek < 1 || currentWeek > ScheduleUtils.maxWeek)) {
      currentWeek = null;
    }
    // 识别不到周次时不加 warning：预览页会按学校校历给默认值，或问「现在是第几周？」
    // （v1.5.0，PLAN-1.5 D8）。
    DateTime? detectedStartDate;
    if (currentWeek != null) {
      detectedStartDate = ScheduleUtils.addDays(
        ScheduleUtils.mondayOf(at),
        -(currentWeek - 1) * 7,
      );
    }

    // 正方的课表接口不带节次时刻，detectedPeriods 留空，由预览页兜底。
    return ImportResult(
      courses: courses,
      unscheduled: unscheduled,
      termName: termName,
      rawTermName: rawTermName,
      termCode: termCodeOf(xnm, xqm),
      studentName: _str(xsxx['XM']),
      detectedStartDate: detectedStartDate,
      detectedCurrentWeek: currentWeek,
      schoolId: id,
      systemType: systemType,
      warnings: warnings,
    );
  }

  /// 剥掉脚本的 `{ok, data, error, stage}` 信封；`ok:false` 直接抛异常。
  Map<String, dynamic> _unwrap(Map<String, dynamic> envelope) {
    // 直接把课表接口的原始响应丢进来也支持（方便测试与调试）。
    if (envelope.containsKey('kbList') ||
        envelope.containsKey('sjkList') ||
        envelope.containsKey('xsxx')) {
      return <String, dynamic>{'kb': envelope};
    }
    if (envelope['ok'] == false) {
      throw _errorFromScript(
        _str(envelope['error']),
        importStageFromKey(envelope['stage']),
      );
    }
    final data = _asMap(envelope['data']);
    if (data != null) return data;
    throw const ImportException(
      '教务系统返回的数据格式无法识别（缺少 data 字段）。',
      stage: ImportStage.parse,
    );
  }

  ImportException _errorFromScript(String? code, ImportStage stage) {
    if (code == '__LOGIN__') {
      return ImportException.notLoggedIn(stage: stage);
    }
    if (code == '__NOTJSON__') {
      return const ImportException(
        '教务系统返回的内容看不懂，可能还没登录成功。',
        stage: ImportStage.schedule,
        suggestion: '请回到教务首页确认能正常看到课表后重试。',
      );
    }
    if (code == '__NETWORK__') {
      return const ImportException(
        '请求教务接口失败，可能是登录已失效或网络不通。',
        stage: ImportStage.schedule,
        suggestion:
            '校外访问教务系统需要学校 VPN；也可能是登录会话过期了，'
            '点「回教务首页」重新登录一次再试。',
      );
    }
    if (code == 'JS timeout') {
      return const ImportException(
        '抓取超时，教务系统没有在 30 秒内响应。',
        stage: ImportStage.schedule,
        suggestion: '请检查网络（校外可能需要 VPN），稍后重试。',
      );
    }
    return ImportException(
      '抓取失败：${code ?? '未知错误'}',
      stage: stage,
      suggestion: '请回到教务首页（能看到自己的课表）后再点「一键导入课表」。',
    );
  }

  // ------------------------------------------------------------- kbList 解析

  List<Course> _parseKbList(Object? raw, List<String> warnings) {
    if (raw is! List) {
      if (raw != null) {
        debugPrint('[ZfsoftAdapter] kbList 字段不是数组：${raw.runtimeType}');
        warnings.add('课程列表格式异常，已忽略。');
      }
      return <Course>[];
    }
    // key -> 合并后的课程；用 LinkedHashMap 保持首次出现顺序。
    final merged = <String, _MergedCourse>{};
    var skippedNoName = 0;
    var skippedBadTime = 0;
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        debugPrint('[ZfsoftAdapter] 第 ${i + 1} 条课表记录不是对象');
        skippedNoName++;
        continue;
      }
      final m = Map<String, dynamic>.from(item);
      final name = _str(m['kcmc']);
      if (name == null) {
        debugPrint('[ZfsoftAdapter] 第 ${i + 1} 条课表记录缺少 kcmc');
        skippedNoName++;
        continue;
      }
      final day = _int(m['xqj']);
      if (day == null || day < 1 || day > 7) {
        debugPrint('[ZfsoftAdapter] 「$name」星期异常：xqj=${m['xqj']}');
        skippedBadTime++;
        continue;
      }
      final span = parsePeriodSpan(
        _str(m['jcs']),
        _str(m['jc']),
        warnings: warnings,
        courseName: name,
      );
      if (span == null) {
        debugPrint(
          '[ZfsoftAdapter] 「$name」节次无法解析：jcs=${m['jcs']}, jc=${m['jc']}',
        );
        skippedBadTime++;
        continue;
      }
      final weeks = ScheduleUtils.parseWeeksText(_str(m['zcd']));
      if (weeks.isEmpty) {
        debugPrint('[ZfsoftAdapter] 「$name」周次无法解析：zcd=${m['zcd']}');
        skippedBadTime++;
        continue;
      }
      final teacher = _cleanTeacher(_str(m['xm']));
      final location = _str(m['cdmc']);
      // 合并 key 带上教学班（jxbmc）：同名同老师同教室同节次但不同教学班的两条记录
      // 是两门不同的课，不能把周次并到一起。
      final classGroup = _str(m['jxbmc']) ?? '';
      final key =
          '$name|${teacher ?? ''}|${location ?? ''}|$day|'
          '${span.$1}|${span.$2}|$classGroup';
      final existing = merged[key];
      if (existing != null) {
        existing.weeks.addAll(weeks);
      } else {
        merged[key] = _MergedCourse(
          key: key,
          courseCode: _str(m['kch']),
          classGroup: classGroup,
          name: name,
          teacher: teacher,
          location: location,
          day: day,
          startPeriod: span.$1,
          endPeriod: span.$2,
          weeks: weeks.toSet(),
          note: _noteOf(m),
        );
      }
    }
    if (skippedNoName > 0) {
      warnings.add('有 $skippedNoName 条记录缺少课程名，已跳过。');
    }
    if (skippedBadTime > 0) {
      warnings.add('有 $skippedBadTime 节课的时间看不懂，已跳过，可以手动补上。');
    }

    final result = <Course>[];
    final usedKeys = <String>{};
    var ordinal = 0;
    for (final mc in merged.values) {
      // 同一门课（课程号 + 教学班）的几个时段共用一个 groupId，改颜色时一起改。
      final groupBase = '${mc.courseCode ?? mc.name}|${mc.classGroup}';
      var externalKey =
          '$groupBase|${mc.day}|${mc.startPeriod}-${mc.endPeriod}';
      // 同一时段换教室 / 换老师会拆成两条，外部键加序号保证唯一。
      if (!usedKeys.add(externalKey)) {
        var n = 2;
        while (!usedKeys.add('$externalKey#$n')) {
          n++;
        }
        externalKey = '$externalKey#$n';
      }
      result.add(
        Course(
          id: _courseId(ordinal, mc.key),
          name: mc.name,
          teacher: mc.teacher,
          location: mc.location,
          day: mc.day,
          startPeriod: mc.startPeriod,
          endPeriod: mc.endPeriod,
          weeks: mc.weeks.toList(),
          colorIndex: colorIndexFor(mc.name),
          note: mc.note,
          source: sourceTag,
          groupId: '$sourceTag-g-${stableHash(groupBase).toRadixString(16)}',
          externalKey: externalKey,
        ),
      );
      ordinal++;
    }
    result.sort((a, b) {
      final d = a.day.compareTo(b.day);
      return d != 0 ? d : a.startPeriod.compareTo(b.startPeriod);
    });
    return result;
  }

  // ------------------------------------------------------------ sjkList 解析

  List<Course> _parseSjkList(Object? raw, List<String> warnings) {
    if (raw is! List) return <Course>[];
    final result = <Course>[];
    var ordinal = 0;
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final name = _str(m['kcmc']);
      if (name == null) {
        warnings.add('有一条「无固定时间」的记录没有课程名，已忽略。');
        continue;
      }
      final weeksText = _str(m['zcd']) ?? _str(m['qsjsz']);
      result.add(
        Course(
          id: _courseId(ordinal, 'sjk|$name', prefix: 'sjk'),
          name: name,
          teacher: _cleanTeacher(_str(m['xm'])),
          location: _str(m['cdmc']),
          day: 0,
          startPeriod: 0,
          endPeriod: 0,
          weeks: ScheduleUtils.parseWeeksText(weeksText),
          colorIndex: colorIndexFor(name),
          note: _noteOf(m),
          source: sourceTag,
          externalKey:
              'sjk|${_str(m['kch']) ?? name}|${_str(m['jxbmc']) ?? ''}',
        ),
      );
      ordinal++;
    }
    return result;
  }

  // ------------------------------------------------------------------ 小工具

  /// 学期字段默认值：秋季学期。
  static const String defaultXqm = '3';

  String _courseId(int ordinal, String key, {String prefix = 'kb'}) =>
      '$sourceTag-$prefix-$ordinal-'
      '${stableHash(key).toRadixString(16)}';

  /// 课程名 → 稳定的颜色索引 0..9（同名课永远同色，重装 App 也一样）。
  static int colorIndexFor(String name) => stableHash(name) % 10;

  /// FNV-1a 风格的 32 位稳定哈希（与平台/运行次数无关）。
  static int stableHash(String input) {
    var h = 2166136261;
    for (final unit in input.codeUnits) {
      h ^= unit;
      h = (h * 16777619) & 0x7fffffff;
    }
    return h;
  }

  /// 从 `jcs`（"1-2"）与 `jc`（"1-2节"）解析起止节次；都解析不出时返回 null。
  ///
  /// 两个字段不一致时取**跨度更大**的那个（宁可多占一格也别把课截短），
  /// 并写一条 warning 让用户去核对。
  static (int, int)? parsePeriodSpan(
    String? jcs,
    String? jc, {
    List<String>? warnings,
    String? courseName,
  }) {
    final fromJcs = _spanOf(jcs);
    final fromJc = _spanOf(jc);
    if (fromJcs == null) return fromJc;
    if (fromJc == null) return fromJcs;
    if (fromJcs == fromJc) return fromJcs;
    final chosen = (fromJc.$2 - fromJc.$1) > (fromJcs.$2 - fromJcs.$1)
        ? fromJc
        : fromJcs;
    debugPrint(
      '[ZfsoftAdapter] 「${courseName ?? '某门课'}」节次不一致：jcs=$jcs, jc=$jc',
    );
    warnings?.add(
      '「${courseName ?? '某门课'}」的上课节次信息不一致，'
      '已按跨度更大的第 ${chosen.$1}-${chosen.$2} 节处理，请核对。',
    );
    return chosen;
  }

  /// 从一段文本里抠出起止节次；抠不出返回 null。
  static (int, int)? _spanOf(String? raw) {
    if (raw == null) return null;
    final nums = RegExp(r'\d+')
        .allMatches(raw)
        .map((m) => int.parse(m.group(0)!))
        .toList();
    if (nums.isEmpty) return null;
    var start = nums.first;
    var end = nums.length > 1 ? nums[1] : nums.first;
    if (start > end) {
      final tmp = start;
      start = end;
      end = tmp;
    }
    if (start < 1 || start > maxPeriod) return null;
    if (end > maxPeriod) end = maxPeriod;
    return (start, end);
  }

  /// 允许的最大节次，防御脏数据。
  static const int maxPeriod = 30;

  /// 按当前日期推断学年起始年：9 月及以后算今年，否则算去年。
  static String fallbackXnm(DateTime at) =>
      (at.month >= 9 ? at.year : at.year - 1).toString();

  /// `xnm=2026, xqm=3` → `2026-2027 秋`。
  static String? termNameOf(String? xnm, String? xqm) {
    const seasons = <String, String>{'3': '秋', '12': '春', '16': '夏'};
    final season = seasons[xqm?.trim()];
    final startYear = int.tryParse((xnm ?? '').trim());
    if (startYear == null) return season;
    final years = '$startYear-${startYear + 1}';
    return season == null ? years : '$years $season';
  }

  /// `xnm=2026, xqm=3` → `2026-2027-1`；学期码不认识时原样拼在后面。
  static String? termCodeOf(String? xnm, String? xqm) {
    final startYear = int.tryParse((xnm ?? '').trim());
    if (startYear == null) return null;
    const order = <String, String>{'3': '1', '12': '2', '16': '3'};
    final q = xqm?.trim() ?? '';
    final suffix = order[q] ?? q;
    final years = '$startYear-${startYear + 1}';
    return suffix.isEmpty ? years : '$years-$suffix';
  }

  /// `yyyy-MM-dd`。
  static String formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// 粗略判断一段文本是不是登录页 HTML。
  static bool looksLikeLoginHtml(String text) {
    final head = text.length > 6000 ? text.substring(0, 6000) : text;
    if (!head.contains('<')) return false;
    final lower = head.toLowerCase();
    return lower.contains('login') ||
        lower.contains('authserver') ||
        lower.contains('newsso') ||
        head.contains('统一身份认证') ||
        head.contains('用户登录') ||
        head.contains('账号登录');
  }

  static String? _noteOf(Map<String, dynamic> m) {
    final parts = <String>[];
    final classroom = _str(m['jxbmc']);
    if (classroom != null) parts.add(classroom);
    final campus = _str(m['xqmc']);
    if (campus != null) parts.add(campus);
    final time = _str(m['sksj']);
    if (time != null) parts.add(time);
    final remark = _str(m['sjkcsm']) ?? _str(m['kcxz']);
    if (remark != null) parts.add(remark);
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 正方的 `xm` 偶尔是 `张三,李四` 或带多余空白。
  static String? _cleanTeacher(String? raw) {
    if (raw == null) return null;
    final cleaned = raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('，', ',')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static String? _joinNonEmpty(List<String?> parts) {
    final kept = parts.whereType<String>().where((s) => s.trim().isNotEmpty);
    if (kept.isEmpty) return null;
    return kept.join(' ');
  }

  static Map<String, dynamic>? _asMap(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : null;

  static String? _str(Object? v) {
    if (v == null) return null;
    final s = v is String ? v : v.toString();
    final trimmed = s.trim();
    if (trimmed.isEmpty || trimmed == 'null') return null;
    return trimmed;
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }
}

class _MergedCourse {
  final String key;
  final String? courseCode;
  final String classGroup;
  final String name;
  final String? teacher;
  final String? location;
  final int day;
  final int startPeriod;
  final int endPeriod;
  final Set<int> weeks;
  final String? note;

  _MergedCourse({
    required this.key,
    required this.courseCode,
    required this.classGroup,
    required this.name,
    required this.teacher,
    required this.location,
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    required this.note,
  });
}

/// 注入 WebView 的抓取脚本模板。
///
/// 要点（见 PLAN §0.1）：
/// - `fetch` 是异步的，`runJavaScriptReturningResult` 拿不到 Promise 结果，
///   所以结果一律通过 `__CHANNEL__.postMessage` 回传。
/// - 全程用 Promise 链而不是 async/await，兼容老版本 Android System WebView。
/// - **字符串与正则里的中文一律写成 `\uXXXX`**，避免脚本经过 `runJavaScript`
///   时的编码问题（注释里的中文不参与运行，保留可读性）。
/// - 每一步都 catch，并把 stage 写进回传消息。
const String _scrapeTemplate = r'''
(function () {
  var BASE = '__BASE__';
  /* SSO 回跳有可能把页面落在 http:// 上（同域但不同 scheme）。
     此时从 http 源 fetch https 的 BASE 是跨源请求，会被 CORS 打掉。
     域名一致就把 BASE 改写成「当前文档的源 + 原来的路径」。 */
  try {
    var _a = document.createElement('a'); _a.href = BASE;
    if (_a.hostname && _a.hostname.toLowerCase() === location.hostname.toLowerCase()) {
      BASE = location.protocol + '//' + location.host + _a.pathname.replace(/\/$/, '');
    }
  } catch (e) {}
  var done = false;
  function post(o) { try { __CHANNEL__.postMessage(JSON.stringify(o)); } catch (e) {} }
  function progress(s) { if (!done) post({ progress: true, stage: s }); }
  /* sample：出错时顺带回传拿到的原始响应（前 200KB），只用于用户主动导出的
     诊断样本，App 端写文件前会先在本机脱敏。 */
  function fail(s, e, sample) {
    if (done) return;
    done = true;
    var m;
    try { m = (e && e.message) ? String(e.message) : String(e); } catch (x) { m = 'unknown error'; }
    var o = { ok: false, stage: s, error: m };
    if (sample) { try { o.sample = String(sample).substring(0, 204800); } catch (x) { } }
    post(o);
  }
  function succeed(d) {
    if (done) return;
    done = true;
    post({ ok: true, stage: 'done', data: d });
  }
  function looksLikeLogin(t) {
    if (!t) return false;
    var s = String(t);
    if (s.length > 6000) s = s.substring(0, 6000);
    if (s.indexOf('<') < 0) return false;
    var lower = s.toLowerCase();
    return lower.indexOf('login') >= 0
      || lower.indexOf('authserver') >= 0
      || lower.indexOf('newsso') >= 0
      || s.indexOf('\u7edf\u4e00\u8eab\u4efd\u8ba4\u8bc1') >= 0
      || s.indexOf('\u7528\u6237\u767b\u5f55') >= 0
      || s.indexOf('\u8d26\u53f7\u767b\u5f55') >= 0;
  }
  /* 401/403，或者被 302 到教务域名之外（统一身份认证），都算「没登录」。
     不看这两项的话，跨源 302 会让 fetch 直接 reject，
     最后被当成网络故障报出去，用户完全看不懂。 */
  function checkLogin(r) {
    if (r.status === 401 || r.status === 403) { throw { __login: true }; }
    if (('redirected' in r) && r.redirected && String(r.url).indexOf(BASE) !== 0) {
      throw { __login: true };
    }
    return r;
  }
  /* 正方少数站点仍是 GBK；Response.text() 一律按 UTF-8 解，
     那样「第 N 周」永远匹配不到。按 content-type 走 TextDecoder。 */
  function decodeBody(r) {
    var ct = '';
    try { ct = String(r.headers.get('content-type') || '').toLowerCase(); } catch (e) { ct = ''; }
    if (ct.indexOf('gb') >= 0 && typeof TextDecoder !== 'undefined') {
      return r.arrayBuffer().then(function (buf) {
        try { return new TextDecoder('gbk').decode(buf); }
        catch (e) {
          try { return new TextDecoder('gb18030').decode(buf); }
          catch (e2) { return ''; }
        }
      });
    }
    return r.text();
  }
  function getText(url) {
    return fetch(url, {
      credentials: 'include',
      headers: { 'X-Requested-With': 'XMLHttpRequest' }
    }).then(checkLogin).then(decodeBody);
  }
  /* 「当前第 N 周」优先，其次「本周…第 N 周」，最后才是宽松匹配。
     页面上常有「第1周-第18周」这种范围文本，直接宽松匹配会抓到 1，
     开学日期整体偏移。strict = true 时不做宽松匹配。 */
  function matchWeek(t, strict) {
    var s = String(t);
    var m = s.match(/\u5f53\u524d[^0-9]{0,6}\u7b2c\s*(\d+)\s*\u5468/);
    if (!m) m = s.match(/\u672c\s*\u5468[^0-9]{0,4}\u7b2c\s*(\d+)\s*\u5468/);
    if (!m && !strict) m = s.match(/\u7b2c\s*(\d+)\s*\u5468/);
    return m ? parseInt(m[1], 10) : null;
  }
  function selectedOption(doc, id) {
    var sel = doc.querySelector('#' + id);
    if (!sel) return null;
    var opt = sel.querySelector('option[selected]');
    if (!opt) {
      var all = sel.querySelectorAll('option');
      if (all && all.length) opt = all[0];
    }
    if (!opt) return null;
    var v = opt.getAttribute('value');
    var t = opt.textContent || '';
    return { value: v ? String(v).trim() : '', text: t.replace(/\s+/g, ' ').trim() };
  }

  var now = new Date();
  var out = {
    xnm: String((now.getMonth() + 1) >= 9 ? now.getFullYear() : now.getFullYear() - 1),
    xqm: '3',
    xnmText: null,
    xqmText: null,
    currentWeek: null,
    weekSource: null,
    kb: null
  };

  setTimeout(function () { fail('kb', 'JS timeout'); }, 30000);

  progress('index');
  getText(BASE + '/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default')
    .then(function (html) {
      if (looksLikeLogin(html)) { throw { __login: true }; }
      try {
        var doc = new DOMParser().parseFromString(html, 'text/html');
        var a = selectedOption(doc, 'xnm');
        var b = selectedOption(doc, 'xqm');
        if (a && a.value) { out.xnm = a.value; out.xnmText = a.text; }
        if (b && b.value) { out.xqm = b.value; out.xqmText = b.text; }
      } catch (e) { /* 读不到 select 就用推断出来的默认值 */ }
    })
    .catch(function (e) {
      if (e && e.__login) { throw e; }
      /* 网络抖动不致命，继续用默认学期 */
    })
    .then(function () {
      progress('week');
      /* 第三条（v1.5.0）：正方部分部署把「第 N 周」放在首页的这个区块里。
         这个区块没人核对过，只认「当前 / 本周 第 N 周」的写法（strict），
         免得把「第1周-第18周」当成第 1 周、顶掉更可靠的学校校历。 */
      var urls = [
        { u: BASE + '/xtgl/index_initMenu.html', strict: false },
        { u: BASE + '/xtgl/index_cxAreaSix.html?localeKey=zh_CN&gnmkdm=index', strict: false },
        { u: BASE + '/xtgl/index_cxshjdAreaFive.html?localeKey=zh_CN&gnmkdm=index', strict: true }
      ];
      var chain = Promise.resolve();
      urls.forEach(function (item) {
        chain = chain.then(function () {
          if (out.currentWeek) return null;
          return getText(item.u).then(function (t) {
            var w = matchWeek(t, item.strict);
            if (w) { out.currentWeek = w; out.weekSource = item.u; }
          }).catch(function () { });
        });
      });
      return chain;
    })
    .then(function () {
      progress('kb');
      var body = 'xnm=' + encodeURIComponent(out.xnm)
        + '&xqm=' + encodeURIComponent(out.xqm)
        + '&kzlx=ck&xsdm=';
      return fetch(BASE + '/kbcx/xskbcx_cxXsgrkb.html?gnmkdm=N2151', {
        method: 'POST',
        credentials: 'include',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json, text/javascript, */*; q=0.01'
        },
        body: body
      }).then(checkLogin).then(decodeBody);
    })
    .then(function (txt) {
      if (done) return;
      var json = null;
      try { json = JSON.parse(txt); } catch (e) { json = null; }
      if (json === null || typeof json !== 'object') {
        if (looksLikeLogin(txt)) { fail('kb', '__LOGIN__', txt); return; }
        fail('kb', '__NOTJSON__', txt);
        return;
      }
      out.kb = json;
      succeed(out);
    })
    .catch(function (e) {
      if (e && e.__login) { fail('index', '__LOGIN__'); return; }
      /* fetch 在跨源/断网时 reject 的是 TypeError('Failed to fetch')，
         它不是「接口变了」，而是登录失效或网络不通。 */
      var isNet = e && (e.name === 'TypeError'
        || String(e).indexOf('Failed to fetch') >= 0);
      fail('kb', isNet ? '__NETWORK__' : e);
    });
})();
''';
