#!/usr/bin/env dart
// diagnose_api.dart - Diagnose API connection issues

import 'dart:io';
import 'dart:convert';

void main() async {
  print('🔍 Gemini API Diagnostic Tool');
  print('==============================\n');
  
  // 1. Check for .env file
  print('1️⃣ Checking for .env file...');
  String? apiKey;
  
  if (File('.env').existsSync()) {
    print('   ✅ Found .env in current directory');
    final lines = File('.env').readAsLinesSync();
    for (final line in lines) {
      if (line.startsWith('GOOGLE_API_KEY=')) {
        apiKey = line.substring('GOOGLE_API_KEY='.length).trim();
        print('   ✅ API key loaded (${apiKey.length} chars)');
        break;
      }
    }
  }
  
  if (apiKey == null || apiKey.isEmpty) {
    print('   ❌ API key not found in .env');
    print('\nCreate .env file with:');
    print('  GOOGLE_API_KEY=your_key_here');
    exit(1);
  }
  
  // 2. Test basic HTTPS connection
  print('\n2️⃣ Testing HTTPS connection...');
  try {
    final client = HttpClient();
    final request = await client.getUrl(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey')
    );
    final response = await request.close();
    
    if (response.statusCode == 200) {
      print('   ✅ API connection successful');
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      final models = data['models'] as List;
      print('   ✅ Found ${models.length} available models');
      
      // Show available models
      print('\n   Available models:');
      for (var i = 0; i < models.length && i < 5; i++) {
        final model = models[i];
        print('     • ${model['name']}');
      }
    } else {
      print('   ❌ API returned: ${response.statusCode}');
      final body = await response.transform(utf8.decoder).join();
      print('   Response: $body');
    }
    
    client.close();
  } catch (e) {
    print('   ❌ Connection failed: $e');
  }
  
  // 3. Test generate content endpoint
  print('\n3️⃣ Testing generateContent endpoint...');
  try {
    final client = HttpClient();
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey'
    );
    
    final request = await client.postUrl(url);
    request.headers.set('Content-Type', 'application/json');
    
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': 'Say "Hello, API is working!"'}
          ]
        }
      ]
    });
    
    request.write(body);
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    
    if (response.statusCode == 200) {
      print('   ✅ Generate content works!');
      final data = jsonDecode(responseBody);
      final text = data['candidates'][0]['content']['parts'][0]['text'];
      print('   Response: $text');
    } else {
      print('   ❌ Generate content failed: ${response.statusCode}');
      print('   Response: $responseBody');
      
      if (response.statusCode == 404) {
        print('\n   💡 Model "gemini-1.5-flash" not found.');
        print('   Try using "gemini-pro" or "gemini-1.0-pro" instead');
      }
    }
    
    client.close();
  } catch (e) {
    print('   ❌ Test failed: $e');
  }
  
  print('\n✅ Diagnostic complete!');
}
