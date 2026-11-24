import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/app_state.dart';
import 'package:shu_schedule/core/native_bridge.dart';
import 'package:shu_schedule/core/theme/theme_controller.dart';
import 'package:shu_schedule/core/update/update_checker.dart';
import 'package:shu_schedule/features/settings/settings_page.dart';
import 'package:shu_schedule/features/widgets/add_widget_helper.dart';
import 'package:shu_schedule/features/widgets/widget_add_guide.dart';

import 'helpers/harness.dart';

/// v1.5.0 D4：设置 →「添加桌面小组件」面板。
///
/// 原生端用真实的 [NativeBridge] + mock MethodChannel：可以配 `requestPinWidget`
/// 的返回值和 `getDeviceInfo` 的内容，并记录每次调用的方法和参数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const testChannel = MethodChannel('test/add_widget');
  const appChannel = MethodChannel(NativeBridge.channelName);

  final storage = TempStorage();
  setUp(() => storage.setUp('add_widget_sheet'));
  tearDown(() async {
    messenger.setMockMethodCallHandler(testChannel, null);
    messenger.setMockMethodCallHandler(appChannel, null);
    await storage.tearDown();
  });

  ValueKey<String> k(String s) => ValueKey<String>(s);

  /// 假原生端：记录 `requestPinWidget` 收到的 provider。
  late List<Object?> pinArgs;

  /// 装一个假原生端。[pin] 是 `requestPinWidget` 的结果（可以是 Future，用来卡住它）。
  void mockNative(
    MethodChannel channel, {
    FutureOr<bool?> Function()? pin,
    Map<String, Object?> device = const <String, Object?>{},
  }) {
    pinArgs = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'requestPinWidget':
          pinArgs.add(call.arguments);
          return pin == null ? true : await pin();
        case 'getDeviceInfo':
          return device;
      }
      return null;
    });
  }

  /// 一个只有「打开面板」按钮的页面，点开面板。
  Future<void> openSheet(WidgetTester tester, NativeBridge bridge) async {
    final (AppState state, ThemeController controller) = await loadState(
      tester,
    );
    await pumpApp(
      tester,
      state,
      controller,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showAddWidgetSheet(context, bridge: bridge),
              child: const Text('打开面板'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开面板'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder inSheet(Finder f) =>
      find.descendant(of: find.byKey(k('add-widget-sheet')), matching: f);

  /// 某个品牌标题上的「这台手机」小标签。
  Finder mineTag(WidgetGuideBrand b) => find.descendant(
    of: find.byKey(k('add-widget-brand-${b.name}')),
    matching: find.textContaining('  这台手机', findRichText: true),
  );

  Finder stepsOf(WidgetGuideBrand b) =>
      find.byKey(k('add-widget-brand-${b.name}-steps'));

  testWidgets('面板：标题、两张卡片（预览图 + 说明 + 按钮）、手动添加那一行', (tester) async {
    mockNative(testChannel);
    await openSheet(tester, NativeBridge(channel: testChannel));

    expect(inSheet(find.text(addWidgetSheetTitle)), findsOneWidget);
    expect(inSheet(find.text('当天课程 · 4×2')), findsOneWidget);
    expect(inSheet(find.text('下一节课 · 2×1')), findsOneWidget);
    expect(inSheet(find.text('今天 / 明天的课按时间排好，可以翻页')), findsOneWidget);
    expect(inSheet(find.text('只显示最近的一节课，适合放在桌面第一屏')), findsOneWidget);
    expect(inSheet(find.byType(Image)), findsNWidgets(2));
    expect(inSheet(find.text('添加到桌面')), findsNWidgets(2));
    expect(find.byKey(k('add-widget-pin-day')), findsOneWidget);
    expect(find.byKey(k('add-widget-pin-next')), findsOneWidget);

    // 预览图指向 assets/widgets/ 下的两张图，4×2 在上、2×1 在下。
    final day = tester.widget<Image>(find.byKey(k('add-widget-preview-day')));
    final next = tester.widget<Image>(find.byKey(k('add-widget-preview-next')));
    expect(
      (day.image as AssetImage).assetName,
      'assets/widgets/widget_day_preview.png',
    );
    expect(
      (next.image as AssetImage).assetName,
      'assets/widgets/widget_next_preview.png',
    );
    expect(
      tester.getTopLeft(find.byKey(k('add-widget-card-day'))).dy,
      lessThan(tester.getTopLeft(find.byKey(k('add-widget-card-next'))).dy),
    );

    // 手动添加那一行一直在，但没点之前不展开、不高亮，也没有任何结果提示。
    expect(inSheet(find.text(addWidgetManualTitle)), findsOneWidget);
    expect(find.byKey(k('add-widget-steps')), findsNothing);
    expect(find.byKey(k('add-widget-manual-highlight')), findsNothing);
    expect(find.text(addWidgetRequestedText), findsNothing);
    expect(find.text(addWidgetUnsupportedText), findsNothing);
    expect(pinArgs, isEmpty, reason: '打开面板不应该自己去请求添加');

    // 面板上没有技术词。
    final texts = tester
        .widgetList<Text>(inSheet(find.byType(Text)))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join('\n');
    for (final word in <String>['API', 'SDK', 'Android', '启动器', 'provider']) {
      expect(texts, isNot(contains(word)), reason: word);
    }
  });

  testWidgets('原生返回 true：传 provider=day，卡片下出现提示，手动那一行高亮但不展开', (tester) async {
    mockNative(testChannel, pin: () => true);
    await openSheet(tester, NativeBridge(channel: testChannel));

    await tapVisible(tester, find.byKey(k('add-widget-pin-day')));

    expect(pinArgs, <Object?>[
      <String, Object?>{'provider': 'day'},
    ]);
    expect(
      find.descendant(
        of: find.byKey(k('add-widget-card-day')),
        matching: find.text(addWidgetRequestedText),
      ),
      findsOneWidget,
    );
    // 只在点过的那张卡片下面。
    expect(find.byKey(k('add-widget-status-next')), findsNothing);
    expect(find.byKey(k('add-widget-manual-highlight')), findsOneWidget);
    expect(find.byKey(k('add-widget-steps')), findsNothing);
    expect(find.text(addWidgetUnsupportedText), findsNothing);

    // 点那一行 → 展开步骤，高亮随之去掉。
    await tapVisible(tester, find.byKey(k('add-widget-manual')));
    expect(find.byKey(k('add-widget-steps')), findsOneWidget);
    expect(find.byKey(k('add-widget-manual-highlight')), findsNothing);
    expect(find.text(addWidgetUnsupportedText), findsNothing);
    // 再点一次收起。
    await tapVisible(tester, find.byKey(k('add-widget-manual')));
    expect(find.byKey(k('add-widget-steps')), findsNothing);
    // 收起后因为状态仍是 requested，手动行重新高亮；收到原生 onWidgetPinned 后变「已添加到桌面 ✓」并去掉高亮。
    expect(find.byKey(k('add-widget-manual-highlight')), findsOneWidget);
    final callData = const StandardMethodCodec().encodeMethodCall(
      const MethodCall('onWidgetPinned', 'day'),
    );
    await messenger.handlePlatformMessage(testChannel.name, callData, (_) {});
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(k('add-widget-card-day')),
        matching: find.text(addWidgetPinnedText),
      ),
      findsOneWidget,
    );
    expect(find.text(addWidgetRequestedText), findsNothing);
    expect(find.byKey(k('add-widget-manual-highlight')), findsNothing);
  });

  testWidgets('原生返回 false：传 provider=next，直接展开手动步骤并提示', (tester) async {
    mockNative(testChannel, pin: () => false);
    await openSheet(tester, NativeBridge(channel: testChannel));

    await tapVisible(tester, find.byKey(k('add-widget-pin-next')));

    expect(pinArgs, <Object?>[
      <String, Object?>{'provider': 'next'},
    ]);
    expect(find.byKey(k('add-widget-steps')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(k('add-widget-steps')),
        matching: find.text(addWidgetUnsupportedText),
      ),
      findsOneWidget,
    );
    expect(find.text(addWidgetRequestedText), findsNothing);
    expect(find.byKey(k('add-widget-manual-highlight')), findsNothing);
    // 拿不到品牌 → 「其他手机」那一套展开，并且被滚到了视野里。
    expect(stepsOf(WidgetGuideBrand.other), findsOneWidget);
    expect(find.text('1. 回到桌面，长按空白处').hitTestable(), findsOneWidget);
    expect(find.text('3. $widgetGuideFindStep'), findsOneWidget);
  });

  testWidgets('等原生返回时两个按钮都禁用，返回后恢复', (tester) async {
    final pending = Completer<bool?>();
    mockNative(testChannel, pin: () => pending.future);
    await openSheet(tester, NativeBridge(channel: testChannel));

    await tester.ensureVisible(find.byKey(k('add-widget-pin-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(k('add-widget-pin-day')));
    await tester.pump();

    bool enabled(String key) =>
        tester.widget<ButtonStyleButton>(find.byKey(k(key))).enabled;
    expect(enabled('add-widget-pin-day'), isFalse);
    expect(enabled('add-widget-pin-next'), isFalse);

    pending.complete(true);
    await tester.pumpAndSettle();
    expect(enabled('add-widget-pin-day'), isTrue);
    expect(enabled('add-widget-pin-next'), isTrue);
    expect(pinArgs, hasLength(1));
  });

  testWidgets('小米 / 红米手机：默认展开小米那一套、排第一并标「这台手机」，其它折叠可点开', (tester) async {
    mockNative(
      testChannel,
      pin: () => true,
      device: <String, Object?>{
        'manufacturer': 'Xiaomi',
        'brand': 'Redmi',
        'model': '23078RKD5C',
      },
    );
    await openSheet(tester, NativeBridge(channel: testChannel));
    await tapVisible(tester, find.byKey(k('add-widget-manual')));

    expect(stepsOf(WidgetGuideBrand.xiaomi), findsOneWidget);
    for (final b in WidgetGuideBrand.values.where(
      (b) => b != WidgetGuideBrand.xiaomi,
    )) {
      expect(stepsOf(b), findsNothing, reason: b.name);
      expect(find.byKey(k('add-widget-brand-${b.name}')), findsOneWidget);
    }
    expect(find.text('2. 点「添加小组件」（有的版本叫「小部件」）'), findsOneWidget);
    expect(mineTag(WidgetGuideBrand.xiaomi), findsOneWidget);
    expect(find.textContaining('  这台手机', findRichText: true), findsOneWidget);

    // 小米那一套排在最前面。
    final xiaomiY = tester
        .getTopLeft(find.byKey(k('add-widget-brand-xiaomi')))
        .dy;
    for (final b in WidgetGuideBrand.values.where(
      (b) => b != WidgetGuideBrand.xiaomi,
    )) {
      expect(
        tester.getTopLeft(find.byKey(k('add-widget-brand-${b.name}'))).dy,
        greaterThan(xiaomiY),
        reason: b.name,
      );
    }

    // 点开 vivo 那一套也能看；再点小米可以收起。
    await tapVisible(tester, find.byKey(k('add-widget-brand-vivo')));
    expect(stepsOf(WidgetGuideBrand.vivo), findsOneWidget);
    expect(stepsOf(WidgetGuideBrand.xiaomi), findsOneWidget);
    await tapVisible(tester, find.byKey(k('add-widget-brand-xiaomi')));
    expect(stepsOf(WidgetGuideBrand.xiaomi), findsNothing);
    expect(stepsOf(WidgetGuideBrand.vivo), findsOneWidget);
  });

  testWidgets('没有原生端（MissingPlugin）：当成不支持，品牌按「其他」，不崩', (tester) async {
    messenger.setMockMethodCallHandler(testChannel, null);
    await openSheet(tester, NativeBridge(channel: testChannel));
    // 没有 mock 时消息真的发给测试引擎，回复（null → MissingPluginException）
    // 走真实事件循环，fake async 里要让出一点真实时间。
    Future<void> realReply() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    await realReply(); // getDeviceInfo
    await tapVisible(tester, find.byKey(k('add-widget-pin-day')));
    await realReply(); // requestPinWidget

    expect(tester.takeException(), isNull);
    expect(find.text(addWidgetUnsupportedText), findsOneWidget);
    expect(stepsOf(WidgetGuideBrand.other), findsOneWidget);
    expect(stepsOf(WidgetGuideBrand.xiaomi), findsNothing);
    // 拿不到品牌时不标「这台手机」。
    expect(find.textContaining('  这台手机', findRichText: true), findsNothing);
  });

  testWidgets('设置 →「添加桌面小组件」打开面板，走 App 的原生通道', (tester) async {
    mockNative(
      appChannel,
      pin: () => true,
      device: <String, Object?>{'manufacturer': 'vivo', 'brand': 'iQOO'},
    );
    final (AppState state, ThemeController controller) = await loadState(
      tester,
    );
    await pumpApp(
      tester,
      state,
      controller,
      SettingsPage(updateChecker: UpdateChecker(sources: const <String>[])),
      size: const Size(900, 4000),
    );

    await tapVisible(tester, find.byKey(k('settings-add-widget')));
    expect(find.byKey(k('add-widget-sheet')), findsOneWidget);
    expect(inSheet(find.text(addWidgetSheetTitle)), findsOneWidget);

    await tapVisible(tester, find.byKey(k('add-widget-pin-next')));
    expect(pinArgs, <Object?>[
      <String, Object?>{'provider': 'next'},
    ]);
    expect(find.byKey(k('add-widget-status-next')), findsOneWidget);

    await tapVisible(tester, find.byKey(k('add-widget-manual')));
    expect(stepsOf(WidgetGuideBrand.vivo), findsOneWidget);
    expect(stepsOf(WidgetGuideBrand.other), findsNothing);
  });
}
