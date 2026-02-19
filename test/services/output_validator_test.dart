import 'package:flutter_test/flutter_test.dart';
import 'package:device_profiler/device_profiler.dart';

void main() {
  group('OutputValidator', () {
    late OutputValidator validator;
    
    setUp(() {
      validator = OutputValidator();
    });

    group('Valid JSON', () {
      test('should accept valid task JSON', () async {
        const json = '{"tasks":[{"title":"Test Task","due_time":null,"priority":"medium"}]}';
        
        final result = await validator.validateAndFallback(json, 'test transcript');
        
        expect(result['tasks'], isNotEmpty);
        expect(result['validated'], isTrue);
        expect(result['task_count'], equals(1));
      });

      test('should accept multiple tasks', () async {
        const json = '{"tasks":['
            '{"title":"Task 1","due_time":"tomorrow","priority":"high"},'
            '{"title":"Task 2","due_time":null,"priority":"low"}'
            ']}';
        
        final result = await validator.validateAndFallback(json, 'test');
        
        expect((result['tasks'] as List).length, equals(2));
      });

      test('should normalize priority to lowercase', () async {
        const json = '{"tasks":[{"title":"Test","priority":"HIGH"}]}';
        
        final result = await validator.validateAndFallback(json, 'test');
        final tasks = result['tasks'] as List;
        
        expect(tasks.first['priority'], equals('high'));
      });

      test('should default priority to medium if missing', () async {
        const json = '{"tasks":[{"title":"Test","due_time":null}]}';
        
        final result = await validator.validateAndFallback(json, 'test');
        final tasks = result['tasks'] as List;
        
        expect(tasks.first['priority'], equals('medium'));
      });
    });

    group('Invalid JSON Handling', () {
      test('should return fallback for malformed JSON', () async {
        const invalidJson = 'not valid json at all';
        const transcript = 'original transcript text';
        
        final result = await validator.validateAndFallback(invalidJson, transcript);
        
        expect(result['tasks'], isEmpty);
        expect(result['validated'], isFalse);
        expect(result['fallback_transcript'], equals(transcript));
        expect(result['fallback_reason'], isNotNull);
      });

      test('should return fallback for empty string', () async {
        final result = await validator.validateAndFallback('', 'transcript');
        
        expect(result['tasks'], isEmpty);
        expect(result['validated'], isFalse);
      });

      test('should return fallback for missing tasks key', () async {
        const json = '{"other_key":"value"}';
        
        final result = await validator.validateAndFallback(json, 'test');
        
        expect(result['tasks'], isEmpty);
        expect(result['validated'], isFalse);
      });

      test('should return fallback for non-array tasks', () async {
        const json = '{"tasks":"not an array"}';
        
        final result = await validator.validateAndFallback(json, 'test');
        
        expect(result['tasks'], isEmpty);
      });

      test('should return fallback for missing title', () async {
        const json = '{"tasks":[{"due_time":null,"priority":"medium"}]}';
        
        final result = await validator.validateAndFallback(json, 'test');
        
        expect(result['tasks'], isEmpty);
        expect(result['validated'], isFalse);
      });
    });

    group('Retry Logic', () {
      test('should retry once with callback if first attempt fails', () async {
        var retryCount = 0;
        final validatorWithRetry = OutputValidator(
          onRetry: (prompt) async {
            retryCount++;
            return '{"tasks":[{"title":"Retried Task","priority":"medium"}]}';
          },
        );
        
        const invalidJson = 'invalid json';
        
        final result = await validatorWithRetry.validateAndFallback(invalidJson, 'test');
        
        expect(retryCount, equals(1));
        expect(result['tasks'], isNotEmpty);
        expect(result['validated'], isTrue);
      });

      test('should return fallback if retry also fails', () async {
        final validatorWithRetry = OutputValidator(
          onRetry: (prompt) async {
            return 'still invalid';
          },
        );
        
        const invalidJson = 'invalid';
        
        final result = await validatorWithRetry.validateAndFallback(invalidJson, 'test');
        
        expect(result['tasks'], isEmpty);
        expect(result['validated'], isFalse);
      });

      test('should not retry if initial validation succeeds', () async {
        var retryCount = 0;
        final validatorWithRetry = OutputValidator(
          onRetry: (prompt) async {
            retryCount++;
            return '';
          },
        );
        
        const validJson = '{"tasks":[{"title":"Test","priority":"medium"}]}';
        
        await validatorWithRetry.validateAndFallback(validJson, 'test');
        
        expect(retryCount, equals(0));
      });
    });

    group('JSON Extraction', () {
      test('should extract JSON from surrounding text', () async {
        const messyJson = 'Here is the result: {\"tasks\":[{\"title\":\"Test\"}]} Hope that helps!';
        
        final result = await validator.validateAndFallback(messyJson, 'test');
        
        expect(result['tasks'], isNotEmpty);
      });

      test('should handle markdown code blocks', () async {
        const markdownJson = '```json\n{\"tasks\":[{\"title\":\"Test\"}]}\n```';
        
        final result = await validator.validateAndFallback(markdownJson, 'test');
        
        expect(result['tasks'], isNotEmpty);
      });
    });

    group('Statistics', () {
      test('should track validation failures', () async {
        // Reset stats
        OutputValidator.resetStatistics();
        
        // Cause a validation failure
        await validator.validateAndFallback('invalid', 'test');
        
        final stats = OutputValidator.getStatistics();
        expect(stats['total_validation_failures'], greaterThan(0));
      });

      test('should track fallback usage', () async {
        OutputValidator.resetStatistics();
        
        await validator.validateAndFallback('invalid', 'test');
        
        final stats = OutputValidator.getStatistics();
        expect(stats['total_fallbacks_used'], greaterThan(0));
      });
    });

    group('Edge Cases', () {
      test('should handle null due_time', () async {
        const json = '{"tasks":[{"title":"Test","due_time":null,"priority":"medium"}]}';
        
        final result = await validator.validateAndFallback(json, 'test');
        final tasks = result['tasks'] as List;
        
        expect(tasks.first['due_time'], isNull);
      });

      test('should handle string due_time', () async {
        const json = '{"tasks":[{"title":"Test","due_time":"tomorrow","priority":"medium"}]}';
        
        final result = await validator.validateAndFallback(json, 'test');
        final tasks = result['tasks'] as List;
        
        expect(tasks.first['due_time'], equals('tomorrow'));
      });

      test('should reject invalid priority values', () async {
        const json = '{"tasks":[{"title":"Test","priority":"invalid"}]}';
        
        final result = await validator.validateAndFallback(json, 'test');
        final tasks = result['tasks'] as List;
        
        expect(tasks.first['priority'], equals('medium')); // Defaults to medium
      });

      test('should handle empty tasks array', () async {
        const json = '{"tasks":[]}';
        
        final result = await validator.validateAndFallback(json, 'test');
        
        expect(result['tasks'], isEmpty);
        expect(result['validated'], isTrue); // Valid JSON, just no tasks
      });
    });
  });
}
