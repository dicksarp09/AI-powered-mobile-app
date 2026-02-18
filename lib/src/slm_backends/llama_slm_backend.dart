import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:llama_flutter/llama_flutter.dart';
import '../models/models.dart';
import 'slm_backend.dart';

/// Llama.cpp backend implementation for SLM
/// 
/// This backend uses llama.cpp via llama_flutter for efficient on-device
/// text generation with quantized models (GGUF format).
/// 
/// Supports models like:
/// - Phi-3 Mini (Q4, Q8 quantized)
/// - Llama 3 8B (Q4 quantized)
/// - TinyLlama (Q4 quantized)
/// - Gemma 2B (Q4 quantized)
class LlamaSLMBackend implements SLMBackend {
  static final Logger _logger = Logger('LlamaSLMBackend');
  
  Llama? _llama;
  bool _isInitialized = false;
  String? _currentModelPath;

  @override
  bool get isInitialized => _isInitialized && _llama != null;

  /// Loads a GGUF model from the specified path
  /// 
  /// The model file should be in GGUF format (e.g., phi3-mini-Q4.gguf)
  @override
  Future<void> loadModel(String modelPath) async {
    _logger.info('Loading Llama model from: $modelPath');
    
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
      // Initialize Llama with model
      _llama = await Llama.create(
        modelPath: modelPath,
        // Context size - adjust based on model and device capability
        nCtx: 2048,
        // Batch size for processing
        nBatch: 512,
        // Use GPU if available (Metal on iOS, Vulkan on Android)
        nGpuLayers: 0, // Set to -1 for all layers on GPU if supported
      );
      
      _currentModelPath = modelPath;
      _isInitialized = true;
      
      _logger.info('Llama model loaded successfully');
      _logger.info('  Model path: $modelPath');
      _logger.info('  Model size: ${(await modelFile.length()) ~/ (1024 * 1024)} MB');
    } catch (e, stackTrace) {
      _logger.severe('Failed to load Llama model: $e', e, stackTrace);
      _isInitialized = false;
      _llama = null;
      rethrow;
    }
  }

  /// Unloads the current model and releases resources
  @override
  Future<void> unloadModel() async {
    _logger.info('Unloading Llama model...');
    
    if (_llama == null) {
      _logger.fine('No model to unload');
      return;
    }

    try {
      await _llama?.dispose();
      _llama = null;
      _isInitialized = false;
      _currentModelPath = null;
      _logger.info('Llama model unloaded');
    } catch (e) {
      _logger.warning('Error during model unload: $e');
      // Force cleanup even on error
      _llama = null;
      _isInitialized = false;
    }
  }

  /// Generates text based on the given prompt
  @override
  Future<GenerationResult> generate(
    String prompt, {
    GenerationConfig config = const GenerationConfig(),
  }) async {
    _logger.info('Generating text with Llama');
    _logger.fine('Prompt length: ${prompt.length} chars');
    _logger.fine('Config: $config');
    
    if (!_isInitialized || _llama == null) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Create sampling parameters
      final samplingParams = SamplingParams(
        temperature: config.temperature,
        topP: config.topP,
        topK: config.topK ?? 40,
        repeatPenalty: config.repetitionPenalty,
      );

      // Generate text
      final response = await _llama!.prompt(
        prompt,
        maxTokens: config.maxTokens,
        samplingParams: samplingParams,
      );

      stopwatch.stop();
      
      final text = response.text.trim();
      final tokens = response.tokens;
      
      _logger.info('Generation completed in ${stopwatch.elapsedMilliseconds}ms');
      _logger.info('Generated ${text.length} chars, ~${tokens?.length ?? '?'} tokens');

      return GenerationResult(
        text: text,
        tokensGenerated: tokens?.length,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e, stackTrace) {
      _logger.severe('Generation failed: $e', e, stackTrace);
      rethrow;
    }
  }

  /// Generates text as a stream for streaming responses
  @override
  Stream<String> generateStream(
    String prompt, {
    GenerationConfig config = const GenerationConfig(),
  }) {
    _logger.info('Starting streaming generation with Llama');
    
    if (!_isInitialized || _llama == null) {
      throw StateError('Model not loaded. Call loadModel() first.');
    }

    final controller = StreamController<String>();
    
    controller.onListen = () async {
      try {
        final samplingParams = SamplingParams(
          temperature: config.temperature,
          topP: config.topP,
          topK: config.topK ?? 40,
          repeatPenalty: config.repetitionPenalty,
        );

        final stream = _llama!.promptStream(
          prompt,
          maxTokens: config.maxTokens,
          samplingParams: samplingParams,
        );

        await for (final chunk in stream) {
          controller.add(chunk.text);
          
          // Check for stop sequences
          for (final stopSeq in config.stopSequences) {
            if (chunk.text.contains(stopSeq)) {
              controller.close();
              return;
            }
          }
        }
        
        await controller.close();
      } catch (e) {
        controller.addError(e);
        await controller.close();
      }
    };

    return controller.stream;
  }

  /// Disposes the backend and releases all resources
  @override
  Future<void> dispose() async {
    _logger.info('Disposing LlamaSLMBackend...');
    await unloadModel();
    _logger.info('LlamaSLMBackend disposed');
  }
}

/// Extension to provide sampling params (if not in llama_flutter)
extension on Llama {
  Stream<TokenResponse> promptStream(
    String prompt, {
    required int maxTokens,
    required SamplingParams samplingParams,
  }) async* {
    // This is a placeholder - actual implementation depends on llama_flutter API
    // Most llama.cpp Dart bindings provide streaming APIs
    
    // Fallback: generate and stream character by character
    final response = await this.prompt(
      prompt,
      maxTokens: maxTokens,
      samplingParams: samplingParams,
    );
    
    final text = response.text;
    for (int i = 0; i < text.length; i++) {
      yield TokenResponse(text: text[i]);
      await Future.delayed(Duration.zero);
    }
  }
}

/// Sampling parameters for text generation
class SamplingParams {
  final double temperature;
  final double topP;
  final int topK;
  final double repeatPenalty;

  SamplingParams({
    required this.temperature,
    required this.topP,
    required this.topK,
    required this.repeatPenalty,
  });
}

/// Token response from streaming generation
class TokenResponse {
  final String text;
  
  TokenResponse({required this.text});
}
