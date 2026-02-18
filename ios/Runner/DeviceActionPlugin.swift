import UIKit
import Flutter
import EventKit
import EventKitUI

/**
 * iOS implementation of device action integration for the DeviceActionService plugin.
 *
 * This plugin handles:
 * - Calendar integration via EventKit
 * - Permission management
 * - Event creation and editing
 */
public class DeviceActionPlugin: NSObject, FlutterPlugin, EKEventEditViewDelegate {
    private var eventStore: EKEventStore?
    private var result: FlutterResult?
    private var viewController: UIViewController?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.ai_notes/device_actions",
            binaryMessenger: registrar.messenger()
        )
        let instance = DeviceActionPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        self.result = result

        switch call.method {
        case "addToCalendar":
            handleAddToCalendar(call: call, result: result)
        case "checkCalendarPermission":
            checkCalendarPermission(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Handles adding an event to the calendar
    private func handleAddToCalendar(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Arguments required", details: nil))
            return
        }

        let title = args["title"] as? String ?? "Untitled Event"
        let notes = args["notes"] as? String
        let isAllDay = args["isAllDay"] as? Bool ?? false
        let startDateMs = args["startDate"] as? Int
        let endDateMs = args["endDate"] as? Int

        // Request calendar access
        eventStore = EKEventStore()

        eventStore?.requestAccess(to: .event) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    result(FlutterError(code: "CALENDAR_ERROR", message: error.localizedDescription, details: nil))
                    return
                }

                guard granted else {
                    result([
                        "success": false,
                        "needsPermission": true
                    ])
                    return
                }

                self?.presentEventEditView(
                    title: title,
                    notes: notes,
                    isAllDay: isAllDay,
                    startDate: startDateMs != nil ? Date(timeIntervalSince1970: Double(startDateMs!) / 1000.0) : nil,
                    endDate: endDateMs != nil ? Date(timeIntervalSince1970: Double(endDateMs!) / 1000.0) : nil,
                    result: result
                )
            }
        }
    }

    /// Presents the event edit view controller
    private func presentEventEditView(
        title: String,
        notes: String?,
        isAllDay: Bool,
        startDate: Date?,
        endDate: Date?,
        result: @escaping FlutterResult
    ) {
        guard let eventStore = eventStore else {
            result(FlutterError(code: "CALENDAR_ERROR", message: "Event store not available", details: nil))
            return
        }

        // Create event
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.notes = notes
        event.isAllDay = isAllDay

        if let start = startDate {
            event.startDate = start
            event.endDate = endDate ?? start.addingTimeInterval(3600) // Default 1 hour
        } else {
            // Default to today
            event.startDate = Date()
            event.endDate = Date().addingTimeInterval(3600)
        }

        // Get default calendar
        event.calendar = eventStore.defaultCalendarForNewEvents

        // Present edit view
        let editViewController = EKEventEditViewController()
        editViewController.event = event
        editViewController.eventStore = eventStore
        editViewController.editViewDelegate = self

        // Get root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            self.viewController = rootViewController
            rootViewController.present(editViewController, animated: true)

            result([
                "success": true,
                "method": "eventkit"
            ])
        } else {
            result(FlutterError(code: "UI_ERROR", message: "Could not get root view controller", details: nil))
        }
    }

    /// Checks calendar permission status
    private func checkCalendarPermission(result: @escaping FlutterResult) {
        let status = EKEventStore.authorizationStatus(for: .event)
        result(status == .authorized)
    }

    // MARK: - EKEventEditViewDelegate

    public func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        controller.dismiss(animated: true)

        switch action {
        case .saved:
            print("Event saved successfully")
        case .canceled:
            print("Event creation cancelled")
        case .deleted:
            print("Event deleted")
        @unknown default:
            print("Unknown action")
        }
    }
}
