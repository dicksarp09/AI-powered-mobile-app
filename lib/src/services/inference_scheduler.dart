import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import '../models/models.dart';
import 'audio_capture_service.dart';
import 'device_profile_service.dart';
import 'local_storage_service.dart';
import 'output_validator.dart';
import 'slm_action_extractor.dart';
import 'speech_to_text_service.dart';
import 'transcript_cleaner.dart';

/// Exception thrown when inference scheduling fails
class InferenceException implements Exception {
  final String message;
  final String? phase;
  InferenceException(this.message, {this.phase});
  @override
  String toString() => 'InferenceException: $message${phase != null ? ' (during $phase)' : ''}';
}

/// Tracks the state and metrics of an inference job
class InferenceJob {
  final String jobId;
  final String audioFilePath;
  final bool requestedLiveMode;
  bool actualLiveMode;
  DateTime startTime;
  DateTime? endTime;
  String? sttModel;
  String? slmModel;
  int? tokensUsed;
  int? batteryAtStart;
  int? batteryAtEnd;
  bool success;
  String? error;
  Map<String, dynamic>? result;

  InferenceJob({
    required this.jobId,
    required this.audioFilePath,
    required this.requestedLiveMode,
    this.actualLiveMode = false,
    required this.startTime,
    this.endTime,
    this.sttModel,
    this.slmModel,
    this.tokensUsed,
    this.batteryAtStart,
    this.batteryAtEnd,
    this.success = false,
    this.error,
    this.result,
  });

  Duration? get duration => endTime != null 
      ? endTime!.difference(startTime) 
      : null;

  Map<String, dynamic> toMetrics() {
    return {
      'jobId': jobId,
      'requestedLiveMode': requestedLiveMode,
      'actualLiveMode': actualLiveMode,
      'durationMs': duration?.inMilliseconds,
      'sttModel': sttModel,
      'slmModel': slmModel,
      'tokensUsed': tokensUsed,
      'batteryAtStart': batteryAtStart,
      'batteryAtEnd': batteryAtEnd,
      'success': success,
      'error': error,
    };
  }
}

/// Orchestrates AI inference with battery optimization and power discipline.
///
/// This scheduler ensures:
/// - Debounced processing (no redundant calls)
/// - Battery-aware throttling (auto-switch to batch mode when low battery)
/// - Model lifecycle management (aggressive unloading)
/// - Non-blocking UI (runs in background)
/// - Graceful degradation on resource constraints
///
/// Example usage:
/// ```dart
/// final scheduler = InferenceScheduler();
/// await scheduler.initialize();
///
/// final result = await scheduler.processNote(
///   audioFilePath: '/path/to/audio.wav',
///   liveMode: false,
/// );
/// ```
class InferenceScheduler {
  static final Logger _logger = Logger('InferenceScheduler');
  static const MethodChannel _batteryChannel = MethodChannel('com.ai_notes/battery');
  
  // Services
  final DeviceProfileService _profileService = DeviceProfileService();
  final AudioCaptureService _audioService = AudioCaptureService();
  final SpeechToTextService _sttService = SpeechToTextService();
  final TranscriptCleaner _cleaner = TranscriptCleaner();
  final OutputValidator _validator = OutputValidator();
  final LocalStorageService _storage;
  
  // State
  bool _isInitialized = false;
  ModelConfig? _modelConfig;
  final Map<String, InferenceJob> _activeJobs = {};
  final Map<String, DateTime> _lastProcessed = {};
  
  // Configuration
  static const Duration _debounceWindow = Duration(seconds: 2);
  static const int _lowBatteryThreshold = 30;
  static const int _criticalBatteryThreshold = 15;

  /// Whether the scheduler is initialized
  bool get isInitialized => _isInitialized;

  /// Creates inference scheduler with storage dependency
  InferenceScheduler(this._storage);

  /// Initializes the scheduler and all required services.
  Future<void> initialize() async {
    if (_isInitialized) return;

    _logger.info('Initializing InferenceScheduler...');

    try {
      // Get device profile and model configuration
      _modelConfig = await _profileService.initializeAndGetConfig();
      _logger.info('Model configuration loaded: ${_modelConfig?.slmModel}');

      // Initialize storage
      await _storage.initialize();

      _isInitialized = true;
      _logger.info('InferenceScheduler initialized successfully');
      _logger.info('  Battery threshold: $_lowBatteryThreshold%');
      _logger.info('  Debounce window: ${_debounceWindow.inSeconds}s');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize InferenceScheduler: $e', e, stackTrace);
      throw InferenceException('Initialization failed: $e');
    }
  }

  /// Processes a note through the full AI pipeline with optimizations.
  ///
  /// This method:
  /// 1. Checks for duplicate/recent processing (debouncing)
  /// 2. Assesses battery and resource state
  /// 3. Adjusts processing mode if needed
  /// 4. Runs STT → Clean → SLM → Validate → Store pipeline
  /// 5. Aggressively unloads models after completion
  /// 6. Returns safe, validated output
  ///
  /// [audioFilePath]: Path to the recorded audio file
  /// [liveMode]: Whether to use live streaming (may be overridden by battery)
  /// [noteId]: Optional note ID (generated if not provided)
  Future<Map<String, dynamic>> processNote({
    required String audioFilePath,
    bool liveMode = false,
    String? noteId,
  }) async {
    _ensureInitialized();
    
    final jobId = noteId ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    // Check debouncing
    if (_shouldDebounce(audioFilePath)) {
      _logger.info('Debouncing duplicate request for: $audioFilePath');
      await Future.delayed(_debounceWindow);
    }

    // Check battery and adjust mode
    final batteryLevel = await _getBatteryLevel();
    final actualLiveMode = _shouldUseLiveMode(liveMode, batteryLevel);
    
    _logger.info('Starting inference job: $jobId');
    _logger.info('  Battery: $batteryLevel%');
    _logger.info('  Requested liveMode: $liveMode');
    _logger.info('  Actual liveMode: $actualLiveMode');

    // Create job tracking
    final job = InferenceJob(
      jobId: jobId,
      audioFilePath: audioFilePath,
      requestedLiveMode: liveMode,
      actualLiveMode: actualLiveMode,
      startTime: DateTime.now(),
      batteryAtStart: batteryLevel,
      sttModel: _modelConfig?.sttModel,
      slmModel: _modelConfig?.slmModel,
    );
    _activeJobs[jobId] = job;

    try {
      // Phase 1: Speech-to-Text
      _logger.info('Phase 1: Speech-to-Text');
      final transcript = await _runSTT(audioFilePath, actualLiveMode);
      
      if (transcript.isEmpty) {
        throw InferenceException('STT produced empty transcript', phase: 'stt');
      }
      
      _logger.info('STT complete: ${transcript.length} chars');

      // Phase 2: Clean transcript
      _logger.info('Phase 2: Transcript cleaning');
      final cleanedTranscript = _cleaner.clean(transcript);
      _logger.info('Cleaning complete: ${cleanedTranscript.length} chars');

      // Phase 3: SLM Extraction
      _logger.info('Phase 3: SLM extraction');
      final extractedJson = await _runSLM(cleanedTranscript);
      _logger.info('SLM extraction complete');

      // Phase 4: Validate output
      _logger.info('Phase 4: Output validation');
      final validatedOutput = await _validator.validateAndFallback(
        jsonEncode(extractedJson),
        cleanedTranscript,
      );
      _logger.info('Validation complete: ${validatedOutput['tasks']?.length ?? 0} tasks');

      // Phase 5: Store results
      _logger.info('Phase 5: Persisting to storage');
      await _storage.saveNote(
        noteId: jobId,
        transcript: cleanedTranscript,
        extractedJson: validatedOutput,
        audioFilePath: audioFilePath,
        timestamp: DateTime.now(),
      );
      _logger.info('Storage complete');

      // Mark job success
      job.success = true;
      job.result = validatedOutput;
      job.tokensUsed = extractedJson['tasks']?.length ?? 0;

      _logger.info('Inference job completed successfully: $jobId');
      
      return validatedOutput;

    } catch (e, stackTrace) {
      _logger.severe('Inference job failed: $e', e, stackTrace);
      job.success = false;
      job.error = e.toString();
      
      // Return fallback
      return {
        'tasks': [],
        'fallback_transcript': await _fallbackTranscript(audioFilePath),
        'fallback_reason': 'inference_failed: $e',
        'jobId': jobId,
      };
    } finally {
      // Always cleanup
      job.endTime = DateTime.now();
      job.batteryAtEnd = await _getBatteryLevel();
      _lastProcessed[audioFilePath] = DateTime.now();
      _activeJobs.remove(jobId);
      
      // Log metrics
      _logger.info('Job metrics: ${job.toMetrics()}');
      
      // Aggressive cleanup
      await _cleanup();
    }
  }

  /// Runs Speech-to-Text with retry logic.
  Future<String> _runSTT(String audioFilePath, bool liveMode) async {
    try {
      if (liveMode) {
        // For live mode, we'd need to integrate with audio stream
        // For now, fall back to batch
        _logger.warning('Live mode STT not fully implemented, using batch');
      }
      
      return await _sttService.transcribeBatch(
        audioFilePath: audioFilePath,
        modelPath: _modelConfig?.sttModel ?? 'tiny.en',
      );
    } catch (e) {
      _logger.warning('STT failed, attempting retry: $e');
      
      // Retry once with fallback model
      try {
        return await _sttService.transcribeBatch(
          audioFilePath: audioFilePath,
          modelPath: 'tiny.en', // Smallest, most reliable model
        );
      } catch (retryError) {
        throw InferenceException('STT failed after retry: $retryError', phase: 'stt');
      }
    }
  }

  /// Runs SLM extraction with adjusted config for battery.
  Future<Map<String, dynamic>> _runSLM(String cleanedTranscript) async {
    final batteryLevel = await _getBatteryLevel();
    
    // Adjust config for low battery
    var config = GenerationConfig.jsonExtraction;
    if (batteryLevel < _lowBatteryThreshold) {
      _logger.info('Low battery detected, reducing token limit');
      config = config.copyWith(maxTokens: (config.maxTokens * 0.5).round());
    }

    final extractor = SlmActionExtractor(
      modelPath: _modelConfig?.slmModel ?? 'tinyllama-Q4',
      config: config,
    );

    try {
      return await extractor.extract(cleanedTranscript);
    } finally {
      await extractor.dispose();
    }
  }

  /// Gets current battery level.
  Future<int> _getBatteryLevel() async {
    try {
      final level = await _batteryChannel.invokeMethod<int>('getBatteryLevel');
      return level ?? 100;
    } catch (e) {
      _logger.warning('Could not get battery level: $e');
      return 100; // Assume full if unknown
    }
  }

  /// Determines if processing should be debounced.
  bool _shouldDebounce(String audioFilePath) {
    final lastProcess = _lastProcessed[audioFilePath];
    if (lastProcess == null) return false;
    
    return DateTime.now().difference(lastProcess) < _debounceWindow;
  }

  /// Determines actual processing mode based on battery and request.
  bool _shouldUseLiveMode(bool requested, int batteryLevel) {
    // Force batch mode on low battery
    if (batteryLevel < _lowBatteryThreshold) {
      _logger.info('Low battery ($batteryLevel%), forcing batch mode');
      return false;
    }
    
    // Force batch mode on critical battery
    if (batteryLevel < _criticalBatteryThreshold) {
      _logger.warning('Critical battery ($batteryLevel%), disabling all live features');
      return false;
    }
    
    return requested;
  }

  /// Gets fallback transcript when processing fails.
  Future<String> _fallbackTranscript(String audioFilePath) async {
    try {
      // Try to read raw audio file info as fallback
      final file = File(audioFilePath);
      if (await file.exists()) {
        return '[Audio file: ${file.path}]';
      }
    } catch (_) {
      // Ignore
    }
    return '[Transcription unavailable]';
  }

  /// Cleans up resources after inference.
  Future<void> _cleanup() async {
    _logger.fine('Running cleanup...');
    
    // Dispose STT service
    await _sttService.dispose();
    
    // Note: SLM models are disposed in _runSLM finally block
    
    // Force garbage collection suggestion (optional)
    // This is a hint to the Dart VM
    await Future.delayed(Duration.zero);
    
    _logger.fine('Cleanup complete');
  }

  /// Gets current active jobs.
  List<InferenceJob> getActiveJobs() {
    return _activeJobs.values.toList();
  }

  /// Cancels an active job.
  Future<void> cancelJob(String jobId) async {
    final job = _activeJobs[jobId];
    if (job != null) {
      _logger.info('Cancelling job: $jobId');
      job.error = 'Cancelled by user';
      job.endTime = DateTime.now();
      job.success = false;
      _activeJobs.remove(jobId);
    }
  }

  /// Ensures scheduler is initialized.
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw InferenceException('Scheduler not initialized. Call initialize() first.');
    }
  }

  /// Disposes the scheduler and releases resources.
  Future<void> dispose() async {
    _logger.info('Disposing InferenceScheduler...');
    
    // Cancel all active jobs
    for (final jobId in _activeJobs.keys.toList()) {
      await cancelJob(jobId);
    }
    
    // Dispose services
    await _sttService.dispose();
    await _storage.dispose();
    
    _isInitialized = false;
    _logger.info('InferenceScheduler disposed');
  }
}
