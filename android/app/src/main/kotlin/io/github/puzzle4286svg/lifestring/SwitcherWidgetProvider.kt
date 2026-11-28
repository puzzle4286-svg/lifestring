package io.github.puzzle4286svg.lifestring

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.util.Calendar

/**
 * Home-screen task switcher (D49): the eight grid tiles. The tile images and
 * activity ids are written by the Dart side (SwitcherWidget.sync); a tap
 * sends timetracker://switch?id=<id> to the Dart tap handler in the
 * background, so switching never opens the app.
 *
 * Optional timer row (D62): two Chronometers, the session and today's total
 * of the running activity. They tick by themselves; the widget is only
 * redrawn when the Dart side syncs, and once at midnight, when both start
 * again from zero.
 */
class SwitcherWidgetProvider : HomeWidgetProvider() {
    private val tiles = intArrayOf(
        R.id.tile1, R.id.tile2, R.id.tile3, R.id.tile4,
        R.id.tile5, R.id.tile6, R.id.tile7, R.id.tile8,
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = RemoteViews(context.packageName, R.layout.switcher_widget)
        val openApp = openAppIntent(context)
        // The background does nothing. It needs a handler all the same:
        // some launchers open the app on a tap that has none.
        views.setOnClickPendingIntent(R.id.widget_root, ignoredTap(context))
        tiles.forEachIndexed { index, viewId ->
            val position = index + 1
            val id = widgetData.getString("slot_${position}_id", null)
            val bitmap = widgetData.getString("slot_${position}_image", null)
                ?.let { BitmapFactory.decodeFile(it) }
            if (bitmap == null) {
                views.setViewVisibility(viewId, View.INVISIBLE)
                return@forEachIndexed
            }
            views.setViewVisibility(viewId, View.VISIBLE)
            views.setImageViewBitmap(viewId, bitmap)
            // An empty slot ("+") opens the app, where it can be set up.
            val tap = if (id == null) {
                openApp
            } else {
                HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("timetracker://switch?id=$id"),
                )
            }
            tap?.let { views.setOnClickPendingIntent(viewId, it) }
        }
        updateTimer(context, views, widgetData)
        appWidgetManager.updateAppWidget(appWidgetIds, views)
    }

    private fun updateTimer(
        context: Context,
        views: RemoteViews,
        widgetData: SharedPreferences,
    ) {
        val shown = widgetData.getString("timer_shown", null) == "true"
        var sessionStart = widgetData.getString("timer_session_start", null)
            ?.toLongOrNull()
        var closedToday = widgetData.getString("timer_closed_today", null)
            ?.toLongOrNull() ?: 0L
        var dayEnd = widgetData.getString("timer_day_end", null)
            ?.toLongOrNull()
        if (!shown || sessionStart == null || dayEnd == null) {
            views.setViewVisibility(R.id.timer_row, View.GONE)
            return
        }
        val now = System.currentTimeMillis()
        if (now >= dayEnd) {
            // The app splits the entry at midnight: a new day, from zero.
            sessionStart = startOfDay(now)
            closedToday = 0L
            dayEnd = nextMidnight(now)
        }
        val session = (now - sessionStart).coerceAtLeast(0L)
        // Whole seconds, so both bases share the same fraction of a second
        // and the two timers change at the same moment.
        val closed = closedToday - closedToday % 1000
        val sessionBase = SystemClock.elapsedRealtime() - session
        views.setViewVisibility(R.id.timer_row, View.VISIBLE)
        // Every session view gets its visibility: the launcher may apply
        // these views onto the previous ones, keeping what is not set.
        val sessionView = widgetData.getString("timer_glow", null)
            ?.let { glowSessionViews[it] } ?: R.id.timer_session
        (glowSessionViews.values + R.id.timer_session).forEach {
            views.setViewVisibility(
                it,
                if (it == sessionView) View.VISIBLE else View.GONE,
            )
        }
        widgetData.getString("timer_session_color", null)?.toLongOrNull()?.let {
            views.setTextColor(sessionView, it.toInt())
        }
        widgetData.getString("timer_total_color", null)?.toLongOrNull()?.let {
            views.setTextColor(R.id.timer_total, it.toInt())
        }

        views.setChronometer(sessionView, sessionBase, null, true)
        views.setChronometer(R.id.timer_total, sessionBase - closed, null, true)
        scheduleMidnightUpdate(context, dayEnd)
    }

    /**
     * Redraws on a clock change: the timers count from elapsedRealtime, the
     * stored times are wall-clock times.
     */
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            -> {
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(
                    ComponentName(context, SwitcherWidgetProvider::class.java),
                )
                if (ids.isNotEmpty()) {
                    onUpdate(
                        context,
                        manager,
                        ids,
                        HomeWidgetPlugin.getData(context),
                    )
                }
            }
            ACTION_IGNORED_TAP -> Unit
            else -> super.onReceive(context, intent)
        }
    }

    /** A tap on the background: delivered here and dropped. */
    private fun ignoredTap(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        1,
        Intent(context, SwitcherWidgetProvider::class.java)
            .setAction(ACTION_IGNORED_TAP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Opens the app with its current launcher icon (activity-alias). */
    private fun openAppIntent(context: Context): PendingIntent? {
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName) ?: return null
        return PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun startOfDay(millis: Long): Long = Calendar.getInstance().apply {
        timeInMillis = millis
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun nextMidnight(millis: Long): Long = Calendar.getInstance().apply {
        timeInMillis = startOfDay(millis)
        add(Calendar.DAY_OF_MONTH, 1)
    }.timeInMillis

    /**
     * Redraws the widget at [at], within a minute after it (no exact-alarm
     * permission needed). A non-wakeup alarm: if the screen is off, it
     * runs when the phone wakes, before anyone can look.
     */
    private fun scheduleMidnightUpdate(context: Context, at: Long) {
        val manager = AppWidgetManager.getInstance(context)
        val component = ComponentName(context, SwitcherWidgetProvider::class.java)
        val intent = Intent(context, SwitcherWidgetProvider::class.java).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(
                AppWidgetManager.EXTRA_APPWIDGET_IDS,
                manager.getAppWidgetIds(component),
            )
        }
        val pending = PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val alarms = context.getSystemService(AlarmManager::class.java)
        alarms.setWindow(AlarmManager.RTC, at, 60_000L, pending)
    }

    private companion object {
        const val ACTION_IGNORED_TAP =
            "io.github.puzzle4286svg.lifestring.action.WIDGET_BACKGROUND_TAP"
    }
}
