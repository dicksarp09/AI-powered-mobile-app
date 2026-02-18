package com.device_profiler.device_profiler

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity that registers all platform plugins
 */
class MainActivity: FlutterActivity() {
    private val PROFILER_CHANNEL = "com.device_profiler/platform"
    private val ACTIONS_CHANNEL = "com.ai_notes/device_actions"
    
    private var deviceProfilerPlugin: DeviceProfilerPlugin? = null
    private var deviceActionPlugin: DeviceActionPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register Device Profiler Plugin
        val profilerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PROFILER_CHANNEL)
        deviceProfilerPlugin = DeviceProfilerPlugin()
        deviceProfilerPlugin?.onAttachedToEngine(context, profilerChannel)
        
        // Register Device Action Plugin
        val actionsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACTIONS_CHANNEL)
        deviceActionPlugin = DeviceActionPlugin()
        deviceActionPlugin?.onAttachedToEngine(this, actionsChannel)
    }

    override fun onDestroy() {
        deviceProfilerPlugin?.onDetachedFromEngine()
        deviceActionPlugin?.onDetachedFromEngine()
        super.onDestroy()
    }
}
