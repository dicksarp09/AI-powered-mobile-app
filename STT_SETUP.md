# STT Backend Setup Guide

This project includes a complete Speech-to-Text backend using Whisper (whisper.cpp).

## Available Models

The following models are pre-configured and can be downloaded automatically:

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| `tiny` | 39 MB | Fastest | Basic | Low-end devices |
| `tiny.en` | 39 MB | Fastest | Basic | English only, low-end |
| `base` | 74 MB | Fast | Good | Balanced performance |
| `base.en` | 74 MB | Fast | Good | English only |
| `small` | 244 MB | Medium | Better | High-end devices |
| `small.en` | 244 MB | Medium | Better | English only |
| `distil-small.en` | 66 MB | Very Fast | Better | Best for English |

## Quick Start

### 1. Download a Model

```dart
import 'package:device_profiler/device_profiler.dart';

final modelManager = STTModelManager();

// Download a model (e.g., tiny.en for testing)
final modelPath = await modelManager.downloadModel(
  'tiny.en',
  onProgress: (progress) {
    print('Download: ${(progress * 100).toStringAsFixed(1)}%');
  },
);

print('Model downloaded to: $modelPath');
```

### 2. Transcribe Audio

```dart
// Using batch transcription (recommended)
final stt = SpeechToTextService();

final transcript = await stt.transcribeBatch(
  audioFilePath: '/path/to/audio.wav',
  modelPath: modelPath,
);

print('Transcript: $transcript');
```

### 3. Or Use Live Streaming

```dart
final stream = stt.transcribeLive(
  audioStream: audioByteStream,  // From microphone
  modelPath: modelPath,
);

stream.listen(
  (partial) => print('Partial: $partial'),
  onDone: () => print('Transcription complete'),
);
```

## Integration Example

Complete workflow with audio capture:

```dart
import 'package:device_profiler/device_profiler.dart';

class SpeechRecognitionWorkflow {
  final _audioService = AudioCaptureService();
  final _sttService = SpeechToTextService();
  final _modelManager = STTModelManager();
  
  String? _modelPath;
  
  Future<void> initialize() async {
    // Get device profile to choose appropriate model
    final config = await DeviceProfileService().initializeAndGetConfig();
    
    // Recommend model based on RAM
    final recommendedModel = _modelManager.recommendModel(
      config.ramGB,
    );
    
    // Download if not already present
    _modelPath = await _modelManager.downloadModel(recommendedModel);
  }
  
  Future<String> recordAndTranscribe() async {
    // Start recording
    await _audioService.startRecording();
    
    // Wait for user to stop (in real app, use UI button)
    await Future.delayed(Duration(seconds: 5));
    
    // Stop and get file
    final audioPath = await _audioService.stopRecording();
    if (audioPath == null) throw Exception('Recording failed');
    
    // Transcribe
    final transcript = await _sttService.transcribeBatch(
      audioFilePath: audioPath,
      modelPath: _modelPath!,
    );
    
    return transcript;
  }
  
  void dispose() {
    _audioService.dispose();
    _sttService.dispose();
  }
}
```

## Model Management

### Check if Model Exists

```dart
final isDownloaded = await modelManager.isModelDownloaded('base.en');
```

### List Downloaded Models

```dart
final models = await modelManager.listDownloadedModels();
for (final model in models) {
  print('Downloaded: $model');
}
```

### Delete a Model

```dart
await modelManager.deleteModel('tiny.en');
```

### Get Total Storage Used

```dart
final totalBytes = await modelManager.getTotalModelSize();
print('Total: ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB');
```

## Supported Audio Formats

The STT backend expects:
- **Format**: WAV (PCM)
- **Sample Rate**: 16,000 Hz (16kHz)
- **Channels**: Mono (1 channel)
- **Bit Depth**: 16-bit

The `AudioCaptureService` automatically records in this format.

## Performance Tips

1. **Use smaller models on low-end devices** (tiny, base)
2. **Use distilled models for best speed/accuracy** (distil-small.en)
3. **Pre-download models** before they're needed
4. **Always unload models** after transcription (handled automatically)
5. **Batch mode is more efficient** than live streaming

## Troubleshooting

### Model Download Fails

- Check internet connection
- Verify sufficient storage space
- Try a different model

### Transcription is Slow

- Use a smaller model (tiny instead of small)
- Ensure device has sufficient RAM
- Close other apps to free resources

### Poor Accuracy

- Use a larger model (small instead of base)
- Ensure clear audio recording
- Check microphone quality
- Use English-specific models for English audio

### App Crashes on Start

- Ensure models are downloaded before use
- Check that model path is valid
- Verify audio file exists and is valid WAV

## Architecture

```
Audio File → WhisperSTTBackend → Transcription
                  ↑
         whisper_flutter (FFI)
                  ↑
         whisper.cpp (native)
```

The backend uses:
- `whisper_flutter`: Dart bindings for whisper.cpp
- `whisper.cpp`: High-performance C++ implementation
- FFI: Direct native communication (no platform channels)

## License

Whisper models are subject to their respective licenses. Most are MIT or Apache 2.0 licensed.
