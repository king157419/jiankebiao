package cn.shu.schedule

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.util.Log
import cn.shu.schedule.widgets.DayWidgetProvider
import cn.shu.schedule.widgets.NextWidgetProvider
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
 *    v1.5.0 起 4×2 和 2×1 两种都能从 App 里加（`provider` 参数），
 *    加上以后 [PinResultReceiver] 弹 Toast「小组件已添加到桌面」。
 * 2. **设备信息**（`getDeviceInfo`，给「反馈 → 复制诊断信息」用）。
 *
 * v1.5.0 删掉了长按图标的静态快捷方式（`getLaunchAction` / `onAction` 那一套）。
 */
class MainActivity : FlutterActivity() {

  private var channel: MethodChannel? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    ch.setMethodCallHandler { call, result ->
      when (call.method) {
        "isPinWidgetSupported" -> result.success(isPinWidgetSupported())
        "requestPinWidget" -> result.success(requestPinWidget(call.argument<String>("provider")))
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
    onPinned = { provider ->
      runOnUiThread { channel?.invokeMethod("onWidgetPinned", provider) }
    }
  }

  override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
    onPinned = null
    channel?.setMethodCallHandler(null)
    channel = null
    super.cleanUpFlutterEngine(flutterEngine)
  }

  /**
   * App 已经在前台（`launchMode="singleTop"`）时新的 Intent（点通知、点小组件）从这里进来。
   * `super` 会转给插件（flutter_local_notifications、home_widget 各自处理自己的 Intent）；
   * `setIntent` 让 `getIntent()` 指向最新的这一个，和 v1.4.0 的行为保持一致。
   */
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
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
   * 请求系统弹出「添加到桌面」确认框。[provider]：`"day"` = 4×2 [DayWidgetProvider]，
   * `"next"` = 2×1 [NextWidgetProvider]，其它值直接返回 false。
   *
   * 用法照官方「Widget discoverability → Let users pin a widget」
   * （developer.android.com/develop/ui/views/appwidgets/discoverability）：
   * successCallback 是一个 `FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE` 的广播 PendingIntent，
   * 指向不导出的 [PinResultReceiver]，小组件真放上桌面后由它弹 Toast。
   *
   * 按 `AppWidgetManager.requestPinAppWidget` 的文档：返回 true 只说明启动器支持这个功能，
   * **不代表确认框一定弹出来了、更不代表已经加上**（有的桌面返回 true 却什么都不弹；
   * 用户点取消也没有任何回调）；返回 false 是系统太老（< API 26）、启动器不支持、
   * 开了应用锁、或调用本身抛了异常（没有前台 Activity 时是 IllegalStateException）。
   * Dart 侧面板两种情况都留着「手动添加」的步骤。
   */
  private fun requestPinWidget(provider: String?): Boolean {
    val providerClass = when (provider) {
      PIN_DAY -> DayWidgetProvider::class.java
      PIN_NEXT -> NextWidgetProvider::class.java
      else -> {
        Log.w(TAG, "requestPinWidget：不认识的 provider=$provider")
        return false
      }
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    return try {
      // 两种小组件各用一个 request code：FLAG_UPDATE_CURRENT 会改写同一个 PendingIntent 的
      // extras，共用的话先点 4×2 再点 2×1，4×2 的回调日志就会写成 next。
      val successCallback = PendingIntent.getBroadcast(
          applicationContext,
          if (provider == PIN_DAY) PIN_RESULT_DAY else PIN_RESULT_NEXT,
          Intent(applicationContext, PinResultReceiver::class.java)
              .putExtra(PinResultReceiver.EXTRA_PROVIDER, provider),
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
      AppWidgetManager.getInstance(this)
          .requestPinAppWidget(ComponentName(this, providerClass), null, successCallback)
    } catch (e: Exception) {
      Log.w(TAG, "requestPinAppWidget 失败（provider=$provider）", e)
      false
    }
  }

  companion object {
    private const val TAG = "ShuNative"

    /** 和 Dart 侧 `NativeBridge.channelName` 一致。 */
    private const val CHANNEL = "cn.shu.schedule/native"

    /** `requestPinWidget` 的 provider 参数，和 Dart 侧 `NativeBridge.pinDay` / `pinNext` 一致。 */
    private const val PIN_DAY = "day"
    private const val PIN_NEXT = "next"

    /**
     * 成功回调 PendingIntent 的 request code（指向 [PinResultReceiver]，
     * 和 widgets/ 里小组件闹钟的 0x5149–0x514C 不是同一个 Intent，这里避开只是为了好查）。
     */
    private const val PIN_RESULT_DAY = 0x5150
    private const val PIN_RESULT_NEXT = 0x5151

    /** [PinResultReceiver] 收到添加成功广播后通知当前存活的 Activity 回传给 Dart。 */
    @Volatile var onPinned: ((String?) -> Unit)? = null
  }
}
