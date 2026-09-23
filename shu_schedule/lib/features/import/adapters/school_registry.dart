import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../../../core/presets.dart';
import 'school_adapter.dart';
import 'zfsoft_adapter.dart';

/// 学校适配的验证状态（学校选择页上的标签）。
enum SchoolStatus {
  /// 开发者自己用真实账号跑通过。
  verified,

  /// 社区用户报告可用，开发者没有亲自验证。
  community,

  /// 按系统类型套用的通用适配，没有人验证过。
  experimental;

  /// 界面上的中文标签。
  String get label {
    switch (this) {
      case SchoolStatus.verified:
        return '已验证';
      case SchoolStatus.community:
        return '社区';
      case SchoolStatus.experimental:
        return '实验';
    }
  }

  /// JSON 字符串 → 枚举；不认识的一律当 [experimental]（宁可低报）。
  static SchoolStatus parse(Object? raw) {
    switch (raw) {
      case 'verified':
        return SchoolStatus.verified;
      case 'community':
        return SchoolStatus.community;
      default:
        return SchoolStatus.experimental;
    }
  }
}

/// `assets/schools.json` 里的一条学校记录（纯数据）。
///
/// 结构：`{id, name, pinyin, aliases, type, entryUrl, baseUrl, allowedHosts,
/// overrides:{}, periodProfileId, status}`。`overrides` 目前认这些键：
/// `homeUrl`、`description`、`userAgent`、`termPresets`
/// （`[{id, name, startDate: "yyyy-MM-dd", totalWeeks}]`）。
class SchoolEntry {
  final String id;
  final String name;

  /// 全拼，音节之间用空格隔开（`shang hai da xue`），搜索时同时匹配连写与首字母。
  final String pinyin;
  final List<String> aliases;

  /// 教务系统类型，目前只有 `zfsoft`。
  final String type;
  final String entryUrl;
  final String baseUrl;
  final List<String> allowedHosts;
  final Map<String, dynamic> overrides;
  final String? periodProfileId;
  final SchoolStatus status;

  const SchoolEntry({
    required this.id,
    required this.name,
    this.pinyin = '',
    this.aliases = const <String>[],
    required this.type,
    required this.entryUrl,
    required this.baseUrl,
    this.allowedHosts = const <String>[],
    this.overrides = const <String, dynamic>{},
    this.periodProfileId,
    this.status = SchoolStatus.experimental,
  });

  /// 解析一条记录；缺关键字段（id / name / type / baseUrl）返回 null。
  static SchoolEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    String? str(String key) {
      final v = json[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    }

    List<String> strList(String key) {
      final v = json[key];
      if (v is! List) return const <String>[];
      return v
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }

    final id = str('id');
    final name = str('name');
    final type = str('type');
    final baseUrl = str('baseUrl');
    if (id == null || name == null || type == null || baseUrl == null) {
      return null;
    }
    final overrides = json['overrides'];
    return SchoolEntry(
      id: id,
      name: name,
      pinyin: str('pinyin') ?? '',
      aliases: strList('aliases'),
      type: type,
      entryUrl: str('entryUrl') ?? baseUrl,
      baseUrl: baseUrl,
      allowedHosts: strList('allowedHosts'),
      overrides: overrides is Map
          ? Map<String, dynamic>.from(overrides)
          : const <String, dynamic>{},
      periodProfileId: str('periodProfileId'),
      status: SchoolStatus.parse(json['status']),
    );
  }

  String? _override(String key) {
    final v = overrides[key];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  /// 展示在列表里的一句话说明。
  String get description =>
      _override('description') ?? '${systemTypeLabel(type)} · 登录后一键导入';

  /// `overrides.termPresets` → 学期预设；没有或格式不对返回 null。
  List<TermPreset>? get termPresets {
    final raw = overrides['termPresets'];
    if (raw is! List) return null;
    final out = <TermPreset>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = item['name'];
      final start = item['startDate'];
      final date = start is String ? DateTime.tryParse(start) : null;
      if (name is! String || date == null) continue;
      final weeks = item['totalWeeks'];
      out.add(
        TermPreset(
          id: item['id'] is String ? item['id'] as String : '$id-$start',
          name: name,
          startDate: DateTime(date.year, date.month, date.day),
          totalWeeks: weeks is int && weeks > 0 ? weeks : 18,
        ),
      );
    }
    return out.isEmpty ? null : out;
  }

  /// 按 [type] 生成适配器；不支持的类型返回 null。
  SchoolAdapter? buildAdapter() {
    switch (type) {
      case ZfsoftAdapter.type:
        return ZfsoftAdapter(
          id: id,
          name: name,
          baseUrl: baseUrl,
          homeUrl: _override('homeUrl') ?? entryUrl,
          entryUrl: entryUrl,
          description: description,
          allowedHosts: allowedHosts,
          userAgent: _override('userAgent'),
          presets: termPresets,
          periodProfileId: periodProfileId,
        );
      default:
        return null;
    }
  }

  /// 搜索匹配：名称 / id / 别名 / 拼音（连写或首字母），大小写不敏感。
  bool matches(String query) {
    final q = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (q.isEmpty) return true;
    if (name.toLowerCase().contains(q)) return true;
    if (id.toLowerCase().contains(q)) return true;
    for (final a in aliases) {
      if (a.toLowerCase().contains(q)) return true;
    }
    final syllables = pinyin
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (syllables.isEmpty) return false;
    if (syllables.join().contains(q)) return true;
    final initials = syllables.map((s) => s[0]).join();
    return initials.contains(q);
  }
}

/// 系统类型的中文名。
String systemTypeLabel(String type) {
  switch (type) {
    case ZfsoftAdapter.type:
      return '正方教务';
    default:
      return type;
  }
}

/// 支持一键导入的学校清单，数据来自 `assets/schools.json`。
///
/// 用法：页面先 `await SchoolRegistry.ensureLoaded()`，之后 [byId] / [search]
/// 都是同步的。asset 读不到或整个坏掉时退回内置的 [fallbackJson]
/// （和 asset 里唯一的已验证条目保持一致，有测试盯着）。
class SchoolRegistry {
  SchoolRegistry._();

  /// asset 路径。
  static const String assetPath = 'assets/schools.json';

  /// asset 读不到时的兜底清单：只有内置的那一所已验证学校。
  static const String fallbackJson = '''
{"version":1,"schools":[{"id":"shu","name":"上海大学","pinyin":"shang hai da xue",
"aliases":["上大","SHU"],"type":"zfsoft","entryUrl":"https://jwxt.shu.edu.cn/",
"baseUrl":"https://jwxt.shu.edu.cn/jwglxt","allowedHosts":["jwxt.shu.edu.cn"],
"overrides":{},"periodProfileId":"default-12","status":"verified"}]}
''';

  static List<SchoolEntry>? _entries;
  static Future<void>? _loading;

  /// 解析时丢掉的条目说明（只用于调试 / 测试）。
  static List<String> lastLoadWarnings = const <String>[];

  /// 是否已经加载过。
  static bool get isLoaded => _entries != null;

  /// 全部学校（未加载时为空列表）。
  static List<SchoolEntry> get entries =>
      List<SchoolEntry>.unmodifiable(_entries ?? const <SchoolEntry>[]);

  /// 从 asset 加载并缓存；重复调用只加载一次。
  static Future<void> ensureLoaded({AssetBundle? bundle}) {
    if (_entries != null) return Future<void>.value();
    return _loading ??= _load(bundle ?? rootBundle).whenComplete(() {
      _loading = null;
    });
  }

  static Future<void> _load(AssetBundle bundle) async {
    String text;
    try {
      text = await bundle.loadString(assetPath, cache: false);
    } catch (_) {
      text = fallbackJson;
    }
    loadFromJson(text);
    if (_entries!.isEmpty) loadFromJson(fallbackJson);
  }

  /// 直接用一段 JSON 填充清单（测试 / 以后的远程清单用）。
  ///
  /// 顶层可以是 `{"schools":[...]}` 或裸数组。坏条目、重复 id 丢掉并记进
  /// [lastLoadWarnings]；整段解析失败时清单为空。
  static void loadFromJson(String text) {
    final warnings = <String>[];
    final out = <SchoolEntry>[];
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      warnings.add('schools.json 不是合法 JSON：$e');
    }
    final list = decoded is Map ? decoded['schools'] : decoded;
    if (list is List) {
      for (var i = 0; i < list.length; i++) {
        final entry = SchoolEntry.fromJson(list[i]);
        if (entry == null) {
          warnings.add('第 ${i + 1} 条缺少 id / name / type / baseUrl，已忽略');
          continue;
        }
        if (out.any((e) => e.id == entry.id)) {
          warnings.add('学校 id「${entry.id}」重复，只保留第一条');
          continue;
        }
        out.add(entry);
      }
    } else if (decoded != null) {
      warnings.add('schools.json 顶层应为 {"schools": [...]}');
    }
    _entries = out;
    lastLoadWarnings = warnings;
  }

  /// 清掉缓存（测试用）。
  static void resetForTest() {
    _entries = null;
    _loading = null;
    lastLoadWarnings = const <String>[];
  }

  /// 按 id 找学校；找不到或未加载返回 null。
  static SchoolEntry? byId(String id) {
    for (final e in _entries ?? const <SchoolEntry>[]) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// 按 id 直接拿适配器。
  static SchoolAdapter? adapterFor(String id) => byId(id)?.buildAdapter();

  /// 按名称 / 拼音 / 别名 / id 模糊搜索，[query] 为空时返回全部。
  /// 已验证的排前面，其次社区、实验；同档保持清单顺序。
  static List<SchoolEntry> search(String query) {
    final hits = (_entries ?? const <SchoolEntry>[])
        .where((e) => e.matches(query))
        .toList();
    final indexed = <SchoolEntry, int>{
      for (var i = 0; i < hits.length; i++) hits[i]: i,
    };
    hits.sort((a, b) {
      final s = a.status.index.compareTo(b.status.index);
      return s != 0 ? s : indexed[a]!.compareTo(indexed[b]!);
    });
    return hits;
  }
}

/// 「我的学校不在列表」：从用户输入的教务网址推断系统类型的结果。
class SchoolUrlGuess {
  /// 推断出的临时学校条目；推断不出时为 null。
  final SchoolEntry? entry;

  /// 推断失败的原因（给用户看），或推断成功时的提醒。
  final String? message;

  const SchoolUrlGuess._(this.entry, this.message);

  bool get supported => entry != null;

  /// 按网址特征猜教务系统类型。目前只认正方新版：路径里含 `/jwglxt`。
  ///
  /// - `baseUrl` 取到 `/jwglxt` 为止（含端口，不含尾斜杠）；
  /// - `homeUrl` 取源（`scheme://host[:port]/`），`entryUrl` 用用户输入的地址；
  /// - `allowedHosts` 只放这个 host；状态固定为 [SchoolStatus.experimental]。
  ///
  /// 没写 scheme 时补 `https://`。
  static SchoolUrlGuess fromUrl(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return const SchoolUrlGuess._(null, '请输入教务系统的网址。');
    }
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
      text = 'https://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return const SchoolUrlGuess._(null, '这不是一个有效的 http / https 网址。');
    }
    final host = uri.host.toLowerCase();
    final path = uri.path;
    final match = RegExp(
      r'/jwglxt(?=/|$)',
      caseSensitive: false,
    ).firstMatch(path);
    if (match == null) {
      return const SchoolUrlGuess._(
        null,
        '暂时只能识别正方教务系统（网址里带 /jwglxt 的那种）。'
        '你的学校用的可能是强智、树维、URP 或其他系统，暂不支持一键导入。',
      );
    }
    final origin = uri.hasPort
        ? '${uri.scheme}://$host:${uri.port}'
        : '${uri.scheme}://$host';
    final baseUrl = '$origin${path.substring(0, match.end)}';
    final entryUrl = uri.removeFragment().toString();
    final entry = SchoolEntry(
      id: 'custom-$host',
      name: host,
      type: ZfsoftAdapter.type,
      entryUrl: entryUrl,
      baseUrl: baseUrl,
      allowedHosts: <String>[host],
      overrides: <String, dynamic>{
        'homeUrl': '$origin/',
        'description': '按网址推断的正方教务（未验证）',
      },
      periodProfileId: periodTemplates.first.id,
      status: SchoolStatus.experimental,
    );
    String? note;
    if (uri.scheme == 'http' && !_isEduCn(host)) {
      note =
          '这是 http 明文地址且不在 edu.cn 域名下，Android 可能会拒绝打开；'
          '如果打不开，试试改成 https。';
    }
    return SchoolUrlGuess._(entry, note);
  }

  static bool _isEduCn(String host) =>
      host == 'edu.cn' || host.endsWith('.edu.cn');
}
