import 'dart:async';
import 'package:logging/logging.dart';
import '../models/models.dart';

/// Result from an SLM generation operation
class GenerationResult {
  /// The generated text
  final String text;
  
  /// Number of tokens generated
  final int? tokensGenerated;
  
  /// Generation duration in milliseconds
  final int? durationMs;
  
  /// Whether generation was stopped by a stop sequence
  final bool? stopped;

  const GenerationResult({
    required this.text,
    this.tokensGenerated,
    this.durationMs,
    this.stopped,
  });
}

/// Abstract interface for SLM (Small Language Model) backends
/// 
/// Implementations must handle:
/// - Model loading/unloading
/// - Text generation with configurable parameters
/// - Resource cleanup
abstract class SLMBackend {
  /// Whether the backend is currently initialized with a loaded model
  bool get isInitialized;
  
  /// Loads a quantized model from the specified path
  /// 
  /// [modelPath]: Path to the GGUF or similar quantized model file
  Future<void> loadModel(String modelPath);
  
  /// Unloads the current model and releases resources
  Future<void> unloadModel();
  
  /// Generates text based on the given prompt
  /// 
  /// [prompt]: The input prompt text
  /// [config]: Generation configuration parameters
  /// 
  /// Returns the generation result containing the output text
  Future<GenerationResult> generate(
    String prompt, {
    GenerationConfig config = const GenerationConfig(),
  });
  
  /// Generates text as a stream (for streaming responses)
  /// 
  /// [prompt]: The input prompt text
  /// [config]: Generation configuration parameters
  /// 
  /// Returns a stream of generated text chunks
  Stream<String> generateStream(
    String prompt, {
    GenerationConfig config = const GenerationConfig(),
  });
  
  /// Disposes the backend and releases all resources
  Future<void> dispose();
}
