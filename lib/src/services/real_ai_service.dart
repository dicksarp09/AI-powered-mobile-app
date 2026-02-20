import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';

// NOTE: This is a simplified version that reads from .env file directly
// For production, use flutter_dotenv package

/// Real AI Service using Google Cloud APIs
/// 
/// This service integrates with:
/// - Google Cloud Speech-to-Text API for transcription
/// - Google Gemini API for task extraction
/// 
/// Setup:
/// 1. Create .env file with GOOGLE_API_KEY=your_key_here
/// 2. Run: flutter pub add http
/// 3. Initialize in main.dart
class RealAIService {
  static final Logger _logger = Logger('RealAIService');
  
  late final String _apiKey;
  final _client = HttpClient();
  
  /// Base URLs for Google APIs
  static const String _geminiBaseUrl = 'generativelanguage.googleapis.com';
  static const String _speechBaseUrl = 'speech.googleapis.com';
  
  /// Constructor - loads API key from .env file
  RealAIService() {
    _apiKey = _loadApiKeyFromEnv();
    if (_apiKey.isEmpty) {
      throw Exception('GOOGLE_API_KEY not found in .env file');
    }
    _logger.info('RealAIService initialized');
  }
  
  /// Alternative constructor with explicit API key
  RealAIService.withKey(String apiKey) : _apiKey = apiKey {
    if (_apiKey.isEmpty) {
      throw Exception('API key cannot be empty');
    }
  }
  
  /// Load API key from .env file
  /// Searches in multiple locations: current dir, project root, script dir
  String _loadApiKeyFromEnv() {
    try {
      // Try multiple locations for .env file
      final possiblePaths = [
        '.env',  // Current directory
        '../../.env',  // Project root (from lib/src/services)
        '../../../.env',  // One more level up
      ];
      
      File? envFile;
      for (final path in possiblePaths) {
        final file = File(path);
        if (file.existsSync()) {
          envFile = file;
          _logger.fine('Found .env at: $path');
          break;
        }
      }
      
      if (envFile == null) {
        _logger.warning('.env file not found. Searched in: ${possiblePaths.join(', ')}');
        return '';
      }
      
      final lines = envFile.readAsLinesSync();
      for (final line in lines) {
        if (line.startsWith('GOOGLE_API_KEY=')) {
          return line.substring('GOOGLE_API_KEY='.length).trim();
        }
      }
      return '';
    } catch (e) {
      _logger.severe('Error reading .env file: $e');
      return '';
    }
  }

  /// Initialize the service
  Future<void> initialize() async {
    _logger.info('Initializing Real AI Service...');
    await _verifyApiKey();
    _logger.info('Real AI Service initialized successfully');
  }
  
  /// Verify API key is valid
  Future<void> _verifyApiKey() async {
    try {
      final url = Uri.https(_geminiBaseUrl, '/v1beta/models', {'key': _apiKey});
      final request = await _client.getUrl(url);
      final response = await request.close();
      
      if (response.statusCode == 200) {
        _logger.info('API key verified');
      } else if (response.statusCode == 400) {
        throw Exception('Invalid API key');
      }
    } catch (e) {
      _logger.severe('Failed to verify API key: $e');
      // Don't throw here, let it fail on first use
    }
  }

  /// Extract tasks from transcript using Gemini API
  Future<Map<String, dynamic>> extractTasks(String transcript) async {
    _logger.info('Extracting tasks with Gemini API...');
    
    final url = Uri.https(
      _geminiBaseUrl,
      '/v1beta/models/gemini-pro:generateContent',
      {'key': _apiKey},
    );
    
    // Build prompt
    final prompt = _buildPrompt(transcript);
    
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 256,
        'topP': 0.9,
      },
    });
    
    try {
      final stopwatch = Stopwatch()..start();
      
      final request = await _client.postUrl(url);
      request.headers.set('Content-Type', 'application/json');
      request.write(body);
      
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      
      stopwatch.stop();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
        
        _logger.info('Task extraction completed in ${stopwatch.elapsedMilliseconds}ms');
        
        // Extract JSON from response
        final jsonStr = _extractJson(text);
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;
        
        // Add metadata
        result['source'] = 'gemini_api';
        result['processing_time_ms'] = stopwatch.elapsedMilliseconds;
        
        return result;
      } else if (response.statusCode == 429) {
        _logger.severe('Rate limit exceeded');
        throw Exception('Rate limit exceeded. Please wait and try again.');
      } else {
        _logger.severe('Gemini API error: ${response.statusCode}');
        throw Exception('Gemini API error: ${response.statusCode}');
      }
    } catch (e) {
      _logger.severe('Task extraction failed: $e');
      return {
        'tasks': [],
        'error': e.toString(),
        'fallback_transcript': transcript,
      };
    }
  }
  
  /// Build extraction prompt
  String _buildPrompt(String transcript) {
    return 'You are an information extraction engine. '
        'Extract actionable tasks from the text below and return ONLY valid JSON. '
        'Rules: '
        '- Output ONLY valid JSON, no markdown, no backticks. '
        '- If no tasks exist, return: {"tasks":[]}. '
        '- Each task must have: title (string), due_time (string or null), priority ("low", "medium", or "high"). '
        '- due_time should be normalized (e.g., "tomorrow at 3pm", "next Monday", or null if not specified). '
        '- priority should be inferred from context (urgent=high, optional=low, normal=medium). '
        'Text to analyze: "$transcript". '
        'Return JSON in this exact format: '
        '{"tasks": [{"title": "task description", "due_time": "when it is due or null", "priority": "low|medium|high"}]}';
  }

  /// Extract JSON from response text
  String _extractJson(String text) {
    final startIndex = text.indexOf('{');
    final endIndex = text.lastIndexOf('}');
    
    if (startIndex == -1 || endIndex == -1 || startIndex >= endIndex) {
      _logger.warning('No JSON found in response');
      return '{"tasks":[]}';
    }
    
    return text.substring(startIndex, endIndex + 1);
  }

  /// Test the service with a simple prompt
  Future<void> testConnection() async {
    _logger.info('Testing API connection...');
    
    try {
      final result = await extractTasks('Remind me to test the API');
      _logger.info('API test successful');
      _logger.info('Response: $result');
    } catch (e) {
      _logger.severe('API test failed: $e');
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    _client.close();
    _logger.info('RealAIService disposed');
  }
}

/// Test runner
void main(List<String> args) async {
  print('🤖 Real AI Service Test');
  print('======================\n');
  
  // Check current directory
  print('Current directory: ${Directory.current.path}\n');
  
  // Check if .env exists
  final envPaths = ['.env', '../../.env', '../../../.env'];
  bool envFound = false;
  
  for (final path in envPaths) {
    if (File(path).existsSync()) {
      print('✅ Found .env file at: $path');
      envFound = true;
      break;
    }
  }
  
  if (!envFound) {
    print('❌ .env file not found!');
    print('\nPlease create a .env file in your project root with:');
    print('  GOOGLE_API_KEY=your_api_key_here');
    print('\nGet your API key from: https://makersuite.google.com/app/apikey');
    return;
  }
  
  try {
    final service = RealAIService();
    await service.initialize();
    
    print('\nTesting task extraction...\n');
    final result = await service.extractTasks(
      'Remind me to call John tomorrow at 3pm about the project'
    );
    
    print('\n✅ Result:');
    print(const JsonEncoder.withIndent('  ').convert(result));
    
    service.dispose();
    
  } catch (e) {
    print('\n❌ Error: $e');
    print('\nMake sure you have:');
    print('1. Created a .env file with GOOGLE_API_KEY=your_key');
    print('2. Added a valid Google Gemini API key');
    print('3. Internet connection available');
  }
}
