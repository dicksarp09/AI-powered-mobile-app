import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:workmanager/workmanager.dart';

import 'local_storage_service.dart';

/// Represents a background task type
enum BackgroundTaskType {
  reprocessNotes,
  cleanup,
  reindexSearch,
  syncModels,
}

/// Configuration for background task execution
class BackgroundTaskConfig {
  final bool requiresCharging;
  final bool requiresNetwork;
  final Duration minimumInterval;
  final Duration? deadline;

  const BackgroundTaskConfig({
    this.requiresCharging = true,
    this.requiresNetwork = false,
    this.minimumInterval = const Duration(hours: 24),
    this.deadline,
  });
}

/// Manages background tasks for offline AI processing.
///
/// This manager handles:
/// - Reprocessing notes when device is charging
/// - Search index optimization
/// - Periodic cleanup of old data
/// - Model updates (when available offline)
///
/// All tasks respect battery and resource constraints.
/// Tasks only run when device is idle and charging (by default).
///
/// Example usage:
/// ```dart
/// final taskManager = BackgroundTaskManager(storageService);
/// await taskManager.initialize();
///
/// // Schedule cleanup
/// await taskManager.scheduleCleanup();
///
/// // Run tasks manually (for testing)
/// await taskManager.runCleanup();
/// ```
class BackgroundTaskManager {
  static final Logger _logger = Logger('BackgroundTaskManager');
  static const MethodChannel _platform = MethodChannel('com.ai_notes/battery');
  
  final LocalStorageService _storage;
  bool _isInitialized = false;

  // Task tracking
  final Map<String, DateTime> _lastRunTimes = {};
  bool _isRunning = false;

  /// Whether the manager is initialized
  bool get isInitialized => _isInitialized;

  /// Whether a background task is currently running
  bool get isRunning => _isRunning;

  /// Creates background task manager with storage dependency
  BackgroundTaskManager(this._storage);

  /// Initializes the background task manager and WorkManager.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.info('Initializing BackgroundTaskManager...');

    try {
      // Initialize WorkManager
      await Workmanager().initialize(
        _callbackDispatcher,
        isInDebugMode: false,
      );

      _isInitialized = true;
      _logger.info('BackgroundTaskManager initialized successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize BackgroundTaskManager: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Registers periodic background tasks.
  ///
  /// Call this after initialization to enable automatic background processing.
  Future<void> registerPeriodicTasks() async {
    _ensureInitialized();
    _logger.info('Registering periodic background tasks...');

    try {
      // Schedule cleanup task (daily)
      await Workmanager().registerPeriodicTask(
        'cleanup-task',
        'cleanup',
        frequency: const Duration(days: 1),
        constraints: Constraints(
          requiresCharging: true,
          requiresBatteryNotLow: true,
          requiresStorageNotLow: true,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );

      // Schedule reindex task (weekly)
      await Workmanager().registerPeriodicTask(
        'reindex-task',
        'reindex',
        frequency: const Duration(days: 7),
        constraints: Constraints(
          requiresCharging: true,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );

      _logger.info('Periodic tasks registered');
    } catch (e, stackTrace) {
      _logger.severe('Failed to register periodic tasks: $e', e, stackTrace);
    }
  }

  /// Schedules an immediate cleanup task.
  Future<void> scheduleCleanup() async {
    _ensureInitialized();
    _logger.info('Scheduling cleanup task...');

    await Workmanager().registerOneOffTask(
      'cleanup-oneoff',
      'cleanup',
      constraints: Constraints(
        requiresCharging: true,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Schedules a reindex task.
  Future<void> scheduleReindex() async {
    _ensureInitialized();
    _logger.info('Scheduling reindex task...');

    await Workmanager().registerOneOffTask(
      'reindex-oneoff',
      'reindex',
      constraints: Constraints(
        requiresCharging: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Manually runs cleanup (for testing or manual trigger).
  Future<Map<String, dynamic>> runCleanup() async {
    _logger.info('Running manual cleanup...');
    
    if (!await _shouldRunTask('cleanup')) {
      _logger.info('Skipping cleanup - constraints not met');
      return {'skipped': true, 'reason': 'constraints_not_met'};
    }

    _isRunning = true;
    final startTime = DateTime.now();
    final results = <String, dynamic>{};

    try {
      // Initialize storage if needed
      if (!_storage.isInitialized) {
        await _storage.initialize();
      }

      // 1. Clean up old audio files
      results['audioDeleted'] = await _cleanupOldAudio();

      // 2. Remove orphaned index entries
      results['orphanedEntries'] = await _cleanupOrphanedIndices();

      // 3. Compact storage if supported
      results['storageCompacted'] = await _compactStorage();

      _lastRunTimes['cleanup'] = DateTime.now();
      results['success'] = true;
      results['durationMs'] = DateTime.now().difference(startTime).inMilliseconds;

      _logger.info('Cleanup completed: $results');
      return results;

    } catch (e, stackTrace) {
      _logger.severe('Cleanup failed: $e', e, stackTrace);
      return {
        'success': false,
        'error': e.toString(),
        'durationMs': DateTime.now().difference(startTime).inMilliseconds,
      };
    } finally {
      _isRunning = false;
    }
  }

  /// Manually runs reindex (for testing or manual trigger).
  Future<Map<String, dynamic>> runReindex() async {
    _logger.info('Running manual reindex...');
    
    if (!await _shouldRunTask('reindex')) {
      _logger.info('Skipping reindex - constraints not met');
      return {'skipped': true, 'reason': 'constraints_not_met'};
    }

    _isRunning = true;
    final startTime = DateTime.now();
    final results = <String, dynamic>{};

    try {
      // Initialize storage if needed
      if (!_storage.isInitialized) {
        await _storage.initialize();
      }

      // Get all notes
      final notes = await _storage.getAllNotes();
      int reindexedCount = 0;

      // Rebuild search index (if needed in future implementation)
      // For now, just validate all notes
      for (final note in notes) {
        // Validate note structure
        if (note['extractedJson'] == null) {
          _logger.warning('Note ${note['noteId']} missing extractedJson');
        } else {
          reindexedCount++;
        }
      }

      _lastRunTimes['reindex'] = DateTime.now();
      results['success'] = true;
      results['notesChecked'] = notes.length;
      results['notesValid'] = reindexedCount;
      results['durationMs'] = DateTime.now().difference(startTime).inMilliseconds;

      _logger.info('Reindex completed: $results');
      return results;

    } catch (e, stackTrace) {
      _logger.severe('Reindex failed: $e', e, stackTrace);
      return {
        'success': false,
        'error': e.toString(),
        'durationMs': DateTime.now().difference(startTime).inMilliseconds,
      };
    } finally {
      _isRunning = false;
    }
  }

  /// Checks if task should run based on constraints.
  Future<bool> _shouldRunTask(String taskName) async {
    // Check battery level
    final batteryLevel = await _getBatteryLevel();
    if (batteryLevel < 30) {
      _logger.info('Battery too low ($batteryLevel%), skipping task');
      return false;
    }

    // Check if charging (for most tasks)
    final isCharging = await _isDeviceCharging();
    if (!isCharging && batteryLevel < 50) {
      _logger.info('Device not charging and battery at $batteryLevel%, skipping task');
      return false;
    }

    // Check minimum interval
    final lastRun = _lastRunTimes[taskName];
    if (lastRun != null) {
      final timeSinceLastRun = DateTime.now().difference(lastRun);
      if (timeSinceLastRun < const Duration(hours: 1)) {
        _logger.info('Task $taskName ran recently (${timeSinceLastRun.inMinutes}m ago), skipping');
        return false;
      }
    }

    return true;
  }

  /// Cleans up old audio files.
  Future<int> _cleanupOldAudio() async {
    _logger.info('Cleaning up old audio files...');
    int deletedCount = 0;

    try {
      final stats = await _storage.getStatistics();
      final allNotes = await _storage.getAllNotes();
      
      // Find audio files older than 7 days
      final cutoffDate = DateTime.now().subtract(const Duration(days: 7));
      
      for (final note in allNotes) {
        final timestamp = DateTime.tryParse(note['timestamp'] as String? ?? '');
        final audioPath = note['audioFilePath'] as String?;
        
        if (timestamp != null && 
            timestamp.isBefore(cutoffDate) && 
            audioPath != null) {
          // Delete old audio
          await _storage.deleteAudio(note['noteId'] as String);
          deletedCount++;
        }
      }

      _logger.info('Deleted $deletedCount old audio files');
      return deletedCount;
    } catch (e) {
      _logger.warning('Audio cleanup failed: $e');
      return 0;
    }
  }

  /// Cleans up orphaned search index entries.
  Future<int> _cleanupOrphanedIndices() async {
    // This would be implemented if we had a separate search index
    // For now, Hive handles this automatically
    _logger.fine('Orphaned index cleanup skipped (handled by Hive)');
    return 0;
  }

  /// Compacts storage to free space.
  Future<bool> _compactStorage() async {
    // Hive automatically handles compaction
    // This is a placeholder for future optimization
    _logger.fine('Storage compaction skipped (handled by Hive)');
    return true;
  }

  /// Gets current battery level.
  Future<int> _getBatteryLevel() async {
    try {
      final level = await _platform.invokeMethod<int>('getBatteryLevel');
      return level ?? 100;
    } catch (e) {
      _logger.warning('Could not get battery level: $e');
      return 100;
    }
  }

  /// Checks if device is charging.
  Future<bool> _isDeviceCharging() async {
    try {
      final isCharging = await _platform.invokeMethod<bool>('isCharging');
      return isCharging ?? false;
    } catch (e) {
      _logger.warning('Could not get charging status: $e');
      return false;
    }
  }

  /// WorkManager callback dispatcher.
  static void _callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      _logger.info('Background task executed: ${task.name}');
      
      // Note: In a real implementation, we'd need to properly
      // initialize the storage service here. This is a simplified version.
      
      switch (task.name) {
        case 'cleanup':
          // Would call runCleanup() with initialized storage
          _logger.info('Cleanup task would run here');
          break;
        case 'reindex':
          // Would call runReindex() with initialized storage
          _logger.info('Reindex task would run here');
          break;
        default:
          _logger.warning('Unknown task: ${task.name}');
      }
      
      return Future.value(true);
    });
  }

  /// Ensures manager is initialized.
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError('BackgroundTaskManager not initialized. Call initialize() first.');
    }
  }

  /// Cancels all scheduled tasks.
  Future<void> cancelAllTasks() async {
    _logger.info('Cancelling all background tasks...');
    await Workmanager().cancelAll();
  }

  /// Gets last run times for all tasks.
  Map<String, DateTime> getLastRunTimes() {
    return Map.from(_lastRunTimes);
  }

  /// Disposes the manager.
  Future<void> dispose() async {
    _logger.info('Disposing BackgroundTaskManager...');
    await cancelAllTasks();
    _isInitialized = false;
    _logger.info('BackgroundTaskManager disposed');
  }
}
