import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'app_state.dart';
import 'holiday_presets.dart';
import 'repo_config.dart';
import 'storage.dart';
import 'update/update_checker.dart';
import 'update/update_config.dart';

/// 一次联网刷新假日表的结论。
enum HolidayRefreshStatus {
  /// 发布仓库还是占位符（`kRepo`），没有发请求。
  notConfigured,

  /// 24 小时内已经刷新过（且不是强制刷新），没有发请求。
  throttled,

  /// 下载到更新的数据，已写入本地缓存。
  updated,

  /// 远端数据不比当前用的新。
  unchanged,

  /// 所有地址都失败（网络、超时、太大、格式不对、SHA-256 不匹配、写缓存失败）。
  failed,
}

/// 一次刷新的结果。
class HolidayRefreshResult {
  final HolidayRefreshStatus status;

  /// [HolidayRefreshStatus.updated] 时是新数据；[HolidayRefreshStatus.unchanged] 时是当前数据。
  final HolidayPresets? presets;

  /// [HolidayRefreshStatus.updated] 时刷新前正在用的旧数据（触发点 (c) 对比本校条目有没变）。
  final HolidayPresets? previousPresets;

  /// 成功读到数据的地址。
  final Uri? source;

  /// 每个失败地址的原因（按尝试顺序），形如「cdn.jsdelivr.net：超时」——只有 host 和
  /// 简短原因，不带完整 URL（界面只显示第一条，见 [firstError]）。
  final List<String> errors;

  const HolidayRefreshResult(
    this.status, {
    this.presets,
    this.previousPresets,
    this.source,
    this.errors = const <String>[],
  });

  bool get isUpdated => status == HolidayRefreshStatus.updated;

  /// 第一条错误（SnackBar 只显示这一条，review-G P3-6）；没有错误时 null。
  String? get firstError => errors.isEmpty ? null : errors.first;
}

/// 假日表的来源与刷新（v1.4.0）。
///
/// - [load]：读安装包内置的 `assets/holidays.json`；如果本地缓存
///   `holidays.remote.json`（在 [Storage.dataDirectory]）存在、能解析、
///   `version == 1` 且 `updatedAt` 比内置的新，就**整体**用缓存（不逐条合并）。
/// - [refresh]：按 [RepoConfig.rawUrls] 的顺序（Gitee → jsDelivr → GitHub raw）下载
///   仓库里的 `shu_schedule/assets/holidays.json`，比当前数据新就原子写入缓存。
///   只在发布仓库已配置时联网；非强制刷新 24 小时最多一次。
///   `latest.json` 里有 `"holidays": {"sha256": …}` 时校验下载内容，没有就只依赖 TLS。
///   v1.4.0 修复轮：某个地址「不比当前新」时继续试后面的（镜像滞后不挡更新，P3-5）；
///   同一地址的 `latest.json` 与 `holidays.json` 并发取，整次刷新最多 [totalTimeout]（P3-4）；
///   只有成功（updated / unchanged）才记刷新时间（fixlist ①）。
class HolidayRepository {
  HolidayRepository({
    UpdateFetch? fetch,
    this.repo = kRepo,
    FutureOr<Directory> Function()? dirProvider,
    Future<HolidayPresets> Function()? loadBundled,
    this.timeout = UpdateConfig.perSourceTimeout,
    this.totalTimeout = defaultTotalTimeout,
    this.maxBytes = defaultMaxBytes,
  }) : fetch =
           fetch ??
           ((uri, t) => UpdateChecker.httpFetch(uri, t, maxBytes: maxBytes)),
       _dirProvider = dirProvider ?? Storage.dataDirectory,
       _loadBundled = loadBundled ?? HolidayPresets.loadBundled;

  /// 仓库里假日表的路径（相对仓库根目录）。
  static const String remotePath = 'shu_schedule/assets/holidays.json';

  /// 本地缓存文件名（在 [Storage.dataDirectory] 里）。
  static const String cacheFileName = 'holidays.remote.json';

  /// 假日表的下载上限（`latest.json` 是 64 KiB，这里放宽到 256 KiB）。
  static const int defaultMaxBytes = 256 * 1024;

  /// 非强制刷新的最短间隔。
  static const Duration refreshInterval = Duration(hours: 24);

  /// 一次刷新（所有地址加起来）最多等多久。断网时刷新按钮最多转这么久。
  static const Duration defaultTotalTimeout = Duration(seconds: 10);

  final RepoConfig repo;
  final UpdateFetch fetch;

  /// 单个地址的超时。
  final Duration timeout;

  /// 整次刷新的超时（[defaultTotalTimeout]）。
  final Duration totalTimeout;
  final int maxBytes;
  final FutureOr<Directory> Function() _dirProvider;
  final Future<HolidayPresets> Function() _loadBundled;

  /// 当前应该用的数据：缓存比内置新就用缓存，否则用内置。不抛异常。
  Future<HolidayPresets> load() async {
    HolidayPresets bundled;
    try {
      bundled = await _loadBundled();
    } catch (_) {
      bundled = HolidayPresets.empty;
    }
    final cached = await _readCache();
    if (cached != null && isNewer(cached, bundled)) return cached;
    return bundled;
  }

  /// [candidate] 的 `updatedAt` 是否比 [current] 的新（[current] 没有日期时，有日期就算新）。
  static bool isNewer(HolidayPresets candidate, HolidayPresets current) {
    final a = candidate.updatedAt;
    if (a == null) return false;
    final b = current.updatedAt;
    return b == null || a.isAfter(b);
  }

  /// 非强制刷新的节流：从没刷新过、上次时间在「未来」（改过系统时间）、
  /// 或者距上次已满 [interval] 才刷新。
  ///
  /// 这里比的是两个时间点之间真实流逝的时长（不是日历日期运算），
  /// 所以用 `difference` 没有夏令时问题。
  static bool shouldRefresh({
    required DateTime? lastRefresh,
    required DateTime now,
    Duration interval = refreshInterval,
  }) {
    if (lastRefresh == null) return true;
    if (lastRefresh.isAfter(now)) return true;
    return now.difference(lastRefresh) >= interval;
  }

  /// 联网刷新。顺序：未配置 → [HolidayRefreshStatus.notConfigured]；
  /// 24 小时内刷新过且非 [force] → [HolidayRefreshStatus.throttled]；
  /// 否则依次尝试每个地址：
  ///
  /// - 读到合法、比当前新的数据 → 写缓存，[HolidayRefreshStatus.updated]；
  /// - 读到合法但不比当前新 → **接着试下一个地址**（镜像可能滞后），都不比当前新 →
  ///   [HolidayRefreshStatus.unchanged]；
  /// - 一个合法的都没读到 → [HolidayRefreshStatus.failed]。
  ///
  /// 只有 updated / unchanged 才调用 [onSuccess]（调用方记下刷新时间）；失败不记，
  /// 下次打开 App 还会再试（fixlist ①）。
  ///
  /// 校验：[manifest] 是调用方已经拿到的 `latest.json`（自动检查更新之后顺带刷新时传入）。
  /// 不传时，每个地址的 `latest.json` 和 `holidays.json` **并发**去取，用同一个地址的
  /// `holidays.sha256` 校验；传了但对不上时（镜像滞后：manifest 来自还没同步的镜像），
  /// 再读一次这个地址自己的 `latest.json` 核对。一个校验值都拿不到时只依赖 TLS。
  /// 整次刷新不超过 [totalTimeout]。不抛异常。
  Future<HolidayRefreshResult> refresh({
    bool force = false,
    DateTime? now,
    DateTime? lastRefresh,
    FutureOr<void> Function(DateTime time)? onSuccess,
    UpdateInfo? manifest,
  }) async {
    if (repo.isPlaceholder) {
      return const HolidayRefreshResult(HolidayRefreshStatus.notConfigured);
    }
    final time = now ?? DateTime.now();
    if (!force && !shouldRefresh(lastRefresh: lastRefresh, now: time)) {
      return const HolidayRefreshResult(HolidayRefreshStatus.throttled);
    }

    final current = await load();
    // 真实流逝的时长（Stopwatch），不是日历运算。
    final clock = Stopwatch()..start();
    Duration remaining() => totalTimeout - clock.elapsed;

    final errors = <String>[];
    final holidayUrls = repo.rawUrls(remotePath);
    final latestUrls = repo.rawUrls(UpdateConfig.latestJsonPath);
    Uri? unchangedFrom;
    for (var i = 0; i < holidayUrls.length; i++) {
      final uri = holidayUrls[i];
      if (remaining() <= Duration.zero) {
        errors.add('${uri.host}：超时（整次刷新超过 ${totalTimeout.inSeconds} 秒）');
        continue;
      }
      final latestUri = i < latestUrls.length ? latestUrls[i] : null;
      try {
        // 没有现成的 manifest：这个地址的 latest.json 和 holidays.json 一起取。
        final latestFuture = manifest == null && latestUri != null
            ? _sha256From(latestUri, remaining())
            : null;
        final body = await _fetchBounded(uri, remaining());
        final bytes = utf8.encode(body);
        if (bytes.length > maxBytes) {
          throw FormatException('超过 ${maxBytes ~/ 1024} KiB');
        }
        final actual = crypto.sha256.convert(bytes).toString();
        final known = <String>{
          ?manifest?.holidaysSha256,
          if (latestFuture != null) ?await latestFuture,
        };
        if (known.isNotEmpty && !known.contains(actual)) {
          // 传入的 manifest 可能来自还没同步的镜像：再看这个地址自己的 latest.json。
          final own =
              manifest != null &&
                  latestUri != null &&
                  remaining() > Duration.zero
              ? await _sha256From(latestUri, remaining())
              : null;
          if (own != actual) {
            throw const FormatException('SHA-256 与 latest.json 不一致');
          }
        }
        final parsed = HolidayPresets.tryParseStrict(jsonDecode(body));
        if (parsed == null) {
          throw const FormatException('不是有效的假期表（version / updatedAt）');
        }
        if (!isNewer(parsed, current)) {
          unchangedFrom ??= uri;
          continue;
        }
        try {
          await Storage.writeAtomic(await _cacheFile(), body);
        } catch (e) {
          errors.add('写入本地缓存失败：${shortError(e)}');
          return HolidayRefreshResult(
            HolidayRefreshStatus.failed,
            errors: errors,
          );
        }
        await _report(onSuccess, time);
        return HolidayRefreshResult(
          HolidayRefreshStatus.updated,
          presets: parsed,
          previousPresets: current,
          source: uri,
          errors: errors,
        );
      } on TimeoutException {
        errors.add('${uri.host}：超时');
      } on FormatException catch (e) {
        errors.add('${uri.host}：${e.message}');
      } catch (e) {
        errors.add('${uri.host}：${shortError(e)}');
      }
    }
    if (unchangedFrom != null) {
      await _report(onSuccess, time);
      return HolidayRefreshResult(
        HolidayRefreshStatus.unchanged,
        presets: current,
        source: unchangedFrom,
        errors: errors,
      );
    }
    return HolidayRefreshResult(HolidayRefreshStatus.failed, errors: errors);
  }

  static Future<void> _report(
    FutureOr<void> Function(DateTime time)? onSuccess,
    DateTime time,
  ) async {
    try {
      await onSuccess?.call(time);
    } catch (_) {
      // 记不下时间不影响这次刷新的结果。
    }
  }

  /// 取一个地址，超时取「单个地址的超时」和「整次刷新剩下的时间」中较短的那个。
  Future<String> _fetchBounded(Uri uri, Duration remaining) {
    final t = remaining < timeout ? remaining : timeout;
    return fetch(uri, t).timeout(t);
  }

  /// 读 [uri]（某个地址的 `latest.json`）里的 `holidays.sha256`；读不到 / 没写 → null。
  Future<String?> _sha256From(Uri uri, Duration remaining) async {
    try {
      final body = await _fetchBounded(uri, remaining);
      return UpdateInfo.fromJson(jsonDecode(body)).holidaysSha256;
    } catch (_) {
      return null;
    }
  }

  /// 错误的简短说法（只给 host 后面那半句用）：`HttpException` 去掉完整 URL，
  /// 连不上 / TLS 失败换成中文，其余截到 60 个字符（review-G P3-6）。
  static String shortError(Object e) {
    if (e is HttpException) return e.message;
    if (e is SocketException) return '连不上服务器';
    if (e is HandshakeException || e is TlsException) return '安全连接失败';
    var text = e.toString();
    if (text.startsWith('Exception: ')) text = text.substring(11);
    return text.length > 60 ? '${text.substring(0, 60)}…' : text;
  }

  /// 用 [AppState] 里的上次刷新时间调用 [refresh]，成功（updated / unchanged）时
  /// 把这次的时间写回 `AppSettings.lastHolidayRefresh`。
  Future<HolidayRefreshResult> refreshFor(
    AppState appState, {
    bool force = false,
    DateTime? now,
    UpdateInfo? manifest,
  }) => refresh(
    force: force,
    now: now,
    lastRefresh: appState.settings.lastHolidayRefresh,
    onSuccess: appState.setLastHolidayRefresh,
    manifest: manifest,
  );

  Future<File> _cacheFile() async {
    final dir = await _dirProvider();
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$cacheFileName');
  }

  /// 读本地缓存；不存在、读不了、坏 JSON、版本不对、没有 `updatedAt` → null。
  Future<HolidayPresets?> _readCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      return HolidayPresets.tryParseStrict(
        jsonDecode(text),
        source: HolidayDataSource.remote,
      );
    } catch (_) {
      return null;
    }
  }
}
