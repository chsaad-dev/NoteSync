package com.notesync.notesync

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class PinnedNotesWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray, widgetData: android.content.SharedPreferences) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.pinned_notes_widget)

            // Setup Quick Capture button
            val quickCaptureIntent = Intent(context, MainActivity::class.java).apply {
                data = Uri.parse("notesync://quick_capture")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val quickCapturePendingIntent = PendingIntent.getActivity(
                context,
                "quick_capture".hashCode(),
                quickCaptureIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.btn_quick_capture, quickCapturePendingIntent)

            // Load Pinned Notes (up to 3 slots)
            val slots = arrayOf(
                Triple(R.id.layout_note_0, R.id.txt_title_0, R.id.txt_body_0),
                Triple(R.id.layout_note_1, R.id.txt_title_1, R.id.txt_body_1),
                Triple(R.id.layout_note_2, R.id.txt_title_2, R.id.txt_body_2)
            )

            var hasPinnedNotes = false

            for (i in 0 until 3) {
                val title = widgetData.getString("pinned_title_$i", "") ?: ""
                val body = widgetData.getString("pinned_body_$i", "") ?: ""
                val noteId = widgetData.getString("pinned_id_$i", "") ?: ""

                val slot = slots[i]

                if (title.isNotEmpty() || body.isNotEmpty()) {
                    hasPinnedNotes = true
                    views.setViewVisibility(slot.first, View.VISIBLE)
                    views.setTextViewText(slot.second, title)
                    views.setTextViewText(slot.third, if (body.length > 60) body.substring(0, 60) + "..." else body)

                    // Set up click intent to open the specific note
                    val noteIntent = Intent(context, MainActivity::class.java).apply {
                        data = Uri.parse("notesync://notes/$noteId")
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    }
                    val pendingIntent = PendingIntent.getActivity(
                        context, 
                        noteId.hashCode(), 
                        noteIntent, 
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    views.setOnClickPendingIntent(slot.first, pendingIntent)
                } else {
                    views.setViewVisibility(slot.first, View.GONE)
                }
            }

            if (hasPinnedNotes) {
                views.setViewVisibility(R.id.txt_no_pinned, View.GONE)
            } else {
                views.setViewVisibility(R.id.txt_no_pinned, View.VISIBLE)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
