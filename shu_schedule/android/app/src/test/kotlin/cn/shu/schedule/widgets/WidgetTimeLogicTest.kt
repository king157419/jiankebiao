package cn.shu.schedule.widgets

import java.time.LocalDate
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * v1.4.0 任务 C：小组件里跟「现在几点」有关的纯逻辑（ShuWidgetProvider.kt / WidgetStatus.kt）。
 *
 * 只用 java.util.Calendar 和快照数据类，不碰 Android API，所以是普通 JVM 单测：
 * `cd android && gradlew :app:testDebugUnitTest`。
 */
class WidgetTimeLogicTest {

  private val shanghai: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")

  private fun at(y: Int, m: Int, d: Int, h: Int, min: Int, tz: TimeZone = shanghai): Calendar =
      Calendar.getInstance(tz).apply {
        clear()
        set(y, m - 1, d, h, min, 0)
      }

  private fun course(name: String, start: String, end: String, location: String = "东区 J-101") =
      WidgetCourse(name, location, "", start, end, 0)

  private fun day(
      date: String,
      weekday: Int,
      week: Int?,
      courses: List<WidgetCourse> = emptyList(),
      label: String? = null,
  ) = WidgetDay(date, weekday, week, courses, label, null)

  private fun snap(vararg days: WidgetDay) = WidgetSnapshot("示例", WidgetPalette.FALLBACK, days.toList())

  private val english = course("大学英语", "10:00", "11:50", "东区 E-305")
  private val ds = course("数据结构", "13:00", "14:40", "计算机楼 A-301")

  /** 10/7 周三（第 4 周）两节课；10/8 周四三节；10/9 周五没课；10/10 停课。 */
  private val term =
      snap(
          day("2026-10-07", 3, 4, listOf(english, ds)),
          day(
              "2026-10-08",
              4,
              4,
              listOf(
                  course("高等数学", "08:00", "09:40"),
                  course("大学物理", "10:00", "11:40"),
                  course("体育", "15:00", "16:40"),
              ),
          ),
          day("2026-10-09", 5, 4),
          day("2026-10-10", 6, 4, label = "停课"),
          day("2026-10-11", 7, 4),
          day("2026-10-12", 1, 5),
          day("2026-10-13", 2, 5),
          day("2026-10-14", 3, 5),
          day("2026-10-15", 4, 5),
      )

  // ------------------------------------------------------------ resolveDisplay

  @Test
  fun todayWithClassesLeftShowsToday() {
    val home = DisplayDay(dayIndex = 0, daysFromToday = 0, autoTomorrow = false, isHome = true)
    assertEquals(home, resolveDisplay(term, at(2026, 10, 7, 12, 0), OFFSET_DEFAULT))
    // 默认那天就是今天时，显式的 0 和哨兵看到的是同一天。
    assertEquals(home, resolveDisplay(term, at(2026, 10, 7, 12, 0), 0))
  }

  @Test
  fun lastClassEndedSwitchesToTomorrow() {
    assertFalse(resolveDisplay(term, at(2026, 10, 7, 14, 39), OFFSET_DEFAULT).autoTomorrow)
    val d = resolveDisplay(term, at(2026, 10, 7, 14, 40), OFFSET_DEFAULT)
    assertEquals(DisplayDay(dayIndex = 1, daysFromToday = 1, autoTomorrow = true, isHome = true), d)
    assertEquals("明天", relativeDayLabel(d.daysFromToday))
  }

  @Test
  fun offsetZeroIsTodayEvenWhenHomeIsTomorrow() {
    // fixlist ②：自动看明天时，偏移 0 = 上完课的今天，不再等于「默认那天」。
    val evening = at(2026, 10, 7, 20, 0)
    val d = resolveDisplay(term, evening, 0)
    assertEquals(DisplayDay(dayIndex = 0, daysFromToday = 0, autoTomorrow = false, isHome = false), d)
    assertFalse(canPagePrev(d))
    assertTrue(canPageNext(d))
    val home = resolveDisplay(term, evening, OFFSET_DEFAULT)
    assertTrue(home.isHome)
    assertTrue("默认那天是明天，◀ 可以回到今天", canPagePrev(home))
  }

  @Test
  fun dayWithoutClassesSwitchesAt18() {
    // 10/9 周五没课：17:59 还看今天，18:00 起看明天。
    val before = resolveDisplay(term, at(2026, 10, 9, 17, 59), OFFSET_DEFAULT)
    assertEquals(2, before.dayIndex)
    assertFalse(before.autoTomorrow)
    val after = resolveDisplay(term, at(2026, 10, 9, 18, 0), OFFSET_DEFAULT)
    assertEquals(3, after.dayIndex)
    assertTrue(after.autoTomorrow)
  }

  @Test
  fun cancelledDayCountsAsNoClasses() {
    assertFalse(resolveDisplay(term, at(2026, 10, 10, 9, 0), OFFSET_DEFAULT).autoTomorrow)
    val d = resolveDisplay(term, at(2026, 10, 10, 18, 30), OFFSET_DEFAULT)
    assertEquals(4, d.dayIndex)
    assertTrue(d.autoTomorrow)
  }

  @Test
  fun pagedOffsetIsDaysFromTodayEvenAfterAutoSwitch() {
    val noon = at(2026, 10, 7, 12, 0)
    val evening = at(2026, 10, 7, 20, 0)
    // 偏移 2 = 今天 + 2，不管今天是否已自动切到明天，翻到的那天不跳。
    assertEquals(DisplayDay(2, 2, autoTomorrow = false, isHome = false), resolveDisplay(term, noon, 2))
    assertEquals(DisplayDay(2, 2, autoTomorrow = false, isHome = false), resolveDisplay(term, evening, 2))
    // 自动看明天时偏移 1 就是默认那天。
    assertEquals(DisplayDay(1, 1, autoTomorrow = true, isHome = true), resolveDisplay(term, evening, 1))
    assertEquals(DisplayDay(1, 1, autoTomorrow = false, isHome = false), resolveDisplay(term, noon, 1))
  }

  @Test
  fun snapshotEndingTodayKeepsShowingToday() {
    val only = snap(day("2026-10-07", 3, 4, listOf(english)))
    val d = resolveDisplay(only, at(2026, 10, 7, 20, 0), OFFSET_DEFAULT)
    assertEquals(DisplayDay(0, 0, autoTomorrow = false, isHome = true), d)
    assertEquals(-1, resolveDisplay(only, at(2026, 10, 7, 20, 0), 1).dayIndex)
  }

  @Test
  fun missingTodayOrSnapshotNeedsRefresh() {
    assertEquals(-1, resolveDisplay(term, at(2026, 11, 30, 9, 0), OFFSET_DEFAULT).dayIndex)
    val none = resolveDisplay(null, at(2026, 10, 7, 9, 0), OFFSET_DEFAULT)
    assertEquals(-1, none.dayIndex)
    assertEquals(0, none.daysFromToday)
    assertTrue(none.isHome)
    assertEquals(-1, todayIndexOf(term, at(2026, 10, 6, 9, 0)))
  }

  @Test
  fun relativeLabelUsesRealDateDifference() {
    // 快照中间缺了一天：下标差 1，日期差 2 → 「后天」。
    val gap = snap(day("2026-10-07", 3, 4), day("2026-10-09", 5, 4))
    val d = resolveDisplay(gap, at(2026, 10, 7, 9, 0), 1)
    assertEquals(1, d.dayIndex)
    assertEquals(2, d.daysFromToday)
    assertEquals("后天", relativeDayLabel(d.daysFromToday))
    assertEquals("3 天后", relativeDayLabel(3))
  }

  @Test
  fun unparsableEndTimesNeverTriggerAutoSwitch() {
    assertFalse(isDayOver(day("2026-10-07", 3, 4, listOf(course("怪课", "", ""))), 23 * 60))
    assertTrue(isDayOver(day("2026-10-07", 3, 4, listOf(course("怪课", "", ""), english)), 12 * 60))
  }

  // ------------------------------------------------------------ 翻页

  @Test
  fun pagingFromToday() {
    val noon = at(2026, 10, 7, 12, 0)
    assertEquals(1, nextPageOffset(term, noon, OFFSET_DEFAULT, 1))
    // 翻回默认那天（今天）存哨兵，跟着默认那天走。
    assertEquals(OFFSET_DEFAULT, nextPageOffset(term, noon, 1, -1))
    assertEquals(OFFSET_DEFAULT, nextPageOffset(term, noon, OFFSET_DEFAULT, -1))
    assertEquals(MAX_DAY_OFFSET, nextPageOffset(term, noon, MAX_DAY_OFFSET, 1))
    assertEquals(OFFSET_DEFAULT, nextPageOffset(term, noon, 4, PAGE_DELTA_RESET))
  }

  @Test
  fun pagingWhenHomeIsTomorrow() {
    val evening = at(2026, 10, 7, 20, 0)
    // 默认看明天：▶ 到后天（偏移 2），◀ 回到默认（哨兵）。
    assertEquals(2, nextPageOffset(term, evening, OFFSET_DEFAULT, 1))
    assertEquals(OFFSET_DEFAULT, nextPageOffset(term, evening, 2, -1))
    assertEquals(4, nextPageOffset(term, evening, 3, 1))
    // fixlist ②：默认那天（明天）再 ◀ → 0 = 上完课的今天；今天再 ◀ 夹住；▶ 回到默认。
    assertEquals(0, nextPageOffset(term, evening, OFFSET_DEFAULT, -1))
    assertEquals(0, nextPageOffset(term, evening, 0, -1))
    assertEquals(OFFSET_DEFAULT, nextPageOffset(term, evening, 0, 1))
    assertEquals(OFFSET_DEFAULT, nextPageOffset(term, evening, 0, PAGE_DELTA_RESET))
  }

  @Test
  fun storedOffsetIsClampedWithSentinel() {
    assertEquals(OFFSET_DEFAULT, clampOffset(-5))
    assertEquals(OFFSET_DEFAULT, clampOffset(OFFSET_DEFAULT))
    assertEquals(0, clampOffset(0))
    assertEquals(MAX_DAY_OFFSET, clampOffset(99))
    assertEquals("day_offset_9", keyOffset(9))
  }

  // ------------------------------------------------------------ 头部副标题

  private fun sub(now: Calendar, offset: Int = OFFSET_DEFAULT, s: WidgetSnapshot = term): String {
    val d = resolveDisplay(s, now, offset)
    return dayHeaderSub(s.days[d.dayIndex], d, minutesOfDay(now))
  }

  @Test
  fun headerOngoing() {
    assertEquals("第 4 周 · 上课中 · 至 11:50", sub(at(2026, 10, 7, 10, 0)))
    assertEquals("第 4 周 · 上课中 · 至 11:50", sub(at(2026, 10, 7, 11, 49)))
  }

  @Test
  fun headerCountdownAndNext() {
    assertEquals("第 4 周 · 51 分钟后上课", sub(at(2026, 10, 7, 12, 9)))
    // 11:50 整英语刚下课（结束那一分钟就不算上课中了），离 13:00 还有 70 分钟。
    assertEquals("第 4 周 · 70 分钟后上课", sub(at(2026, 10, 7, 11, 50)))
    assertEquals("第 4 周 · 1 分钟后上课", sub(at(2026, 10, 7, 12, 59)))
    assertEquals("第 4 周 · 上课中 · 至 14:40", sub(at(2026, 10, 7, 13, 0)))
    val onlyAfternoon = snap(day("2026-10-07", 3, 4, listOf(ds)), day("2026-10-08", 4, 4))
    assertEquals("第 4 周 · 90 分钟后上课", sub(at(2026, 10, 7, 11, 30), s = onlyAfternoon))
    assertEquals("第 4 周 · 下一节 13:00", sub(at(2026, 10, 7, 11, 29), s = onlyAfternoon))
    assertEquals("第 4 周 · 下一节 10:00", sub(at(2026, 10, 7, 7, 0)))
  }

  @Test
  fun headerAutoTomorrow() {
    assertEquals("明天 · 第 4 周 · 3 节课", sub(at(2026, 10, 7, 15, 0)))
    // 10/8 晚上 → 10/9 没课。
    assertEquals("明天 · 第 4 周 · 没有课", sub(at(2026, 10, 8, 19, 0)))
    // 10/9 晚上 → 10/10 停课：沿用原来的文案。
    assertEquals("第 4 周 · 明天", sub(at(2026, 10, 9, 19, 0)))
  }

  @Test
  fun headerTodayEndedWhenPagedBackInAutoMode() {
    // 自动看明天时 ◀ 翻回今天：「今天 · 已结束」。
    assertEquals("第 4 周 · 今天 · 已结束", sub(at(2026, 10, 7, 15, 0), offset = 0))
    // 今天本来没课（10/9 晚上翻回今天）：不写「已结束」。
    assertEquals("第 4 周 · 今天", sub(at(2026, 10, 9, 19, 0), offset = 0))
    // 快照只到今天、课上完了：默认那天就是今天，也写「已结束」。
    val only = snap(day("2026-10-07", 3, 4, listOf(english)))
    assertEquals("第 4 周 · 今天 · 已结束", sub(at(2026, 10, 7, 20, 0), s = only))
  }

  @Test
  fun headerCancelledAndOtherDaysKeepOldCopy() {
    assertEquals("第 4 周 · 今天", sub(at(2026, 10, 10, 9, 0)))
    assertEquals("第 4 周 · 后天", sub(at(2026, 10, 7, 12, 0), offset = 2))
    val holiday = snap(day("2026-10-07", 3, null), day("2026-10-08", 4, null), day("2026-10-09", 5, null))
    assertEquals("假期 · 后天", sub(at(2026, 10, 7, 9, 0), offset = 2, s = holiday))
    assertEquals("明天 · 假期 · 没有课", sub(at(2026, 10, 7, 18, 0), s = holiday))
  }

  // ------------------------------------------------------------ 2×1「下一节」

  @Test
  fun nextClassOngoingUpcomingTomorrowNone() {
    val ongoing = findNextClass(term, at(2026, 10, 7, 11, 0))!!
    assertEquals("大学英语", ongoing.course.name)
    assertTrue(ongoing.ongoing)
    assertEquals("上课中 · 至 11:50", nextClassTimeText(ongoing))

    val upcoming = findNextClass(term, at(2026, 10, 7, 11, 50))!!
    assertEquals("数据结构", upcoming.course.name)
    assertFalse(upcoming.ongoing)
    assertEquals(0, upcoming.daysFromToday)
    assertEquals("13:00-14:40", nextClassTimeText(upcoming))

    val tomorrow = findNextClass(term, at(2026, 10, 7, 14, 40))!!
    assertEquals("高等数学", tomorrow.course.name)
    assertEquals(1, tomorrow.daysFromToday)
    assertEquals("明天 · 08:00-09:40", nextClassTimeText(tomorrow))

    // 10/8 最后一节 16:40 下课，10/9 没课、10/10 停课、之后一周都没课 → 近期没有课程。
    assertNull(findNextClass(term, at(2026, 10, 8, 17, 0)))
    // 快照里没有今天 → 也是 null，由调用方用 todayIndexOf 区分「打开 App 刷新」。
    assertNull(findNextClass(term, at(2026, 12, 1, 9, 0)))
    assertNull(findNextClass(null, at(2026, 10, 7, 9, 0)))
  }

  @Test
  fun nextClassLooksAheadSevenDays() {
    // 测试缺口 5 / P2-5：周五晚上 → 下周一第一节，标签用星期。
    val weekend =
        snap(
            day("2026-10-16", 5, 5, listOf(english)),
            day("2026-10-17", 6, 5),
            day("2026-10-18", 7, 5),
            day("2026-10-19", 1, 6, listOf(course("高等数学", "08:00", "08:45"), english)),
        )
    val mon = findNextClass(weekend, at(2026, 10, 16, 20, 0))!!
    assertEquals("高等数学", mon.course.name)
    assertEquals(3, mon.daysFromToday)
    assertEquals("2026-10-19", mon.date)
    assertEquals("周一 · 08:00-08:45", nextClassTimeText(mon))

    // 明天有课仍然写「明天」。
    val tue = findNextClass(term, at(2026, 10, 7, 14, 40))!!
    assertEquals("明天 · 08:00-09:40", nextClassTimeText(tue))

    // 正好一周后（和今天同一个星期几）→ 写日期；超过 7 天 → 近期没有课程。
    val week =
        snap(
            day("2026-10-07", 3, 4),
            day("2026-10-08", 4, 4),
            day("2026-10-09", 5, 4),
            day("2026-10-10", 6, 4),
            day("2026-10-11", 7, 4),
            day("2026-10-12", 1, 5),
            day("2026-10-13", 2, 5),
            day("2026-10-14", 3, 5, listOf(ds)),
            day("2026-10-15", 4, 5, listOf(english)),
        )
    val sameWeekday = findNextClass(week, at(2026, 10, 7, 9, 0))!!
    assertEquals(7, sameWeekday.daysFromToday)
    assertEquals("10月14日 · 13:00-14:40", nextClassTimeText(sameWeekday))
    assertNull(findNextClass(week, at(2026, 10, 6, 9, 0)))
    val farOnly = snap(day("2026-10-07", 3, 4), day("2026-10-15", 4, 5, listOf(english)))
    assertNull(findNextClass(farOnly, at(2026, 10, 7, 9, 0)))

    // 停课日（快照里没有课）被跳过：国庆 10/10 停课 → 找到之后的课。
    val holiday =
        snap(
            day("2026-10-09", 5, 4),
            day("2026-10-10", 6, 4, label = "停课"),
            day("2026-10-11", 7, 4),
            day("2026-10-12", 1, 5, listOf(english)),
        )
    assertEquals("周一 · 10:00-11:50", nextClassTimeText(findNextClass(holiday, at(2026, 10, 9, 20, 0))!!))
  }

  // ------------------------------------------------------------ 重绘时刻

  private fun hm(millis: Long, tz: TimeZone = shanghai): String {
    val c = Calendar.getInstance(tz).apply { timeInMillis = millis }
    return String.format(
        "%02d-%02d %02d:%02d:%02d",
        c.get(Calendar.MONTH) + 1,
        c.get(Calendar.DAY_OF_MONTH),
        c.get(Calendar.HOUR_OF_DAY),
        c.get(Calendar.MINUTE),
        c.get(Calendar.SECOND),
    )
  }

  @Test
  fun boundaryIsNearestOfClassEdgesEveningAndMidnight() {
    // 07:00：最近的是 10:00 开课前 90 分钟（08:30，开始显示倒计时）。
    assertEquals("10-07 08:30:00", hm(nextBoundaryMillis(term, at(2026, 10, 7, 7, 0))))
    // 09:00 正在倒计时：10 分钟后再画一次。
    assertEquals("10-07 09:10:00", hm(nextBoundaryMillis(term, at(2026, 10, 7, 9, 0))))
    // 09:55：开课时刻比倒计时刷新更近。
    assertEquals("10-07 10:00:00", hm(nextBoundaryMillis(term, at(2026, 10, 7, 9, 55))))
    // 10:30 上课中：13:00 的倒计时起点 11:30 早于 11:50 下课。
    assertEquals("10-07 11:30:00", hm(nextBoundaryMillis(term, at(2026, 10, 7, 10, 30))))
    // 14:00 上课中：14:40 下课。
    assertEquals("10-07 14:40:00", hm(nextBoundaryMillis(term, at(2026, 10, 7, 14, 0))))
    // 15:00 课都上完了：18:00。
    assertEquals("10-07 18:00:00", hm(nextBoundaryMillis(term, at(2026, 10, 7, 15, 0))))
    // 18:00 整及以后：次日 00:00:30。
    assertEquals("10-08 00:00:30", hm(nextBoundaryMillis(term, at(2026, 10, 7, 18, 0))))
    assertEquals("10-08 00:00:30", hm(nextBoundaryMillis(term, at(2026, 10, 7, 23, 59))))
    // 没有快照也照样排 18:00 / 跨天。
    assertEquals("10-07 18:00:00", hm(nextBoundaryMillis(null, at(2026, 10, 7, 9, 0))))
  }

  @Test
  fun boundaryIsAlwaysInTheFuture() {
    for (h in 0 until 24) {
      for (m in listOf(0, 1, 29, 30, 59)) {
        val now = at(2026, 10, 7, h, m)
        val b = nextBoundaryMillis(term, now)
        assertTrue("$h:$m", b > now.timeInMillis)
        assertTrue("$h:$m", b - now.timeInMillis <= 24L * 3600 * 1000)
      }
    }
  }

  @Test
  fun boundaryUsesLocalWallClockAcrossDst() {
    // 开发机所在的 America/Denver 有夏令时（NOTES.md §2.1）。
    val denver = TimeZone.getTimeZone("America/Denver")
    val fallBack = snap(day("2026-11-01", 7, 8))
    assertEquals("11-01 18:00:00", hm(nextBoundaryMillis(fallBack, at(2026, 11, 1, 0, 30, denver)), denver))
    val springForward = snap(day("2026-03-07", 6, 1))
    assertEquals(
        "03-08 00:00:30",
        hm(nextBoundaryMillis(springForward, at(2026, 3, 7, 23, 0, denver)), denver),
    )
  }

  // ------------------------------------------------------------ 日期差

  @Test
  fun epochDayMatchesJavaTime() {
    for (iso in listOf("1970-01-01", "1969-12-31", "2000-02-29", "2024-02-29", "2026-03-08", "2026-10-07", "2026-11-01", "2100-03-01")) {
      assertEquals(iso, LocalDate.parse(iso).toEpochDay(), epochDayOf(iso))
    }
    assertEquals(1, daysBetweenIso("2026-12-31", "2027-01-01"))
    assertEquals(1, daysBetweenIso("2026-03-07", "2026-03-08"))
    assertNull(epochDayOf("2026-10"))
    assertNull(epochDayOf("2026-13-01"))
    assertNull(daysBetweenIso("x", "2026-10-07"))
  }
}
