package cn.shu.schedule

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast

/**
 * v1.5.0：App 内「添加到桌面」成功后的回调（`requestPinAppWidget` 的 successCallback）。
 *
 * 只有用户在启动器的确认框里点了「添加」、小组件真的放上桌面之后才会收到；
 * 用户取消或启动器不理这个请求时**什么都不会来**（AppWidgetManager 文档原话），
 * 所以 Dart 侧的面板不管原生返回什么都留着「没弹出确认框？」的手动入口。
 *
 * `exported=false`：广播由 [MainActivity] 建的 PendingIntent 以本 App 的身份发出，
 * 不导出也收得到，别的 App 也就没法伪造这条广播来弹 Toast。
 *
 * PendingIntent 是 `FLAG_IMMUTABLE`，启动器填进来的 `EXTRA_APPWIDGET_ID` 会被丢掉；
 * 这里只弹一句提示，用不到小组件 id。哪种小组件看 [EXTRA_PROVIDER]（发请求时就写好了）。
 * `onReceive` 在主线程执行，可以直接 Toast。
 */
class PinResultReceiver : BroadcastReceiver() {

  override fun onReceive(context: Context, intent: Intent) {
    val provider = intent.getStringExtra(EXTRA_PROVIDER)
    Log.i(TAG, "小组件已添加到桌面：provider=$provider")
    Toast.makeText(context, R.string.widget_pinned_toast, Toast.LENGTH_SHORT).show()
    MainActivity.onPinned?.invoke(provider)
  }

  companion object {
    const val TAG = "ShuPinResult"

    /** 发请求时写进 Intent 的小组件种类（`"day"` / `"next"`），只用于日志。 */
    const val EXTRA_PROVIDER = "cn.shu.schedule.extra.PIN_PROVIDER"
  }
}
