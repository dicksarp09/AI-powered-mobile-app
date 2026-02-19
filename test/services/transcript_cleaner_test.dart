import 'package:flutter_test/flutter_test.dart';
import 'package:device_profiler/device_profiler.dart';

void main() {
  group('TranscriptCleaner', () {
    late TranscriptCleaner cleaner;
    
    setUp(() {
      cleaner = TranscriptCleaner();
    });

    group('Basic Cleaning', () {
      test('should trim whitespace', () {
        const input = '  hello world  ';
        final result = cleaner.clean(input);
        expect(result, equals('Hello world.'));
      });

      test('should normalize multiple spaces', () {
        const input = 'hello    world   test';
        final result = cleaner.clean(input);
        expect(result, equals('Hello world test.'));
      });
    });

    group('Filler Word Removal', () {
      test('should remove "um"', () {
        const input = 'Um, remind me to call John';
        final result = cleaner.clean(input);
        expect(result, isNot(contains('um')));
        expect(result, contains('Remind me to call John'));
      });

      test('should remove "uh"', () {
        const input = 'Uh, I need to uh buy milk';
        final result = cleaner.clean(input);
        expect(result, isNot(contains('uh')));
      });

      test('should remove "like"', () {
        const input = 'I like need to like go shopping';
        final result = cleaner.clean(input);
        expect(result, isNot(contains('like')));
      });

      test('should remove "you know"', () {
        const input = 'You know, I need to you know call mom';
        final result = cleaner.clean(input);
        expect(result, isNot(contains('you know')));
      });

      test('should not remove "like" from "likely"', () {
        const input = 'I will likely call tomorrow';
        final result = cleaner.clean(input);
        expect(result, contains('likely'));
      });
    });

    group('Time Normalization', () {
      test('should normalize "3 pm" to "3pm"', () {
        const input = 'Meet at 3 pm tomorrow';
        final result = cleaner.clean(input);
        expect(result, contains('3pm'));
        expect(result, isNot(contains('3 pm')));
      });

      test('should normalize "3 p.m." to "3pm"', () {
        const input = 'Meet at 3 p.m. tomorrow';
        final result = cleaner.clean(input);
        expect(result, contains('3pm'));
      });

      test('should normalize "5 am" to "5am"', () {
        const input = 'Wake up at 5 am';
        final result = cleaner.clean(input);
        expect(result, contains('5am'));
      });

      test('should normalize "15 00" to "15:00"', () {
        const input = 'Meeting at 15 00';
        final result = cleaner.clean(input);
        expect(result, contains('15:00'));
      });
    });

    group('Duplicate Removal', () {
      test('should remove consecutive duplicates', () {
        const input = 'Buy buy milk today';
        final result = cleaner.clean(input);
        expect(result, equals('Buy milk today.'));
      });

      test('should remove triple duplicates', () {
        const input = 'Call call call John';
        final result = cleaner.clean(input);
        expect(result, equals('Call John.'));
      });
    });

    group('Punctuation', () {
      test('should capitalize first letter', () {
        const input = 'remind me to call john';
        final result = cleaner.clean(input);
        expect(result.startsWith('R'), isTrue);
      });

      test('should add period if missing', () {
        const input = 'Call John tomorrow';
        final result = cleaner.clean(input);
        expect(result.endsWith('.'), isTrue);
      });

      test('should not add period if already present', () {
        const input = 'Call John tomorrow.';
        final result = cleaner.clean(input);
        expect(result.endsWith('..'), isFalse);
      });
    });

    group('Edge Cases', () {
      test('should handle empty string', () {
        final result = cleaner.clean('');
        expect(result, equals(''));
      });

      test('should handle only fillers', () {
        const input = 'um uh like you know';
        final result = cleaner.clean(input);
        expect(result.isEmpty || result == '.', isTrue);
      });

      test('should handle complex input', () {
        const input = 'Um, I need to uh, like, call John tomorrow at 3 pm, you know?';
        final result = cleaner.clean(input);
        
        expect(result, isNot(contains('um')));
        expect(result, isNot(contains('uh')));
        expect(result, isNot(contains('like')));
        expect(result, isNot(contains('you know')));
        expect(result, contains('3pm'));
        expect(result.startsWith('I'), isTrue);
        expect(result.endsWith('.'), isTrue);
      });
    });

    group('Live Preview Mode', () {
      test('should only trim in live preview', () {
        const input = '  um uh test  ';
        final result = cleaner.cleanForLivePreview(input);
        expect(result, equals('um uh test'));
      });

      test('should not remove fillers in live preview', () {
        const input = 'um test uh';
        final result = cleaner.cleanForLivePreview(input);
        expect(result, contains('um'));
        expect(result, contains('uh'));
      });

      test('should handle empty in live preview', () {
        final result = cleaner.cleanForLivePreview('');
        expect(result, equals(''));
      });
    });

    group('Custom Fillers', () {
      test('should accept custom filler list', () {
        final customCleaner = TranscriptCleaner(
          fillers: ['well', 'actually', 'basically'],
        );
        
        const input = 'Well, I actually need to basically go';
        final result = customCleaner.clean(input);
        
        expect(result, isNot(contains('well')));
        expect(result, isNot(contains('actually')));
        expect(result, isNot(contains('basically')));
      });
    });

    group('Performance', () {
      test('should complete in under 5ms', () {
        const input = 'Um, remind me to uh call John like tomorrow at 3 pm';
        final stopwatch = Stopwatch()..start();
        
        for (var i = 0; i < 100; i++) {
          cleaner.clean(input);
        }
        
        stopwatch.stop();
        final avgTime = stopwatch.elapsedMilliseconds / 100;
        
        expect(avgTime, lessThan(5.0));
      });
    });
  });
}
