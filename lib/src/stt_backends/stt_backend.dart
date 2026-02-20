import 'dart:async';

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
