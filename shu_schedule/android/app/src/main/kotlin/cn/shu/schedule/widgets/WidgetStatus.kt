package cn.shu.schedule.widgets

import java.util.Calendar

// v1.4.0：小组件里所有「跟现在几点有关」的文案和刷新时刻。
//
// 4×2 的头部副标题（[dayHeaderSub]）、2×1「下一节」的内容（[findNextClass] / [nextClassTimeText]）
// 和两者共用的「下一次该重绘的时刻」（[nextBoundaryMillis]）都在这里，
// 只依赖 java.util.Calendar 和快照数据类，JVM 单测直接跑。
// 文案和 ShuWidgetProvider.kt 里的 relativeDayLabel 一样写在 Kotlin 里（要拼接、要单测），
// 只有启动器要读的名字 / 描述和整句空态放在 strings.xml。

/** 「第 N 周」；不在学期内（快照 `week = null`）是「假期」。 */
fun weekText(day: WidgetDay): String = day.week?.let { "第 $it 周" } ?: "假期"

/**
 * 4×2 头部的副标题（`day_header_sub`，单行）。
 *
 * - 停课日：沿用原来的「第 N 周 · 今天 / 明天 / …」（空态那里另有停课文案）。
 * - 自动看明天：「明天 · 第 N 周 · 3 节课」（没课是「没有课」）。
 * - 今天：上课中 →「第 N 周 · 上课中 · 至 11:50」；下一节在 [COUNTDOWN_MINUTES] 分钟内 →
 *   「第 N 周 · 51 分钟后上课」；更远 →「第 N 周 · 下一节 10:00」；课都上完了（自动看明天时
 *   ◀ 翻回今天）→「第 N 周 · 今天 · 已结束」；今天本来没课 →「第 N 周 · 今天」。
 * - 其他日子：「第 N 周 · 后天」这类（日期差来自 [DisplayDay.daysFromToday]）。
 */
fun dayHeaderSub(day: WidgetDay, display: DisplayDay, nowMinutes: Int): String {
  val week = weekText(day)
  val plain = "$week · ${relativeDayLabel(display.daysFromToday)}"
  if (day.label == LABEL_CANCELLED) return plain

  if (display.autoTomorrow) {
    val count = day.courses.size
    return "明天 · $week · " + if (count > 0) "$count 节课" else "没有课"
  }

  if (display.daysFromToday == 0) {
    val ongoing = ongoingCourse(day.courses, nowMinutes)
    if (ongoing != null) return "$week · 上课中 · 至 ${ongoing.end}"
    val next = day.courses.firstOrNull { it.startMinutes > nowMinutes }
    if (next != null) {
      val wait = next.startMinutes - nowMinutes
      return if (wait <= COUNTDOWN_MINUTES) "$week · $wait 分钟后上课" else "$week · 下一节 ${next.start}"
    }
    if (day.courses.isNotEmpty() && isDayOver(day, nowMinutes)) return "$week · 今天 · 已结束"
  }
  return plain
}

/** 正在上的那节课（开始 ≤ 现在 < 结束；有重叠时取开始最早的那节）；没有返回 null。 */
fun ongoingCourse(courses: List<WidgetCourse>, nowMinutes: Int): WidgetCourse? =
    courses.firstOrNull { it.startMinutes in 0..nowMinutes && it.endMinutes > nowMinutes }

/** 2×1 往后找下一节课最多看几天（v1.4.0 修复轮，review-G P2-5：周五晚上也能看到周一的课）。 */
const val NEXT_CLASS_LOOKAHEAD_DAYS = 7

/**
 * 2×1「下一节」要显示的那节课。
 *
 * @property daysFromToday 0 = 今天（[ongoing] 区分上课中 / 还没开始），1..[NEXT_CLASS_LOOKAHEAD_DAYS] = 之后那天的第一节。
 * @property date 那天的 `yyyy-MM-dd`；[weekday] 1 = 周一 … 7 = 周日。
 */
data class NextClass(
    val course: WidgetCourse,
    val daysFromToday: Int,
    val ongoing: Boolean,
    val date: String = "",
    val weekday: Int = 0,
)

/**
 * 2×1 的内容：今天还没结束的第一节（上课中或下一节）；今天没了就往后找
 * [NEXT_CLASS_LOOKAHEAD_DAYS] 天内第一个有课的日子的第一节；都没有返回 null（显示「近期没有课程」）。
 * 快照里没有今天时也返回 null——调用方先用 [todayIndexOf] 区分「打开 App 刷新」。
 * 停课日在快照里没有课，自然被跳过。
 */
fun findNextClass(snapshot: WidgetSnapshot?, now: Calendar): NextClass? {
  val days = snapshot?.days ?: return null
  val todayIndex = todayIndexOf(snapshot, now)
  if (todayIndex < 0) return null
  val nowMinutes = minutesOfDay(now)

  val today = days[todayIndex]
  val current = today.courses.firstOrNull { it.endMinutes > nowMinutes }
  if (current != null) {
    return NextClass(
        current,
        daysFromToday = 0,
        ongoing = current.startMinutes in 0..nowMinutes,
        date = today.date,
        weekday = today.weekday,
    )
  }
  for (i in todayIndex + 1 until days.size) {
    val day = days[i]
    val diff = daysBetweenIso(today.date, day.date) ?: (i - todayIndex)
    if (diff > NEXT_CLASS_LOOKAHEAD_DAYS) break
    val first = day.courses.firstOrNull() ?: continue
    return NextClass(first, daysFromToday = diff, ongoing = false, date = day.date, weekday = day.weekday)
  }
  return null
}

/**
 * 2×1 上「哪一天」的说法：明天 →「明天」；2～6 天后 →「周一」这样的星期；
 * 正好一周后（和今天同一个星期几，说星期会误会）→「10月14日」。
 */
fun nextClassDayLabel(next: NextClass): String =
    when {
      next.daysFromToday == 1 -> relativeDayLabel(1)
      next.daysFromToday in 2..6 && next.weekday in 1..7 -> weekdayNameCn(next.weekday)
      next.date.isNotBlank() -> formatDateCn(next.date)
      else -> relativeDayLabel(next.daysFromToday)
    }

/** 2×1 第二行：「上课中 · 至 11:40」/「10:00-11:40」/「明天 · 08:00-09:40」/「周一 · 08:00-08:45」。 */
fun nextClassTimeText(next: NextClass): String {
  val c = next.course
  return when {
    next.ongoing -> "上课中 · 至 ${c.end}"
    next.daysFromToday == 0 -> formatCourseSpan(c.start, c.end)
    else -> "${nextClassDayLabel(next)} · ${formatCourseSpan(c.start, c.end)}"
  }
}

/**
 * 下一次该重绘的时刻（墙上时间毫秒），取下面这些里**严格晚于现在**的最早一个：
 * - 今天每节课的开始、结束（上课中 / 下一节 / 自动看明天都在这些时刻变）；
 * - 每节课开始前 [COUNTDOWN_MINUTES] 分钟（「下一节 10:00」变成「90 分钟后上课」）；
 * - 倒计时显示期间，现在 + [COUNTDOWN_REFRESH_MINUTES] 分钟（让「N 分钟后」别停太久）；
 * - 今天 18:00（今天没课时改看明天）；
 * - 明天 00:00:30（跨天）。
 *
 * 都按 [now] 所在时区用 Calendar 设字段得到，夏令时切换日也是当地的那个钟点。
 */
fun nextBoundaryMillis(snapshot: WidgetSnapshot?, now: Calendar): Long {
  val nowMinutes = minutesOfDay(now)
  val candidates = mutableListOf<Int>() // 今天的第几分钟
  candidates.add(EVENING_SWITCH_MINUTES)

  val todayIndex = todayIndexOf(snapshot, now)
  val courses = if (todayIndex >= 0) snapshot!!.days[todayIndex].courses else emptyList()
  for (c in courses) {
    if (c.startMinutes >= 0) {
      candidates.add(c.startMinutes)
      candidates.add(c.startMinutes - COUNTDOWN_MINUTES)
    }
    if (c.endMinutes >= 0) candidates.add(c.endMinutes)
  }
  val counting = courses.any { it.startMinutes > nowMinutes && it.startMinutes - nowMinutes <= COUNTDOWN_MINUTES }
  if (counting) candidates.add(nowMinutes + COUNTDOWN_REFRESH_MINUTES)

  val todayNext = candidates.filter { it in (nowMinutes + 1) until 24 * 60 }.minOrNull()
  if (todayNext != null) return atMinuteOfDay(now, todayNext, dayShift = 0, second = 0)
  return atMinuteOfDay(now, 0, dayShift = 1, second = 30)
}

/** [now] 那天（再加 [dayShift] 天）的 [minute] 分 [second] 秒，当地时间。 */
private fun atMinuteOfDay(now: Calendar, minute: Int, dayShift: Int, second: Int): Long {
  val c = now.clone() as Calendar
  if (dayShift != 0) c.add(Calendar.DAY_OF_YEAR, dayShift)
  c.set(Calendar.HOUR_OF_DAY, minute / 60)
  c.set(Calendar.MINUTE, minute % 60)
  c.set(Calendar.SECOND, second)
  c.set(Calendar.MILLISECOND, 0)
  return c.timeInMillis
}
