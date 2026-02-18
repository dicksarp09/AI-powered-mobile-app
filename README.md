# Device & Resource Profiling Layer

This Flutter package provides device profiling capabilities for offline-first mobile AI applications.

## Usage

```dart
import 'package:device_profiler/device_profiler.dart';

// Initialize and get configuration
final config = await DeviceProfileService().initializeAndGetConfig();

// Use the configuration
print(config.sttModel);      // "distil-small-int8"
print(config.slmModel);      // "phi3-mini-q4"
print(config.quantization);  // "4bit"
print(config.maxTokens);     // 256
print(config.mode);          // "batch"
```

## Model Selection Rules

The service automatically selects models based on device capabilities:

### RAM-based Selection
- **< 4GB**: Entry-level (moonshine-tiny, tinyllama-q4)
- **4-8GB**: Mid-tier (distil-small-int8, phi3-mini-q4)
- **> 8GB**: High-tier (distil-medium-int8, phi3-mini-q8)

### Battery Conservation
- When battery < 30%: Forces batch mode and reduces max_tokens by 50%

### Memory Pressure
- When low memory warning triggers: Downgrades to smallest SLM, forces 4bit, sets max_tokens to 128

## Architecture

- `DeviceProfile` - Device hardware metrics (RAM, CPU cores, battery, memory status)
- `ModelConfig` - AI model configuration (models, quantization, tokens, mode)
- `DeviceProfileService` - Main service that gathers metrics and applies selection rules

## Platform Support

- Android (Kotlin) - Uses ActivityManager for memory, BatteryManager for battery
- iOS (Swift) - Uses ProcessInfo for hardware, DispatchSourceMemoryPressure for memory warnings
