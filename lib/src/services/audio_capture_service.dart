import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Exception thrown when microphone permission is denied
class MicrophonePermissionDeniedException implements Exception {
  final String message;
  MicrophonePermissionDeniedException([this.message = 'Microphone permission denied']);
  @override
  String toString() => message;
}

/// Exception thrown when recording is already in progress
class RecordingInProgressException implements Exception {
  final String message;
  RecordingInProgressException([this.message = 'Recording already in progress']);
  @override
  String toString() => message;
}

/// Exception thrown when no recording is active
class NoActiveRecordingException implements Exception {
  final String message;
  NoActiveRecordingException([this.message = 'No active recording']);
  @override
  String toString() => message;
}

/// Service responsible for capturing high-quality audio for AI processing.
///
/// This service handles:
/// - Recording audio at 16kHz, mono, WAV PCM 16-bit
/// - Microphone permission management
/// - Real-time amplitude monitoring
/// - Proper resource cleanup and mic release
/// - Auto-stop when app goes to background
///
/// Example usage:
/// ```dart
/// final audioService = AudioCaptureService();
/// await audioService.startRecording();
/// // ... user speaks ...
/// final filePath = await audioService.stopRecording();
/// ```
class AudioCaptureService extends WidgetsBindingObserver {
  static final Logger _logger = Logger('AudioCaptureService');
  
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _amplitudeController = StreamController<double>.broadcast();
  
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  bool _isRecording = false;
  Timer? _amplitudeTimer;
  AppLifecycleState? _lastLifecycleState;

  /// Stream of audio amplitude values (0.0 to 1.0) for waveform visualization
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  /// Whether a recording is currently in progress
  bool get isRecording => _isRecording;

  /// The path of the current or last recording
  String? get currentRecordingPath => _currentRecordingPath;

  /// Duration of the current recording, or null if not recording
  Duration? get recordingDuration {
    if (_recordingStartTime == null || !_isRecording) return null;
    return DateTime.now().difference(_recordingStartTime!);
  }

  /// Constructor - registers for app lifecycle notifications
  AudioCaptureService() {
    WidgetsBinding.instance.addObserver(this);
    _logger.info('AudioCaptureService initialized');
  }

  /// Requests microphone permission from the user.
  ///
  /// Returns true if permission is granted, false otherwise.
  /// Throws [MicrophonePermissionDeniedException] if permission is denied.
  Future<bool> requestPermission() async {
    _logger.info('Requesting microphone permission...');
    
    final status = await Permission.microphone.request();
    
    if (status.isGranted) {
      _logger.info('Microphone permission granted');
      return true;
    } else if (status.isDenied) {
      _logger.warning('Microphone permission denied');
      throw MicrophonePermissionDeniedException(
        'Microphone permission is required to record audio. '
        'Please grant permission in app settings.'
      );
    } else if (status.isPermanentlyDenied) {
      _logger.warning('Microphone permission permanently denied');
      throw MicrophonePermissionDeniedException(
        'Microphone permission is permanently denied. '
        'Please enable it in system settings.'
      );
    }
    
    return false;
  }

  /// Checks if microphone permission is granted.
  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Starts recording audio.
  ///
  /// If recording is already in progress, this method does nothing and returns.
  /// Requests microphone permission if not already granted.
  ///
  /// Throws [MicrophonePermissionDeniedException] if permission is denied.
  Future<void> startRecording() async {
    // Prevent duplicate recording
    if (_isRecording) {
      _logger.warning('startRecording() called while already recording - ignoring');
      throw RecordingInProgressException();
    }

    _logger.info('Starting audio recording...');

    // Check/request permission
    final hasMicPermission = await hasPermission();
    if (!hasMicPermission) {
      await requestPermission();
    }

    // Check if recorder is available
    final isEncoderSupported = await _recorder.isEncoderSupported(AudioEncoder.wav);
    if (!isEncoderSupported) {
      _logger.severe('WAV encoder not supported on this device');
      throw Exception('WAV encoder not supported');
    }

    // Generate file path with timestamp
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'recording_$timestamp.wav';
    _currentRecordingPath = path.join(tempDir.path, fileName);

    _logger.info('Recording to file: $_currentRecordingPath');

    // Configure and start recording
    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,      // 16kHz for AI processing
      numChannels: 1,         // Mono
      bitRate: 256000,        // Appropriate for 16kHz mono PCM
      autoGain: true,         // Auto gain control for consistent levels
      echoCancel: true,       // Echo cancellation for cleaner audio
      noiseSuppress: true,    // Noise suppression
    );

    await _recorder.start(config, path: _currentRecordingPath!);
    
    _isRecording = true;
    _recordingStartTime = DateTime.now();
    
    _logger.info('Recording started successfully');
    _logger.info('  Sample Rate: 16000 Hz');
    _logger.info('  Channels: 1 (Mono)');
    _logger.info('  Format: WAV PCM 16-bit');
    _logger.info('  File: $_currentRecordingPath');

    // Start amplitude monitoring
    _startAmplitudeMonitoring();
  }

  /// Stops the current recording and returns the file path.
  ///
  /// Returns the path to the recorded WAV file, or null if no recording was active.
  /// Immediately releases the microphone.
  ///
  /// Throws [NoActiveRecordingException] if no recording is active.
  Future<String?> stopRecording() async {
    if (!_isRecording) {
      _logger.warning('stopRecording() called with no active recording');
      throw NoActiveRecordingException();
    }

    _logger.info('Stopping audio recording...');

    // Stop amplitude monitoring first
    _stopAmplitudeMonitoring();

    // Stop recording and release mic immediately
    await _recorder.stop();
    
    final duration = recordingDuration;
    _isRecording = false;
    
    _logger.info('Recording stopped successfully');
    _logger.info('  Duration: ${duration?.inSeconds}s ${duration?.inMilliseconds.remainder(1000)}ms');
    _logger.info('  File saved: $_currentRecordingPath');

    return _currentRecordingPath;
  }

  /// Cancels the current recording and deletes the temp file.
  ///
  /// This is useful when the user wants to discard the recording.
  /// Throws [NoActiveRecordingException] if no recording is active.
  Future<void> cancelRecording() async {
    if (!_isRecording) {
      _logger.warning('cancelRecording() called with no active recording');
      throw NoActiveRecordingException();
    }

    _logger.info('Cancelling audio recording...');

    // Stop amplitude monitoring
    _stopAmplitudeMonitoring();

    // Stop recording
    await _recorder.stop();
    
    // Delete the temp file
    if (_currentRecordingPath != null) {
      final file = File(_currentRecordingPath!);
      if (await file.exists()) {
        await file.delete();
        _logger.info('Deleted temp recording file: $_currentRecordingPath');
      }
    }

    _isRecording = false;
    _currentRecordingPath = null;
    _recordingStartTime = null;

    _logger.info('Recording cancelled and cleaned up');
  }

  /// Disposes the service and releases all resources.
  ///
  /// This should be called when the service is no longer needed.
  /// Automatically stops any active recording.
  Future<void> dispose() async {
    _logger.info('Disposing AudioCaptureService...');

    // Stop any active recording
    if (_isRecording) {
      await cancelRecording();
    }

    // Stop amplitude monitoring
    _stopAmplitudeMonitoring();

    // Close amplitude stream
    await _amplitudeController.close();

    // Dispose recorder
    await _recorder.dispose();

    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _logger.info('AudioCaptureService disposed');
  }

  /// Starts monitoring audio amplitude for waveform visualization.
  void _startAmplitudeMonitoring() {
    _logger.fine('Starting amplitude monitoring');
    
    _amplitudeTimer?.cancel();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      if (!_isRecording) {
        timer.cancel();
        return;
      }

      try {
        final amplitude = await _recorder.getAmplitude();
        // Convert dB to normalized value (0.0 to 1.0)
        // Typical range: -40dB (quiet) to 0dB (loud)
        final normalized = _normalizeAmplitude(amplitude.current);
        _amplitudeController.add(normalized);
      } catch (e) {
        _logger.warning('Error getting amplitude: $e');
      }
    });
  }

  /// Stops amplitude monitoring.
  void _stopAmplitudeMonitoring() {
    _logger.fine('Stopping amplitude monitoring');
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    // Send 0.0 to indicate silence
    if (!_amplitudeController.isClosed) {
      _amplitudeController.add(0.0);
    }
  }

  /// Normalizes amplitude from dB to 0.0-1.0 range.
  double _normalizeAmplitude(double db) {
    // Typical range: -40dB (quiet) to 0dB (max)
    const minDb = -40.0;
    const maxDb = 0.0;
    
    if (db <= minDb) return 0.0;
    if (db >= maxDb) return 1.0;
    
    return (db - minDb) / (maxDb - minDb);
  }

  /// Handles app lifecycle changes.
  /// 
  /// Automatically stops recording when app goes to background
  /// to ensure microphone is released and battery is conserved.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    _logger.fine('App lifecycle state changed: $state');
    
    // Auto-stop recording when app goes to background
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_isRecording) {
        _logger.warning('App went to background while recording - auto-stopping');
        stopRecording().catchError((e) {
          _logger.severe('Error auto-stopping recording: $e');
        });
      }
    }
    
    _lastLifecycleState = state;
  }
}
