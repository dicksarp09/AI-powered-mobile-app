import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'package:logging/logging.dart';
import '../models/models.dart';
import '../slm_backends/slm_backends.dart';

/// Exception thrown when SLM extraction fails
class SlmExtractionException implements Exception {
  final String message;
  final String? transcript;
  SlmExtractionException(this.message, {this.transcript});
  @override
  String toString() => 'SlmExtractionException: $message';
}

/// Extracts structured actions from cleaned transcript text using an SLM.
/// 
/// This class follows strict guidelines:
/// - Loads quantized SLM only when needed
/// - Injects strict prompt template
/// - Forces JSON-only output
/// - Validates schema
/// - Unloads model immediately after generation
/// 
/// Expected output format:
/// ```json
/// {
///   "tasks": [
///     {
///       "title": "string",
///       "due_time": "string|null",
///       "priority": "low|medium|high"
///     }
///   ]
/// }
/// ```
/// 
/// Usage:
/// ```dart
/// final extractor = SlmActionExtractor(
///   modelPath: '/path/to/model.gguf',
/// );
/// 
/// final result = await extractor.extract(
///   'Remind me to call John tomorrow at 3pm, it's urgent',
/// );
/// 
/// print(result); // { "tasks": [{ "title": "Call John", "due_time": "tomorrow at 3pm", "priority": "high" }] }
/// ```
class SlmActionExtractor {
  static final Logger _logger = Logger('SlmActionExtractor');
  
  final String modelPath;
  final GenerationConfig config;
  final SLMBackend? _backendOverride;
  
  SLMBackend? _backend;
  bool _isProcessing = false;

  /// Creates an action extractor with the specified model and config
  /// 
  /// [modelPath]: Path to the quantized GGUF model file
  /// [config]: Generation configuration (defaults to JSON extraction settings)
  /// [_backendOverride]: Optional backend for dependency injection (testing)
  SlmActionExtractor({
    required this.modelPath,
    this.config = GenerationConfig.jsonExtraction,
    SLMBackend? backend,
  }) : _backendOverride = backend {
    _logger.info('SlmActionExtractor created');
    _logger.info('  Model: $modelPath');
    _logger.info('  Config: $config');
  }

  /// Creates the SLM backend instance
  /// Override this for dependency injection in tests
  SLMBackend _createBackend() {
    return _backendOverride ?? LlamaSLMBackend();
  }

  /// Extracts structured actions from the cleaned transcript.
  /// 
  /// Returns a Map with the schema:
  /// ```dart
  /// {
  ///   "tasks": [
  ///     {
  ///       "title": "string",
  ///       "due_time": "string?",
  ///       "priority": "low|medium|high"
  ///     }
  ///   ]
  /// }
  /// ```
  /// 
  /// If extraction fails or no tasks are found, returns `{"tasks": []}`.
  /// This method never throws - all errors are caught and return safe defaults.
  Future<Map<String, dynamic>> extract(String cleanedTranscript) async {
    _logger.info('Starting action extraction');
    _logger.fine('Transcript: $cleanedTranscript');

    // Validate input
    if (cleanedTranscript.trim().isEmpty) {
      _logger.warning('Empty transcript provided, returning empty tasks');
      return _emptyResult();
    }

    // Prevent concurrent extractions
    if (_isProcessing) {
      _logger.warning('Extraction already in progress');
      return _emptyResult();
    }

    _isProcessing = true;

    try {
      // Create backend and load model
      _backend = _createBackend();
      
      _logger.info('Loading SLM model...');
      await _backend!.loadModel(modelPath);
      _logger.info('Model loaded successfully');

      // Generate extraction
      final result = await _generateExtraction(cleanedTranscript);
      
      // Validate and parse
      final parsed = _validateAndParse(result.text);
      
      _logger.info('Extraction completed successfully');
      _logger.info('  Tasks found: ${(parsed["tasks"] as List).length}');
      
      return parsed;
    } catch (e, stackTrace) {
      _logger.severe('Extraction failed: $e', e, stackTrace);
      return _emptyResult();
    } finally {
      // ALWAYS unload model
      _logger.info('Unloading SLM model...');
      await _unloadModel();
      _isProcessing = false;
      _logger.info('Extraction session complete');
    }
  }

  /// Generates extraction using the SLM with retry logic
  Future<GenerationResult> _generateExtraction(String transcript) async {
    final prompt = _buildPrompt(transcript);
    
    _logger.fine('Generation prompt:\n$prompt');

    // First attempt
    var result = await _backend!.generate(prompt, config: config);
    
    _logger.fine('First generation result:\n${result.text}');

    // Validate JSON
    if (!_isValidJson(result.text)) {
      _logger.warning('First attempt returned invalid JSON, retrying once...');
      
      // Retry with reminder
      final retryPrompt = '$prompt\n\nReminder: Output valid JSON only.\nJSON:';
      result = await _backend!.generate(retryPrompt, config: config);
      
      _logger.fine('Retry generation result:\n${result.text}');
    }

    return result;
  }

  /// Builds the strict prompt template with the transcript
  String _buildPrompt(String transcript) {
    return '''You are an information extraction engine.

Extract actionable tasks from the text below.

Rules:
- Output ONLY valid JSON.
- Do NOT include explanations.
- Do NOT include markdown.
- Do NOT include backticks.
- If no tasks exist, return: {"tasks":[]}
- All keys must exist.
- due_time must be null if not specified.
- priority must be one of: low, medium, high.
- No trailing text after closing brace.

Text:
$transcript

JSON:'''
;
  }

  /// Validates and parses the generated JSON
  Map<String, dynamic> _validateAndParse(String generatedText) {
    try {
      // Extract JSON between first { and last }
      final jsonString = _extractJson(generatedText);
      
      if (jsonString.isEmpty) {
        _logger.warning('No JSON found in generated text');
        return _emptyResult();
      }

      // Parse JSON
      final parsed = jsonDecode(jsonString) as Map<String, dynamic>;
      
      // Validate schema
      if (!_validateSchema(parsed)) {
        _logger.warning('JSON schema validation failed');
        return _emptyResult();
      }

      // Clean and normalize tasks
      final tasks = (parsed['tasks'] as List).map((task) {
        return {
          'title': (task['title'] ?? '').toString(),
          'due_time': task['due_time'],
          'priority': _normalizePriority(task['priority']),
        };
      }).toList();

      return {'tasks': tasks};
    } catch (e) {
      _logger.warning('JSON parsing failed: $e');
      return _emptyResult();
    }
  }

  /// Extracts JSON substring from text
  String _extractJson(String text) {
    final startIndex = text.indexOf('{');
    final endIndex = text.lastIndexOf('}');
    
    if (startIndex == -1 || endIndex == -1 || startIndex >= endIndex) {
      return '';
    }

    return text.substring(startIndex, endIndex + 1);
  }

  /// Checks if text contains valid JSON structure
  bool _isValidJson(String text) {
    final jsonStr = _extractJson(text);
    if (jsonStr.isEmpty) return false;
    
    try {
      jsonDecode(jsonStr);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Validates the JSON schema
  bool _validateSchema(Map<String, dynamic> json) {
    // Check 'tasks' key exists
    if (!json.containsKey('tasks')) {
      _logger.warning('Schema validation failed: missing "tasks" key');
      return false;
    }

    final tasks = json['tasks'];
    
    // Check tasks is a list
    if (tasks is! List) {
      _logger.warning('Schema validation failed: "tasks" is not a list');
      return false;
    }

    // Validate each task
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      
      if (task is! Map) {
        _logger.warning('Schema validation failed: task $i is not an object');
        return false;
      }

      final taskMap = task as Map<String, dynamic>;
      
      // Check required keys
      if (!taskMap.containsKey('title')) {
        _logger.warning('Schema validation failed: task $i missing "title"');
        return false;
      }

      // Validate priority if present
      if (taskMap.containsKey('priority')) {
        final priority = taskMap['priority']?.toString().toLowerCase();
        if (!['low', 'medium', 'high', null].contains(priority)) {
          _logger.warning('Schema validation failed: task $i has invalid priority');
          return false;
        }
      }
    }

    return true;
  }

  /// Normalizes priority value
  String _normalizePriority(dynamic priority) {
    if (priority == null) return 'medium';
    
    final normalized = priority.toString().toLowerCase();
    if (['low', 'medium', 'high'].contains(normalized)) {
      return normalized;
    }
    
    // Try to infer from keywords
    final priorityStr = normalized.toString();
    if (priorityStr.contains('urgent') || 
        priorityStr.contains('asap') || 
        priorityStr.contains('important')) {
      return 'high';
    }
    
    return 'medium';
  }

  /// Returns empty result structure
  Map<String, dynamic> _emptyResult() {
    return {'tasks': <dynamic>[]};  
  }

  /// Unloads the SLM model
  Future<void> _unloadModel() async {
    if (_backend == null) return;
    
    try {
      await _backend!.unloadModel();
      await _backend!.dispose();
      _backend = null;
      _logger.info('Model unloaded');
    } catch (e) {
      _logger.warning('Error unloading model: $e');
      _backend = null;
    }
  }

  /// Disposes the extractor and releases resources
  Future<void> dispose() async {
    _logger.info('Disposing SlmActionExtractor...');
    await _unloadModel();
    _logger.info('SlmActionExtractor disposed');
  }
}
