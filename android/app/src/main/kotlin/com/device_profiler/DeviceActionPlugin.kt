package com.device_profiler.device_profiler

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.*

/**
 * Android implementation of device action integration for the DeviceActionService plugin.
 * 
 * This class handles:
 * - Calendar integration via CalendarContract
 * - Permission management
 * - Intent-based calendar event creation
 */
class DeviceActionPlugin : MethodCallHandler {
    private var activity: android.app.Activity? = null
    private var methodChannel: MethodChannel? = null

    companion object {
        const val CHANNEL_NAME = "com.ai_notes/device_actions"
        const val PERMISSION_REQUEST_CODE = 1001
        
        @JvmStatic
        fun registerWith(engine: FlutterEngine, activity: android.app.Activity) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            val plugin = DeviceActionPlugin()
            plugin.activity = activity
            plugin.methodChannel = channel
            channel.setMethodCallHandler(plugin)
        }
    }
    
    fun onAttachedToEngine(activity: android.app.Activity, channel: MethodChannel) {
        this.activity = activity
        this.methodChannel = channel
        channel.setMethodCallHandler(this)
    }
    
    fun onDetachedFromEngine() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        activity = null
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "addToCalendar" -> {
                handleAddToCalendar(call, result)
            }
            "checkCalendarPermission" -> {
                checkCalendarPermission(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    /**
     * Handles adding an event to the calendar
     */
    private fun handleAddToCalendar(call: MethodCall, result: Result) {
        val title = call.argument<String>("title")
        val description = call.argument<String>("description")
        val beginTime = call.argument<Long>("beginTime")
        val endTime = call.argument<Long>("endTime")
        val isAllDay = call.argument<Boolean>("isAllDay") ?: false
        
        if (title == null) {
            result.error("INVALID_ARGUMENT", "Title is required", null)
            return
        }
        
        try {
            // Check calendar permission
            if (!hasCalendarPermission()) {
                // Request permission
                requestCalendarPermission()
                // Return success but note that permission might be needed
                result.success(mapOf(
                    "success" to false,
                    "needsPermission" to true
                ))
                return
            }
            
            // Create calendar intent
            val intent = Intent(Intent.ACTION_INSERT)
                .setData(CalendarContract.Events.CONTENT_URI)
                .putExtra(CalendarContract.Events.TITLE, title)
                .putExtra(CalendarContract.Events.DESCRIPTION, description)
                .putExtra(CalendarContract.EXTRA_EVENT_ALL_DAY, isAllDay)
            
            // Add times if specified
            if (beginTime != null) {
                intent.putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, beginTime)
            }
            if (endTime != null) {
                intent.putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endTime)
            }
            
            // Launch calendar app
            activity?.startActivity(intent)
            
            result.success(mapOf(
                "success" to true,
                "method" to "intent"
            ))
        } catch (e: Exception) {
            result.error("CALENDAR_ERROR", "Failed to add event: ${e.message}", null)
        }
    }
    
    /**
     * Checks if calendar permission is granted
     */
    private fun hasCalendarPermission(): Boolean {
        val activity = this.activity ?: return false
        return ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.WRITE_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * Requests calendar permission
     */
    private fun requestCalendarPermission() {
        val activity = this.activity ?: return
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(
                Manifest.permission.WRITE_CALENDAR,
                Manifest.permission.READ_CALENDAR
            ),
            PERMISSION_REQUEST_CODE
        )
    }
    
    /**
     * Checks calendar permission status
     */
    private fun checkCalendarPermission(result: Result) {
        result.success(hasCalendarPermission())
    }
    
    /**
     * Inserts event directly via ContentResolver (requires permission)
     */
    private fun insertEventDirectly(
        title: String,
        description: String?,
        beginTime: Long?,
        endTime: Long?,
        isAllDay: Boolean
    ): Long? {
        val activity = this.activity ?: return null
        
        if (!hasCalendarPermission()) {
            return null
        }
        
        // Get primary calendar ID
        val projection = arrayOf(CalendarContract.Calendars._ID)
        val cursor = activity.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            "${CalendarContract.Calendars.VISIBLE} = 1 AND ${CalendarContract.Calendars.IS_PRIMARY} = 1",
            null,
            null
        )
        
        val calendarId = if (cursor?.moveToFirst() == true) {
            cursor.getLong(0)
        } else {
            // Fallback to first available calendar
            val allCalendarsCursor = activity.contentResolver.query(
                CalendarContract.Calendars.CONTENT_URI,
                projection,
                "${CalendarContract.Calendars.VISIBLE} = 1",
                null,
                null
            )
            
            val id = if (allCalendarsCursor?.moveToFirst() == true) {
                allCalendarsCursor.getLong(0)
            } else {
                null
            }
            allCalendarsCursor?.close()
            id
        }
        cursor?.close()
        
        if (calendarId == null) {
            return null
        }
        
        // Insert event
        val values = ContentValues().apply {
            put(CalendarContract.Events.DTSTART, beginTime ?: System.currentTimeMillis())
            put(CalendarContract.Events.DTEND, endTime ?: (beginTime ?: System.currentTimeMillis()) + 3600000)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
        }
        
        val uri = activity.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
        
        // Return event ID
        return uri?.lastPathSegment?.toLongOrNull()
    }
}
