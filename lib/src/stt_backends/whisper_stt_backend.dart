import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'package:whisper_flutter/whisper_flutter.dart';

/// Result from a transcription operation
class TranscriptionResult {
  /// The transcribed text
  final String text;
  
  /// Confidence score (0.0 to 1.0) if available
  final double? confidence;
  
  /// Duration of the audio in seconds
  final double? duration;
  
  /// Language detected (ISO code)
  final String? language;
  
  /// Segments with timestamps (optional)
  final List<TranscriptionSegment>? segments;

  const TranscriptionResult({
    required this.text,
    this.confidence,
    this.duration,
    this.language,
    this.segments,
  });
}

/// A segment of transcribed text with timing information
class TranscriptionSegment {
  /// Start time in seconds
  final double start;
  
  /// End time in seconds
  final double end;
  
  /// Transcribed text for this segment
  final String text;
  
  /// Confidence for this segment
  final double? confidence;

  const TranscriptionSegment({
    required this.start,
    required this.end,
    required this.text,
    this.confidence,
  });
}

/// Abstract interface for STT backends
abstract class STTBackend {
  /// Whether the backend is currently initialized with a loaded model
  bool get isInitialized;
  
  /// Loads a model from the specified path
  Future<void> loadModel(String modelPath);
  
  /// Unloads the current model and releases resources
  Future<void> unloadModel();
  
  /// Transcribes an audio file and returns the result
  Future<TranscriptionResult> transcribeFile(String audioFilePath);
  
  /// Processes audio chunks for live transcription
  /// Returns partial transcript text
  Future<String> processAudioChunk(List<int> audioChunk);
  
  /// Disposes the backend and releases all resources
  Future<void> dispose();
}

/// Whisper.cpp backend implementation using whisper_flutter
/// 
/// This backend uses the whisper.cpp library for efficient on-device
/// speech recognition. It supports:
/// - Loading quantized models (ggml format)
/// - Batch transcription of audio files
/// - Streaming/live transcription (experimental)
class WhisperSTTBackend implements STTBackend {
  static final Logger _logger = Logger('WhisperSTTBackend');
  
  Whisper? _whisper;
  bool _isInitialized = false;
  String? _currentModelPath;
  
  // Audio buffer for live transcription
  final BytesBuilder _liveAudioBuffer = BytesBuilder();
  DateTime? _lastChunkTime;
  
  // Configuration
  static const int _sampleRate = 16000;
  static const int _liveChunkDurationMs = 1000; // Process every 1 second

  @override
  bool get isInitialized => _isInitialized && _whisper != null;

  /// Loads a Whisper model from the specified path
  /// 
  /// The model file should be in ggml format (e.g., ggml-tiny.bin, ggml-base.bin)
  @override
  Future<void> loadModel(String modelPath) async {
    _logger.info('Loading Whisper model from: $modelPath');
    
    if (_isInitialized) {
      _logger.warning('Model already loaded, unloading first');
      await unloadModel();
    }

    // Verify model file exists
    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      throw FileSystemException('Model file not found', modelPath);
    }

    try {
      // Initialize Whisper
      _whisper = Whisper(
        modelPath: modelPath,
        useGpu: false, // Use CPU for broader compatibility
      );
      
      _currentModelPath = modelPath;
      _isInitialized = true;
      
      _logger.info('Whisper model loaded successfully');
      _logger.info('  Model path: $modelPath');
      _logger.info('  Model size: ${(await modelFile.length()) ~/ (1024 * 1024)} MB');
    } catch (e, stackTrace) {
      _logger.severe('Failed to load Whisper model: $e', e, stackTrace);
      _isInitialized = false;
      _whisper = null;
      rethrow;
    }
  }

  /// Unloads the current model and releases resources
  @override
  Future<void> unloadModel() async {
    _logger.info('Unloading Whisper model...');
    
    if (_whisper == null) {
      _logger.fine('No model to unload');
      return;
    }

    try {
      // Clear live buffer
      _liveAudioBuffer.clear();
      
      // Whisper doesn't require explicit cleanup, just dereference
      _whisper = null;
      _isInitialized = false;
      _currentModelPath = null;
      
      _logger.info('Whisper model unloaded');
    } catch (e) {
      _logger.warning('Error during model unload: $e');
      // Force cleanup even on error
      _whisper = null;
      _isInitialized = false;
    }
  }

  /// Transcribes an audio file and returns the full transcript
  /// 
  /// Supports WAV files with 16kHz sample rate, mono, 16-bit PCM
  @override
  Future<TranscriptionResult> transcribeFile(String audioFilePath) async {
    _logger.info('Transcribing audio file: $audioFilePath');
    
    if (!_isInitialized || _whisper == null) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }

    // Verify audio file exists
    final audioFile = File(audioFilePath);
    if (!await audioFile.exists()) {
      throw FileSystemException('Audio file not found', audioFilePath);
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Read audio file as bytes
      final audioBytes = await audioFile.readAsBytes();
      _logger.fine('Audio file loaded: ${audioBytes.length} bytes');

      // Transcribe using Whisper
      final result = await _whisper!.transcribe(
        audio: audioBytes,
        language: 'auto', // Auto-detect language
        splitOnWord: true,
        speedUp: false, // Keep quality high
      );

      stopwatch.stop();
      
      _logger.info('Transcription completed in ${stopwatch.elapsedMilliseconds}ms');
      _logger.info('Transcript: ${result.text.substring(0, result.text.length.clamp(0, 100))}...');

      return TranscriptionResult(
        text: result.text.trim(),
        language: result.language,
        duration: stopwatch.elapsedMilliseconds / 1000.0,
      );
    } catch (e, stackTrace) {
      _logger.severe('Transcription failed: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Processes audio chunks for live/real-time transcription
  /// 
  /// Accumulates audio chunks and processes them when enough data
  /// is collected (every ~1 second of audio)
  @override
  Future<String> processAudioChunk(List<int> audioChunk) async {
    if (!_isInitialized || _whisper == null) {
      return '';
    }

    // Add chunk to buffer
    _liveAudioBuffer.add(audioChunk);
    _lastChunkTime = DateTime.now();

    // Check if we have enough audio to process (1 second at 16kHz, 16-bit = 32000 bytes)
    const bytesPerSecond = _sampleRate * 2; // 16-bit = 2 bytes per sample
    if (_liveAudioBuffer.length < bytesPerSecond) {
      return ''; // Not enough data yet
    }

    try {
      // Get accumulated audio
      final audioData = _liveAudioBuffer.toBytes();
      
      // Process only the most recent 3 seconds to keep latency low
      final recentBytes = audioData.length > bytesPerSecond * 3
          ? audioData.sublist(audioData.length - bytesPerSecond * 3)
          : audioData;

      _logger.fine('Processing live audio chunk: ${recentBytes.length} bytes');

      // Transcribe
      final result = await _whisper!.transcribe(
        audio: recentBytes,
        language: 'auto',
        speedUp: true, // Speed up for lower latency
      );

      // Clear buffer after processing (for sliding window, keep last 0.5s)
      final keepBytes = bytesPerSecond ~/ 2;
      if (_liveAudioBuffer.length > keepBytes) {
        final allBytes = _liveAudioBuffer.toBytes();
        _liveAudioBuffer.clear();
        if (allBytes.length > keepBytes) {
          _liveAudioBuffer.add(allBytes.sublist(allBytes.length - keepBytes));
        }
      }

      return result.text.trim();
    } catch (e) {
      _logger.warning('Live transcription chunk failed: $e');
      return '';
    }
  }

  /// Finalizes live transcription with remaining audio buffer
  Future<String> finalizeLiveTranscription() async {
    if (!_isInitialized || _whisper == null || _liveAudioBuffer.isEmpty) {
      return '';
    }

    try {
      final audioData = _liveAudioBuffer.toBytes();
      _logger.fine('Finalizing live transcription with ${audioData.length} bytes');

      final result = await _whisper!.transcribe(
        audio: audioData,
        language: 'auto',
        speedUp: false, // Quality over speed for final
      );

      _liveAudioBuffer.clear();
      return result.text.trim();
    } catch (e) {
      _logger.warning('Final live transcription failed: $e');
      return '';
    }
  }

  /// Disposes the backend and releases all resources
  @override
  Future<void> dispose() async {
    _logger.info('Disposing WhisperSTTBackend...');
    await unloadModel();
    _liveAudioBuffer.clear();
    _logger.info('WhisperSTTBackend disposed');
  }
}
