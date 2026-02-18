# SLM (Small Language Model) Action Extraction Layer

This layer converts cleaned transcript text into structured JSON using quantized local language models.

## Architecture

```
Transcript Text → SlmActionExtractor → LlamaSLMBackend → Structured JSON
                                    ↑
                              llama_flutter (FFI)
                                    ↑
                              llama.cpp (C++ native)
```

## Quick Start

### 1. Download an SLM Model

```dart
import 'package:device_profiler/device_profiler.dart';

final manager = SlmModelManager();

// Download a model
final modelPath = await manager.downloadModel(
  'phi3-mini-Q4',
  onProgress: (progress) {
    print('Download: ${(progress * 100).toStringAsFixed(1)}%');
  },
);

print('Model downloaded to: $modelPath');
```

### 2. Extract Actions from Transcript

```dart
// Create extractor
final extractor = SlmActionExtractor(
  modelPath: modelPath,
  config: GenerationConfig.jsonExtraction,
);

// Extract from transcript
final result = await extractor.extract(
  'Remind me to call John tomorrow at 3pm, it\'s urgent',
);

print(result);
// Output:
// {
//   "tasks": [
//     {
//       "title": "Call John",
//       "due_time": "tomorrow at 3pm",
//       "priority": "high"
//     }
//   ]
// }
```

## Available Models

| Model | Size | RAM Required | Speed | Quality | Best For |
|-------|------|--------------|-------|---------|----------|
| `tinyllama-Q4` | 638 MB | 2-3 GB | Very Fast | Good | Low-end devices |
| `phi3-mini-Q4` | 2.3 GB | 4-6 GB | Fast | Very Good | Balanced performance |
| `phi3-mini-Q8` | 4.1 GB | 6-8 GB | Medium | Excellent | High-end devices |
| `gemma-2b-Q4` | 1.5 GB | 3-4 GB | Fast | Good | General use |
| `llama3-8b-Q4` | 4.7 GB | 6-8 GB | Medium | Excellent | Complex reasoning |

## Configuration

### Generation Parameters

```dart
final config = GenerationConfig(
  temperature: 0.3,        // Lower = more deterministic
  topP: 0.9,              // Nucleus sampling
  maxTokens: 256,         // Maximum output length
  repetitionPenalty: 1.1,  // Avoid repetition
  stopSequences: ['}'],    // Stop at JSON close
);
```

### Predefined Configs

```dart
// For JSON extraction (default)
GenerationConfig.jsonExtraction

// For strict deterministic output
GenerationConfig.strict
```

## Complete Workflow Example

```dart
import 'package:device_profiler/device_profiler.dart';

class CompleteWorkflow {
  final _audioService = AudioCaptureService();
  final _sttService = SpeechToTextService();
  final _sttManager = STTModelManager();
  final _slmManager = SlmModelManager();
  
  String? _sttModelPath;
  String? _slmModelPath;
  
  Future<void> initialize() async {
    // Get device profile
    final config = await DeviceProfileService().initializeAndGetConfig();
    
    // Download appropriate models
    final sttModel = _sttManager.recommendModel(config.ramGB);
    final slmModel = _slmManager.recommendModel(config.ramGB);
    
    _sttModelPath = await _sttManager.downloadModel(sttModel);
    _slmModelPath = await _slmManager.downloadModel(slmModel);
  }
  
  Future<Map<String, dynamic>> recordTranscribeAndExtract() async {
    // 1. Record audio
    await _audioService.startRecording();
    await Future.delayed(Duration(seconds: 5));
    final audioPath = await _audioService.stopRecording();
    
    // 2. Transcribe
    final transcript = await _sttService.transcribeBatch(
      audioFilePath: audioPath!,
      modelPath: _sttModelPath!,
    );
    
    // 3. Extract actions
    final extractor = SlmActionExtractor(modelPath: _slmModelPath!);
    final actions = await extractor.extract(transcript);
    
    return actions;
  }
}
```

## Output Schema

The extractor always returns valid JSON with this schema:

```json
{
  "tasks": [
    {
      "title": "string",
      "due_time": "string or null",
      "priority": "low | medium | high"
    }
  ]
}
```

### Example Outputs

**Single task:**
```json
{
  "tasks": [
    {
      "title": "Buy groceries",
      "due_time": "this evening",
      "priority": "medium"
    }
  ]
}
```

**Multiple tasks:**
```json
{
  "tasks": [
    {
      "title": "Email the report",
      "due_time": "tomorrow morning",
      "priority": "high"
    },
    {
      "title": "Schedule meeting",
      "due_time": "next week",
      "priority": "low"
    }
  ]
}
```

**No actionable items:**
```json
{
  "tasks": []
}
```

## Prompt Template

The extractor uses this strict prompt:

```
You are an information extraction engine.

Extract actionable tasks from the text below.

Rules:
- Output ONLY valid JSON.
- Do NOT include explanations.
- Do NOT include markdown.
- Do NOT include backticks.
- If no tasks exist, return: {"tasks":[]}
- All keys must exist.
- due_time must be null if not specified.
- priority must be one of: low, medium, high.
- No trailing text after closing brace.

Text:
[USER TRANSCRIPT]

JSON:
```

## Error Handling

The extractor is designed to never crash:

- Empty transcript → Returns `{"tasks": []}`
- Model load failure → Returns `{"tasks": []}`
- Invalid JSON output → Returns `{"tasks": []}`
- JSON parsing error → Returns `{"tasks": []}`

## Retry Logic

If the first generation produces invalid JSON, the extractor automatically retries once with a reminder:

```
[Original Prompt]

Reminder: Output valid JSON only.
JSON:
```

## Performance

- **Model Loading**: 2-5 seconds (first time)
- **Generation**: 1-3 seconds on mid-tier devices
- **Memory**: Model unloaded immediately after extraction
- **Battery**: Batch processing optimized for low power

## Model Management

### Check if Model Exists

```dart
final exists = await manager.isModelDownloaded('phi3-mini-Q4');
```

### List Downloaded Models

```dart
final models = await manager.listDownloadedModels();
```

### Delete Model

```dart
await manager.deleteModel('tinyllama-Q4');
```

### Get Storage Usage

```dart
final bytes = await manager.getTotalModelSize();
print('SLM Storage: ${(bytes / 1024 / 1024).toStringAsFixed(1)} MB');
```

## Best Practices

1. **Pre-download models** before they're needed
2. **Use appropriate models** for device capabilities
3. **Keep transcripts short** for faster processing
4. **Handle empty results** gracefully in UI
5. **Cache extraction results** if needed

## Troubleshooting

### Model Download Fails

- Check internet connection
- Verify sufficient storage (at least 2x model size free)
- Try a smaller model

### Generation is Slow

- Use Q4 quantized models instead of Q8
- Reduce max_tokens in config
- Use tinyllama for fastest results

### Poor Extraction Quality

- Use phi3-mini or llama3 models
- Ensure transcripts are clear
- Check generation temperature (lower = more deterministic)

### App Crashes on Start

- Verify model path is correct
- Check model file isn't corrupted
- Ensure sufficient RAM (2-3x model size)

## Advanced Usage

### Custom Generation Config

```dart
final extractor = SlmActionExtractor(
  modelPath: modelPath,
  config: GenerationConfig(
    temperature: 0.2,  // More deterministic
    maxTokens: 512,    // Allow longer outputs
    topP: 0.95,        // More diverse
  ),
);
```

### Using Custom Backend (Testing)

```dart
// For testing with mock backend
class MockSLMBackend implements SLMBackend {
  @override
  Future<GenerationResult> generate(String prompt, {GenerationConfig? config}) {
    return Future.value(GenerationResult(
      text: '{"tasks":[{"title":"Test","due_time":null,"priority":"medium"}]}',
    ));
  }
  
  // ... implement other methods
}

final extractor = SlmActionExtractor(
  modelPath: 'mock',
  backend: MockSLMBackend(),
);
```
