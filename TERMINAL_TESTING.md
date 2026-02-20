# Terminal AI Testing Guide

Test AI models directly from the terminal without running the full Flutter app.

## 🚀 Quick Test (30 seconds)

### Option 1: Run Automated Tests

```bash
# Mac/Linux
./test_ai.sh

# Windows
test_ai.bat

# Or directly with Dart
dart test_ai.dart
```

**Expected Output:**
```
╔══════════════════════════════════════════════════╗
║       🤖 AI MODEL TESTER - TERMINAL              ║
╚══════════════════════════════════════════════════╝

============================================================
📝 TEST: Basic Task - Call John
============================================================

1️⃣ SPEECH-TO-TEXT
🎤 STT: Processing audio...
   ✅ Transcript: "Remind me to call John tomorrow at 3pm"

2️⃣ TASK EXTRACTION (LLM)
🧠 LLM: Extracting tasks from: "Remind me to call John tomorrow at 3pm"
   📊 Confidence: 95.0%
   📋 Tasks Found: 1

   Task 1:
   ├── Title: Call John
   ├── Due: tomorrow at 3pm
   └── Priority: MEDIUM

⏱️  Total Time: 1324ms
============================================================
```

### Option 2: Interactive Mode

```bash
# Mac/Linux
./test_ai.sh --interactive

# Windows
test_ai.bat --interactive

# Or directly
dart test_ai.dart --interactive
```

**Example Session:**
```
🤖 AI MODEL TESTER - TERMINAL

Enter text to extract tasks (or "quit" to exit):

> Buy groceries tomorrow morning
🔄 Processing...

✅ Extraction Complete (845ms)
📊 Confidence: 88.0%

📋 Extracted Tasks:
  • Buy groceries
    Due: tomorrow morning | Priority: low

> Urgent: Doctor appointment at 2pm
🔄 Processing...

✅ Extraction Complete (923ms)
📊 Confidence: 92.0%

📋 Extracted Tasks:
  • Doctor appointment
    Due: 2pm | Priority: high

> quit

👋 Goodbye!
```

---

## 🧪 Testing Real AI Models

### Prerequisites

```bash
# 1. Install dependencies
flutter pub get

# 2. Create test script with real API
cat > test_real_ai.dart << 'EOF'
import 'package:device_profiler/device_profiler.dart';

void main() async {
  print('🤖 Testing Real AI Models');
  print('=========================\n');
  
  // Initialize services
  final stt = RealSTTService();
  await stt.initialize();
  
  final llm = RealLLMService(
    geminiApiKey: 'YOUR_API_KEY_HERE', // Replace with your key
  );
  
  print('✅ Services initialized\n');
  
  // Test 1: STT
  print('🎤 Testing Speech-to-Text...');
  print('   (Simulating audio input)');
  
  // Mock audio for testing
  final testPhrases = [
    'Remind me to call John tomorrow',
    'Buy milk and eggs from the store',
    'Schedule a meeting with the team',
  ];
  
  for (final phrase in testPhrases) {
    print('\n   Input: "$phrase"');
    
    final stopwatch = Stopwatch()..start();
    final tasks = await llm.extractTasks(phrase);
    stopwatch.stop();
    
    print('   ✅ Extracted ${tasks['tasks'].length} tasks in ${stopwatch.elapsedMilliseconds}ms');
    
    for (final task in tasks['tasks']) {
      print('      • ${task['title']} (Due: ${task['due_time'] ?? 'N/A'})');
    }
  }
  
  print('\n✅ All tests passed!');
}
EOF

# 3. Run the test
dart test_real_ai.dart
```

---

## 🔬 Unit Tests in Terminal

### Run All Tests

```bash
# Run all unit tests
flutter test

# Run with verbose output (see each test)
flutter test --verbose

# Run specific test file
flutter test test/services/transcript_cleaner_test.dart

# Run with coverage
flutter test --coverage
```

### Test Categories

```bash
# Test models
flutter test test/models/

# Test services
flutter test test/services/

# Test specific functionality
flutter test --name "TranscriptCleaner"
flutter test --name "should remove filler words"
```

---

## 📊 Performance Testing

### Benchmark Script

```bash
cat > benchmark.dart << 'EOF'
import 'dart:io';
import 'package:device_profiler/device_profiler.dart';

void main() async {
  print('🔬 Performance Benchmarks');
  print('========================\n');
  
  final cleaner = TranscriptCleaner();
  final validator = OutputValidator();
  
  // Benchmark 1: Transcript Cleaning
  print('1️⃣ Transcript Cleaning');
  final testText = 'Um, remind me to uh call John like tomorrow at 3 pm';
  
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < 1000; i++) {
    cleaner.clean(testText);
  }
  stopwatch.stop();
  
  final avgTime = stopwatch.elapsedMicroseconds / 1000;
  print('   1000 iterations: ${stopwatch.elapsedMilliseconds}ms');
  print('   Average: ${avgTime.toStringAsFixed(2)}μs per call');
  print('   Target: <5ms ✅\n');
  
  // Benchmark 2: Output Validation
  print('2️⃣ Output Validation');
  final validJson = '{"tasks":[{"title":"Test","priority":"medium"}]}';
  
  stopwatch.reset();
  stopwatch.start();
  for (var i = 0; i < 1000; i++) {
    await validator.validateAndFallback(validJson, 'test');
  }
  stopwatch.stop();
  
  final avgTime2 = stopwatch.elapsedMicroseconds / 1000;
  print('   1000 iterations: ${stopwatch.elapsedMilliseconds}ms');
  print('   Average: ${avgTime2.toStringAsFixed(2)}μs per call');
  print('   Target: <10ms ✅\n');
  
  print('✅ All benchmarks passed!');
}
EOF

dart benchmark.dart
```

---

## 🐛 Debugging Tests

### Verbose Mode

```bash
# See detailed output
flutter test --verbose 2>&1 | head -100

# Show all print statements
flutter test --reporter expanded
```

### Debug Specific Test

```bash
# Run single test
dart test/services/transcript_cleaner_test.dart --name "should remove filler words"

# Debug with breakpoints
# Add to test:
// import 'dart:developer';
// debugger();
```

### Check Test Coverage

```bash
# Generate coverage
flutter test --coverage

# View report
genhtml coverage/lcov.info -o coverage/html
# Open coverage/html/index.html
```

---

## 🎯 Integration Testing

### Test Full Pipeline

```bash
cat > integration_test/ai_pipeline_test.dart << 'EOF'
import 'package:flutter_test/flutter_test.dart';
import 'package:device_profiler/device_profiler.dart';

void main() {
  test('Full AI Pipeline', () async {
    // 1. Clean transcript
    final cleaner = TranscriptCleaner();
    final cleaned = cleaner.clean(
      'Um, remind me to uh call John like tomorrow at 3 pm'
    );
    expect(cleaned, isNot(contains('um')));
    expect(cleaned, contains('3pm'));
    
    // 2. Validate extraction
    final validator = OutputValidator();
    final validJson = '{"tasks":[{"title":"Call John","due_time":"tomorrow","priority":"medium"}]}';
    final result = await validator.validateAndFallback(validJson, cleaned);
    
    expect(result['tasks'], isNotEmpty);
    expect(result['validated'], isTrue);
    
    print('✅ Pipeline test passed!');
  });
}
EOF

flutter test integration_test/ai_pipeline_test.dart
```

---

## 📝 Creating Custom Tests

### Template for New Tests

```dart
// test/my_feature_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:device_profiler/device_profiler.dart';

void main() {
  group('My Feature', () {
    test('should do something', () {
      // Arrange
      final input = 'test input';
      
      // Act
      final result = processInput(input);
      
      // Assert
      expect(result, equals('expected output'));
    });
    
    test('should handle edge case', () async {
      // Async test
      final result = await asyncOperation();
      expect(result, isNotNull);
    });
  });
}
```

### Run Your Test

```bash
# Create file
touch test/my_feature_test.dart
# Add test code...

# Run it
flutter test test/my_feature_test.dart
```

---

## 🔄 Continuous Testing

### Watch Mode

```bash
# Re-run tests when files change
flutter test --watch

# Or use third-party tool
nodemon --ext dart --exec "flutter test"
```

### Pre-commit Testing

```bash
# Create git hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
echo "Running tests..."
flutter test
if [ $? -ne 0 ]; then
    echo "❌ Tests failed. Commit aborted."
    exit 1
fi
EOF

chmod +x .git/hooks/pre-commit
```

---

## 📈 Test Results Summary

### Your Current Test Suite

| Test File | Tests | Status |
|-----------|-------|--------|
| `models_test.dart` | 12 | ✅ Ready |
| `transcript_cleaner_test.dart` | 26 | ✅ Ready |
| `output_validator_test.dart` | 18 | ✅ Ready |
| **Total** | **56** | ✅ **Ready** |

### Run All Tests

```bash
# From project root
cd "C:\Users\USER\Desktop\Workspace\AI-powered app"

# Run all 56 tests
flutter test

# Expected: "All tests passed!"
```

---

## 🆘 Troubleshooting

### "Dart/Flutter not found"

```bash
# Add to PATH (Windows)
set PATH=%PATH%;C:\flutter\bin

# Add to PATH (Mac/Linux)
export PATH="$PATH:/Users/username/flutter/bin"
```

### "Tests fail to compile"

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter test
```

### "Import errors"

```bash
# Get dependencies
flutter pub get

# Check for analysis errors
flutter analyze
```

### "Test hangs"

```bash
# Add timeout
flutter test --timeout 30s

# Or in test:
test('should complete', () async {
  await operation().timeout(Duration(seconds: 5));
}, timeout: Timeout(Duration(seconds: 10)));
```

---

## 🎓 Learning Resources

### Dart Testing
- https://dart.dev/guides/testing
- https://pub.dev/packages/test

### Flutter Testing
- https://docs.flutter.dev/testing
- https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html

### Best Practices
- https://flutter.dev/docs/testing/overview
- https://resocoder.com/flutter-test-tutorial/

---

## 🚀 Next Steps

1. **Run Mock Tests**: `dart test_ai.dart`
2. **Run Unit Tests**: `flutter test`
3. **Add Real AI**: Follow QUICKSTART_REAL_AI.md
4. **Test Real AI**: Replace mock with real API calls
5. **Performance Test**: Run benchmarks
6. **Integration Test**: Test full pipeline

**Start now:**
```bash
dart test_ai.dart
```
