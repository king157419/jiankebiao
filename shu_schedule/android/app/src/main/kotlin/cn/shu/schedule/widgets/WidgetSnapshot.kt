package cn.shu.schedule.widgets

import android.content.SharedPreferences
import android.graphics.Color
import android.util.Log
import org.json.JSONObject

/**
 * 小组件用的调色板，由 Flutter 端 `WidgetPalette` 以 `#RRGGBB` 写进快照。
 *
 * 任何一个颜色解析失败都回退到 [FALLBACK] 对应项，绝不让小组件因为脏数据变成黑底黑字。
 */
data class WidgetPalette(
    val background: Int,
    val surface: Int,
    val text: Int,
    val mutedText: Int,
    val accent: Int,
    val todayHighlight: Int,
    val courseTextOnBlock: Int,
    val isDark: Boolean,
    val courseColors: List<Int>,
) {
  companion object {
    /** design/themes.json 的「樱花粉」，和 Dart 侧 `WidgetPalette.fallback()` 保持一致。 */
    val FALLBACK =
        WidgetPalette(
            background = 0xFFFFF7FA.toInt(),
            surface = 0xFFFFFFFF.toInt(),
            text = 0xFF342632.toInt(),
            mutedText = 0xFF68505F.toInt(),
            accent = 0xFF933E6A.toInt(),
            todayHighlight = 0xFFF5DCE8.toInt(),
            courseTextOnBlock = 0xFF352D3B.toInt(),
            isDark = false,
            courseColors = listOf(0xFFF4C4D4.toInt()),
        )

    fun from(json: JSONObject?): WidgetPalette {
      if (json == null) return FALLBACK
      val colors = mutableListOf<Int>()
      val arr = json.optJSONArray("courseColors")
      if (arr != null) {
        for (i in 0 until arr.length()) {
          colors.add(parseColor(arr.optString(i), FALLBACK.courseColors[0]))
        }
      }
      return WidgetPalette(
          background = parseColor(json.optString("background"), FALLBACK.background),
          surface = parseColor(json.optString("surface"), FALLBACK.surface),
          text = parseColor(json.optString("text"), FALLBACK.text),
          mutedText = parseColor(json.optString("mutedText"), FALLBACK.mutedText),
          accent = parseColor(json.optString("accent"), FALLBACK.accent),
          todayHighlight = parseColor(json.optString("todayHighlight"), FALLBACK.todayHighlight),
          courseTextOnBlock =
              parseColor(json.optString("courseTextOnBlock"), FALLBACK.courseTextOnBlock),
          isDark = json.optBoolean("isDark", false),
          courseColors = if (colors.isEmpty()) FALLBACK.courseColors else colors,
      )
    }

    /** `"#RRGGBB"` → ARGB int；解析失败返回 [fallback]。 */
    fun parseColor(value: String?, fallback: Int): Int {
      if (value.isNullOrBlank()) return fallback
      return try {
        Color.parseColor(value)
      } catch (e: IllegalArgumentException) {
        fallback
      }
    }
  }
}

/** 快照里的一节课。 */
data class WidgetCourse(
    val name: String,
    val location: String,
    val teacher: String,
    val start: String,
    val end: String,
    val color: Int,
) {
  /** 开始时刻的「当天分钟数」，解析失败返回 -1。 */
  val startMinutes: Int
    get() = toMinutes(start)

  /** 结束时刻的「当天分钟数」，解析失败返回 -1。 */
  val endMinutes: Int
    get() = toMinutes(end)

  companion object {
    fun toMinutes(hhmm: String): Int {
      val parts = hhmm.split(":")
      if (parts.size != 2) return -1
      val h = parts[0].trim().toIntOrNull() ?: return -1
      val m = parts[1].trim().toIntOrNull() ?: return -1
      return h * 60 + m
    }
  }
}

/** 快照里的一天。[week] 为 null 表示不在学期内（假期）。 */
data class WidgetDay(
    val date: String,
    val weekday: Int,
    val week: Int?,
    val courses: List<WidgetCourse>,
)

/** Flutter 端 `WidgetSync.push` 写进 SharedPreferences 的整份快照。 */
data class WidgetSnapshot(
    val timetableName: String,
    val palette: WidgetPalette,
    val days: List<WidgetDay>,
) {

  /** 找 `yyyy-MM-dd` 对应的那天；快照里没有（比如两周没开 App）返回 null。 */
  fun dayFor(date: String): WidgetDay? = days.firstOrNull { it.date == date }

  companion object {
    const val TAG = "ShuWidget"

    /** home_widget 存数据用的 key，和 Dart 侧 `WidgetSync.snapshotKey` 一致。 */
    const val KEY_SNAPSHOT = "snapshot"

    /** 读取并解析快照；不存在 / 解析失败一律返回 null（调用方显示「打开 App 刷新」）。 */
    fun read(prefs: SharedPreferences): WidgetSnapshot? {
      val raw =
          try {
            prefs.getString(KEY_SNAPSHOT, null)
          } catch (e: ClassCastException) {
            null
          }
      if (raw.isNullOrBlank()) return null
      return try {
        parse(JSONObject(raw))
      } catch (e: Exception) {
        Log.w(TAG, "快照解析失败", e)
        null
      }
    }

    private fun parse(root: JSONObject): WidgetSnapshot {
      val palette = WidgetPalette.from(root.optJSONObject("palette"))
      val daysArray = root.optJSONArray("days")
      val days = mutableListOf<WidgetDay>()
      if (daysArray != null) {
        for (i in 0 until daysArray.length()) {
          val dayJson = daysArray.optJSONObject(i) ?: continue
          val coursesArray = dayJson.optJSONArray("courses")
          val courses = mutableListOf<WidgetCourse>()
          if (coursesArray != null) {
            for (j in 0 until coursesArray.length()) {
              val c = coursesArray.optJSONObject(j) ?: continue
              courses.add(
                  WidgetCourse(
                      name = c.optString("name", "").ifBlank { "未命名课程" },
                      location = c.optString("location", ""),
                      teacher = c.optString("teacher", ""),
                      start = c.optString("start", ""),
                      end = c.optString("end", ""),
                      color = WidgetPalette.parseColor(c.optString("color"), palette.accent),
                  )
              )
            }
          }
          courses.sortBy { it.startMinutes }
          days.add(
              WidgetDay(
                  date = dayJson.optString("date", ""),
                  weekday = dayJson.optInt("weekday", 1),
                  week = if (dayJson.isNull("week")) null else dayJson.optInt("week"),
                  courses = courses,
              )
          )
        }
      }
      return WidgetSnapshot(
          timetableName = root.optString("timetableName", ""),
          palette = palette,
          days = days,
      )
    }
  }
}
