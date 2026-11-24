package cn.shu.schedule.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import cn.shu.schedule.R
import es.antonborri.home_widget.HomeWidgetPlugin
import java.util.Calendar

/**
 * 给「简课表」4×2 小组件里的 `ListView`（`R.id.day_list`）供数据的远程适配器服务。
 *
 * RemoteViews 的 `ListView` 不能像普通列表那样直接塞 View：系统会跨进程
 * 绑定这个 Service，拿到一个 [RemoteViewsService.RemoteViewsFactory]，
 * 再由它一行行造 RemoteViews。manifest 里必须声明
 * `android:permission="android.permission.BIND_REMOTEVIEWS"`，否则系统拒绝绑定。
 */
class DayWidgetService : RemoteViewsService() {

  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
    val widgetId =
        intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
    return DayRemoteViewsFactory(applicationContext, widgetId)
  }
}

/**
 * 一个小组件实例（[widgetId]）对应一个工厂。
 *
 * 数据来源和 [DayWidgetProvider] 完全一致：
 * - 课表快照：home_widget 写的那份 SharedPreferences（`HomeWidgetPlugin.getData`）；
 * - 翻页偏移：[PREFS_PAGE] 里按 appWidgetId 存的 offset（跨天自动回 0）；
 * - 显示哪一天：和 Provider 共用 [resolveDisplay]（含 v1.4.0 的「今天上完了自动看明天」）。
 *
 * 只在 [onDataSetChanged] 里读一次盘，之后 [getViewAt] 纯内存取值——
 * 这个回调跑在 binder 线程上，系统会等它返回才刷新列表，不能做慢活。
 */
class DayRemoteViewsFactory(
    private val context: Context,
    private val widgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {

  private var palette: WidgetPalette = WidgetPalette.FALLBACK
  private var courses: List<WidgetCourse> = emptyList()

  /**
   * 要高亮的行（当前 / 下一节）；-1 = 不高亮。
   * 今天：第一节还没结束的课；自动看明天：明天第一节（它就是「下一节」）；其他日子不高亮。
   */
  private var highlightIndex: Int = -1

  override fun onCreate() = Unit

  override fun onDataSetChanged() {
    val snapshot =
        try {
          WidgetSnapshot.read(HomeWidgetPlugin.getData(context))
        } catch (e: Exception) {
          null
        }
    palette = snapshot?.palette ?: WidgetPalette.FALLBACK

    val calendar = Calendar.getInstance()
    val today = todayKey(calendar)
    val offset =
        try {
          readOffset(pageStore(context), widgetId, today)
        } catch (e: Exception) {
          OFFSET_DEFAULT
        }

    // 和 DayWidgetProvider.render 同一个函数决定显示哪一天，两边不会错位。
    val display = resolveDisplay(snapshot, calendar, offset)
    val day = snapshot?.days?.getOrNull(display.dayIndex)
    courses = day?.courses ?: emptyList()

    // 「当前 / 下一节」：今天 = 第一门还没结束的课（结束时刻那一分钟起就不算了，和头部一致）；
    // 自动看明天 = 明天第一节。
    val nowMinutes = minutesOfDay(calendar)
    highlightIndex =
        when {
          display.daysFromToday == 0 -> courses.indexOfFirst { it.endMinutes > nowMinutes }
          display.autoTomorrow && courses.isNotEmpty() -> 0
          else -> -1
        }
  }

  override fun getCount(): Int = courses.size

  override fun getViewAt(position: Int): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.widget_day_item)
    // 数据在系统取这一行之前被换掉过（翻页 + 推送撞在一起）时兜个底，别抛异常。
    val course = courses.getOrNull(position) ?: return views

    val isHighlight = position == highlightIndex
    val highlightBg = blendColors(palette.accent, palette.surface, 0.14f)
    views.setInt(
        R.id.item_root,
        "setBackgroundColor",
        if (isHighlight) highlightBg else Color.TRANSPARENT,
    )
    views.setInt(R.id.item_bar, "setBackgroundColor", course.color)

    views.setTextViewText(R.id.item_time, formatCourseSpan(course.start, course.end))
    views.setTextColor(R.id.item_time, if (isHighlight) palette.accent else palette.mutedText)

    views.setTextViewText(R.id.item_name, course.name)
    views.setTextColor(R.id.item_name, palette.text)

    if (course.location.isBlank()) {
      views.setViewVisibility(R.id.item_location, View.GONE)
    } else {
      views.setViewVisibility(R.id.item_location, View.VISIBLE)
      views.setTextViewText(R.id.item_location, course.location)
      views.setTextColor(R.id.item_location, palette.mutedText)
    }

    // 列表项自己不能带 PendingIntent，只能填一个 fill-in Intent，
    // 由 Provider 通过 setPendingIntentTemplate 设的模板（打开 App）来接。
    views.setOnClickFillInIntent(R.id.item_root, Intent())
    return views
  }

  override fun getLoadingView(): RemoteViews? = null

  override fun getViewTypeCount(): Int = 1

  override fun getItemId(position: Int): Long = position.toLong()

  override fun hasStableIds(): Boolean = true

  override fun onDestroy() {
    courses = emptyList()
  }
}
