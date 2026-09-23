package cn.shu.schedule

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.util.Log
import cn.shu.schedule.widgets.DayWidgetProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 唯一的 Activity。
 *
 * 除了跑 Flutter，还负责两件原生的事（都走 [CHANNEL] 这个 MethodChannel）：
 * 1. **直接弹系统的「添加小组件」确认框**（`requestPinAppWidget`，API 26+）。
 *    vivo / MIUI 这类启动器会把第三方小组件埋进「应用挂件」之类的二级菜单里，
 *    让用户自己去桌面翻很不现实，从 App 里弹一个确认框是最短的路径。
 * 2. **长按 App 图标的快捷方式**：静态快捷方式发来的 Intent 落在这里，
 *    冷启动时 Flutter 主动来取（`getLaunchAction`），
 *    App 已经在跑时由 [onNewIntent] 反过来调 Flutter 的 `onAction`。
 */
class MainActivity : FlutterActivity() {

  private var channel: MethodChannel? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    ch.setMethodCallHandler { call, result ->
      when (call.method) {
        "isPinWidgetSupported" -> result.success(isPinWidgetSupported())
        "requestPinWidget" -> result.success(requestPinWidget())
        "getLaunchAction" -> result.success(consumeLaunchAction())
        // 「设置 → 反馈 → 复制诊断信息」用。只读 Build 的公开字段，不需要权限。
        "getDeviceInfo" -> result.success(
            mapOf(
                "release" to Build.VERSION.RELEASE,
                "sdkInt" to Build.VERSION.SDK_INT,
                "manufacturer" to Build.MANUFACTURER,
                "brand" to Build.BRAND,
                "model" to Build.MODEL,
            ),
        )
        else -> result.notImplemented()
      }
    }
    channel = ch
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    channel?.setMethodCallHandler(null)
    channel = null
    super.cleanUpFlutterEngine(flutterEngine)
  }

  /**
   * App 已经在前台（`launchMode="singleTop"`，快捷方式不会新建 Activity）时，
   * 快捷方式的 Intent 从这里进来。
   */
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    val key = shortcutKey(intent.action) ?: return
    // 消费掉，免得之后的 getLaunchAction 又取到同一个。
    intent.action = null
    channel?.invokeMethod("onAction", key)
  }

  // ------------------------------------------------------------ 桌面小组件

  private fun isPinWidgetSupported(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    return try {
      AppWidgetManager.getInstance(this).isRequestPinAppWidgetSupported
    } catch (e: Exception) {
      Log.w(TAG, "查询 isRequestPinAppWidgetSupported 失败", e)
      false
    }
  }

  /**
   * 请求系统弹出「添加到桌面」确认框。
   *
   * 返回 false 有三种可能：系统太老（< API 26）、启动器不支持、调用本身抛了异常。
   * 这三种情况 Dart 侧都会退回去显示「手动添加」的图文步骤。
   */
  private fun requestPinWidget(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    return try {
      AppWidgetManager.getInstance(this)
          .requestPinAppWidget(
              ComponentName(this, DayWidgetProvider::class.java),
              null,
              null,
          )
    } catch (e: Exception) {
      Log.w(TAG, "requestPinAppWidget 失败", e)
      false
    }
  }

  // ------------------------------------------------------------ 快捷方式

  /**
   * 取本次启动携带的快捷方式动作，取完就清掉。
   *
   * 清掉这一步很重要：`getIntent()` 会在配置变更（旋转、深色模式切换）后原样重放，
   * 不清的话每次重建都会再触发一次跳转。
   */
  private fun consumeLaunchAction(): String? {
    val current = intent ?: return null
    val key = shortcutKey(current.action) ?: return null
    current.action = null
    return key
  }

  /** `cn.shu.schedule.action.SHORTCUT_TODAY` → `today`；不是快捷方式动作返回 null。 */
  private fun shortcutKey(action: String?): String? {
    if (action == null || !action.startsWith(SHORTCUT_PREFIX)) return null
    val key = action.removePrefix(SHORTCUT_PREFIX).lowercase()
    return if (key.isBlank()) null else key
  }

  companion object {
    private const val TAG = "ShuNative"

    /** 和 Dart 侧 `NativeBridge.channelName` 一致。 */
    private const val CHANNEL = "cn.shu.schedule/native"

    /** 静态快捷方式 action 的前缀，和 res/xml/shortcuts.xml 一致。 */
    private const val SHORTCUT_PREFIX = "cn.shu.schedule.action.SHORTCUT_"
  }
}
