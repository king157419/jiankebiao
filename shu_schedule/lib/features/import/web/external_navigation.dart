/// WebView 里一次跳转该怎么处理（纯函数，有单测）。
///
/// 统一身份认证常带「企业微信 / 微信 / QQ 扫码或一键登录」，点下去页面会跳
/// `wxwork://`、`weixin://`、`mqqapi://` 或 Android 的 `intent://`。WebView
/// 自己打不开这些地址，只会显示 `ERR_UNKNOWN_URL_SCHEME`，所以要拦下来交给系统。
enum NavigationKind {
  /// 普通网页，WebView 自己加载。
  web,

  /// 交给系统（外部 App）打开。
  external,

  /// 什么都不做：空地址、解析不了的地址，以及不该交给外部的本地地址（`file:` / `content:`）。
  block,
}

/// 一次跳转的处理决定。
class NavigationPlan {
  final NavigationKind kind;

  /// [NavigationKind.external] 时要交给系统的地址。
  final Uri? externalUri;

  /// 外部 App 打不开时，WebView 可以退回加载的网页地址
  /// （`intent://` 里的 `S.browser_fallback_url`）。
  final Uri? fallbackUrl;

  const NavigationPlan._(this.kind, {this.externalUri, this.fallbackUrl});

  static const NavigationPlan web = NavigationPlan._(NavigationKind.web);
  static const NavigationPlan block = NavigationPlan._(NavigationKind.block);
}

/// WebView 能自己处理的 scheme。
const Set<String> _webSchemes = <String>{
  'http',
  'https',
  'about',
  'data',
  'blob',
  'javascript',
};

/// 决定 [url] 这次跳转怎么处理。
NavigationPlan planNavigation(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return NavigationPlan.block;
  final schemeMatch = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):')
      .firstMatch(trimmed);
  if (schemeMatch == null) return NavigationPlan.web; // 相对地址，交给 WebView。
  final scheme = schemeMatch.group(1)!.toLowerCase();
  if (_webSchemes.contains(scheme)) return NavigationPlan.web;
  if (scheme == 'file' || scheme == 'content') return NavigationPlan.block;
  if (scheme == 'intent') return _planIntent(trimmed);
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return NavigationPlan.block;
  return NavigationPlan._(NavigationKind.external, externalUri: uri);
}

/// `intent://host/path#Intent;scheme=weixin;package=...;S.browser_fallback_url=...;end`
/// → `weixin://host/path`，并带上 fallback 网页地址。
NavigationPlan _planIntent(String url) {
  final hashIndex = url.indexOf('#Intent;');
  final body = hashIndex >= 0 ? url.substring(0, hashIndex) : url;
  final params = <String, String>{};
  if (hashIndex >= 0) {
    var tail = url.substring(hashIndex + '#Intent;'.length);
    if (tail.endsWith('end')) tail = tail.substring(0, tail.length - 3);
    for (final part in tail.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      params[part.substring(0, eq)] = part.substring(eq + 1);
    }
  }

  Uri? fallback;
  final rawFallback = params['S.browser_fallback_url'];
  if (rawFallback != null && rawFallback.isNotEmpty) {
    try {
      final decoded = Uri.decodeComponent(rawFallback);
      final f = Uri.tryParse(decoded);
      if (f != null && (f.scheme == 'http' || f.scheme == 'https')) {
        fallback = f;
      }
    } catch (_) {
      // 编码坏了就不要 fallback。
    }
  }

  final scheme = params['scheme'];
  Uri? target;
  if (scheme != null && RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*$').hasMatch(scheme)) {
    // body 形如 `intent://xxx`，把 `intent` 换成真实 scheme。
    final rest = body.substring('intent'.length); // `://xxx`
    target = Uri.tryParse('$scheme$rest');
  }
  if (target == null && fallback == null) return NavigationPlan.block;
  if (target == null) {
    // 只有网页 fallback：externalUri 为空，调用方直接在 WebView 里加载 fallback。
    return NavigationPlan._(NavigationKind.external, fallbackUrl: fallback);
  }
  return NavigationPlan._(
    NavigationKind.external,
    externalUri: target,
    fallbackUrl: fallback,
  );
}
