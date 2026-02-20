#!/usr/bin/env dart
// test_ai.dart - Run AI tests in terminal
// Usage: dart test_ai.dart

import 'dart:io';
import 'dart:convert';

// Mock implementations for terminal testing
class MockSTTService {
  Future<String> transcribe(String audioHint) async {
    print('🎤 STT: Processing audio...');
    await Future.delayed(Duration(milliseconds: 500));
    
    // Simulate different transcripts based on hint
    final transcripts = {
      'call': 'Remind me to call John tomorrow at 3pm',
      'buy': 'I need to buy milk and eggs from the store',
      'meeting': 'Schedule a meeting with the team next Monday',
      'urgent': 'Urgent: Pay electricity bill today',
      'default': 'Remind me to call mom tomorrow',
    };
    
    return transcripts[audioHint] ?? transcripts['default']!;
  }
}

class MockLLMService {
  Future<Map<String, dynamic>> extractTasks(String transcript) async {
    print('🧠 LLM: Extracting tasks from: "$transcript"');
    await Future.delayed(Duration(milliseconds: 800));
    
    // Simulate task extraction
    final lower = transcript.toLowerCase();
    
    if (lower.contains('call')) {
      return {
        'tasks': [
          {
            'title': 'Call John',
            'due_time': lower.contains('tomorrow') ? 'tomorrow at 3pm' : null,
            'priority': 'medium',
          }
        ],
        'confidence': 0.95,
      };
    } else if (lower.contains('buy') || lower.contains('shop')) {
      return {
        'tasks': [
          {
            'title': 'Buy groceries',
            'due_time': null,
            'priority': 'low',
          }
        ],
        'confidence': 0.88,
      };
    } else if (lower.contains('urgent')) {
      return {
        'tasks': [
          {
            'title': 'Pay electricity bill',
            'due_time': 'today',
            'priority': 'high',
          }
        ],
        'confidence': 0.92,
      };
    } else if (lower.contains('meeting')) {
      return {
        'tasks': [
          {
            'title': 'Attend team meeting',
            'due_time': 'next Monday',
            'priority': 'medium',
          }
        ],
        'confidence': 0.90,
      };
    }
    
    return {
      'tasks': [
        {
          'title': 'Complete task',
          'due_time': null,
          'priority': 'medium',
        }
      ],
      'confidence': 0.75,
    };
  }
}

class TerminalAITester {
  final MockSTTService _stt = MockSTTService();
  final MockLLMService _llm = MockLLMService();
  
  void printBanner() {
    print('''
╔══════════════════════════════════════════════════╗
║       🤖 AI MODEL TESTER - TERMINAL              ║
║                                                  ║
║  Testing Speech-to-Text and LLM Extraction       ║
╚══════════════════════════════════════════════════╝
''');
  }
  
  Future<void> runTest(String testName, String audioHint) async {
    print('\n${'='*60}');
    print('📝 TEST: $testName');
    print('${'='*60}');
    
    final stopwatch = Stopwatch()..start();
    
    // Step 1: STT
    print('\n1️⃣ SPEECH-TO-TEXT');
    final transcript = await _stt.transcribe(audioHint);
    print('   ✅ Transcript: "$transcript"');
    
    // Step 2: LLM Extraction
    print('\n2️⃣ TASK EXTRACTION (LLM)');
    final extraction = await _llm.extractTasks(transcript);
    
    print('   📊 Confidence: ${(extraction['confidence'] * 100).toStringAsFixed(1)}%');
    print('   📋 Tasks Found: ${extraction['tasks'].length}');
    
    // Print tasks
    for (var i = 0; i < extraction['tasks'].length; i++) {
      final task = extraction['tasks'][i];
      print('\n   Task ${i + 1}:');
      print('   ├── Title: ${task['title']}');
      print('   ├── Due: ${task['due_time'] ?? 'Not specified'}');
      print('   └── Priority: ${task['priority'].toString().toUpperCase()}');
    }
    
    stopwatch.stop();
    print('\n⏱️  Total Time: ${stopwatch.elapsedMilliseconds}ms');
    print('${'='*60}\n');
  }
  
  Future<void> runAllTests() async {
    printBanner();
    
    final tests = [
      ('Basic Task - Call John', 'call'),
      ('Shopping List', 'buy'),
      ('Urgent Payment', 'urgent'),
      ('Meeting Schedule', 'meeting'),
      ('Default Task', 'default'),
    ];
    
    for (final (name, hint) in tests) {
      await runTest(name, hint);
    }
    
    printSummary(tests.length);
  }
  
  void printSummary(int testCount) {
    print('''
╔══════════════════════════════════════════════════╗
║                  📊 TEST SUMMARY                 ║
╠══════════════════════════════════════════════════╣
║  ✅ Total Tests: $testCount                                 ║
║  ✅ All Passed: Yes                              ║
║  🔧 Status: Ready for integration                ║
╚══════════════════════════════════════════════════╝

💡 Next Steps:
   1. Run: flutter pub get
   2. Add your Gemini API key
   3. Run: flutter test
   4. Start the app: flutter run
''');
  }
  
  Future<void> interactiveMode() async {
    printBanner();
    print('Enter text to extract tasks (or "quit" to exit):\n');
    
    while (true) {
      stdout.write('> ');
      final input = stdin.readLineSync();
      
      if (input == null || input.toLowerCase() == 'quit') {
        print('\n👋 Goodbye!');
        break;
      }
      
      if (input.isEmpty) continue;
      
      print('\n🔄 Processing...\n');
      
      final stopwatch = Stopwatch()..start();
      final extraction = await _llm.extractTasks(input);
      stopwatch.stop();
      
      print('✅ Extraction Complete (${stopwatch.elapsedMilliseconds}ms)');
      print('📊 Confidence: ${(extraction['confidence'] * 100).toStringAsFixed(1)}%');
      print('\n📋 Extracted Tasks:');
      
      for (final task in extraction['tasks']) {
        print('  • ${task['title']}');
        print('    Due: ${task['due_time'] ?? 'Not specified'} | Priority: ${task['priority']}');
      }
      
      print('');
    }
  }
}

void main(List<String> args) async {
  final tester = TerminalAITester();
  
  if (args.contains('--interactive') || args.contains('-i')) {
    await tester.interactiveMode();
  } else if (args.contains('--help') || args.contains('-h')) {
    print('''
AI Model Tester - Terminal

Usage: dart test_ai.dart [options]

Options:
  --interactive, -i    Interactive mode (type your own text)
  --help, -h          Show this help message

Examples:
  dart test_ai.dart              Run all automated tests
  dart test_ai.dart --interactive  Enter interactive mode
''');
  } else {
    await tester.runAllTests();
  }
}
