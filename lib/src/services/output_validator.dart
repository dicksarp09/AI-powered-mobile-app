import 'dart:convert';
import 'dart:developer' as developer;
import 'package:logging/logging.dart';

/// Exception thrown when output validation fails
class ValidationException implements Exception {
  final String message;
  final String? details;
  ValidationException(this.message, {this.details});
  @override
  String toString() => 'ValidationException: $message${details != null ? ' ($details)' : ''}';
}

/// Validates structured JSON output from SLM and provides safe fallbacks.
///
/// This layer ensures:
/// - JSON is valid and parseable
/// - Schema matches expected structure
/// - Graceful fallback on any failure
/// - App never crashes from invalid model output
///
/// Example usage:
/// ```dart
/// final validator = OutputValidator();
///
/// final safeOutput = await validator.validateAndFallback(
///   rawModelOutput: '{"tasks":[{"title":"Test","due_time":null,"priority":"medium"}]}',
///   originalTranscript: 'Remind me to test',
/// );
///
/// print(safeOutput); // Validated and safe to use
/// ```
///
/// Performance: Runs in <10ms for typical output.
class OutputValidator {
  static final Logger _logger = Logger('OutputValidator');
  
  /// Tracks validation failures for analytics/debugging
  static int _totalValidationFailures = 0;
  static int _totalRetryAttempts = 0;
  static int _totalFallbacksUsed = 0;
  
  /// Callback for retry attempt - should re-run SLM extraction
  /// Returns new model output string
  final Future<String> Function(String stricterPrompt)? onRetry;

  /// Creates an output validator with optional retry callback
  OutputValidator({this.onRetry});

  /// Validates raw model output and returns safe structured data.
  ///
  /// This method:
  /// 1. Attempts to parse JSON
  /// 2. Validates schema (tasks structure)
  /// 3. Retries once if invalid (if callback provided)
  /// 4. Returns fallback JSON if all else fails
  ///
  /// Never throws - always returns valid Map.
  Future<Map<String, dynamic>> validateAndFallback(
    String rawModelOutput,
    String originalTranscript,
  ) async {
    _logger.info('Starting output validation');
    _logger.fine('Raw output: ${rawModelOutput.substring(0, rawModelOutput.length.clamp(0, 100))}...');

    // Handle empty input
    if (rawModelOutput.trim().isEmpty) {
      _logger.warning('Empty model output received');
      return _createFallback(originalTranscript, reason: 'empty_input');
    }

    // Attempt 1: Validate original output
    var result = _attemptValidation(rawModelOutput);
    
    if (result.isValid) {
      _logger.info('Validation successful on first attempt');
      return result.data!;
    }

    _logger.warning('First validation failed: ${result.error}');
    _totalValidationFailures++;

    // Attempt 2: Retry with stricter prompt (if callback provided)
    if (onRetry != null) {
      _logger.info('Attempting retry with stricter prompt...');
      _totalRetryAttempts++;
      
      try {
        final stricterPrompt = _buildStricterPrompt(originalTranscript);
        final retryOutput = await onRetry!(stricterPrompt);
        
        result = _attemptValidation(retryOutput);
        
        if (result.isValid) {
          _logger.info('Validation successful on retry');
          return result.data!;
        }
        
        _logger.warning('Retry validation failed: ${result.error}');
      } catch (e) {
        _logger.severe('Retry callback failed: $e');
      }
    }

    // Fallback: Return safe default
    _logger.warning('All validation attempts failed, using fallback');
    _totalFallbacksUsed++;
    return _createFallback(originalTranscript, reason: result.error ?? 'validation_failed');
  }

  /// Attempts to validate the raw output.
  /// Returns validation result with data or error.
  _ValidationResult _attemptValidation(String rawOutput) {
    try {
      // Step 1: Extract JSON substring
      final jsonString = _extractJson(rawOutput);
      
      if (jsonString.isEmpty) {
        return _ValidationResult.invalid('no_json_found');
      }

      // Step 2: Parse JSON
      final dynamic parsed = jsonDecode(jsonString);
      
      if (parsed is! Map) {
        return _ValidationResult.invalid('root_not_object');
      }

      final Map<String, dynamic> data = Map<String, dynamic>.from(parsed);

      // Step 3: Validate schema
      final schemaResult = _validateSchema(data);
      if (!schemaResult.isValid) {
        return _ValidationResult.invalid(schemaResult.error!);
      }

      // Step 4: Normalize and clean data
      final normalizedData = _normalizeData(data);
      
      return _ValidationResult.valid(normalizedData);
    } on FormatException catch (e) {
      _logger.fine('JSON parse error: $e');
      return _ValidationResult.invalid('json_parse_error: ${e.message}');
    } catch (e) {
      _logger.fine('Unexpected validation error: $e');
      return _ValidationResult.invalid('unexpected_error: $e');
    }
  }

  /// Extracts JSON substring from text.
  String _extractJson(String text) {
    // Find first '{' and last '}'
    final startIndex = text.indexOf('{');
    final endIndex = text.lastIndexOf('}');
    
    if (startIndex == -1 || endIndex == -1 || startIndex >= endIndex) {
      return '';
    }

    return text.substring(startIndex, endIndex + 1);
  }

  /// Validates the JSON schema.
  _ValidationResult _validateSchema(Map<String, dynamic> data) {
    // Check 'tasks' key exists
    if (!data.containsKey('tasks')) {
      return _ValidationResult.invalid('missing_tasks_key');
    }

    final tasks = data['tasks'];
    
    // Check tasks is a list
    if (tasks is! List) {
      return _ValidationResult.invalid('tasks_not_list');
    }

    // Validate each task
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      
      if (task is! Map) {
        return _ValidationResult.invalid('task_$i:not_object');
      }

      final taskMap = Map<String, dynamic>.from(task);
      
      // Check required keys
      if (!taskMap.containsKey('title')) {
        return _ValidationResult.invalid('task_$i:missing_title');
      }
      
      if (taskMap['title'] is! String) {
        return _ValidationResult.invalid('task_$i:title_not_string');
      }

      // Validate due_time (optional, but must be string or null)
      if (taskMap.containsKey('due_time')) {
        final dueTime = taskMap['due_time'];
        if (dueTime != null && dueTime is! String) {
          return _ValidationResult.invalid('task_$i:due_time_invalid');
        }
      }

      // Validate priority
      if (taskMap.containsKey('priority')) {
        final priority = taskMap['priority']?.toString().toLowerCase();
        if (!['low', 'medium', 'high', null].contains(priority)) {
          return _ValidationResult.invalid('task_$i:invalid_priority');
        }
      }
    }

    return _ValidationResult.valid(data);
  }

  /// Normalizes and cleans validated data.
  Map<String, dynamic> _normalizeData(Map<String, dynamic> data) {
    final tasks = (data['tasks'] as List).map((task) {
      final taskMap = Map<String, dynamic>.from(task as Map);
      
      return {
        'title': (taskMap['title'] ?? '').toString().trim(),
        'due_time': taskMap['due_time'],
        'priority': _normalizePriority(taskMap['priority']),
      };
    }).toList();

    return {
      'tasks': tasks,
      'validated': true,
      'task_count': tasks.length,
    };
  }

  /// Normalizes priority value.
  String _normalizePriority(dynamic priority) {
    if (priority == null) return 'medium';
    
    final normalized = priority.toString().toLowerCase();
    if (['low', 'medium', 'high'].contains(normalized)) {
      return normalized;
    }
    
    return 'medium';
  }

  /// Builds stricter prompt for retry.
  String _buildStricterPrompt(String originalTranscript) {
    return '''You are an information extraction engine.

Extract actionable tasks from the text below.

CRITICAL RULES:
- Return ONLY valid JSON.
- NO explanations.
- NO markdown.
- NO backticks.
- MUST be valid JSON format: {"tasks":[{"title":"...","due_time":"...","priority":"..."}]}
- due_time can be null.
- priority MUST be: low, medium, or high.

Text:
$originalTranscript

JSON ONLY:'''
;
  }

  /// Creates fallback response with original transcript preserved.
  Map<String, dynamic> _createFallback(
    String originalTranscript, {
    required String reason,
  }) {
    _logger.info('Creating fallback response (reason: $reason)');
    
    return {
      'tasks': <dynamic>[],
      'fallback_transcript': originalTranscript,
      'fallback_reason': reason,
      'validated': false,
      'task_count': 0,
    };
  }

  /// Gets validation statistics for analytics.
  static Map<String, int> getStatistics() {
    return {
      'total_validation_failures': _totalValidationFailures,
      'total_retry_attempts': _totalRetryAttempts,
      'total_fallbacks_used': _totalFallbacksUsed,
    };
  }

  /// Resets validation statistics.
  static void resetStatistics() {
    _totalValidationFailures = 0;
    _totalRetryAttempts = 0;
    _totalFallbacksUsed = 0;
  }
}

/// Internal validation result class
class _ValidationResult {
  final bool isValid;
  final Map<String, dynamic>? data;
  final String? error;

  _ValidationResult._({required this.isValid, this.data, this.error});

  factory _ValidationResult.valid(Map<String, dynamic> data) {
    return _ValidationResult._(isValid: true, data: data);
  }

  factory _ValidationResult.invalid(String error) {
    return _ValidationResult._(isValid: false, error: error);
  }
}
