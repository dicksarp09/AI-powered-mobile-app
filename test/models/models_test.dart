import 'package:flutter_test/flutter_test.dart';
import 'package:device_profiler/device_profiler.dart';

void main() {
  group('GenerationConfig', () {
    test('should create with default values', () {
      const config = GenerationConfig();
      
      expect(config.temperature, equals(0.3));
      expect(config.topP, equals(0.9));
      expect(config.maxTokens, equals(256));
      expect(config.repetitionPenalty, equals(1.1));
    });

    test('should create with custom values', () {
      const config = GenerationConfig(
        temperature: 0.5,
        maxTokens: 512,
        topK: 50,
      );
      
      expect(config.temperature, equals(0.5));
      expect(config.maxTokens, equals(512));
      expect(config.topK, equals(50));
    });

    test('should copy with modified values', () {
      const config = GenerationConfig();
      final modified = config.copyWith(
        temperature: 0.7,
        maxTokens: 128,
      );
      
      expect(modified.temperature, equals(0.7));
      expect(modified.maxTokens, equals(128));
      expect(modified.topP, equals(0.9)); // Unchanged
    });

    test('jsonExtraction preset should have correct values', () {
      const config = GenerationConfig.jsonExtraction;
      
      expect(config.temperature, equals(0.3));
      expect(config.stopSequences, contains('}'));
    });

    test('strict preset should have lower temperature', () {
      const config = GenerationConfig.strict;
      
      expect(config.temperature, lessThan(GenerationConfig.jsonExtraction.temperature));
    });

    test('should convert to map correctly', () {
      const config = GenerationConfig(
        temperature: 0.4,
        topK: 40,
      );
      
      final map = config.toMap();
      
      expect(map['temperature'], equals(0.4));
      expect(map['top_k'], equals(40));
      expect(map['max_tokens'], equals(256));
    });
  });

  group('DeviceProfile', () {
    test('should create device profile', () {
      const profile = DeviceProfile(
        ramGB: 6.0,
        cpuCores: 8,
        batteryLevel: 80,
        isLowMemory: false,
      );
      
      expect(profile.ramGB, equals(6.0));
      expect(profile.cpuCores, equals(8));
      expect(profile.batteryLevel, equals(80));
      expect(profile.isLowMemory, isFalse);
    });

    test('should convert to and from map', () {
      const profile = DeviceProfile(
        ramGB: 4.5,
        cpuCores: 4,
        batteryLevel: 45,
        isLowMemory: true,
      );
      
      final map = profile.toMap();
      final restored = DeviceProfile.fromMap(map);
      
      expect(restored.ramGB, equals(profile.ramGB));
      expect(restored.cpuCores, equals(profile.cpuCores));
      expect(restored.batteryLevel, equals(profile.batteryLevel));
      expect(restored.isLowMemory, equals(profile.isLowMemory));
    });

    test('should implement equality correctly', () {
      const profile1 = DeviceProfile(
        ramGB: 8.0,
        cpuCores: 8,
        batteryLevel: 90,
        isLowMemory: false,
      );
      
      const profile2 = DeviceProfile(
        ramGB: 8.0,
        cpuCores: 8,
        batteryLevel: 90,
        isLowMemory: false,
      );
      
      expect(profile1, equals(profile2));
      expect(profile1.hashCode, equals(profile2.hashCode));
    });
  });

  group('ModelConfig', () {
    test('should create model config', () {
      const config = ModelConfig(
        sttModel: 'base.en',
        slmModel: 'phi3-mini-Q4',
        quantization: '4bit',
        maxTokens: 256,
        mode: 'batch',
      );
      
      expect(config.sttModel, equals('base.en'));
      expect(config.slmModel, equals('phi3-mini-Q4'));
      expect(config.quantization, equals('4bit'));
      expect(config.maxTokens, equals(256));
      expect(config.mode, equals('batch'));
    });

    test('fallback should return minimal config', () {
      final fallback = ModelConfig.fallback();
      
      expect(fallback.sttModel, equals('moonshine-tiny'));
      expect(fallback.slmModel, equals('tinyllama-q4'));
      expect(fallback.quantization, equals('4bit'));
      expect(fallback.maxTokens, equals(128));
      expect(fallback.mode, equals('batch'));
    });

    test('should convert to and from map', () {
      const config = ModelConfig(
        sttModel: 'small.en',
        slmModel: 'phi3-mini-Q8',
        quantization: '8bit',
        maxTokens: 512,
        mode: 'live',
      );
      
      final map = config.toMap();
      final restored = ModelConfig.fromMap(map);
      
      expect(restored.sttModel, equals(config.sttModel));
      expect(restored.slmModel, equals(config.slmModel));
      expect(restored.maxTokens, equals(config.maxTokens));
    });
  });
}
