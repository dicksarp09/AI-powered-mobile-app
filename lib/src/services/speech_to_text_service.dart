import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';

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

/// Represents a loaded STT model instance
/// 
/// This is an internal class that manages the model lifecycle.
/// The actual implementation depends on the STT backend being used
/// (whisper.cpp, ONNX Runtime, etc.)
class _STTModel {
  final String modelPath;
  final DateTime loadedAt;
  bool _isDisposed = false;
  
  // Internal model reference - actual type depends on backend
  // For whisper.cpp: WhisperContext
  // For ONNX: OrtSession
  dynamic _nativeModel;

  _STTModel(this.modelPath, this._nativeModel) : loadedAt = DateTime.now();

  bool get isDisposed => _isDisposed;
  dynamic get nativeModel => _nativeModel;

  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    
    // Backend-specific cleanup
    // For whisper.cpp: whisper_free(context)
    // For ONNX: session.release()
    _nativeModel = null;
  }
}

/// Service responsible for converting audio to text using offline STT models.
///
/// This service follows strict lifecycle management:
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
///   modelPath: '/path/to/model.bin',
/// );
/// ```
///
/// Example usage (Live):
/// ```dart
/// final stt = SpeechToTextService();
/// final transcriptStream = stt.transcribeLive(
///   audioStream: audioCaptureStream,
///   modelPath: '/path/to/model.bin',
/// );
/// transcriptStream.listen((partial) => print(partial));
/// ```
class SpeechToTextService {
  static final Logger _logger = Logger('SpeechToTextService');
  
  _STTModel? _currentModel;
  bool _isTranscribing = false;
  final _transcriptionController = StreamController<String>.broadcast();
  StreamSubscription<List<int>>? _audioSubscription;

  /// Whether a transcription is currently in progress
  bool get isTranscribing => _isTranscribing;

  /// Constructor
  SpeechToTextService() {
    _logger.info('SpeechToTextService initialized');
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
  /// - [modelPath]: Path to the STT model file (e.g., .bin for whisper.cpp)
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
      _logger.warning('Transcription already in progress, waiting...');
      throw STTTranscriptionException('Another transcription is in progress');
    }

    _isTranscribing = true;
    final stopwatch = Stopwatch()..start();

    try {
      // Load model
      _logger.info('Loading STT model...');
      await _loadModel(modelPath);
      _logger.info('Model loaded successfully in ${stopwatch.elapsedMilliseconds}ms');

      // Perform transcription
      _logger.info('Starting transcription...');
      final transcript = await _performBatchTranscription(audioFilePath);
      
      stopwatch.stop();
      _logger.info('Transcription completed in ${stopwatch.elapsedMilliseconds}ms');
      _logger.info('Transcript length: ${transcript.length} characters');

      return transcript;
    } catch (e, stackTrace) {
      _logger.severe('Transcription failed: $e', e, stackTrace);
      throw STTTranscriptionException(
        'Transcription failed: $e',
        audioPath: audioFilePath,
      );
    } finally {
      // ALWAYS unload model, even on error
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
  /// - [modelPath]: Path to the STT model file
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
        // Load model once for the entire stream
        _logger.info('Loading STT model for live transcription...');
        await _loadModel(modelPath);
        isModelLoaded = true;
        _logger.info('Model loaded for live transcription');

        // Subscribe to audio stream
        _audioSubscription = audioStream.listen(
          (audioChunk) async {
            try {
              // Process audio chunk and get partial transcript
              final partial = await _processAudioChunk(audioChunk);
              if (partial.isNotEmpty) {
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

  /// Loads the STT model from the specified path.
  /// 
  /// This is an internal method that handles the actual model loading
  /// based on the STT backend being used.
  Future<void> _loadModel(String modelPath) async {
    // Check if model file exists
    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      throw STTModelLoadException(modelPath, 'Model file not found');
    }

    // Ensure any previous model is unloaded
    if (_currentModel != null) {
      _logger.warning('Previous model still loaded, unloading first');
      await _unloadModel();
    }

    try {
      // Backend-specific model loading
      // TODO: Replace with actual implementation based on your STT backend
      
      // Example for whisper.cpp:
      // final context = await WhisperContext.createContext(modelPath: modelPath);
      // _currentModel = _STTModel(modelPath, context);
      
      // Example for ONNX Runtime:
      // final session = OrtSession.fromFile(modelFile);
      // _currentModel = _STTModel(modelPath, session);
      
      // Placeholder implementation
      _logger.info('Loading model from: $modelPath');
      await Future.delayed(const Duration(milliseconds: 100)); // Simulate loading
      _currentModel = _STTModel(modelPath, null);
      
      _logger.info('Model loaded successfully: $modelPath');
    } catch (e) {
      throw STTModelLoadException(modelPath, 'Failed to load: $e');
    }
  }

  /// Unloads the currently loaded STT model.
  Future<void> _unloadModel() async {
    if (_currentModel == null) {
      _logger.fine('No model to unload');
      return;
    }

    try {
      final modelPath = _currentModel!.modelPath;
      await _currentModel!.dispose();
      _currentModel = null;
      _logger.info('Model unloaded: $modelPath');
    } catch (e) {
      _logger.warning('Error unloading model: $e');
      _currentModel = null; // Force clear even on error
    }
  }

  /// Performs batch transcription on an audio file.
  /// 
  /// This is the internal implementation that uses the loaded model.
  Future<String> _performBatchTranscription(String audioFilePath) async {
    if (_currentModel == null || _currentModel!.isDisposed) {
      throw STTTranscriptionException('Model not loaded');
    }

    // Backend-specific transcription
    // TODO: Replace with actual implementation based on your STT backend
    
    // Example for whisper.cpp:
    // final result = await _currentModel!.nativeModel.transcribe(
    //   audioPath: audioFilePath,
    //   language: 'en',
    // );
    // return result.text;
    
    // Placeholder implementation
    _logger.info('Transcribing audio file: $audioFilePath');
    await Future.delayed(const Duration(seconds: 1)); // Simulate transcription
    
    // Return a placeholder transcript
    // In real implementation, this would be the actual transcription result
    return 'This is a placeholder transcript. Replace with actual STT backend integration.';
  }

  /// Processes a single audio chunk for live transcription.
  /// 
  /// Returns partial transcript text for this chunk.
  Future<String> _processAudioChunk(List<int> audioChunk) async {
    if (_currentModel == null || _currentModel!.isDisposed) {
      return '';
    }

    // Backend-specific chunk processing
    // TODO: Replace with actual implementation
    
    // Accumulate chunks and process when enough data is available
    // Return partial transcript
    
    return ''; // Placeholder
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
