import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shu_schedule/core/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  final channel = MethodChannel(NativeBridge.channelName);

  late NativeBridge bridge;
  late List<String> calls;

  setUp(() {
    calls = <String>[];
    bridge = NativeBridge(channel: channel);
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await bridge.dispose();
  });

  /// 装一个「原生端」；[answers] 里没有的方法返回 null。
  void mockNative(Map<String, Object?> answers) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
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
      expect(await bridge.requestPinWidget(), isTrue);
      expect(calls, <String>['isPinWidgetSupported', 'requestPinWidget']);
    });

    test('原生返回 false 时如实返回 false', () async {
      mockNative(<String, Object?>{'requestPinWidget': false});
      expect(await bridge.requestPinWidget(), isFalse);
    });

    test('原生返回 null 时当成 false（老启动器什么都不给）', () async {
      mockNative(<String, Object?>{});
      expect(await bridge.isPinWidgetSupported(), isFalse);
      expect(await bridge.requestPinWidget(), isFalse);
    });

    test('launchAction 取到快捷方式动作', () async {
      mockNative(<String, Object?>{'getLaunchAction': 'import'});
      expect(await bridge.launchAction(), 'import');
    });

    test('没有快捷方式时 launchAction 返回 null', () async {
      mockNative(<String, Object?>{'getLaunchAction': null});
      expect(await bridge.launchAction(), isNull);
    });
  });

  group('原生抛异常时都要降级而不是崩', () {
    test('PlatformException → false / null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'BOOM', message: '启动器不认这个 API');
      });
      expect(await bridge.isPinWidgetSupported(), isFalse);
      expect(await bridge.requestPinWidget(), isFalse);
      expect(await bridge.launchAction(), isNull);
    });

    test('MissingPluginException（没有原生实现）→ false / null', () async {
      // 不装 handler，MethodChannel 自己就会抛 MissingPluginException。
      messenger.setMockMethodCallHandler(channel, null);
      expect(await bridge.isPinWidgetSupported(), isFalse);
      expect(await bridge.requestPinWidget(), isFalse);
      expect(await bridge.launchAction(), isNull);
    });
  });

  group('onAction', () {
    test('原生推来的动作会从 actions 流里出来', () async {
      final seen = <String>[];
      final sub = bridge.actions.listen(seen.add);

      await messenger.handlePlatformMessage(
        NativeBridge.channelName,
        codec.encodeMethodCall(const MethodCall('onAction', 'today')),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        NativeBridge.channelName,
        codec.encodeMethodCall(const MethodCall('onAction', 'add_widget')),
        (_) {},
      );
      // 空串和非字符串都该被挡掉。
      await messenger.handlePlatformMessage(
        NativeBridge.channelName,
        codec.encodeMethodCall(const MethodCall('onAction', '')),
        (_) {},
      );
      await messenger.handlePlatformMessage(
        NativeBridge.channelName,
        codec.encodeMethodCall(const MethodCall('onAction', 42)),
        (_) {},
      );
      // 不认识的方法不该炸。
      await messenger.handlePlatformMessage(
        NativeBridge.channelName,
        codec.encodeMethodCall(const MethodCall('somethingElse')),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);
      expect(seen, <String>['today', 'add_widget']);
      await sub.cancel();
    });
  });
}
