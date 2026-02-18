import 'dart:async';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import '../models/models.dart';

/// Service responsible for profiling device capabilities and determining
/// the optimal AI model configuration.
/// 
/// This service gathers hardware metrics via platform channels and applies
/// deterministic rules to select appropriate models, quantization levels,
/// and processing parameters.
class DeviceProfileService {
  static const MethodChannel _channel =
      MethodChannel('com.device_profiler/platform');
  
  static final Logger _logger = Logger('DeviceProfileService');
  
  DeviceProfile? _cachedProfile;
  ModelConfig? _cachedConfig;
  
  /// Singleton instance
  static final DeviceProfileService _instance = DeviceProfileService._internal();
  
  factory DeviceProfileService() => _instance;
  
  DeviceProfileService._internal();

  /// Initializes the service and returns the model configuration.
  /// 
  /// This method should be called before loading any AI models.
  /// It gathers device metrics, applies selection rules, and returns
  /// the optimal configuration.
  Future<ModelConfig> initializeAndGetConfig() async {
    _logger.info('Initializing DeviceProfileService...');
    
    try {
      // Gather device profile from platform
      final profile = await _getDeviceProfile();
      _cachedProfile = profile;
      _logger.info('Device profile gathered: $profile');
      
      // Apply rules to determine configuration
      final config = _determineModelConfig(profile);
      _cachedConfig = config;
      _logger.info('Model configuration determined: $config');
      
      return config;
    } catch (e, stackTrace) {
      _logger.severe('Error during initialization: $e', e, stackTrace);
      _logger.warning('Falling back to minimum configuration');
      return ModelConfig.fallback();
    }
  }

  /// Gets the cached device profile, or null if not initialized
  DeviceProfile? get cachedProfile => _cachedProfile;
  
  /// Gets the cached model configuration, or null if not initialized
  ModelConfig? get cachedConfig => _cachedConfig;

  /// Gathers device metrics from the platform
  Future<DeviceProfile> _getDeviceProfile() async {
    _logger.fine('Requesting device metrics from platform...');
    
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceProfile');
      
      if (result == null) {
        throw PlatformException(
          code: 'NULL_RESULT',
          message: 'Platform returned null device profile',
        );
      }
      
      // Convert dynamic map to typed map
      final typedMap = Map<String, dynamic>.from(result);
      final profile = DeviceProfile.fromMap(typedMap);
      
      _logger.fine('Device metrics received: $profile');
      return profile;
    } on PlatformException catch (e) {
      _logger.severe('Platform error getting device profile: ${e.message}', e);
      rethrow;
    } catch (e) {
      _logger.severe('Unexpected error getting device profile: $e', e);
      rethrow;
    }
  }

  /// Determines the model configuration based on device profile rules
  ModelConfig _determineModelConfig(DeviceProfile profile) {
    _logger.info('Determining model configuration for device...');
    _logger.info('  RAM: ${profile.ramGB.toStringAsFixed(1)} GB');
    _logger.info('  CPU Cores: ${profile.cpuCores}');
    _logger.info('  Battery: ${profile.batteryLevel}%');
    _logger.info('  Low Memory: ${profile.isLowMemory}');

    // Start with base configuration based on RAM
    late ModelConfig config;
    
    if (profile.ramGB < 4.0) {
      _logger.info('RAM < 4GB detected - selecting entry-level configuration');
      config = const ModelConfig(
        sttModel: 'moonshine-tiny',
        slmModel: 'tinyllama-q4',
        quantization: '4bit',
        maxTokens: 128,
        mode: 'batch',
      );
    } else if (profile.ramGB >= 4.0 && profile.ramGB <= 8.0) {
      _logger.info('RAM between 4GB and 8GB detected - selecting mid-tier configuration');
      config = const ModelConfig(
        sttModel: 'distil-small-int8',
        slmModel: 'phi3-mini-q4',
        quantization: '4bit',
        maxTokens: 256,
        mode: 'batch',
      );
    } else {
      _logger.info('RAM > 8GB detected - selecting high-tier configuration');
      config = const ModelConfig(
        sttModel: 'distil-medium-int8',
        slmModel: 'phi3-mini-q8',
        quantization: '8bit',
        maxTokens: 512,
        mode: 'live',
      );
    }

    // Apply battery constraint
    if (profile.batteryLevel < 30) {
      _logger.info('Battery below 30% - applying battery conservation rules');
      config = _applyBatteryConstraints(config);
    }

    // Apply memory pressure constraint
    if (profile.isLowMemory) {
      _logger.warning('Low memory warning detected - applying emergency downgrades');
      config = _applyMemoryPressureDowngrade(config);
    }

    _logger.info('Final configuration selected:');
    _logger.info('  STT Model: ${config.sttModel}');
    _logger.info('  SLM Model: ${config.slmModel}');
    _logger.info('  Quantization: ${config.quantization}');
    _logger.info('  Max Tokens: ${config.maxTokens}');
    _logger.info('  Mode: ${config.mode}');

    return config;
  }

  /// Applies battery conservation rules to the configuration
  ModelConfig _applyBatteryConstraints(ModelConfig config) {
    _logger.info('Applying battery conservation: forcing batch mode and reducing tokens by 50%');
    
    return ModelConfig(
      sttModel: config.sttModel,
      slmModel: config.slmModel,
      quantization: config.quantization,
      maxTokens: (config.maxTokens * 0.5).round(),
      mode: 'batch',
    );
  }

  /// Applies emergency downgrades when memory pressure is detected
  ModelConfig _applyMemoryPressureDowngrade(ModelConfig config) {
    _logger.info('Applying memory pressure downgrade: smallest SLM, 4bit quantization, 128 max tokens');
    
    return ModelConfig(
      sttModel: config.sttModel,
      slmModel: 'tinyllama-q4',
      quantization: '4bit',
      maxTokens: 128,
      mode: 'batch',
    );
  }

  /// Refreshes the device profile and recalculates configuration.
  /// 
  /// This can be called periodically or when app returns to foreground
  /// to adapt to changing conditions (battery, memory pressure).
  Future<ModelConfig> refreshConfig() async {
    _logger.info('Refreshing device configuration...');
    _cachedProfile = null;
    _cachedConfig = null;
    return initializeAndGetConfig();
  }

  /// Sets up a listener for memory pressure events from the platform.
  /// 
  /// This allows the app to react to memory warnings in real-time.
  void setupMemoryPressureListener(void Function() onLowMemory) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLowMemory') {
        _logger.warning('Received low memory warning from platform');
        onLowMemory();
      }
    });
    _logger.info('Memory pressure listener registered');
  }
}
