import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'src/models/models.dart';
import 'src/services/services.dart';

/// Example usage demonstrating the DeviceProfilerService
/// 
/// This is not a UI - just showing how to use the API
void main() async {
  // Setup logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  // Initialize and get configuration
  final service = DeviceProfileService();
  
  // This is the main API the rest of your app will use
  final config = await service.initializeAndGetConfig();
  
  // Use the configuration to load appropriate models
  debugPrint('Ready to load models:');
  debugPrint('STT: ${config.sttModel}');
  debugPrint('SLM: ${config.slmModel}');
  debugPrint('Quantization: ${config.quantization}');
  debugPrint('Max Tokens: ${config.maxTokens}');
  debugPrint('Mode: ${config.mode}');
}
