import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/app_state.dart';
import '../../../core/feedback_links.dart';
import '../../../core/holiday_presets.dart';
import '../../../core/holiday_repository.dart';
import '../adapters/school_adapter.dart';
import '../adapters/school_registry.dart';
import '../diagnostics/diagnostic_sample.dart';
import '../web/edu_session.dart';
import '../web/external_navigation.dart';
import 'import_preview_page.dart';

/// 导入流程第二步：在 WebView 里登录教务系统，然后注入脚本抓课表。
class WebLoginPage extends StatefulWidget {
  const WebLoginPage({super.key, required this.adapter, this.status});

  final SchoolAdapter adapter;

  /// 学校的验证状态（学校选择页传进来，只用于诊断样本与提示）。
  final SchoolStatus? status;

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  /// 整个抓取过程的兜底超时（脚本内部也有 30s 超时）。
  static const Duration _importTimeout = Duration(seconds: 40);

  late final WebViewController _controller;

  String _currentUrl = '';
  int _progress = 100;
  bool _loggedIn = false;
  bool _importing = false;
  ImportStage _stage = ImportStage.indexPage;

  /// 等待页面通过 JavaScriptChannel 回传最终结果。
  Completer<String>? _pending;

  /// 等待诊断用的页面快照。
  Completer<String>? _diagPending;

  /// 最近一次抓取脚本回传的原始消息（诊断样本用）。
  String? _lastRaw;

  /// 最近一次失败的说明（诊断样本用）。
  String? _lastError;
  ImportStage? _lastErrorStage;

  /// 进页面时读到的「记住教务登录」开关。
  bool _rememberLogin = false;

  /// 本页面的登录态已经按策略清理过了（导入成功时清），离开时不用再清。
  bool _sessionHandled = false;

  @override
  void initState() {
    super.initState();
    try {
      _rememberLogin = context.read<AppState>().settings.rememberEduLogin;
    } catch (_) {
      _rememberLogin = false; // 没有 Provider（测试）时按默认值。
    }
    _currentUrl = widget.adapter.loginUrl;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        importChannelName,
        onMessageReceived: _onChannelMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (url) => _updateUrl(url),
          onPageFinished: (url) {
            _updateUrl(url);
            if (mounted) setState(() => _progress = 100);
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _updateUrl(url);
          },
          onWebResourceError: (error) {
            // 子资源（图片/广告脚本）失败不提示，只有主框架失败才提示。
            if (error.isForMainFrame != true) return;
            // ERR_CLEARTEXT_NOT_PERMITTED：network_security_config 只对 edu.cn
            // （含子域）放行明文 http，别的域名走 http 会被系统拦掉。
            final cleartext = error.description.toUpperCase().contains(
              'CLEARTEXT',
            );
            final host = Uri.tryParse(error.url ?? '')?.host ?? '';
            _showError(
              '网页加载失败：${error.description}',
              suggestion: cleartext
                  ? '教务系统跳转到了明文 http 地址${host.isEmpty ? '' : '（$host）'}。'
                        '出于安全考虑，App 只允许 edu.cn 域名使用明文 http。'
                  : '请检查网络连接（校外访问教务系统可能需要 VPN），然后点右上角刷新。',
            );
          },
        ),
      );
    final ua = widget.adapter.userAgent;
    if (ua != null && ua.isNotEmpty) _controller.setUserAgent(ua);
    _controller.loadRequest(Uri.parse(widget.adapter.loginUrl));
  }

  @override
  void dispose() {
    // 没导入就离开（或导入失败后返回）：没开「记住教务登录」时也清掉登录态。
    // dispose 里不能 await，清理是尽力而为，失败也不影响任何东西。
    if (!_sessionHandled) {
      unawaited(
        clearEduSessionIfNeeded(
          rememberLogin: _rememberLogin,
          event: EduSessionEvent.loginPageClosed,
          store: WebViewEduSessionStore(controller: _controller),
        ),
      );
    }
    super.dispose();
  }

  void _updateUrl(String url) {
    if (!mounted) return;
    final loggedIn = widget.adapter.isLoggedIn(url);
    if (url == _currentUrl && loggedIn == _loggedIn) return;
    setState(() {
      _currentUrl = url;
      _loggedIn = loggedIn;
    });
  }

  String get _hostLabel {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null || uri.host.isEmpty) return widget.adapter.name;
    return uri.host;
  }

  // ------------------------------------------------------------ 外部跳转

  /// 非 http(s) 的跳转（企业微信 / 微信 / QQ 扫码登录等）交给系统打开。
  /// 判定逻辑在 [planNavigation]（纯函数，有单测）。
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final plan = planNavigation(request.url);
    switch (plan.kind) {
      case NavigationKind.web:
        return NavigationDecision.navigate;
      case NavigationKind.block:
        return NavigationDecision.prevent;
      case NavigationKind.external:
        unawaited(_launchExternal(plan));
        return NavigationDecision.prevent;
    }
  }

  Future<void> _launchExternal(NavigationPlan plan) async {
    final target = plan.externalUri;
    var launched = false;
    if (target != null) {
      try {
        launched = await launchUrl(
          target,
          mode: LaunchMode.externalNonBrowserApplication,
        );
      } catch (_) {
        launched = false;
      }
    }
    if (launched || !mounted) return;
    final fallback = plan.fallbackUrl;
    if (fallback != null) {
      await _controller.loadRequest(fallback);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '没有找到能打开这个登录方式的 App'
          '${target == null ? '' : '（${target.scheme}）'}，'
          '请改用账号密码登录，或先安装对应的 App。',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 抓取流程

  /// 处理脚本回传的消息。判定逻辑在 [parseChannelMessage]（纯函数，有单测）。
  void _onChannelMessage(JavaScriptMessage message) {
    final raw = message.message;
    final parsed = parseChannelMessage(raw);
    switch (parsed.kind) {
      case ChannelMessageKind.ignore:
        return;
      case ChannelMessageKind.progress:
        final stage = parsed.stage;
        if (stage != null && mounted && _importing) {
          setState(() => _stage = stage);
        }
        return;
      case ChannelMessageKind.result:
        final pending = _pending;
        if (pending != null && !pending.isCompleted) {
          _lastRaw = raw;
          pending.complete(raw);
        }
        return;
      case ChannelMessageKind.diagnostic:
        final diag = _diagPending;
        if (diag != null && !diag.isCompleted) diag.complete(raw);
        return;
    }
  }

  Future<void> _startImport() async {
    if (_importing) return;

    // 注入脚本是在「当前文档」的源里跑的：还停在统一身份认证的域名时，
    // 对教务域名的带凭据 fetch 是跨源请求，会被 CORS 拦掉，
    // 用户只会看到一句莫名其妙的 `Failed to fetch`。先拦在这里。
    if (!widget.adapter.isAllowedHost(_currentUrl)) {
      final actual = Uri.tryParse(_currentUrl)?.host.toLowerCase();
      _showError(
        '当前页面还在 ${actual == null || actual.isEmpty ? '登录页' : actual}，'
        '无法直接抓取教务数据。',
        suggestion: '点下面的「重新打开教务」，等页面显示出教务系统（能看到自己的课表）再点导入。',
      );
      return;
    }

    final pending = Completer<String>();
    setState(() {
      _importing = true;
      _stage = ImportStage.indexPage;
      _pending = pending;
      _lastRaw = null;
      _lastError = null;
      _lastErrorStage = null;
    });

    String raw;
    try {
      await _controller.runJavaScript(widget.adapter.scrapeScript);
      raw = await pending.future.timeout(_importTimeout);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _pending = null;
      });
      _showError(
        '抓取超时，教务系统在 ${_importTimeout.inSeconds} 秒内没有响应。',
        suggestion: '请确认页面已经进入教务系统（能看到自己的课表），再试一次。',
        stage: _stage,
        offerDiagnostics: true,
      );
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _pending = null;
      });
      _showError('注入脚本失败：$e', suggestion: '请回到教务首页后重试。');
      return;
    }

    if (!mounted) return;
    setState(() => _stage = ImportStage.parse);

    ImportResult result;
    try {
      result = widget.adapter.parse(raw);
    } on ImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _pending = null;
      });
      _showError(
        e.message,
        suggestion: e.suggestion,
        stage: e.stage,
        offerDiagnostics: true,
      );
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _pending = null;
      });
      _showError(
        '解析课表数据失败：$e',
        suggestion: '教务系统的接口可能有变化，请把这条错误反馈给开发者。',
        stage: ImportStage.parse,
        offerDiagnostics: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _importing = false;
      _pending = null;
    });

    if (result.isEmpty) {
      _showError(
        '没有解析到任何课程。',
        suggestion:
            '可能是当前学期还没排课，或者教务系统默认选中的学期不对。'
            '可以先在网页里手动切到正确的学期并查询一次，再点导入。',
        stage: ImportStage.parse,
        offerDiagnostics: true,
      );
      return;
    }

    // 预览页按学校校历推开学日期（PLAN-1.5 D8）：先把当前的假日表读好传进去，
    // 预览页里不做 IO。读不到就当空表（只剩教务识别 / 问用户两条路）。
    final holidays = await _loadHolidayPresets();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportPreviewPage(
          result: result,
          schoolName: widget.adapter.name,
          adapter: widget.adapter,
          holidayPresets: holidays,
          diagnostics: _diagnosticInput(
            secrets: <String>[
              if (result.studentName != null) result.studentName!,
            ],
          ),
          onImported: _onImported,
        ),
      ),
    );
  }

  /// 当前用的假日表（内置，或联网更新过的较新缓存）；出错时为空表。
  static Future<HolidayPresets> _loadHolidayPresets() async {
    try {
      return await HolidayRepository().load();
    } catch (_) {
      return HolidayPresets.empty;
    }
  }

  /// 预览页写入成功、退回首页之前调用：按策略清理登录态。
  Future<void> _onImported() async {
    _sessionHandled = true;
    await clearEduSessionIfNeeded(
      rememberLogin: _rememberLogin,
      event: EduSessionEvent.importSucceeded,
      store: WebViewEduSessionStore(controller: _controller),
    );
  }

  // ------------------------------------------------------------ 诊断样本

  DiagnosticInput _diagnosticInput({
    String? pageHtml,
    List<String> secrets = const <String>[],
  }) => DiagnosticInput(
    schoolId: widget.adapter.id,
    schoolName: widget.adapter.name,
    systemType: widget.adapter.systemType,
    status: widget.status?.label,
    url: _currentUrl,
    stage: _lastErrorStage?.name,
    error: _lastError,
    response: _lastRaw,
    pageHtml: pageHtml,
    secrets: secrets,
  );

  /// 让页面把当前 DOM 通过通道发回来（最多等 3 秒）。
  Future<String?> _capturePageHtml() async {
    final completer = Completer<String>();
    _diagPending = completer;
    try {
      await _controller.runJavaScript(_diagnosticScript);
      final raw = await completer.future.timeout(const Duration(seconds: 3));
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['html'] is String) {
        return decoded['html'] as String;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      _diagPending = null;
    }
  }

  Future<void> _exportDiagnostics() async {
    final messenger = ScaffoldMessenger.of(context);
    final html = await _capturePageHtml();
    final input = _diagnosticInput(pageHtml: html);
    if (!input.hasPayload) {
      messenger.showSnackBar(
        const SnackBar(content: Text('还没有抓到任何数据，打开课表页后再试')),
      );
      return;
    }
    try {
      await DiagnosticSample.exportAndShare(input);
    } catch (e) {
      debugPrint('导出导入记录失败：$e');
      messenger.showSnackBar(const SnackBar(content: Text('导出导入记录失败，请稍后再试')));
    }
  }

  static const String _diagnosticScript =
      '(function(){try{var h=document.documentElement?'
      'document.documentElement.outerHTML:"";'
      '$importChannelName.postMessage(JSON.stringify({diag:true,'
      'url:String(location.href),html:String(h).substring(0,204800)}));}'
      'catch(e){try{$importChannelName.postMessage(JSON.stringify('
      '{diag:true,url:"",html:""}));}catch(x){}}})();';

  // ---------------------------------------------------------------- 错误框

  /// 是否已经有一个错误对话框在屏幕上。
  ///
  /// SSO 链路里一次跳转常常连着触发 2~3 次 `onWebResourceError`，
  /// 不去重会把对话框叠成一摞，用户要连点好几次「知道了」。
  bool _errorShowing = false;

  void _showError(
    String message, {
    String? suggestion,
    ImportStage? stage,
    bool offerDiagnostics = false,
  }) {
    if (!mounted || _errorShowing) return;
    _errorShowing = true;
    _lastError = message;
    _lastErrorStage = stage;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入失败'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message),
            if (suggestion != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(suggestion, style: Theme.of(ctx).textTheme.bodySmall),
            ],
            if (offerDiagnostics) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                FeedbackLinks.diagnosticHint,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        actions: <Widget>[
          if (offerDiagnostics)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _exportDiagnostics();
              },
              child: const Text('导出导入记录'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _controller.loadRequest(Uri.parse(widget.adapter.homeUrl));
            },
            child: const Text('重新打开教务'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    ).whenComplete(() => _errorShowing = false);
  }

  // ------------------------------------------------------------------ 构建

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.adapter.name, style: theme.textTheme.titleMedium),
            Text(
              _hostLabel,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _importing ? null : () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            enabled: !_importing,
            onSelected: (v) {
              if (v == 'diag') _exportDiagnostics();
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'diag', child: Text('导出导入记录')),
            ],
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
        bottom: _progress >= 100
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: WebViewWidget(controller: _controller)),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: _buildBottomBar(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    if (_importing) {
      return Row(
        children: <Widget>[
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              importStageLabel(_stage),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }

    if (_loggedIn) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _startImport,
          icon: const Icon(Icons.download),
          label: const Text('一键导入课表'),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.lock_outline, size: 16, color: theme.disabledColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '请先登录（统一身份认证）',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.disabledColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton(onPressed: _startImport, child: const Text('我已登录，直接导入')),
      ],
    );
  }
}
