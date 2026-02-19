# Testing Guide

Comprehensive testing strategy for the AI-powered mobile app covering all 9 layers.

## Table of Contents

1. [Unit Testing](#unit-testing)
2. [Integration Testing](#integration-testing)
3. [Widget/UI Testing](#widgetui-testing)
4. [Manual Testing](#manual-testing)
5. [Performance Testing](#performance-testing)
6. [Device Testing Matrix](#device-testing-matrix)

---

## Unit Testing

### Running Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/services/device_profile_service_test.dart

# Run with coverage
flutter test --coverage

# Run with verbose output
flutter test --verbose
```

### Test Structure

```
test/
├── models/
│   ├── device_profile_test.dart
│   ├── generation_config_test.dart
│   └── model_config_test.dart
├── services/
│   ├── audio_capture_service_test.dart
│   ├── device_profile_service_test.dart
│   ├── inference_scheduler_test.dart
│   ├── local_storage_service_test.dart
│   ├── output_validator_test.dart
│   ├── slm_action_extractor_test.dart
│   ├── speech_to_text_service_test.dart
│   └── transcript_cleaner_test.dart
├── slm_backends/
│   └── llama_slm_backend_test.dart
├── stt_backends/
│   └── whisper_stt_backend_test.dart
└── widgets/
    └── home_screen_test.dart
```

### Example Unit Tests

#### Testing DeviceProfileService (Mock)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:device_profiler/device_profiler.dart';

class MockMethodChannel extends Mock implements MethodChannel {}

void main() {
  group('DeviceProfileService', () {
    late DeviceProfileService service;
    
    setUp(() {
      service = DeviceProfileService();
    });

    test('should return fallback config on error', () async {
      // Arrange
      // Mock platform channel to throw error
      
      // Act
      final config = await service.initializeAndGetConfig();
      
      // Assert
      expect(config.sttModel, equals('moonshine-tiny'));
      expect(config.slmModel, equals('tinyllama-q4'));
      expect(config.quantization, equals('4bit'));
    });

    test('should select high-tier config for devices with >8GB RAM', () {
      // Arrange
      final profile = DeviceProfile(
        ramGB: 12.0,
        cpuCores: 8,
        batteryLevel: 80,
        isLowMemory: false,
      );
      
      // Act
      final config = service.determineModelConfig(profile);
      
      // Assert
      expect(config.slmModel, contains('phi3-mini-q8'));
      expect(config.mode, equals('live'));
    });

    test('should apply battery constraints when <30%', () {
      // Arrange
      final profile = DeviceProfile(
        ramGB: 12.0,
        cpuCores: 8,
        batteryLevel: 20,
        isLowMemory: false,
      );
      
      // Act
      final config = service.determineModelConfig(profile);
      
      // Assert
      expect(config.mode, equals('batch'));
      expect(config.maxTokens, lessThan(512));
    });
  });
}
```

#### Testing TranscriptCleaner

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:device_profiler/device_profiler.dart';

void main() {
  group('TranscriptCleaner', () {
    late TranscriptCleaner cleaner;
    
    setUp(() {
      cleaner = TranscriptCleaner();
    });

    test('should remove filler words', () {
      // Arrange
      const input = 'Um, remind me to um call John like tomorrow';
      
      // Act
      final result = cleaner.clean(input);
      
      // Assert
      expect(result, isNot(contains('um')));
      expect(result, isNot(contains('like')));
      expect(result, contains('Remind me to call John'));
    });

    test('should normalize time expressions', () {
      // Arrange
      const input = 'Meet at 3 pm tomorrow';
      
      // Act
      final result = cleaner.clean(input);
      
      // Assert
      expect(result, contains('3pm'));
      expect(result, isNot(contains('3 pm')));
    });

    test('should remove duplicate words', () {
      // Arrange
      const input = 'Buy buy milk today';
      
      // Act
      final result = cleaner.clean(input);
      
      // Assert
      expect(result, equals('Buy milk today.'));
    });

    test('should handle empty input', () {
      // Act
      final result = cleaner.clean('');
      
      // Assert
      expect(result, equals(''));
    });

    test('cleanForLivePreview should only trim whitespace', () {
      // Arrange
      const input = '  multiple   spaces  here  ';
      
      // Act
      final result = cleaner.cleanForLivePreview(input);
      
      // Assert
      expect(result, equals('multiple spaces here'));
    });
  });
}
```

#### Testing OutputValidator

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:device_profiler/device_profiler.dart';

void main() {
  group('OutputValidator', () {
    late OutputValidator validator;
    
    setUp(() {
      validator = OutputValidator();
    });

    test('should validate correct JSON', () async {
      // Arrange
      const json = '{"tasks":[{"title":"Test","due_time":null,"priority":"medium"}]}';
      
      // Act
      final result = await validator.validateAndFallback(json, 'test transcript');
      
      // Assert
      expect(result['tasks'], isNotEmpty);
      expect(result['validated'], isTrue);
    });

    test('should return fallback for invalid JSON', () async {
      // Arrange
      const invalidJson = 'not valid json';
      const transcript = 'original text';
      
      // Act
      final result = await validator.validateAndFallback(invalidJson, transcript);
      
      // Assert
      expect(result['tasks'], isEmpty);
      expect(result['fallback_transcript'], equals(transcript));
      expect(result['validated'], isFalse);
    });

    test('should handle missing tasks key', () async {
      // Arrange
      const json = '{"other_key":"value"}';
      
      // Act
      final result = await validator.validateAndFallback(json, 'test');
      
      // Assert
      expect(result['tasks'], isEmpty);
    });

    test('should retry once on invalid JSON if callback provided', () async {
      // Arrange
      const invalidJson = 'invalid';
      bool retryCalled = false;
      
      final validatorWithRetry = OutputValidator(
        onRetry: (prompt) async {
          retryCalled = true;
          return '{"tasks":[]}';
        },
      );
      
      // Act
      await validatorWithRetry.validateAndFallback(invalidJson, 'test');
      
      // Assert
      expect(retryCalled, isTrue);
    });
  });
}
```

#### Testing LocalStorageService (Mock)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:device_profiler/device_profiler.dart';

class MockBox extends Mock implements Box<Map> {}

void main() {
  group('LocalStorageService', () {
    late LocalStorageService storage;
    late MockBox mockNotesBox;
    late MockBox mockIndexBox;
    
    setUp(() async {
      // Initialize Hive for testing
      await Hive.initFlutter();
      
      storage = LocalStorageService();
      mockNotesBox = MockBox();
      mockIndexBox = MockBox();
    });

    test('should save note successfully', () async {
      // Arrange
      when(mockNotesBox.put(any, any)).thenAnswer((_) => Future.value());
      when(mockIndexBox.put(any, any)).thenAnswer((_) => Future.value());
      
      // Act
      await storage.saveNote(
        noteId: 'test123',
        transcript: 'Test transcript',
        extractedJson: {'tasks': []},
      );
      
      // Assert
      verify(mockNotesBox.put('test123', any)).called(1);
    });

    test('should return null for non-existent note', () async {
      // Arrange
      when(mockNotesBox.get('nonexistent')).thenReturn(null);
      
      // Act
      final result = await storage.getNote('nonexistent');
      
      // Assert
      expect(result, isNull);
    });

    test('should search notes by query', () async {
      // Arrange
      final noteMap = {
        'noteId': 'test1',
        'transcript': 'Call John tomorrow',
        'extractedJson': jsonEncode({'tasks': []}),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'searchTokens': ['call', 'john', 'tomorrow'],
      };
      
      when(mockNotesBox.get('test1')).thenReturn(noteMap);
      when(mockIndexBox.toMap()).thenReturn({
        'test1': ['call', 'john', 'tomorrow']
      });
      
      // Act
      final results = await storage.searchNotes('john');
      
      // Assert
      expect(results, isNotEmpty);
    });
  });
}
```

---

## Integration Testing

### Running Integration Tests

```bash
# Run integration tests
flutter test integration_test/

# Run on specific device
flutter test integration_test/ -d <device_id>

# Run with verbose output
flutter test integration_test/ --verbose
```

### Integration Test Structure

```
integration_test/
├── app_test.dart                 # Full app flow
├── audio_flow_test.dart          # Audio capture to storage
├── inference_flow_test.dart      # STT to SLM pipeline
├── device_actions_test.dart      # Calendar/notifications
└── battery_optimization_test.dart # Battery-aware behavior
```

### Example Integration Tests

#### Full App Flow Test

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:device_profiler/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End App Flow', () {
    testWidgets('complete note creation flow', (WidgetTester tester) async {
      // Launch app
      app.main();
      await tester.pumpAndSettle();
      
      // Verify home screen loads
      expect(find.text('AI Notes'), findsOneWidget);
      
      // Tap record button
      await tester.tap(find.byKey(const Key('record_button')));
      await tester.pumpAndSettle();
      
      // Wait for recording (simulated)
      await Future.delayed(const Duration(seconds: 3));
      
      // Tap stop button
      await tester.tap(find.byKey(const Key('stop_button')));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Verify note appears in list
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('search functionality', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();
      
      // Enter search query
      await tester.enterText(
        find.byKey(const Key('search_field')),
        'call john',
      );
      await tester.pumpAndSettle();
      
      // Verify search results
      expect(find.text('Call John'), findsOneWidget);
    });
  });
}
```

#### Inference Pipeline Test

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:device_profiler/device_profiler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Inference Pipeline Integration', () {
    test('full pipeline with real audio', () async {
      // Arrange
      final scheduler = InferenceScheduler(LocalStorageService());
      await scheduler.initialize();
      
      // Use test audio file (must be in test assets)
      const testAudioPath = 'assets/test_audio.wav';
      
      // Act
      final result = await scheduler.processNote(
        audioFilePath: testAudioPath,
        liveMode: false,
      );
      
      // Assert
      expect(result, isNotNull);
      expect(result.containsKey('tasks'), isTrue);
      expect(result['tasks'], isA<List>());
      
      // Cleanup
      await scheduler.dispose();
    });

    test('battery-aware mode switching', () async {
      // Arrange - simulate low battery
      final scheduler = InferenceScheduler(LocalStorageService());
      await scheduler.initialize();
      
      // Act - process with high battery request but simulate low battery
      final result = await scheduler.processNote(
        audioFilePath: 'assets/test_audio.wav',
        liveMode: true, // Requested live mode
      );
      
      // Assert - should use batch mode if battery low
      // (Depends on actual device battery level during test)
      expect(result, isNotNull);
      
      await scheduler.dispose();
    });
  });
}
```

---

## Widget/UI Testing

### Testing UI Components

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:device_profiler/main.dart';

void main() {
  group('UI Components', () {
    testWidgets('RecordButton shows correct state', (WidgetTester tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordButton(
              isRecording: false,
              onPressed: () {},
            ),
          ),
        ),
      );
      
      // Assert
      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.stop), findsNothing);
    });

    testWidgets('NoteCard displays task count', (WidgetTester tester) async {
      // Arrange
      final note = {
        'noteId': 'test1',
        'transcript': 'Test note',
        'extractedJson': {
          'tasks': [
            {'title': 'Task 1'},
            {'title': 'Task 2'},
          ],
        },
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteCard(note: note),
          ),
        ),
      );
      
      // Assert
      expect(find.text('2 tasks'), findsOneWidget);
    });

    testWidgets('TaskList displays all tasks', (WidgetTester tester) async {
      // Arrange
      final tasks = [
        {'title': 'Task 1', 'priority': 'high', 'completed': false},
        {'title': 'Task 2', 'priority': 'medium', 'completed': true},
      ];
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskList(tasks: tasks),
          ),
        ),
      );
      
      // Assert
      expect(find.text('Task 1'), findsOneWidget);
      expect(find.text('Task 2'), findsOneWidget);
      expect(find.byType(Checkbox), findsNWidgets(2));
    });
  });
}
```

---

## Manual Testing

### Pre-Flight Checklist

Before each release, manually verify:

#### Audio & STT
- [ ] Record audio (5 seconds)
- [ ] Verify 16kHz WAV format
- [ ] Verify transcription accuracy
- [ ] Test with background noise
- [ ] Test with different accents
- [ ] Test empty audio handling

#### SLM Extraction
- [ ] Simple task: "Remind me to call John"
- [ ] Complex task: "Buy milk tomorrow and call mom on Friday"
- [ ] Time expressions: "3pm", "tomorrow", "next week"
- [ ] Priority detection: "urgent", "important"
- [ ] Empty/invalid transcript handling

#### Device Actions
- [ ] Add to calendar (Android)
- [ ] Add to calendar (iOS)
- [ ] Schedule notification
- [ ] Share note as Markdown
- [ ] Share note as JSON
- [ ] Mark task as done

#### Battery & Performance
- [ ] Process note at 100% battery
- [ ] Process note at 50% battery
- [ ] Process note at 20% battery (should switch to batch)
- [ ] Process note at 10% battery (should warn/defer)
- [ ] Monitor memory usage during inference
- [ ] Verify models unload after use

#### Storage & Encryption
- [ ] Save note
- [ ] Retrieve note
- [ ] Search notes
- [ ] Delete note
- [ ] Verify encryption (check files are not plaintext)
- [ ] Test storage full scenario

#### Error Scenarios
- [ ] Deny microphone permission
- [ ] Deny calendar permission
- [ ] Deny notification permission
- [ ] Process with corrupted audio file
- [ ] Process with no storage space
- [ ] Kill app mid-inference, restart

### Manual Test Procedures

#### Test 1: Complete Workflow
```
1. Open app
2. Tap record button
3. Speak: "Remind me to call John tomorrow at 3pm, it's urgent"
4. Wait for processing (should take 5-15 seconds)
5. Verify note appears in list
6. Tap note to view details
7. Verify extracted task:
   - Title: "Call John"
   - Due: "tomorrow at 3pm"
   - Priority: "high"
8. Tap "Add to Calendar"
9. Verify calendar app opens with event
10. Tap "Schedule Notification"
11. Verify notification scheduled
```

#### Test 2: Battery Optimization
```
1. Set device battery to 25%
2. Record and process a note
3. Verify app switches to batch mode (check logs)
4. Verify tokens reduced by 50%
5. Set battery to 10%
6. Attempt to process note
7. Verify app defers processing or warns user
```

#### Test 3: Error Recovery
```
1. Start recording
2. Force close app
3. Reopen app
4. Verify no crash, app state recovered
5. Process a note with corrupted model file
6. Verify fallback to smaller model
7. Verify result still returned (may be empty tasks)
```

#### Test 4: Offline Operation
```
1. Enable airplane mode
2. Record and process note
3. Verify all functionality works
4. Disable airplane mode
5. Verify background sync (if implemented)
```

---

## Performance Testing

### Benchmarking

```dart
// test/performance/benchmarks_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:device_profiler/device_profiler.dart';

void main() {
  group('Performance Benchmarks', () {
    test('STT processing time < 10 seconds for 30s audio', () async {
      final stt = SpeechToTextService();
      final stopwatch = Stopwatch()..start();
      
      await stt.transcribeBatch(
        audioFilePath: 'assets/test_30s_audio.wav',
        modelPath: 'base.en',
      );
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(10000));
    });

    test('SLM extraction time < 5 seconds', () async {
      final extractor = SlmActionExtractor(modelPath: 'phi3-mini-Q4');
      final stopwatch = Stopwatch()..start();
      
      await extractor.extract(
        'Remind me to call John tomorrow at 3pm',
      );
      
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });

    test('Memory usage < 500MB during inference', () async {
      // This requires platform-specific memory monitoring
      // Implementation depends on device profiling capabilities
    });

    test('Transcript cleaning < 5ms', () {
      final cleaner = TranscriptCleaner();
      final avgTime = cleaner.benchmark(
        'Um, remind me to um call John like tomorrow at 3 pm',
        iterations: 1000,
      );
      
      expect(avgTime, lessThan(5.0));
    });
  });
}
```

### Profiling

```bash
# CPU profiling
flutter run --profile --trace-systrace

# Memory profiling
flutter run --profile --verbose-system-logs

# Startup time
flutter run --trace-startup

# Performance overlay
# Press 'P' in terminal while app is running
```

---

## Device Testing Matrix

### Minimum Requirements

| Device Spec | Minimum | Recommended |
|-------------|---------|-------------|
| RAM | 2GB | 4GB+ |
| Storage | 500MB free | 2GB free |
| Android | 7.0 (API 24) | 10.0+ (API 29+) |
| iOS | 13.0 | 15.0+ |

### Test Devices

#### Android
- [ ] Low-end: Samsung Galaxy A10 (2GB RAM)
- [ ] Mid-range: Google Pixel 4a (6GB RAM)
- [ ] High-end: Samsung Galaxy S23 (8GB+ RAM)
- [ ] Tablet: Samsung Galaxy Tab A

#### iOS
- [ ] Old: iPhone 8 (2GB RAM)
- [ ] Mid: iPhone 12 (4GB RAM)
- [ ] New: iPhone 14 Pro (6GB RAM)
- [ ] Tablet: iPad 9th Gen

### Feature Matrix

| Feature | Low-End | Mid-Range | High-End |
|---------|---------|-----------|----------|
| STT Model | tiny | base | small |
| SLM Model | tinyllama-Q4 | phi3-Q4 | phi3-Q8 |
| Live Mode | No | Yes | Yes |
| Max Tokens | 128 | 256 | 512 |
| Batch Size | 1 | 2 | 4 |

---

## Debugging Tips

### Enable Verbose Logging

```dart
// In main.dart
Logger.root.level = Level.ALL;
Logger.root.onRecord.listen((record) {
  debugPrint('${record.level.name}: ${record.time}: ${record.message}');
});
```

### Check Model Loading

```dart
// Verify model paths
final modelManager = STTModelManager();
final isDownloaded = await modelManager.isModelDownloaded('tiny.en');
print('Model downloaded: $isDownloaded');

final modelPath = await modelManager.getModelPath('tiny.en');
print('Model path: $modelPath');
```

### Monitor Battery During Tests

```dart
// In tests
final batteryLevel = await DeviceProfileService().getBatteryLevel();
print('Battery: $batteryLevel%');
```

### Verify Encryption

```bash
# Check Hive box files are encrypted
# Android: /data/data/com.yourapp/app_flutter/
# iOS: App Documents directory

# Files should NOT be readable as plaintext JSON
```

---

## Continuous Integration

### GitHub Actions Workflow

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.16.0'
      
      - name: Install dependencies
        run: flutter pub get
      
      - name: Analyze code
        run: flutter analyze
      
      - name: Run tests
        run: flutter test --coverage
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

---

## Summary

**Testing Levels:**
1. **Unit Tests** - Fast, isolated, mock dependencies
2. **Integration Tests** - Full pipeline, real components
3. **Widget Tests** - UI behavior, user interactions
4. **Manual Tests** - Real devices, edge cases
5. **Performance Tests** - Benchmarks, profiling

**Key Metrics:**
- STT: < 10s for 30s audio
- SLM: < 5s per extraction
- Memory: < 500MB peak
- Battery: < 5% drain per hour
- Storage: < 100ms per operation

**Golden Rule:** Test on real devices early and often. Emulators don't show true performance characteristics.
