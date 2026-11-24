package cn.shu.schedule.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import cn.shu.schedule.MainActivity
import cn.shu.schedule.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import java.util.Calendar

/**
 * v1.4.0「下一节」2×1 小组件：只显示一节课（课程名 / 时间 / 地点三行，没有列表、没有翻页）。
 *
 * 内容（[findNextClass]）：今天正在上或下一节；今天没了就是明天第一节，第二行标「明天」；
 * 都没有显示「近期没有课程」；快照里连今天都没有显示「打开 App 刷新课表」。
 *
 * 和 4×2 的 [DayWidgetProvider] 读同一份快照，刷新来源也一样：30 分钟系统周期、
 * 自己的每日 00:00:30 闹钟、自己的「下一个时间边界」闹钟（request code 都和 4×2 不同）、
 * App 推送时 `WidgetSync.refreshTargets` 里的 `HomeWidget.updateWidget`。
 *
 * v1.5.0 起和 4×2 一样能在 App 里一键添加（`MainActivity.requestPinWidget`，provider = `"next"`）。
 */
class NextWidgetProvider : ShuWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    val snapshot = WidgetSnapshot.read(widgetData)
    val palette = snapshot?.palette ?: WidgetPalette.FALLBACK
    val now = Calendar.getInstance()

    appWidgetIds.forEach { widgetId ->
      try {
        val views = RemoteViews(context.packageName, R.layout.widget_next)
        render(context, views, palette, snapshot, now)
        appWidgetManager.updateAppWidget(widgetId, views)
      } catch (e: Exception) {
        Log.w(WidgetSnapshot.TAG, "「下一节」小组件渲染失败", e)
      }
    }

    // 课程开始 / 结束、跨天时再画一次（非精确、不唤醒）。
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

  private fun render(
      context: Context,
      views: RemoteViews,
      palette: WidgetPalette,
      snapshot: WidgetSnapshot?,
      now: Calendar,
  ) {
    views.applySurface(R.id.next_root, palette.surface)
    views.setOnClickPendingIntent(
        R.id.next_root,
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
    )

    val next = findNextClass(snapshot, now)
    if (next == null) {
      // 只剩一行灰字，竖直居中。
      val message =
          if (todayIndexOf(snapshot, now) < 0) R.string.widget_need_refresh
          else R.string.widget_next_none
      views.setViewVisibility(R.id.next_bar, View.GONE)
      views.setViewVisibility(R.id.next_time, View.GONE)
      views.setViewVisibility(R.id.next_location, View.GONE)
      views.setTextViewText(R.id.next_name, context.getString(message))
      views.setTextColor(R.id.next_name, palette.mutedText)
      return
    }

    val course = next.course
    views.setViewVisibility(R.id.next_bar, View.VISIBLE)
    views.setInt(R.id.next_bar, "setBackgroundColor", course.color)

    views.setTextViewText(R.id.next_name, course.name)
    views.setTextColor(R.id.next_name, palette.text)

    views.setViewVisibility(R.id.next_time, View.VISIBLE)
    views.setTextViewText(R.id.next_time, nextClassTimeText(next))
    // 今天的（上课中 / 下一节）用强调色，明天的用次要色。
    views.setTextColor(
        R.id.next_time,
        if (next.daysFromToday == 0) palette.accent else palette.mutedText,
    )

    if (course.location.isBlank()) {
      views.setViewVisibility(R.id.next_location, View.GONE)
    } else {
      views.setViewVisibility(R.id.next_location, View.VISIBLE)
      views.setTextViewText(R.id.next_location, course.location)
      views.setTextColor(R.id.next_location, palette.mutedText)
    }
  }

  companion object {
    /** 跨天闹钟的 request code（4×2 是 0x5149）。 */
    private const val REQUEST_DAILY_REFRESH = 0x514B

    /** 「下一个时间边界」重绘闹钟的 request code（4×2 是 0x514A）。 */
    private const val REQUEST_BOUNDARY_REFRESH = 0x514C
  }
}
