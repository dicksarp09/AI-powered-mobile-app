import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:workmanager/workmanager.dart';

import 'local_storage_service.dart';

/// Exception thrown when device actions fail
class DeviceActionException implements Exception {
  final String message;
  final String? action;
  DeviceActionException(this.message, {this.action});
  @override
  String toString() => 'DeviceActionException: $message${action != null ? ' (during $action)' : ''}';
}

/// Service for integrating AI output with device capabilities.
///
/// This layer bridges structured JSON output from SLM to real device actions:
/// - Calendar integration (add tasks)
/// - Notification scheduling
/// - Note sharing (markdown/JSON)
/// - Task completion tracking
///
/// All operations are async and non-blocking.
/// Works offline after initial setup.
///
/// Example usage:
/// ```dart
/// final deviceActions = DeviceActionService(storageService);
/// await deviceActions.initialize();
///
/// // Add task to calendar
/// await deviceActions.addToCalendar({
///   'title': 'Call John',
///   'due_time': 'tomorrow at 3pm',
///   'priority': 'high',
/// });
///
/// // Schedule notification
/// await deviceActions.scheduleNotification(taskJson);
///
/// // Share note
/// await deviceActions.shareNote(
///   noteId: 'note123',
///   transcript: 'Remind me to...',
///   extractedJson: {'tasks': [...]},
///   format: 'markdown',
/// );
/// ```
class DeviceActionService {
  static final Logger _logger = Logger('DeviceActionService');
  static const MethodChannel _platform = MethodChannel('com.ai_notes/device_actions');
  
  final LocalStorageService _storage;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// Whether the service is initialized
  bool get isInitialized => _isInitialized;

  /// Creates device action service with storage dependency
  DeviceActionService(this._storage);

  /// Initializes the device action service.
  ///
  /// Must be called before any other operations.
  /// Sets up notifications, timezone data, and workmanager.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.info('Initializing DeviceActionService...');

    try {
      // Initialize timezone data
      tz.initializeTimeZones();

      // Initialize notifications
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      // Initialize workmanager for background tasks
      await Workmanager().initialize(
        _callbackDispatcher,
        isInDebugMode: false,
      );

      _isInitialized = true;
      _logger.info('DeviceActionService initialized successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize DeviceActionService: $e', e, stackTrace);
      throw DeviceActionException('Initialization failed: $e', action: 'initialize');
    }
  }

  /// Background task callback dispatcher
  static void _callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      _logger.info('Background task executed: $task');
      return Future.value(true);
    });
  }

  /// Notification tap handler
  void _onNotificationTap(NotificationResponse response) {
    _logger.info('Notification tapped: ${response.payload}');
    // Handle notification tap - could navigate to specific note
  }

  /// Adds a task to the device calendar.
  ///
  /// Uses platform-specific APIs:
  /// - Android: CalendarContract via intent
  /// - iOS: EventKit via platform channel
  ///
  /// [task] must contain:
  /// - title: String
  /// - due_time: String (optional, parsed for date/time)
  /// - priority: String (optional)
  Future<void> addToCalendar(Map<String, dynamic> task) async {
    _ensureInitialized();
    _logger.info('Adding task to calendar: ${task['title']}');

    try {
      final title = task['title']?.toString() ?? 'Untitled Task';
      final dueTime = task['due_time']?.toString();
      final priority = task['priority']?.toString() ?? 'medium';

      // Parse due time to DateTime
      final DateTime? eventDate = _parseDueTime(dueTime);

      if (Platform.isAndroid) {
        await _addToCalendarAndroid(title, eventDate, priority);
      } else if (Platform.isIOS) {
        await _addToCalendarIOS(title, eventDate, priority);
      } else {
        _logger.warning('Calendar integration not supported on this platform');
      }

      _logger.info('Task added to calendar successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to add task to calendar: $e', e, stackTrace);
      throw DeviceActionException('Failed to add to calendar: $e', action: 'addToCalendar');
    }
  }

  /// Adds event to Android calendar using intent
  Future<void> _addToCalendarAndroid(
    String title,
    DateTime? eventDate,
    String priority,
  ) async {
    try {
      final Map<String, dynamic> args = {
        'title': title,
        'description': 'Priority: $priority\n\nCreated by AI Notes',
        'isAllDay': eventDate == null,
      };

      if (eventDate != null) {
        args['beginTime'] = eventDate.millisecondsSinceEpoch;
        args['endTime'] = eventDate.add(const Duration(hours: 1)).millisecondsSinceEpoch;
      }

      await _platform.invokeMethod('addToCalendar', args);
    } on PlatformException catch (e) {
      // Fallback to URL launcher
      _logger.warning('Platform channel failed, using URL launcher fallback');
      await _launchCalendarUrl(title, eventDate);
    }
  }

  /// Adds event to iOS calendar using EventKit
  Future<void> _addToCalendarIOS(
    String title,
    DateTime? eventDate,
    String priority,
  ) async {
    try {
      final Map<String, dynamic> args = {
        'title': title,
        'notes': 'Priority: $priority\n\nCreated by AI Notes',
        'isAllDay': eventDate == null,
      };

      if (eventDate != null) {
        args['startDate'] = eventDate.millisecondsSinceEpoch;
        args['endDate'] = eventDate.add(const Duration(hours: 1)).millisecondsSinceEpoch;
      }

      await _platform.invokeMethod('addToCalendar', args);
    } on PlatformException catch (e) {
      _logger.warning('Calendar access denied or unavailable: $e');
      // Could show dialog to user about enabling calendar access
    }
  }

  /// Fallback: Launch calendar URL
  Future<void> _launchCalendarUrl(String title, DateTime? eventDate) async {
    final String encodedTitle = Uri.encodeComponent(title);
    final String? url = eventDate != null
        ? 'https://calendar.google.com/calendar/render?action=TEMPLATE&text=$encodedTitle'
        : null;

    if (url != null && await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  /// Schedules a local notification for a task.
  ///
  /// [task] must contain:
  /// - title: String
  /// - due_time: String (parsed for scheduling)
  ///
  /// If due_time is in the past, schedules immediately.
  Future<void> scheduleNotification(Map<String, dynamic> task) async {
    _ensureInitialized();
    _logger.info('Scheduling notification for: ${task['title']}');

    try {
      final title = task['title']?.toString() ?? 'Task Reminder';
      final dueTime = task['due_time']?.toString();
      final taskId = task['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

      // Parse due time
      DateTime? scheduledDate = _parseDueTime(dueTime);
      
      // If no due time or past date, schedule for 5 minutes from now
      if (scheduledDate == null || scheduledDate.isBefore(DateTime.now())) {
        scheduledDate = DateTime.now().add(const Duration(minutes: 5));
        _logger.info('Due time not specified or in past, scheduling for 5 min from now');
      }

      // Convert to TZDateTime
      final tz.TZDateTime scheduledTZDate = tz.TZDateTime.from(
        scheduledDate,
        tz.local,
      );

      // Android notification details
      final androidDetails = AndroidNotificationDetails(
        'ai_notes_tasks',
        'AI Notes Tasks',
        channelDescription: 'Notifications for AI-generated tasks',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
      );

      // iOS notification details
      final iosDetails = const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Schedule notification
      await _notifications.zonedSchedule(
        taskId.hashCode, // Use hash of task ID as notification ID
        'Task Reminder: $title',
        'Due: ${dueTime ?? 'soon'}',
        scheduledTZDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: jsonEncode(task),
      );

      _logger.info('Notification scheduled for: $scheduledDate');
    } catch (e, stackTrace) {
      _logger.severe('Failed to schedule notification: $e', e, stackTrace);
      throw DeviceActionException('Failed to schedule notification: $e', action: 'scheduleNotification');
    }
  }

  /// Cancels a scheduled notification.
  Future<void> cancelNotification(String taskId) async {
    try {
      await _notifications.cancel(taskId.hashCode);
      _logger.info('Cancelled notification for task: $taskId');
    } catch (e) {
      _logger.warning('Failed to cancel notification: $e');
    }
  }

  /// Marks a task as done.
  ///
  /// Updates the note in storage and cancels any scheduled notifications.
  /// [taskId] is the unique identifier for the task.
  Future<void> markTaskDone(String taskId) async {
    _logger.info('Marking task as done: $taskId');

    try {
      // Cancel any scheduled notification
      await cancelNotification(taskId);

      // Get note from storage
      final note = await _storage.getNote(taskId);
      if (note == null) {
        _logger.warning('Note not found for task completion: $taskId');
        return;
      }

      // Update extracted JSON to mark task as done
      final extractedJson = Map<String, dynamic>.from(note['extractedJson'] as Map);
      final tasks = (extractedJson['tasks'] as List?)?.cast<Map<String, dynamic>>();
      
      if (tasks != null) {
        for (var i = 0; i < tasks.length; i++) {
          if (tasks[i]['id']?.toString() == taskId || i == 0) {
            tasks[i]['completed'] = true;
            tasks[i]['completedAt'] = DateTime.now().toIso8601String();
            break;
          }
        }
      }

      // Save updated note
      await _storage.saveNote(
        noteId: taskId,
        transcript: note['transcript'] as String,
        extractedJson: extractedJson,
        audioFilePath: note['audioFilePath'] as String?,
        timestamp: DateTime.parse(note['timestamp'] as String),
        userEdits: {
          ...(note['userEdits'] as Map<String, dynamic>? ?? {}),
          'markedDone': DateTime.now().toIso8601String(),
        },
      );

      _logger.info('Task marked as done: $taskId');
    } catch (e, stackTrace) {
      _logger.severe('Failed to mark task as done: $e', e, stackTrace);
      throw DeviceActionException('Failed to mark task done: $e', action: 'markTaskDone');
    }
  }

  /// Shares a note in markdown or JSON format.
  ///
  /// [noteId]: The note identifier
  /// [transcript]: The transcript text
  /// [extractedJson]: The structured JSON data
  /// [format]: 'markdown' or 'json'
  Future<void> shareNote({
    required String noteId,
    required String transcript,
    required Map<String, dynamic> extractedJson,
    String format = 'markdown',
  }) async {
    _logger.info('Sharing note: $noteId in $format format');

    try {
      String content;
      String subject;

      if (format.toLowerCase() == 'markdown') {
        content = _convertToMarkdown(transcript, extractedJson);
        subject = 'AI Note: ${_getFirstTaskTitle(extractedJson)}';
      } else if (format.toLowerCase() == 'json') {
        content = jsonEncode({
          'noteId': noteId,
          'transcript': transcript,
          'extractedJson': extractedJson,
          'exportedAt': DateTime.now().toIso8601String(),
        });
        subject = 'AI Note JSON Export';
      } else {
        throw ArgumentError('Invalid format. Use "markdown" or "json"');
      }

      await Share.share(
        content,
        subject: subject,
      );

      _logger.info('Note shared successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to share note: $e', e, stackTrace);
      throw DeviceActionException('Failed to share note: $e', action: 'shareNote');
    }
  }

  /// Converts note data to Markdown format.
  String _convertToMarkdown(String transcript, Map<String, dynamic> extractedJson) {
    final buffer = StringBuffer();
    
    buffer.writeln('# AI Note');
    buffer.writeln();
    buffer.writeln('## Transcript');
    buffer.writeln(transcript);
    buffer.writeln();
    
    final tasks = extractedJson['tasks'] as List?;
    if (tasks != null && tasks.isNotEmpty) {
      buffer.writeln('## Extracted Tasks');
      buffer.writeln();
      
      for (var i = 0; i < tasks.length; i++) {
        final task = tasks[i] as Map<String, dynamic>;
        final title = task['title'] ?? 'Untitled';
        final dueTime = task['due_time'];
        final priority = task['priority'] ?? 'medium';
        final completed = task['completed'] == true;
        
        buffer.write('- [${completed ? 'x' : ' '}] **$title**');
        
        if (dueTime != null) {
          buffer.write(' (Due: $dueTime)');
        }
        
        buffer.write(' - Priority: ${priority.toString().toUpperCase()}');
        buffer.writeln();
      }
    }
    
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln('Generated by AI Notes on ${DateTime.now()}');
    
    return buffer.toString();
  }

  /// Gets the first task title for sharing subject.
  String _getFirstTaskTitle(Map<String, dynamic> extractedJson) {
    final tasks = extractedJson['tasks'] as List?;
    if (tasks != null && tasks.isNotEmpty) {
      final firstTask = tasks.first as Map<String, dynamic>;
      return firstTask['title']?.toString() ?? 'Untitled';
    }
    return 'Untitled Note';
  }

  /// Parses due time string to DateTime.
  ///
  /// Handles various formats:
  /// - "tomorrow at 3pm"
  /// - "next Monday"
  /// - "2024-12-25 15:00"
  /// - "15:00" (today)
  DateTime? _parseDueTime(String? dueTime) {
    if (dueTime == null || dueTime.isEmpty) return null;

    final now = DateTime.now();
    final lowerDue = dueTime.toLowerCase();

    // Handle "tomorrow"
    if (lowerDue.contains('tomorrow')) {
      final tomorrow = now.add(const Duration(days: 1));
      final time = _extractTime(lowerDue);
      if (time != null) {
        return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, time.hour, time.minute);
      }
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0); // Default 9am
    }

    // Handle "today"
    if (lowerDue.contains('today')) {
      final time = _extractTime(lowerDue);
      if (time != null) {
        return DateTime(now.year, now.month, now.day, time.hour, time.minute);
      }
    }

    // Handle ISO format
    try {
      return DateTime.parse(dueTime);
    } catch (_) {
      // Not ISO format, continue
    }

    // Try to extract just time (e.g., "3pm", "15:00")
    final time = _extractTime(lowerDue);
    if (time != null) {
      return DateTime(now.year, now.month, now.day, time.hour, time.minute);
    }

    return null;
  }

  /// Extracts time from string.
  /// Returns _TimeOfDay or null.
  _TimeOfDay? _extractTime(String text) {
    // Match "3pm", "3:30pm", "15:00", "3 pm"
    final timeRegex = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?');
    final match = timeRegex.firstMatch(text);

    if (match != null) {
      int hour = int.parse(match.group(1)!);
      int minute = match.group(2) != null ? int.parse(match.group(2)!) : 0;
      final period = match.group(3);

      if (period != null) {
        if (period.toLowerCase() == 'pm' && hour != 12) {
          hour += 12;
        } else if (period.toLowerCase() == 'am' && hour == 12) {
          hour = 0;
        }
      }

      return _TimeOfDay(hour, minute);
    }

    return null;
  }

  /// Ensures service is initialized.
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw DeviceActionException(
        'Service not initialized. Call initialize() first.',
        action: 'access',
      );
    }
  }

  /// Disposes the service and releases resources.
  Future<void> dispose() async {
    _logger.info('Disposing DeviceActionService...');
    await _notifications.cancelAll();
    _isInitialized = false;
    _logger.info('DeviceActionService disposed');
  }
}

/// Simple time representation
class _TimeOfDay {
  final int hour;
  final int minute;
  _TimeOfDay(this.hour, this.minute);
}
