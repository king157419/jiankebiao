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
import java.util.Locale

/** 每天 00:00:30 的跨天刷新广播（显式指向具体 Provider，不需要 manifest intent-filter）。 */
const val ACTION_DAILY_REFRESH = "cn.shu.schedule.action.DAILY_REFRESH"

/**
 * v1.4.0：「下一个时间边界」的重绘广播（课程开始 / 结束、18:00、次日 00:00:30 等，
 * 见 [nextBoundaryMillis]）。和 [ACTION_DAILY_REFRESH] 一样显式指向具体 Provider。
 */
const val ACTION_BOUNDARY_REFRESH = "cn.shu.schedule.action.BOUNDARY_REFRESH"

/** 「某日课程」◀ / ▶ / 回到今天的翻页广播（显式指向 DayWidgetProvider）。 */
const val ACTION_WIDGET_PAGE = "cn.shu.schedule.action.WIDGET_PAGE"

/** 翻页广播里的位移：+1 / -1 往后往前，[PAGE_DELTA_RESET] 回到今天。 */
const val EXTRA_PAGE_DELTA = "cn.shu.schedule.extra.PAGE_DELTA"

/** [EXTRA_PAGE_DELTA] 的特殊值：不加减，直接回到今天。 */
const val PAGE_DELTA_RESET = 0

/** 翻页能走到的最远一天（今天 + 6 = 一周）。 */
const val MAX_DAY_OFFSET = 6

/**
 * 翻页偏移的哨兵：「默认那天」（今天；今天的课上完了就是明天，见 [resolveDisplay]）。
 * 0 = 固定看今天，k ≥ 1 = 固定看今天 + k（v1.4.0 修复轮，fixlist ②：
 * 自动看明天时也能 ◀ 翻回上完课的今天）。
 */
const val OFFSET_DEFAULT = -1

/** 今天没课时，从几点起小组件改看明天（[resolveDisplay]）。 */
const val EVENING_SWITCH_MINUTES = 18 * 60

/** 下一节课在多少分钟内时，头部显示「N 分钟后上课」而不是「下一节 10:00」。 */
const val COUNTDOWN_MINUTES = 90

/** 倒计时期间额外多久重绘一次（非精确闹钟，实际间隔约 10～17 分钟）。 */
const val COUNTDOWN_REFRESH_MINUTES = 10

/** 快照里停课日的 label（和 Dart 侧 `DateOverride.shortLabel` 一致）。 */
const val LABEL_CANCELLED = "停课"

/**
 * 翻页状态的 SharedPreferences 文件名（和 home_widget 的数据分开放）。
 *
 * [DayWidgetProvider]（写）和 [DayWidgetService] 的工厂（读）都要用，
 * 所以 key 的拼法必须放在包级别共享，不能各写各的。
 */
const val PREFS_PAGE = "cn.shu.schedule.widget_page"

/**
 * 修复轮换了 key 名：老版本存的 0 表示「默认那天」，新语义里 0 是「今天」，
 * 换名让升级后残留的老值自然失效（老 key 只是几个孤儿条目，不影响）。
 */
fun keyOffset(widgetId: Int) = "day_offset_$widgetId"

fun keyDate(widgetId: Int) = "date_$widgetId"

/** 打开翻页状态的存储。 */
fun pageStore(context: Context): SharedPreferences =
    context.getSharedPreferences(PREFS_PAGE, Context.MODE_PRIVATE)

/**
 * 读偏移；没存过、存的日期不是今天（跨天了）或类型不对一律当 [OFFSET_DEFAULT]。
 *
 * 偏移的含义（v1.4.0 修复轮）：[OFFSET_DEFAULT] = 「默认那天」，0 = 今天，
 * k ≥ 1 = 「今天 + k」。
 */
fun readOffset(store: SharedPreferences, widgetId: Int, today: String): Int =
    try {
      if (store.getString(keyDate(widgetId), null) != today) OFFSET_DEFAULT
      else clampOffset(store.getInt(keyOffset(widgetId), OFFSET_DEFAULT))
    } catch (e: ClassCastException) {
      OFFSET_DEFAULT
    }

/** 把存储里读出的偏移夹到 [[OFFSET_DEFAULT], [MAX_DAY_OFFSET]]。 */
fun clampOffset(raw: Int): Int = raw.coerceIn(OFFSET_DEFAULT, MAX_DAY_OFFSET)

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
            action == ACTION_BOUNDARY_REFRESH ||
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

  private fun dailyRefreshIntent(context: Context, requestCode: Int): PendingIntent =
      refreshIntent(context, ACTION_DAILY_REFRESH, requestCode)

  /**
   * v1.4.0：在 [atMillis]（墙上时间）给**本 Provider** 发一次 [ACTION_BOUNDARY_REFRESH]，
   * 用来在课程开始 / 结束、18:00、跨天这些时刻把头部状态和「自动看明天」重绘出来。
   *
   * - `AlarmManager.set(RTC, …)`：**非精确、不唤醒**。官方文档：API 19 起 `set` 的时间
   *   「不会提前、但可能推迟」以便系统批量投递；`RTC` 在休眠时不投递，等下次亮屏再送——
   *   屏幕关着没人看小组件，正合适。所以不需要 `SCHEDULE_EXACT_ALARM`。
   * - 同一个 PendingIntent 再 `set` 一次会**替换**旧的，所以每次渲染完直接重新安排即可。
   * - [requestCode] 每个 Provider 一个，且和 [scheduleDailyRefresh] 的不同。
   */
  protected fun scheduleBoundaryRefresh(context: Context, requestCode: Int, atMillis: Long) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    try {
      alarmManager.set(
          AlarmManager.RTC,
          atMillis,
          refreshIntent(context, ACTION_BOUNDARY_REFRESH, requestCode),
      )
    } catch (e: Exception) {
      Log.w(WidgetSnapshot.TAG, "边界刷新闹钟设置失败", e)
    }
  }

  protected fun cancelBoundaryRefresh(context: Context, requestCode: Int) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    try {
      alarmManager.cancel(refreshIntent(context, ACTION_BOUNDARY_REFRESH, requestCode))
    } catch (e: Exception) {
      Log.w(WidgetSnapshot.TAG, "边界刷新闹钟取消失败", e)
    }
  }

  private fun refreshIntent(context: Context, action: String, requestCode: Int): PendingIntent {
    val intent = Intent(context, javaClass).apply { this.action = action }
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
  return String.format(Locale.ROOT, "%04d-%02d-%02d", y, m, d)
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

/**
 * 距今天 [days] 天的中文说法；超过后天就只说「N 天后」。
 *
 * v1.4.0 起 [days] 是**实际日期差**（[DisplayDay.daysFromToday]），不再是翻页偏移：
 * 自动看明天时偏移是 0，但要说「明天」。
 */
fun relativeDayLabel(days: Int): String =
    when (days) {
      0 -> "今天"
      1 -> "明天"
      2 -> "后天"
      else -> "$days 天后"
    }

private val WEEKDAY_NAMES = arrayOf("", "周一", "周二", "周三", "周四", "周五", "周六", "周日")

fun weekdayNameCn(weekday: Int): String = if (weekday in 1..7) WEEKDAY_NAMES[weekday] else ""

// ---------------------------------------------------------------- 显示哪一天（v1.4.0）
//
// 「4×2 显示哪一天」原来在 DayWidgetProvider.render 和 DayRemoteViewsFactory.onDataSetChanged
// 各算一遍（todayIndex + offset），v1.4.0 加了「自动看明天」以后两边必须完全一致，
// 否则会出现头部是明天、列表还是今天的错位，所以收口到 [resolveDisplay] 一处。
// 下面这些函数只用 java.util.Calendar 和快照数据类，不碰 Android API，JVM 单测直接跑
// （android/app/src/test/.../WidgetTimeLogicTest.kt）。

/**
 * [resolveDisplay] 的结果。
 *
 * @property dayIndex 要显示的那天在 `snapshot.days` 里的下标；-1 = 快照里没有（显示「打开 App 刷新」）。
 * @property daysFromToday 这天距今天的**实际日期差**（按日期字符串算，不按下标算），
 *   给 [relativeDayLabel] 用；快照里连今天都找不到时等于传入的偏移。
 * @property autoTomorrow 今天的课已经上完（或今天没课且已过 18:00），默认视图自动切到了明天。
 * @property isHome 这就是「默认那天」（偏移 [OFFSET_DEFAULT] 看到的那天）：不显示「回到今天 / 明天」。
 *   ◀ 是否可用看 [daysFromToday] > 0（自动看明天时默认那天是明天，◀ 能回到今天）。
 */
data class DisplayDay(
    val dayIndex: Int,
    val daysFromToday: Int,
    val autoTomorrow: Boolean,
    val isHome: Boolean,
)

/** [now] 是当天的第几分钟（0..1439）。 */
fun minutesOfDay(now: Calendar): Int = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)

/** 快照里「今天」的下标；没有返回 -1。 */
fun todayIndexOf(snapshot: WidgetSnapshot?, now: Calendar): Int {
  val today = todayKey(now)
  return snapshot?.days?.indexOfFirst { it.date == today } ?: -1
}

/**
 * 今天是否已经「结束」，默认视图该改看明天了：
 * - 今天有课，且最后一节的结束时间 ≤ 现在；
 * - 今天没课（含停课），且现在 ≥ 18:00。
 *
 * 时间解析失败的课（`endMinutes == -1`）不参与「最后一节」的判断；
 * 一节能解析的都没有时当作「还没上完」，宁可不切。
 */
fun isDayOver(day: WidgetDay, nowMinutes: Int): Boolean {
  if (day.courses.isEmpty()) return nowMinutes >= EVENING_SWITCH_MINUTES
  val lastEnd = day.courses.maxOf { it.endMinutes }
  return lastEnd >= 0 && lastEnd <= nowMinutes
}

/**
 * 4×2 小组件这一刻该显示哪一天。[DayWidgetProvider.render] 和 [DayRemoteViewsFactory] 共用。
 *
 * - 「默认那天」：今天；[isDayOver] 为真且快照里有明天时改成明天（[DisplayDay.autoTomorrow]）。
 *   快照只到今天（很久没开 App）时宁可继续显示今天，也不显示「打开 App 刷新」。
 * - [offset] < 0（[OFFSET_DEFAULT]）→ 默认那天；[offset] = k ≥ 0 → 今天 + k（翻页存的是距今天的
 *   天数，见 [nextPageOffset]），这样自动切到明天前后，用户翻到的那天不会跟着跳一天；
 *   自动看明天时 k = 0 就是上完课的今天（fixlist ②）。
 * - 今天 + k 恰好就是默认那天（自动看明天时 k = 1）→ 按默认那天处理。
 */
fun resolveDisplay(snapshot: WidgetSnapshot?, now: Calendar, offset: Int): DisplayDay {
  val days = snapshot?.days
  val todayIndex = todayIndexOf(snapshot, now)
  if (days == null || todayIndex < 0) {
    return DisplayDay(
        dayIndex = -1,
        daysFromToday = offset.coerceAtLeast(0),
        autoTomorrow = false,
        isHome = offset <= 0,
    )
  }

  val auto = isDayOver(days[todayIndex], minutesOfDay(now)) && todayIndex + 1 < days.size
  val homeIndex = if (auto) todayIndex + 1 else todayIndex
  val wanted = if (offset < 0) homeIndex else todayIndex + offset
  val isHome = wanted == homeIndex

  if (wanted >= days.size) {
    return DisplayDay(
        dayIndex = -1,
        daysFromToday = wanted - todayIndex,
        autoTomorrow = false,
        isHome = isHome,
    )
  }
  val diff = daysBetweenIso(days[todayIndex].date, days[wanted].date) ?: (wanted - todayIndex)
  return DisplayDay(
      dayIndex = wanted,
      daysFromToday = diff,
      autoTomorrow = auto && isHome,
      isHome = isHome,
  )
}

/**
 * ◀ / ▶ / 回到今天之后要存的新偏移（距今天的天数；[OFFSET_DEFAULT] = 默认那天）。
 *
 * 从**当前看到的那天**往前 / 往后一天，夹在 [0, MAX_DAY_OFFSET]；
 * 落在默认那天时存 [OFFSET_DEFAULT]，跟着默认那天走（跨过 18:00 / 最后一节下课时自动换）。
 * 自动看明天时，默认那天是明天，◀ 得到 0 = 上完课的今天（头部「今天 · 已结束」），▶ 再回到默认。
 */
fun nextPageOffset(snapshot: WidgetSnapshot?, now: Calendar, current: Int, delta: Int): Int {
  if (delta == PAGE_DELTA_RESET) return OFFSET_DEFAULT
  val home = resolveDisplay(snapshot, now, OFFSET_DEFAULT).daysFromToday
  val shown = resolveDisplay(snapshot, now, current).daysFromToday
  val target = (shown + delta).coerceIn(0, MAX_DAY_OFFSET)
  return if (target == home) OFFSET_DEFAULT else target
}

/** ◀ 可用：看的不是今天（今天之前不能翻）。 */
fun canPagePrev(display: DisplayDay): Boolean = display.daysFromToday > 0

/** ▶ 可用：还没到最远的那天。 */
fun canPageNext(display: DisplayDay): Boolean = display.daysFromToday < MAX_DAY_OFFSET

/**
 * `yyyy-MM-dd` → 自 1970-01-01 起的天数（公历，纯整数运算），解析失败返回 null。
 *
 * 不用 `Calendar` 相减：本机时区有夏令时的话，两个零点之间不一定正好 24 小时
 * （和 Dart 侧 NOTES.md §2.1 同一个坑）。算法：Howard Hinnant `days_from_civil`。
 */
fun epochDayOf(iso: String): Long? {
  val parts = iso.split("-")
  if (parts.size != 3) return null
  val y = parts[0].toIntOrNull() ?: return null
  val m = parts[1].toIntOrNull() ?: return null
  val d = parts[2].toIntOrNull() ?: return null
  if (m !in 1..12 || d !in 1..31) return null
  val yy = (if (m <= 2) y - 1 else y).toLong()
  val era = (if (yy >= 0) yy else yy - 399) / 400
  val yoe = yy - era * 400
  val mp = (m + 9) % 12
  val doy = (153 * mp + 2) / 5 + d - 1
  val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  return era * 146097 + doe - 719468
}

/** 两个 `yyyy-MM-dd` 之间差几天（[to] − [from]）；任一解析失败返回 null。 */
fun daysBetweenIso(from: String, to: String): Int? {
  val a = epochDayOf(from) ?: return null
  val b = epochDayOf(to) ?: return null
  return (b - a).toInt()
}
