package com.device_profiler.device_profiler

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity that registers the DeviceProfilerPlugin
 */
class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.device_profiler/platform"
    private var deviceProfilerPlugin: DeviceProfilerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        deviceProfilerPlugin = DeviceProfilerPlugin()
        deviceProfilerPlugin?.onAttachedToEngine(context, channel)
    }

    override fun onDestroy() {
        deviceProfilerPlugin?.onDetachedFromEngine()
        super.onDestroy()
    }
}
