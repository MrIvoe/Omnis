package com.omnis.music

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.view.KeyEvent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget (Phase 7 §49 "Widgets"). Title/artist/play-state come
 * from [HomeWidgetService] (Dart side) via the `home_widget` plugin's own
 * SharedPreferences bridge — this class only ever *reads* that data and
 * renders it, it never computes playback state itself.
 *
 * Play/Pause/Next/Previous are wired directly to real
 * `android.intent.action.MEDIA_BUTTON` broadcasts targeted at
 * `com.ryanheise.audioservice.MediaButtonReceiver` (already registered in
 * AndroidManifest.xml for the notification's own controls) rather than a
 * Flutter background-isolate callback — the same mechanism a Bluetooth
 * headset's hardware buttons already use to reach this app's real
 * MediaSession, so tapping the widget genuinely controls playback with no
 * second, separately-initialized audio stack involved.
 */
class OmnisWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val title = widgetData.getString("title", "Not playing")
        val artist = widgetData.getString("artist", "")
        val playing = widgetData.getBoolean("playing", false)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.omnis_widget)
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_artist, artist)
            views.setImageViewResource(
                R.id.widget_play_pause,
                if (playing) R.drawable.ic_widget_pause else R.drawable.ic_widget_play,
            )
            views.setContentDescription(
                R.id.widget_play_pause,
                if (playing) "Pause" else "Play",
            )

            views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context))
            views.setOnClickPendingIntent(
                R.id.widget_play_pause,
                mediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, widgetId * 10 + 1),
            )
            views.setOnClickPendingIntent(
                R.id.widget_next,
                mediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_NEXT, widgetId * 10 + 2),
            )
            views.setOnClickPendingIntent(
                R.id.widget_previous,
                mediaButtonIntent(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS, widgetId * 10 + 3),
            )

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun mediaButtonIntent(
        context: Context,
        keyCode: Int,
        requestCode: Int,
    ): PendingIntent {
        val downIntent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            component = ComponentName(
                context.packageName,
                "com.ryanheise.audioservice.MediaButtonReceiver",
            )
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            downIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
