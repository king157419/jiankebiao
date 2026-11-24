import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 和 `MainActivity` 那个 MethodChannel 说话的唯一入口。
///
/// 只做两件事：
/// 1. **请求把小组件加到桌面**（`requestPinAppWidget`），
///    省得用户自己去桌面翻「小组件 / 应用挂件」二级菜单；v1.5.0 起
///    4×2（[pinDay]）和 2×1（[pinNext]）两种都能加，加上以后原生弹 Toast；
/// 2. **读设备信息**（[deviceInfo]：反馈里的诊断信息，以及添加小组件面板
///    按手机品牌选手动步骤）。
///
/// v1.5.0 删掉了长按图标的快捷方式（`launchAction` / `actions` 那一套）。
///
/// **所有方法都不抛异常**：iOS / 桌面 / 没有这个插件的环境会抛
/// [MissingPluginException]，老启动器会抛 [PlatformException]，
/// 一律吞掉并返回 false / 空 Map，让调用方走降级路径。
class NativeBridge {
  /// MethodChannel 名字，和 Kotlin 侧 `MainActivity.CHANNEL` 一致。
  static const String channelName = 'cn.shu.schedule/native';

  /// 全局单例。测试里请自己 `NativeBridge(channel: ...)` 造一个。
  static final NativeBridge instance = NativeBridge();

  /// [requestPinWidget] 的 `provider`：4×2「简课表」（Kotlin `DayWidgetProvider`）。
  static const String pinDay = 'day';

  /// [requestPinWidget] 的 `provider`：2×1「下一节课」（Kotlin `NextWidgetProvider`）。
  static const String pinNext = 'next';

  final MethodChannel channel;

  late final StreamController<String> _pinnedController =
      StreamController<String>.broadcast(onListen: _attachHandler);

  NativeBridge({MethodChannel? channel})
    : channel = channel ?? const MethodChannel(channelName);

  /// 原生 `PinResultReceiver` 收到添加成功广播后回传的小组件种类（[pinDay] / [pinNext]）。
  Stream<String> get pinned {
    _attachHandler();
    return _pinnedController.stream;
  }

  void _attachHandler() {
    try {
      channel.setMethodCallHandler(_handleNativeCall);
    } catch (_) {
      // Binding 尚未初始化时忽略，真正监听时再挂。
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onWidgetPinned') {
      final provider = call.arguments;
      if (provider is String && provider.isNotEmpty) {
        _pinnedController.add(provider);
      }
    }
    return null;
  }

  /// 当前系统 + 启动器支不支持「请求添加小组件」的系统弹窗。
  Future<bool> isPinWidgetSupported() => _invokeBool('isPinWidgetSupported');

  /// 请求系统弹出「添加到桌面」确认框，[provider] 是 [pinDay] 或 [pinNext]。
  ///
  /// 返回 true 只代表**启动器说它支持**这个功能——确认框不一定真弹出来了
  /// （有的桌面返回 true 却没反应），用户点了「添加」后原生会自己弹 Toast；
  /// 返回 false 表示这条路走不通（老系统、启动器不支持、不认识的 provider），
  /// 调用方应该改成显示手动添加的步骤。
  Future<bool> requestPinWidget({required String provider}) =>
      _invokeBool('requestPinWidget', <String, Object?>{'provider': provider});

  /// 设备信息（给「反馈 → 复制诊断信息」用）：`release`（Android 版本号，如 `15`）、
  /// `sdkInt`、`manufacturer`、`brand`、`model`。拿不到返回空 Map。
  ///
  /// 只读 `android.os.Build` 的公开字段，不需要任何权限，也不会离开这台手机
  /// （只有用户点「复制」才进剪贴板）。
  Future<Map<String, Object?>> deviceInfo() async {
    try {
      final raw = await channel.invokeMethod<Map<Object?, Object?>>(
        'getDeviceInfo',
      );
      if (raw == null) return const <String, Object?>{};
      return <String, Object?>{
        for (final e in raw.entries)
          if (e.key is String) e.key! as String: e.value,
      };
    } on MissingPluginException {
      return const <String, Object?>{};
    } catch (e) {
      debugPrint('[NativeBridge] getDeviceInfo 失败：$e');
      return const <String, Object?>{};
    }
  }

  Future<bool> _invokeBool(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('[NativeBridge] $method 失败：$e');
      return false;
    } catch (e) {
      debugPrint('[NativeBridge] $method 异常：$e');
      return false;
    }
  }
}
