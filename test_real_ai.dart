#!/usr/bin/env dart
// test_real_ai.dart - Test real AI service
// Run from project root: dart test_real_ai.dart

import 'dart:io';
import 'lib/src/services/real_ai_service.dart' as ai;

void main() async {
  print('🤖 Real AI Service Test');
  print('======================\n');
  
  // Show current directory
  print('📁 Current directory: ${Directory.current.path}\n');
  
  // Check if .env exists
  if (!File('.env').existsSync()) {
    print('❌ .env file not found in current directory!');
    print('\nPlease create a .env file with your API key:');
    print('  echo "GOOGLE_API_KEY=your_key_here" > .env');
    print('\nGet your API key from: https://makersuite.google.com/app/apikey');
    exit(1);
  }
  
  print('✅ Found .env file\n');
  
  try {
    // Create service (loads key from .env)
    final service = ai.RealAIService();
    await service.initialize();
    
    print('Testing task extraction...\n');
    
    // Test with sample text
    final result = await service.extractTasks(
      'Remind me to call John tomorrow at 3pm about the project'
    );
    
    print('\n✅ SUCCESS! Result:');
    print(result);
    
    service.dispose();
    
  } catch (e) {
    print('\n❌ ERROR: $e');
    print('\nTroubleshooting:');
    print('1. Check .env file has: GOOGLE_API_KEY=your_actual_key');
    print('2. Verify your API key at: https://makersuite.google.com/app/apikey');
    print('3. Ensure you have internet connection');
    exit(1);
  }
}
