import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../app_brand.dart';
import 'update_config.dart';

/// 读一个 URL 的文本内容。网络层抽出来是为了单测时换成假的。
///
/// 失败（超时、非 200、太大）要抛异常。
typedef UpdateFetch = Future<String> Function(Uri uri, Duration timeout);

/// `latest.json` 里描述的一个版本。
class UpdateInfo {
  final int versionCode;
  final String versionName;
  final String changelog;

  /// 只保留 http / https 地址，按文件里的顺序。
  final List<String> downloadUrls;

  /// APK 的 SHA-256（小写十六进制），没写为 null。
  final String? sha256;

  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    this.changelog = '',
    this.downloadUrls = const <String>[],
    this.sha256,
  });

  /// 第一个可用的下载地址；一个都没有时为 null。
  String? get firstDownloadUrl =>
      downloadUrls.isEmpty ? null : downloadUrls.first;

  /// 解析 `latest.json`。缺 `versionCode`（或不是正整数）、缺 `versionName` 时
  /// 抛 [FormatException]；其余字段容错。
  factory UpdateInfo.fromJson(Object? json) {
    if (json is! Map) throw const FormatException('latest.json 顶层不是对象');
    final rawCode = json['versionCode'];
    final code = rawCode is int
        ? rawCode
        : (rawCode is num
              ? rawCode.toInt()
              : (rawCode is String ? int.tryParse(rawCode.trim()) : null));
    if (code == null || code < 1) {
      throw const FormatException('latest.json 缺少有效的 versionCode');
    }
    final name = json['versionName'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('latest.json 缺少 versionName');
    }
    final rawLog = json['changelog'];
    final String changelog;
    if (rawLog is String) {
      changelog = rawLog.trim();
    } else if (rawLog is List) {
      changelog = rawLog.whereType<String>().map((l) => '· $l').join('\n');
    } else {
      changelog = '';
    }
    final urls = <String>[];
    final rawUrls = json['downloadUrls'];
    if (rawUrls is List) {
      for (final u in rawUrls) {
        if (u is! String) continue;
        final uri = Uri.tryParse(u.trim());
        if (uri == null || uri.host.isEmpty) continue;
        if (uri.scheme != 'https' && uri.scheme != 'http') continue;
        urls.add(u.trim());
      }
    }
    final rawSha = json['sha256'];
    final sha =
        rawSha is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(rawSha.trim())
        ? rawSha.trim().toLowerCase()
        : null;
    return UpdateInfo(
      versionCode: code,
      versionName: name.trim(),
      changelog: changelog,
      downloadUrls: urls,
      sha256: sha,
    );
  }
}

/// 一次检查的结论。
enum UpdateStatus {
  /// 更新源还是占位符，没有发请求。
  notConfigured,

  /// 已是最新（或远端版本不比本机新）。
  upToDate,

  /// 有新版本。
  available,

  /// 所有源都失败了。
  failed,
}

/// 一次检查的结果。
class UpdateCheckResult {
  final UpdateStatus status;

  /// [UpdateStatus.available] / [UpdateStatus.upToDate] 时是远端的版本信息。
  final UpdateInfo? info;

  /// 本机的 versionCode。
  final int? currentVersionCode;

  /// 成功读到 `latest.json` 的源。
  final String? source;

  /// 每个失败源的原因（按尝试顺序）。
  final List<String> errors;

  const UpdateCheckResult({
    required this.status,
    this.info,
    this.currentVersionCode,
    this.source,
    this.errors = const <String>[],
  });

  bool get hasUpdate => status == UpdateStatus.available;
}

/// 检查更新：依次尝试每个源（每源 [UpdateConfig.perSourceTimeout]），
/// 第一个能读到合法 `latest.json` 的源为准，和本机 versionCode 比较。
///
/// 不抛异常；网络错误都折成 [UpdateStatus.failed]。
class UpdateChecker {
  final List<String> sources;
  final Duration timeout;
  final UpdateFetch fetch;

  /// 本机的 versionCode（Android versionCode = pubspec `+` 后面的数）。
  final Future<int> Function() currentVersionCode;

  UpdateChecker({
    List<String>? sources,
    Duration? timeout,
    UpdateFetch? fetch,
    Future<int> Function()? currentVersionCode,
  }) : sources = sources ?? UpdateConfig.sources,
       timeout = timeout ?? UpdateConfig.perSourceTimeout,
       fetch = fetch ?? httpFetch,
       currentVersionCode = currentVersionCode ?? platformVersionCode;

  /// 更新源是否已配置（没有 `OWNER/REPO` 占位符）。
  bool get isConfigured => UpdateConfig.sourcesConfigured(sources);

  Future<UpdateCheckResult> check() async {
    if (!isConfigured) {
      return const UpdateCheckResult(status: UpdateStatus.notConfigured);
    }
    final current = await currentVersionCode();
    final errors = <String>[];
    for (final source in sources) {
      final uri = Uri.tryParse(source);
      if (uri == null) {
        errors.add('$source：地址无效');
        continue;
      }
      try {
        final body = await fetch(uri, timeout).timeout(timeout);
        final info = UpdateInfo.fromJson(jsonDecode(body));
        return UpdateCheckResult(
          status: isNewer(info.versionCode, current)
              ? UpdateStatus.available
              : UpdateStatus.upToDate,
          info: info,
          currentVersionCode: current,
          source: source,
          errors: errors,
        );
      } on TimeoutException {
        errors.add('${uri.host}：超时');
      } on FormatException catch (e) {
        errors.add('${uri.host}：${e.message}');
      } catch (e) {
        errors.add('${uri.host}：$e');
      }
    }
    return UpdateCheckResult(
      status: UpdateStatus.failed,
      currentVersionCode: current,
      errors: errors,
    );
  }

  /// 远端 versionCode 是否比本机新。本机读不到（<= 0）时不提示更新。
  static bool isNewer(int remote, int current) =>
      current > 0 && remote > current;

  /// 自动检查的节流：已同意隐私说明、更新源已配置、今天（本地日历日）还没查过。
  /// 上次检查时间在「未来」（改过系统时间）也允许再查。
  static bool shouldAutoCheck({
    required bool privacyAccepted,
    required bool configured,
    required DateTime? lastCheck,
    required DateTime now,
  }) {
    if (!privacyAccepted || !configured) return false;
    if (lastCheck == null) return true;
    if (lastCheck.isAfter(now)) return true;
    return lastCheck.year != now.year ||
        lastCheck.month != now.month ||
        lastCheck.day != now.day;
  }

  /// 本机 versionCode：`package_info_plus` 的 buildNumber。
  static Future<int> platformVersionCode() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// 默认网络实现：`dart:io` 的 [HttpClient]，只允许 https，
  /// 连接 + 读完都在 [timeout] 内，非 200 / 超过 [UpdateConfig.maxResponseBytes] 抛异常。
  static Future<String> httpFetch(Uri uri, Duration timeout) async {
    if (uri.scheme != 'https') {
      throw const HttpException('只允许 https 更新源');
    }
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = '${AppBrand.slug}-update-check';
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > UpdateConfig.maxResponseBytes) {
          throw const HttpException('latest.json 太大');
        }
      }
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      client.close(force: true);
    }
  }
}
