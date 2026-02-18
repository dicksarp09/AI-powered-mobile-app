package com.device_profiler.device_profiler

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.RandomAccessFile
import java.util.regex.Pattern

/**
 * Android implementation of device profiling for the DeviceProfiler plugin.
 * 
 * This class gathers device hardware metrics including:
 * - Total RAM (GB)
 * - CPU core count
 * - Battery level percentage
 * - Memory pressure state
 */
class DeviceProfilerPlugin : MethodCallHandler {
    private var context: Context? = null
    private var methodChannel: MethodChannel? = null
    private var isLowMemory: Boolean = false
    
    companion object {
        const val CHANNEL_NAME = "com.device_profiler/platform"
        
        @JvmStatic
        fun registerWith(engine: FlutterEngine, context: Context) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            val plugin = DeviceProfilerPlugin()
            plugin.context = context
            plugin.methodChannel = channel
            channel.setMethodCallHandler(plugin)
            plugin.setupMemoryPressureListener(context)
        }
    }
    
    fun onAttachedToEngine(context: Context, channel: MethodChannel) {
        this.context = context
        this.methodChannel = channel
        channel.setMethodCallHandler(this)
        setupMemoryPressureListener(context)
    }
    
    fun onDetachedFromEngine() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        context = null
    }
    
    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "getDeviceProfile" -> {
                try {
                    val profile = getDeviceProfile()
                    result.success(profile)
                } catch (e: Exception) {
                    result.error("PROFILE_ERROR", e.message, e.stackTraceToString())
                }
            }
            else -> {
                result.notImplemented()
            }
        }
    }
    
    /**
     * Gathers all device metrics and returns them as a Map
     */
    private fun getDeviceProfile(): Map<String, Any> {
        val context = this.context ?: throw IllegalStateException("Context not available")
        
        val ramGB = getTotalRamGB(context)
        val cpuCores = getCpuCoreCount()
        val batteryLevel = getBatteryLevel(context)
        
        // Check current memory pressure
        checkMemoryPressure(context)
        
        return mapOf(
            "ramGB" to ramGB,
            "cpuCores" to cpuCores,
            "batteryLevel" to batteryLevel,
            "isLowMemory" to isLowMemory
        )
    }
    
    /**
     * Gets total RAM in gigabytes
     */
    private fun getTotalRamGB(context: Context): Double {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        
        // Convert bytes to GB
        return memoryInfo.totalMem / (1024.0 * 1024.0 * 1024.0)
    }
    
    /**
     * Gets the number of available CPU cores
     */
    private fun getCpuCoreCount(): Int {
        return Runtime.getRuntime().availableProcessors()
    }
    
    /**
     * Gets current battery level as percentage (0-100)
     */
    private fun getBatteryLevel(context: Context): Int {
        val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus = context.registerReceiver(null, intentFilter)
        
        return if (batteryStatus != null) {
            val level = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            
            if (level >= 0 && scale > 0) {
                (level * 100 / scale)
            } else {
                100 // Default to 100% if unable to determine
            }
        } else {
            100 // Default to 100% if unable to determine
        }
    }
    
    /**
     * Checks if the device is under memory pressure
     */
    private fun checkMemoryPressure(context: Context) {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        
        // Consider low memory if either the system flag is set or available memory is < 10% of total
        val memoryThreshold = 0.10
        val availableRatio = memoryInfo.availMem.toDouble() / memoryInfo.totalMem.toDouble()
        
        isLowMemory = memoryInfo.lowMemory || availableRatio < memoryThreshold
    }
    
    /**
     * Sets up listeners for memory pressure events
     */
    private fun setupMemoryPressureListener(context: Context) {
        // Register for system memory warnings via ComponentCallbacks2
        val application = context.applicationContext as android.app.Application
        
        application.registerComponentCallbacks(object : android.content.ComponentCallbacks2 {
            override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
                // Not used
            }
            
            override fun onLowMemory() {
                // This is called when the system is running low on memory
                isLowMemory = true
                notifyLowMemory()
            }
            
            override fun onTrimMemory(level: Int) {
                // Handle different trim memory levels
                when (level) {
                    android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL,
                    android.content.ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> {
                        isLowMemory = true
                        notifyLowMemory()
                    }
                    android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
                    android.content.ComponentCallbacks2.TRIM_MEMORY_MODERATE -> {
                        // Moderate pressure, still concerning
                        isLowMemory = true
                        notifyLowMemory()
                    }
                }
            }
        })
    }
    
    /**
     * Notifies Flutter side about low memory condition
     */
    private fun notifyLowMemory() {
        Handler(Looper.getMainLooper()).post {
            methodChannel?.invokeMethod("onLowMemory", null)
        }
    }
}
