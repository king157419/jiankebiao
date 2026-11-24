package cn.shu.schedule.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import cn.shu.schedule.MainActivity
import cn.shu.schedule.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.util.Calendar

/**
 * 「简课表」4×2 小组件（v1.4.0 另有 2×1 的 [NextWidgetProvider]；两种都能在 App 里一键添加）。
 *
 * - ◀ / ▶ 翻看一周内的任意一天，偏移量以 **appWidgetId 为单位**存在
 *   [PREFS_PAGE] 里，所以同一个小组件放两份、各翻各的互不影响，跨天自动回到默认那天。
 *   偏移是「距今天的天数」，[OFFSET_DEFAULT] 表示默认那天；自动看明天时 ◀ 能翻回今天。
 * - 当天的课放在一个 RemoteViews `ListView`（[R.id.day_list]）里，**可以上下滑动**，
 *   数据由 [DayWidgetService] 的工厂提供，不再有「最多 6 行 + 还有 N 门」的限制。
 * - v1.4.0：今天的课上完了（或今天没课且过了 18:00）默认改看明天；头部副标题按现在的时间
 *   显示「上课中 · 至 11:50」/「51 分钟后上课」/「下一节 10:00」（[resolveDisplay]、[dayHeaderSub]）。
 *
 * 数据来自 Flutter 写的快照 JSON（今天起整学期，最多 150 天），翻页只是换一天渲染，
 * **不需要 Flutter 引擎在跑**。
 *
 * 刷新来源：30 分钟系统周期、每天 00:00:30 的跨天闹钟、v1.4.0 的「下一个时间边界」闹钟
 * （[nextBoundaryMillis]，每次渲染后重排）、App 里 `WidgetSync.push` 之后的 `HomeWidget.updateWidget`
 * （App 启动、数据变化、回到前台都会推）。
 */
class DayWidgetProvider : ShuWidgetProvider() {

  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == ACTION_WIDGET_PAGE) {
      handlePage(context, intent)
      return
    }
    super.onReceive(context, intent)
  }

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val snapshot = WidgetSnapshot.read(widgetData)
    val palette = snapshot?.palette ?: WidgetPalette.FALLBACK
    val now = Calendar.getInstance()
    val today = todayKey(now)
    val store = pageStore(context)

    appWidgetIds.forEach { widgetId ->
      try {
        val offset = readOffset(store, widgetId, today)
        val views = RemoteViews(context.packageName, R.layout.widget_day)
        render(context, views, palette, snapshot, now, offset, widgetId)
        appWidgetManager.updateAppWidget(widgetId, views)
        // 列表的内容不在 RemoteViews 里，必须单独通知系统「数据变了」，
        // 否则翻页 / 推送之后列表还是旧的那一天。
        appWidgetManager.notifyAppWidgetViewDataChanged(widgetId, R.id.day_list)
      } catch (e: Exception) {
        Log.w(WidgetSnapshot.TAG, "小组件渲染失败", e)
      }
    }

    // 下一个课程开始 / 结束、18:00 或跨天时再画一次（非精确、不唤醒，见 scheduleBoundaryRefresh）。
    scheduleBoundaryRefresh(context, REQUEST_BOUNDARY_REFRESH, nextBoundaryMillis(snapshot, now))
  }

  override fun onEnabled(context: Context) {
    super.onEnabled(context)
    scheduleDailyRefresh(context, REQUEST_DAILY_REFRESH)
  }

  override fun onDisabled(context: Context) {
    super.onDisabled(context)
    cancelDailyRefresh(context, REQUEST_DAILY_REFRESH)
    cancelBoundaryRefresh(context, REQUEST_BOUNDARY_REFRESH)
  }

  /** 小组件被拖走时清掉它的翻页状态，免得 id 被系统复用后继承上一个的偏移。 */
  override fun onDeleted(context: Context, appWidgetIds: IntArray) {
    super.onDeleted(context, appWidgetIds)
    try {
      pageStore(context).edit().apply {
        appWidgetIds.forEach {
          remove(keyOffset(it))
          remove(keyDate(it))
        }
        apply()
      }
    } catch (e: Exception) {
      Log.w(WidgetSnapshot.TAG, "翻页状态清理失败", e)
    }
  }

  // ---------------------------------------------------------------- 翻页

  /**
   * 处理 ◀ / ▶ / 回到今天：改存储里的偏移，再让自己走一次正常 update。
   *
   * 新偏移从「现在看到的那天」算（[nextPageOffset]），所以要先读一次快照，知道今天是否已自动切到明天。
   */
  private fun handlePage(context: Context, intent: Intent) {
    val widgetId =
        intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
    if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

    try {
      val now = Calendar.getInstance()
      val today = todayKey(now)
      val store = pageStore(context)
      val delta = intent.getIntExtra(EXTRA_PAGE_DELTA, PAGE_DELTA_RESET)
      val snapshot = WidgetSnapshot.read(HomeWidgetPlugin.getData(context))
      val next = nextPageOffset(snapshot, now, readOffset(store, widgetId, today), delta)
      store.edit().putInt(keyOffset(widgetId), next).putString(keyDate(widgetId), today).apply()
    } catch (e: Exception) {
      Log.w(WidgetSnapshot.TAG, "翻页状态写入失败", e)
    }

    // 走基类那条「补全 appWidgetIds」的路，由 HomeWidgetProvider 自己去取快照。
    super.onReceive(
        context,
        Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, intArrayOf(widgetId))
        },
    )
  }

  // ---------------------------------------------------------------- 渲染

  private fun render(
      context: Context,
      views: RemoteViews,
      palette: WidgetPalette,
      snapshot: WidgetSnapshot?,
      now: Calendar,
      offset: Int,
      widgetId: Int,
  ) {
    views.applySurface(R.id.day_root, palette.surface)

    // 点击除按钮以外的地方打开 App。
    val launch = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
    views.setOnClickPendingIntent(R.id.day_root, launch)
    views.setOnClickPendingIntent(R.id.day_prev, pageIntent(context, widgetId, -1))
    views.setOnClickPendingIntent(R.id.day_next, pageIntent(context, widgetId, 1))
    // 日期块和「回到今天」都指向 reset，用户点哪个都行。
    val reset = pageIntent(context, widgetId, PAGE_DELTA_RESET)
    views.setOnClickPendingIntent(R.id.day_header, reset)
    views.setOnClickPendingIntent(R.id.day_back_today, reset)

    views.setTextColor(R.id.day_header_date, palette.text)
    views.setTextColor(R.id.day_header_sub, palette.mutedText)
    views.setTextColor(R.id.day_back_today, palette.accent)
    views.setTextColor(R.id.day_empty, palette.mutedText)

    // 显示哪一天：和列表的工厂（DayRemoteViewsFactory）走同一个 resolveDisplay，不会错位。
    val display = resolveDisplay(snapshot, now, offset)

    // 箭头到头了就调灰，仍然可点（点了是个空操作，clamp 住）。
    // ◀ 看的是「是不是今天」而不是「是不是默认那天」：自动看明天时能翻回今天（fixlist ②）。
    val disabled = blendColors(palette.mutedText, palette.surface, 0.35f)
    views.setTextColor(R.id.day_prev, if (canPagePrev(display)) palette.accent else disabled)
    views.setTextColor(R.id.day_next, if (canPageNext(display)) palette.accent else disabled)

    // 列表：每个小组件实例一个适配器。Intent 的 data 必须逐实例唯一，
    // 否则系统会把两个小组件当成同一个适配器复用（extras 不参与判重）。
    val adapterIntent =
        Intent(context, DayWidgetService::class.java).apply {
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
          data = Uri.parse("shuwidget://list/$widgetId")
        }
    views.setRemoteAdapter(R.id.day_list, adapterIntent)
    // 列表为空（这天没课 / 快照缺失）时自动显示 day_empty。
    views.setEmptyView(R.id.day_list, R.id.day_empty)
    // 列表项自己不能带 PendingIntent，只能由这个模板 + 每项的 fill-in Intent 合成。
    views.setPendingIntentTemplate(R.id.day_list, launch)

    val day = snapshot?.days?.getOrNull(display.dayIndex)

    if (day == null) {
      // 快照里连今天都没有：App 太久没打开，或者还没推过数据。
      views.setViewVisibility(R.id.day_back_today, View.GONE)
      views.setTextViewText(R.id.day_header_date, formatDateCn(todayKey(now)))
      views.setTextViewText(R.id.day_header_sub, "")
      views.setTextViewText(R.id.day_empty, context.getString(R.string.widget_need_refresh))
      return
    }

    // 「回到今天」只在翻离默认那天时出现；默认那天已自动切到明天时，按钮说「回到明天」。
    views.setViewVisibility(R.id.day_back_today, if (display.isHome) View.GONE else View.VISIBLE)
    val homeIsTomorrow = resolveDisplay(snapshot, now, OFFSET_DEFAULT).autoTomorrow
    views.setTextViewText(
        R.id.day_back_today,
        context.getString(
            if (homeIsTomorrow) R.string.widget_back_to_tomorrow else R.string.widget_back_to_today
        ),
    )
    views.setTextViewText(
        R.id.day_header_date,
        "${formatDateCn(day.date)} ${weekdayNameCn(day.weekday)}".trim(),
    )
    views.setTextViewText(R.id.day_header_sub, dayHeaderSub(day, display, minutesOfDay(now)))
    // 空态文案要在 updateAppWidget 之前设好：列表真的空了时 setEmptyView 会把它显出来。
    // 停课的日子（快照 label = 「停课」）换成停课文案，有备注时另起一行附上。
    val isToday = display.daysFromToday == 0
    val cancelled = day.label == LABEL_CANCELLED
    val emptyText =
        if (cancelled) {
          val base =
              context.getString(
                  if (isToday) R.string.widget_empty_today_cancelled
                  else R.string.widget_empty_other_day_cancelled
              )
          val note = day.note?.takeIf { it != LABEL_CANCELLED }
          if (note.isNullOrEmpty()) base else base + "\n" + note
        } else {
          context.getString(
              if (isToday) R.string.widget_empty_today_rest else R.string.widget_empty_other_day
          )
        }
    views.setTextViewText(R.id.day_empty, emptyText)
  }

  /**
   * 翻页按钮的 PendingIntent。
   *
   * 每个 (widgetId, delta) 必须有**互不相同的 `Intent.data`**：
   * `PendingIntent` 判重时只看 action/data/type/component/category，**不看 extras**，
   * 同一个 data 的话几个按钮会拿到同一个 PendingIntent，第二个小组件会顶掉第一个。
   */
  private fun pageIntent(context: Context, widgetId: Int, delta: Int): PendingIntent {
    val intent =
        Intent(context, DayWidgetProvider::class.java).apply {
          action = ACTION_WIDGET_PAGE
          data = Uri.parse("shuwidget://day/$widgetId/$delta")
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
          putExtra(EXTRA_PAGE_DELTA, delta)
        }
    return PendingIntent.getBroadcast(
        context,
        0,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  companion object {
    /** 跨天闹钟的 request code（[NextWidgetProvider] 用另外的值）。 */
    private const val REQUEST_DAILY_REFRESH = 0x5149

    /** v1.4.0「下一个时间边界」重绘闹钟的 request code。 */
    private const val REQUEST_BOUNDARY_REFRESH = 0x514A
  }
}
