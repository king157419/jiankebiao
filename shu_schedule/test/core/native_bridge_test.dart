import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channel = MethodChannel(NativeBridge.channelName);

  late NativeBridge bridge;
  late List<String> calls;
  late List<Object?> arguments;

  setUp(() {
    calls = <String>[];
    arguments = <Object?>[];
    bridge = NativeBridge(channel: channel);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  /// 装一个「原生端」；[answers] 里没有的方法返回 null。
  void mockNative(Map<String, Object?> answers) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      arguments.add(call.arguments);
      return answers[call.method];
    });
  }

  group('原生可用时', () {
    test('isPinWidgetSupported / requestPinWidget 透传 true', () async {
      mockNative(<String, Object?>{
        'isPinWidgetSupported': true,
        'requestPinWidget': true,
      });
      expect(await bridge.isPinWidgetSupported(), isTrue);
      expect(
        await bridge.requestPinWidget(provider: NativeBridge.pinDay),
        isTrue,
      );
      expect(calls, <String>['isPinWidgetSupported', 'requestPinWidget']);
    });

    // v1.5.0（D4）：两种小组件都能从 App 里加，provider 原样交给 Kotlin。
    test('requestPinWidget 把 provider 透传给原生（day / next）', () async {
      mockNative(<String, Object?>{'requestPinWidget': true});
      expect(NativeBridge.pinDay, 'day');
      expect(NativeBridge.pinNext, 'next');
      expect(
        await bridge.requestPinWidget(provider: NativeBridge.pinDay),
        isTrue,
      );
      expect(
        await bridge.requestPinWidget(provider: NativeBridge.pinNext),
        isTrue,
      );
      expect(calls, <String>['requestPinWidget', 'requestPinWidget']);
      expect(arguments, <Object?>[
        <String, Object?>{'provider': 'day'},
        <String, Object?>{'provider': 'next'},
      ]);
    });

    test('isPinWidgetSupported / getDeviceInfo 不带参数', () async {
      mockNative(<String, Object?>{
        'isPinWidgetSupported': true,
        'getDeviceInfo': <String, Object?>{'brand': 'Redmi'},
      });
      await bridge.isPinWidgetSupported();
      expect(await bridge.deviceInfo(), <String, Object?>{'brand': 'Redmi'});
      expect(arguments, <Object?>[null, null]);
    });

    test('原生返回 false 时如实返回 false', () async {
      mockNative(<String, Object?>{'requestPinWidget': false});
      expect(
        await bridge.requestPinWidget(provider: NativeBridge.pinNext),
        isFalse,
      );
    });

    test('原生返回 null 时当成 false（老启动器什么都不给）', () async {
      mockNative(<String, Object?>{});
      expect(await bridge.isPinWidgetSupported(), isFalse);
      expect(
        await bridge.requestPinWidget(provider: NativeBridge.pinDay),
        isFalse,
      );
    });

    test('pinned 流：原生发 onWidgetPinned 时透传 provider，忽略空值与非字符串', () async {
      final received = <String>[];
      final sub = bridge.pinned.listen(received.add);
      addTearDown(sub.cancel);

      Future<void> emitFromNative(String method, Object? arg) async {
        final data = const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arg),
        );
        await messenger.handlePlatformMessage(
          NativeBridge.channelName,
          data,
          (_) {},
        );
        await Future<void>.delayed(Duration.zero);
      }

      await emitFromNative('onWidgetPinned', 'day');
      await emitFromNative('onWidgetPinned', '');
      await emitFromNative('onWidgetPinned', null);
      await emitFromNative('otherMethod', 'day');
      await emitFromNative('onWidgetPinned', 'next');

      expect(received, <String>['day', 'next']);
    });
  });

  group('原生抛异常时都要降级而不是崩', () {
    test('PlatformException → false / 空 Map', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'BOOM', message: '启动器不认这个 API');
      });
      expect(await bridge.isPinWidgetSupported(), isFalse);
      expect(
        await bridge.requestPinWidget(provider: NativeBridge.pinNext),
        isFalse,
      );
      expect(await bridge.deviceInfo(), isEmpty);
    });

    test('MissingPluginException（没有原生实现）→ false / 空 Map', () async {
      // 不装 handler，MethodChannel 自己就会抛 MissingPluginException。
      messenger.setMockMethodCallHandler(channel, null);
      expect(await bridge.isPinWidgetSupported(), isFalse);
      expect(
        await bridge.requestPinWidget(provider: NativeBridge.pinNext),
        isFalse,
      );
      expect(await bridge.deviceInfo(), isEmpty);
    });
  });

  // v1.5.0（PLAN-1.5 D3）：长按图标的三个快捷方式整套删掉，这里钉住不要残留。
  group('长按图标快捷方式已删除', () {
    const res = 'android/app/src/main/res';

    test('shortcuts.xml 和三张图标都不在了', () {
      expect(File('$res/xml/shortcuts.xml').existsSync(), isFalse);
      for (final name in <String>['today', 'import', 'add_widget']) {
        expect(
          File('$res/drawable/ic_shortcut_$name.xml').existsSync(),
          isFalse,
          reason: 'ic_shortcut_$name.xml 还在',
        );
      }
    });

    test('Manifest / strings / MainActivity 里没有快捷方式的引用', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(manifest, isNot(contains('android.app.shortcuts')));
      expect(manifest, isNot(contains('SHORTCUT_')));
      // 小组件点击拉起 App 的 intent-filter 保留。
      expect(manifest, contains('es.antonborri.home_widget.action.LAUNCH'));

      final strings = File('$res/values/strings.xml').readAsStringSync();
      expect(strings, isNot(contains('name="shortcut_')));

      final activity = File(
        'android/app/src/main/kotlin/cn/shu/schedule/MainActivity.kt',
      ).readAsStringSync();
      for (final gone in <String>[
        '"getLaunchAction"',
        '"onAction"',
        'SHORTCUT_PREFIX',
        'consumeLaunchAction',
      ]) {
        expect(activity, isNot(contains(gone)), reason: '残留：$gone');
      }
      // 小组件和诊断信息的通道方法还在。
      for (final kept in <String>[
        '"isPinWidgetSupported"',
        '"requestPinWidget"',
        '"getDeviceInfo"',
      ]) {
        expect(activity, contains(kept), reason: '缺少：$kept');
      }
    });
  });
}
