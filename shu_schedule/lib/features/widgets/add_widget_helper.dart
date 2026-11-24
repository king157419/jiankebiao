import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/native_bridge.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_controller.dart';
import 'widget_add_guide.dart';

/// 面板标题。
const String addWidgetSheetTitle = '添加桌面小组件';

/// 面板底部那一行（常驻，点开是按品牌分的手动步骤）。
const String addWidgetManualTitle = '没弹出确认框？看看怎么手动添加';

/// 原生返回 true 后，那张卡片按钮下方的小字。
///
/// true 只说明启动器支持，不保证确认框真弹出来了，所以同时把 [addWidgetManualTitle]
/// 那一行高亮，没看到确认框的人顺着往下看。
const String addWidgetRequestedText = '系统应该弹出了确认框，按提示添加就好';

/// 收到 `onWidgetPinned`（用户在系统确认框里点了添加）后，那张卡片按钮下方的小字。
const String addWidgetPinnedText = '已添加到桌面 ✓';

/// 原生返回 false 时，展开的手动步骤顶上的提示。
const String addWidgetUnsupportedText = '这台手机的桌面不支持直接添加，按下面步骤手动加一次';

/// 面板上的一种小组件。
class AddWidgetOption {
  /// 传给 [NativeBridge.requestPinWidget] 的值（[NativeBridge.pinDay] / [NativeBridge.pinNext]）。
  final String provider;
  final String title;
  final String description;

  /// 预览图（从 `android/app/src/main/res/drawable-nodpi/` 原样复制到 `assets/widgets/`，
  /// widget_android_config_test 核对两边字节一致）。
  final String previewAsset;

  /// 预览图显示高度。
  final double previewHeight;

  const AddWidgetOption({
    required this.provider,
    required this.title,
    required this.description,
    required this.previewAsset,
    required this.previewHeight,
  });
}

/// 面板上的两张卡片，从上到下。
const List<AddWidgetOption> addWidgetOptions = <AddWidgetOption>[
  AddWidgetOption(
    provider: NativeBridge.pinDay,
    title: '当天课程 · 4×2',
    description: '今天 / 明天的课按时间排好，可以翻页',
    previewAsset: 'assets/widgets/widget_day_preview.png',
    previewHeight: 150,
  ),
  AddWidgetOption(
    provider: NativeBridge.pinNext,
    title: '下一节课 · 2×1',
    description: '只显示最近的一节课，适合放在桌面第一屏',
    previewAsset: 'assets/widgets/widget_next_preview.png',
    previewHeight: 72,
  ),
];

/// 设置 →「添加桌面小组件」（v1.5.0，D4）：两种小组件各一张卡片（预览图 + 一句说明 +
/// 「添加到桌面」），底下常驻「没弹出确认框？看看怎么手动添加」。
///
/// 点「添加到桌面」走 `requestPinAppWidget`：
/// - 原生返回 true → 卡片下面一行「系统应该弹出了确认框…」，手动添加那一行高亮；
///   用户在确认框里点了添加，原生自己弹 Toast「小组件已添加到桌面」；
/// - 返回 false（老系统 / 启动器不支持 / 没有原生端）→ 直接展开手动步骤并滚过去。
///
/// 手动步骤按 [NativeBridge.deviceInfo] 的厂商 / 品牌默认展开对应的一套，
/// 其它品牌折叠着可点开。[bridge] 只给测试注入。
Future<void> showAddWidgetSheet(BuildContext context, {NativeBridge? bridge}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
      ),
      child: AddWidgetSheet(bridge: bridge ?? NativeBridge.instance),
    ),
  );
}

/// 点了「添加到桌面」之后，原生给的结果。
enum _PinOutcome { requested, pinned, unsupported }

/// 面板本体（[showAddWidgetSheet] 里用；单独公开是为了测试能直接 pump）。
class AddWidgetSheet extends StatefulWidget {
  final NativeBridge bridge;

  const AddWidgetSheet({super.key, required this.bridge});

  @override
  State<AddWidgetSheet> createState() => _AddWidgetSheetState();
}

class _AddWidgetSheetState extends State<AddWidgetSheet> {
  final GlobalKey _manualKey = GlobalKey();
  StreamSubscription<String>? _pinnedSub;

  /// 等原生返回期间两个按钮都禁用：启动器可能忽略同一个 App 连着发的请求。
  bool _busy = false;

  /// provider → 最近一次点按的结果。
  final Map<String, _PinOutcome> _outcomes = <String, _PinOutcome>{};

  /// 手动步骤是否展开。
  bool _manualOpen = false;

  /// 原生返回 false 过：手动步骤顶上显示 [addWidgetUnsupportedText]。
  bool _unsupported = false;

  /// 这台手机的品牌（deviceInfo 回来之前当「其他」）。
  WidgetGuideBrand _brand = WidgetGuideBrand.other;

  /// 展开着的品牌步骤。
  Set<WidgetGuideBrand> _openBrands = <WidgetGuideBrand>{
    WidgetGuideBrand.other,
  };

  /// 用户自己点过品牌标题以后，deviceInfo 回来也不再改展开状态。
  bool _brandsTouched = false;

  @override
  void initState() {
    super.initState();
    _pinnedSub = widget.bridge.pinned.listen((provider) {
      if (!mounted) return;
      setState(() => _outcomes[provider] = _PinOutcome.pinned);
    });
    _loadBrand();
  }

  @override
  void dispose() {
    _pinnedSub?.cancel();
    super.dispose();
  }

  Future<void> _loadBrand() async {
    final device = await widget.bridge.deviceInfo();
    if (!mounted) return;
    final brand = guideBrandOfDevice(device);
    setState(() {
      _brand = brand;
      if (!_brandsTouched) _openBrands = <WidgetGuideBrand>{brand};
    });
  }

  bool get _highlightManual =>
      _outcomes.values.contains(_PinOutcome.requested) && !_manualOpen;

  Future<void> _pin(AddWidgetOption option) async {
    setState(() => _busy = true);
    final ok = await widget.bridge.requestPinWidget(provider: option.provider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _outcomes[option.provider] = ok
          ? _PinOutcome.requested
          : _PinOutcome.unsupported;
      if (!ok) {
        _unsupported = true;
        _manualOpen = true;
      }
    });
    if (!ok) _scrollToManual();
  }

  void _scrollToManual() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _manualKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _toggleBrand(WidgetGuideBrand brand) {
    setState(() {
      _brandsTouched = true;
      _openBrands = <WidgetGuideBrand>{..._openBrands};
      if (!_openBrands.remove(brand)) _openBrands.add(brand);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>().current;
    final colors = theme.colors;

    return SafeArea(
      child: SingleChildScrollView(
        key: const ValueKey<String>('add-widget-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              addWidgetSheetTitle,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            for (final option in addWidgetOptions) ...<Widget>[
              _card(theme, option),
              const SizedBox(height: 12),
            ],
            _manualSection(theme),
          ],
        ),
      ),
    );
  }

  Widget _card(AppTheme theme, AddWidgetOption option) {
    final colors = theme.colors;
    final outcome = _outcomes[option.provider];
    return Container(
      key: ValueKey<String>('add-widget-card-${option.provider}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            option.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Center(child: _preview(theme, option)),
          const SizedBox(height: 8),
          Text(
            option.description,
            style: TextStyle(fontSize: 13, color: colors.onSurfaceMuted),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: ValueKey<String>('add-widget-pin-${option.provider}'),
              onPressed: _busy ? null : () => _pin(option),
              icon: const Icon(Icons.add_to_home_screen, size: 18),
              label: const Text('添加到桌面'),
            ),
          ),
          if (outcome == _PinOutcome.requested ||
              outcome == _PinOutcome.pinned) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              outcome == _PinOutcome.pinned
                  ? addWidgetPinnedText
                  : addWidgetRequestedText,
              key: ValueKey<String>('add-widget-status-${option.provider}'),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: outcome == _PinOutcome.pinned
                    ? colors.primary
                    : colors.onSurfaceMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 预览图放在一个带细边框的圆角框里：2×1 的预览是白底，深色主题下不至于太突兀。
  ///
  /// 圆角取 16：4×2 那张图四个角上带着截图时的深色描边（和启动器列表里用的是同一张，
  /// 不改图），按 150 高显示时角半径约 13，16 能把它整个裁掉。
  Widget _preview(AppTheme theme, AddWidgetOption option) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colors.outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Image.asset(
          option.previewAsset,
          key: ValueKey<String>('add-widget-preview-${option.provider}'),
          height: option.previewHeight,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => SizedBox(
            height: option.previewHeight,
            width: option.previewHeight * 2,
            child: Icon(Icons.widgets_outlined, color: theme.colors.outline),
          ),
        ),
      ),
    );
  }

  Widget _manualSection(AppTheme theme) {
    final colors = theme.colors;
    final highlight = _highlightManual;
    return Container(
      key: _manualKey,
      decoration: BoxDecoration(
        color: highlight ? colors.primary.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(theme.cornerRadius),
        border: Border.all(
          color: highlight ? colors.primary : colors.outline,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            key: const ValueKey<String>('add-widget-manual'),
            borderRadius: BorderRadius.circular(theme.cornerRadius),
            onTap: () => setState(() => _manualOpen = !_manualOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.help_outline,
                    size: 20,
                    color: highlight ? colors.primary : colors.onSurfaceMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      addWidgetManualTitle,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: highlight
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: highlight ? colors.primary : colors.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    _manualOpen ? Icons.expand_less : Icons.expand_more,
                    color: colors.onSurfaceMuted,
                  ),
                ],
              ),
            ),
          ),
          if (highlight)
            // 只给测试认高亮用，不占地方。
            const SizedBox.shrink(
              key: ValueKey<String>('add-widget-manual-highlight'),
            ),
          if (_manualOpen) _steps(theme),
        ],
      ),
    );
  }

  Widget _steps(AppTheme theme) {
    final colors = theme.colors;
    return Padding(
      key: const ValueKey<String>('add-widget-steps'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_unsupported)
            Container(
              key: const ValueKey<String>('add-widget-unsupported'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                addWidgetUnsupportedText,
                style: TextStyle(fontSize: 13, color: colors.onSurface),
              ),
            ),
          for (final guide in widgetGuidesFor(_brand))
            _brandGuide(theme, guide),
        ],
      ),
    );
  }

  Widget _brandGuide(AppTheme theme, WidgetGuide guide) {
    final colors = theme.colors;
    final open = _openBrands.contains(guide.brand);
    final mine = guide.brand == _brand && _brand != WidgetGuideBrand.other;
    final name = guide.brand.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        InkWell(
          key: ValueKey<String>('add-widget-brand-$name'),
          onTap: () => _toggleBrand(guide.brand),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: guide.title,
                      children: <InlineSpan>[
                        if (mine)
                          TextSpan(
                            text: '  这台手机',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.normal,
                              color: colors.primary,
                            ),
                          ),
                      ],
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: colors.onSurfaceMuted,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            key: ValueKey<String>('add-widget-brand-$name-steps'),
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (var i = 0; i < guide.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${i + 1}. ${guide.steps[i]}',
                      style: TextStyle(fontSize: 13, color: colors.onSurface),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
