package cn.shu.schedule.widgets

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/** 每天 00:00:30 的跨天刷新广播（显式指向具体 Provider，不需要 manifest intent-filter）。 */
const val ACTION_DAILY_REFRESH = "cn.shu.schedule.action.DAILY_REFRESH"

/** 「某日课程」◀ / ▶ / 回到今天的翻页广播（显式指向 DayWidgetProvider）。 */
const val ACTION_WIDGET_PAGE = "cn.shu.schedule.action.WIDGET_PAGE"

/** 翻页广播里的位移：+1 / -1 往后往前，[PAGE_DELTA_RESET] 回到今天。 */
const val EXTRA_PAGE_DELTA = "cn.shu.schedule.extra.PAGE_DELTA"

/** [EXTRA_PAGE_DELTA] 的特殊值：不加减，直接回到今天。 */
const val PAGE_DELTA_RESET = 0

/** 翻页能走到的最远一天（今天 + 6 = 一周）。 */
const val MAX_DAY_OFFSET = 6

/**
 * 翻页状态的 SharedPreferences 文件名（和 home_widget 的数据分开放）。
 *
 * [DayWidgetProvider]（写）和 [DayWidgetService] 的工厂（读）都要用，
 * 所以 key 的拼法必须放在包级别共享，不能各写各的。
 */
const val PREFS_PAGE = "cn.shu.schedule.widget_page"

fun keyOffset(widgetId: Int) = "offset_$widgetId"

fun keyDate(widgetId: Int) = "date_$widgetId"

/** 打开翻页状态的存储。 */
fun pageStore(context: Context): SharedPreferences =
    context.getSharedPreferences(PREFS_PAGE, Context.MODE_PRIVATE)

/** 读偏移；存的日期不是今天（跨天了）或超出范围一律当 0。 */
fun readOffset(store: SharedPreferences, widgetId: Int, today: String): Int =
    try {
      if (store.getString(keyDate(widgetId), null) != today) 0
      else store.getInt(keyOffset(widgetId), 0).coerceIn(0, MAX_DAY_OFFSET)
    } catch (e: ClassCastException) {
      0
    }

/**
 * 小组件的公共基类。
 *
 * 只做一件事：**补全 appWidgetIds**。
 * `AppWidgetProvider.onReceive` 只有在 `ACTION_APPWIDGET_UPDATE` 带
 * `EXTRA_APPWIDGET_IDS` 时才会调 `onUpdate`。AlarmManager 定时广播和
 * `adb shell am broadcast -a android.appwidget.action.APPWIDGET_UPDATE -n <provider>`
 * 都带不了 id，所以这里自己查一遍再转发。
 */
abstract class ShuWidgetProvider : HomeWidgetProvider() {

  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action
    val needsIds =
        action == ACTION_DAILY_REFRESH ||
            (action == AppWidgetManager.ACTION_APPWIDGET_UPDATE &&
                intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)?.isNotEmpty() !=
                    true)

    if (needsIds) {
      val ids =
          try {
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, javaClass))
          } catch (e: Exception) {
            null
          }
      if (ids == null || ids.isEmpty()) return
      val filled =
          Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
          }
      super.onReceive(context, filled)
      return
    }

    super.onReceive(context, intent)
  }

  /**
   * 每天 00:00:30 给**本 Provider** 发一次 [ACTION_DAILY_REFRESH]。
   *
   * 用 `setInexactRepeating` 而不是 `setExactAndAllowWhileIdle`：精确闹钟在
   * Android 12+ 需要 `SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM` 权限，
   * 课表小组件晚几分钟换天完全无所谓，不值得为此申请权限。
   *
   * [requestCode] 每个 Provider 必须不同，否则后注册的会顶掉先注册的 PendingIntent。
   */
  protected fun scheduleDailyRefresh(context: Context, requestCode: Int) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    val next =
        Calendar.getInstance().apply {
          set(Calendar.HOUR_OF_DAY, 0)
          set(Calendar.MINUTE, 0)
          set(Calendar.SECOND, 30)
          set(Calendar.MILLISECOND, 0)
          if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
    try {
      alarmManager.setInexactRepeating(
          AlarmManager.RTC,
          next.timeInMillis,
          AlarmManager.INTERVAL_DAY,
          dailyRefreshIntent(context, requestCode),
      )
    } catch (e: Exception) {
      Log.w(WidgetSnapshot.TAG, "跨天闹钟设置失败", e)
    }
  }

  protected fun cancelDailyRefresh(context: Context, requestCode: Int) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    try {
      alarmManager.cancel(dailyRefreshIntent(context, requestCode))
    } catch (e: Exception) {
      Log.w(WidgetSnapshot.TAG, "跨天闹钟取消失败", e)
    }
  }

  private fun dailyRefreshIntent(context: Context, requestCode: Int): PendingIntent {
    val intent = Intent(context, javaClass).apply { action = ACTION_DAILY_REFRESH }
    return PendingIntent.getBroadcast(
        context,
        requestCode,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }
}

/**
 * 给根容器上主题底板色。
 *
 * API 31+ 用 `setBackgroundTintList` 给 `widget_bg_rounded` 着色，圆角保留；
 * 更低版本没有 `RemoteViews.setColorStateList`，只能直接设背景色（会丢圆角）。
 */
fun RemoteViews.applySurface(viewId: Int, color: Int) {
  if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
    setColorStateList(viewId, "setBackgroundTintList", ColorStateList.valueOf(color))
  } else {
    setInt(viewId, "setBackgroundColor", color)
  }
}

/** 把 [fg] 以 [alpha] 的比例压在不透明的 [bg] 上，得到一个不透明色。 */
fun blendColors(fg: Int, bg: Int, alpha: Float): Int {
  val a = alpha.coerceIn(0f, 1f)
  fun ch(shift: Int): Int {
    val f = (fg shr shift) and 0xFF
    val b = (bg shr shift) and 0xFF
    return (f * a + b * (1 - a)).toInt().coerceIn(0, 255)
  }
  return (0xFF shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
}

/** 设备当前日期，格式 `yyyy-MM-dd`，用于在快照里找「今天」。 */
fun todayKey(calendar: Calendar = Calendar.getInstance()): String {
  val y = calendar.get(Calendar.YEAR)
  val m = calendar.get(Calendar.MONTH) + 1
  val d = calendar.get(Calendar.DAY_OF_MONTH)
  return String.format("%04d-%02d-%02d", y, m, d)
}

/** `"2026-09-16"` → `"9月16日"`；解析失败原样返回。 */
fun formatDateCn(iso: String): String {
  val parts = iso.split("-")
  if (parts.size != 3) return iso
  val m = parts[1].toIntOrNull() ?: return iso
  val d = parts[2].toIntOrNull() ?: return iso
  return "${m}月${d}日"
}

/** `"08:00"` + `"09:40"` → `"08:00-09:40"`；缺一半时只显示另一半。 */
fun formatCourseSpan(start: String, end: String): String =
    when {
      start.isBlank() && end.isBlank() -> ""
      end.isBlank() -> start
      start.isBlank() -> end
      else -> "$start-$end"
    }

/** 距今天 [offset] 天的中文说法；超过后天就只说「N 天后」。 */
fun relativeDayLabel(offset: Int): String =
    when (offset) {
      0 -> "今天"
      1 -> "明天"
      2 -> "后天"
      else -> "$offset 天后"
    }

private val WEEKDAY_NAMES = arrayOf("", "周一", "周二", "周三", "周四", "周五", "周六", "周日")

fun weekdayNameCn(weekday: Int): String = if (weekday in 1..7) WEEKDAY_NAMES[weekday] else ""
