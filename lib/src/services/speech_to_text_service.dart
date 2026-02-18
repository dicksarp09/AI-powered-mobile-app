import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import '../stt_backends/stt_backends.dart';

/// Exception thrown when STT model fails to load
class STTModelLoadException implements Exception {
  final String message;
  final String modelPath;
  STTModelLoadException(this.modelPath, [this.message = 'Failed to load STT model']);
  @override
  String toString() => 'STTModelLoadException: $message (model: $modelPath)';
}

/// Exception thrown when transcription fails
class STTTranscriptionException implements Exception {
  final String message;
  final String? audioPath;
  STTTranscriptionException(this.message, {this.audioPath});
  @override
  String toString() => 'STTTranscriptionException: $message ${audioPath != null ? '(audio: $audioPath)' : ''}';
}

/// Service responsible for converting audio to text using offline STT models.
///
/// This service uses a real STT backend (Whisper) and follows strict lifecycle management:
/// - Models are loaded ONLY when transcription is needed
/// - Models are unloaded IMMEDIATELY after transcription completes
/// - No model is kept resident in memory between calls
///
/// Supported modes:
/// - Batch mode (default): Process entire audio file at once
/// - Live mode: Stream audio chunks and get real-time partial transcripts
///
/// Example usage (Batch):
/// ```dart
/// final stt = SpeechToTextService();
/// final transcript = await stt.transcribeBatch(
///   audioFilePath: '/path/to/audio.wav',
///   modelPath: '/path/to/ggml-model.bin',
/// );
/// ```
///
/// Example usage (Live):
/// ```dart
/// final stt = SpeechToTextService();
/// final transcriptStream = stt.transcribeLive(
///   audioStream: audioCaptureStream,
///   modelPath: '/path/to/ggml-model.bin',
/// );
/// transcriptStream.listen((partial) => print(partial));
/// ```
class SpeechToTextService {
  static final Logger _logger = Logger('SpeechToTextService');
  
  // STT Backend instance - uses Whisper
  STTBackend? _backend;
  
  bool _isTranscribing = false;
  final _transcriptionController = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _audioSubscription;

  /// Whether a transcription is currently in progress
  bool get isTranscribing => _isTranscribing;

  /// Constructor
  SpeechToTextService() {
    _logger.info('SpeechToTextService initialized with Whisper backend');
  }

  /// Creates and returns the STT backend instance
  /// Override this for dependency injection in tests
  STTBackend _createBackend() {
    return WhisperSTTBackend();
  }

  /// Transcribes an audio file using the specified model.
  ///
  /// This method:
  /// 1. Loads the STT model from [modelPath]
  /// 2. Processes the entire audio file at [audioFilePath]
  /// 3. Returns the complete transcript
  /// 4. Immediately unloads the model from memory
  ///
  /// The model is always unloaded, even if transcription fails.
  ///
  /// Parameters:
  /// - [audioFilePath]: Path to the 16kHz mono WAV audio file
  /// - [modelPath]: Path to the STT model file (ggml format for Whisper)
  ///
  /// Returns the transcribed text.
  ///
  /// Throws:
  /// - [FileSystemException] if audio file doesn't exist
  /// - [STTModelLoadException] if model fails to load
  /// - [STTTranscriptionException] if transcription fails
  Future<String> transcribeBatch({
    required String audioFilePath,
    required String modelPath,
  }) async {
    _logger.info('Starting batch transcription');
    _logger.info('  Audio file: $audioFilePath');
    _logger.info('  Model: $modelPath');

    // Validate audio file exists
    final audioFile = File(audioFilePath);
    if (!await audioFile.exists()) {
      _logger.severe('Audio file not found: $audioFilePath');
      throw FileSystemException('Audio file not found', audioFilePath);
    }

    // Prevent concurrent transcriptions
    if (_isTranscribing) {
      _logger.warning('Transcription already in progress');
      throw STTTranscriptionException('Another transcription is in progress');
    }

    _isTranscribing = true;
    final stopwatch = Stopwatch()..start();

    try {
      // Create backend
      _backend = _createBackend();
      
      // Load model
      _logger.info('Loading STT model...');
      await _backend!.loadModel(modelPath);
      _logger.info('Model loaded successfully in ${stopwatch.elapsedMilliseconds}ms');

      // Perform transcription
      _logger.info('Starting transcription...');
      final result = await _backend!.transcribeFile(audioFilePath);
      
      stopwatch.stop();
      _logger.info('Transcription completed in ${stopwatch.elapsedMilliseconds}ms');
      _logger.info('Transcript length: ${result.text.length} characters');
      
      if (result.language != null) {
        _logger.info('Detected language: ${result.language}');
      }

      return result.text;
    } on FileSystemException {
      rethrow;
    } catch (e, stackTrace) {
      _logger.severe('Transcription failed: $e', e, stackTrace);
      throw STTTranscriptionException(
        'Transcription failed: $e',
        audioPath: audioFilePath,
      );
    } finally {
      // ALWAYS unload model and dispose backend, even on error
      _logger.info('Unloading STT model...');
      await _unloadModel();
      _isTranscribing = false;
      _logger.info('Model unloaded, transcription session complete');
    }
  }

  /// Transcribes audio from a stream using the specified model.
  ///
  /// This method:
  /// 1. Loads the STT model from [modelPath] once
  /// 2. Accepts streaming audio chunks
  /// 3. Emits partial transcripts via the returned stream
  /// 4. When the input stream closes, finalizes and unloads the model
  ///
  /// WARNING: Live mode is CPU-intensive. Only use when explicitly needed.
  ///
  /// Parameters:
  /// - [audioStream]: Stream of audio data chunks (PCM 16-bit recommended)
  /// - [modelPath]: Path to the STT model file (ggml format)
  ///
  /// Returns a stream of partial transcript strings.
  ///
  /// Throws:
  /// - [STTModelLoadException] if model fails to load
  /// - [STTTranscriptionException] if transcription fails
  Stream<String> transcribeLive({
    required Stream<List<int>> audioStream,
    required String modelPath,
  }) {
    _logger.info('Starting live transcription stream');
    _logger.info('  Model: $modelPath');
    _logger.warning('Live mode is CPU-intensive');

    final controller = StreamController<String>();
    bool isModelLoaded = false;
    final StringBuffer accumulatedTranscript = StringBuffer();

    controller.onListen = () async {
      try {
        // Create backend
        _backend = _createBackend();
        
        // Load model once for the entire stream
        _logger.info('Loading STT model for live transcription...');
        await _backend!.loadModel(modelPath);
        isModelLoaded = true;
        _logger.info('Model loaded for live transcription');

        // Subscribe to audio stream
        _audioSubscription = audioStream.listen(
          (audioChunk) async {
            try {
              // Process audio chunk and get partial transcript
              final partial = await _backend!.processAudioChunk(audioChunk);
              if (partial.isNotEmpty) {
                accumulatedTranscript.write(' ');
                accumulatedTranscript.write(partial);
                controller.add(partial);
                _logger.fine('Live partial: $partial');
              }
            } catch (e) {
              _logger.warning('Error processing audio chunk: $e');
            }
          },
          onError: (error) {
            _logger.severe('Audio stream error: $error');
            controller.addError(error);
          },
          onDone: () async {
            _logger.info('Audio stream closed, finalizing live transcription');
            
            // Finalize with any remaining audio
            if (_backend is WhisperSTTBackend) {
              final finalPartial = await (_backend as WhisperSTTBackend).finalizeLiveTranscription();
              if (finalPartial.isNotEmpty) {
                accumulatedTranscript.write(' ');
                accumulatedTranscript.write(finalPartial);
                controller.add(finalPartial);
              }
            }
            
            final finalTranscript = accumulatedTranscript.toString();
            _logger.info('Final transcript length: ${finalTranscript.length} characters');
            
            // Unload model when stream completes
            if (isModelLoaded) {
              await _unloadModel();
              _logger.info('Model unloaded after live transcription');
            }
            
            await controller.close();
          },
        );
      } catch (e, stackTrace) {
        _logger.severe('Failed to start live transcription: $e', e, stackTrace);
        
        // Cleanup on error
        if (isModelLoaded) {
          await _unloadModel();
        }
        
        controller.addError(STTTranscriptionException(
          'Failed to start live transcription: $e',
        ));
        await controller.close();
      }
    };

    controller.onCancel = () async {
      _logger.info('Live transcription cancelled by listener');
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      
      if (isModelLoaded) {
        await _unloadModel();
        _logger.info('Model unloaded after cancellation');
      }
    };

    return controller.stream;
  }

  /// Unloads the currently loaded STT model and disposes backend
  Future<void> _unloadModel() async {
    if (_backend == null) {
      _logger.fine('No model to unload');
      return;
    }

    try {
      await _backend!.unloadModel();
      await _backend!.dispose();
      _backend = null;
      _logger.info('Model and backend unloaded');
    } catch (e) {
      _logger.warning('Error unloading model: $e');
      _backend = null; // Force clear even on error
    }
  }

  /// Disposes the service and releases all resources.
  /// 
  /// This will cancel any active transcription and unload the model.
  Future<void> dispose() async {
    _logger.info('Disposing SpeechToTextService...');

    // Cancel any active audio subscription
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    // Unload model if loaded
    await _unloadModel();

    // Close transcription controller
    await _transcriptionController.close();

    _logger.info('SpeechToTextService disposed');
  }
}
