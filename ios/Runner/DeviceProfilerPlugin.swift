import UIKit
import Flutter

/**
 * iOS implementation of device profiling for the DeviceProfiler plugin.
 *
 * This plugin gathers device hardware metrics including:
 * - Total RAM (GB)
 * - CPU core count
 * - Battery level percentage
 * - Memory pressure state
 */
public class DeviceProfilerPlugin: NSObject, FlutterPlugin {
    private var isLowMemory: Bool = false
    private var methodChannel: FlutterMethodChannel?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.device_profiler/platform",
            binaryMessenger: registrar.messenger()
        )
        let instance = DeviceProfilerPlugin()
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.setupMemoryPressureMonitoring()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getDeviceProfile":
            do {
                let profile = try getDeviceProfile()
                result(profile)
            } catch {
                result(FlutterError(
                    code: "PROFILE_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /**
     * Gathers all device metrics and returns them as a dictionary
     */
    private func getDeviceProfile() throws -> [String: Any] {
        let ramGB = getTotalRamGB()
        let cpuCores = getCpuCoreCount()
        let batteryLevel = getBatteryLevel()

        // Check current memory pressure
        checkMemoryPressure()

        return [
            "ramGB": ramGB,
            "cpuCores": cpuCores,
            "batteryLevel": batteryLevel,
            "isLowMemory": isLowMemory
        ]
    }

    /**
     * Gets total RAM in gigabytes
     */
    private func getTotalRamGB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        guard kerr == KERN_SUCCESS else {
            // Fallback: use physical memory
            return Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0 * 1024.0)
        }

        return Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0 * 1024.0)
    }

    /**
     * Gets the number of available CPU cores
     */
    private func getCpuCoreCount() -> Int {
        return ProcessInfo.processInfo.processorCount
    }

    /**
     * Gets current battery level as percentage (0-100)
     */
    private func getBatteryLevel() -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel

        if level < 0 {
            // Battery monitoring not available or simulator
            return 100
        }

        return Int(level * 100)
    }

    /**
     * Checks if the device is under memory pressure
     */
    private func checkMemoryPressure() {
        // Check available memory
        let info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / (1024.0 * 1024.0)
            let totalMB = Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0)
            let availableRatio = 1.0 - (usedMB / totalMB)

            // Consider low memory if available is less than 10%
            if availableRatio < 0.10 {
                isLowMemory = true
            }
        }
    }

    /**
     * Sets up monitoring for memory pressure events
     */
    private func setupMemoryPressureMonitoring() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])

        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self = self else { return }

            let event = self.memoryPressureSource?.data
            if event == .warning || event == .critical {
                self.isLowMemory = true
                self.notifyLowMemory()
            }
        }

        memoryPressureSource?.resume()
    }

    /**
     * Notifies Flutter side about low memory condition
     */
    private func notifyLowMemory() {
        DispatchQueue.main.async { [weak self] in
            self?.methodChannel?.invokeMethod("onLowMemory", arguments: nil)
        }
    }

    deinit {
        memoryPressureSource?.cancel()
    }
}
