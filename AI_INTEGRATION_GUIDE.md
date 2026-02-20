# Real AI Model Integration Guide

Complete guide for integrating real STT (Speech-to-Text) and LLM (Large Language Model) into your Flutter app.

## Three Implementation Options

| Option | STT | LLM | Offline | Difficulty | Performance |
|--------|-----|-----|---------|------------|-------------|
| **1. Cloud APIs** | Google Speech | Gemini/ChatGPT | ❌ No | ⭐ Easy | ⭐⭐⭐ Excellent |
| **2. ONNX Runtime** | Whisper ONNX | Phi-2/3 ONNX | ✅ Yes | ⭐⭐ Medium | ⭐⭐ Good |
| **3. Native FFI** | whisper.cpp | llama.cpp | ✅ Yes | ⭐⭐⭐ Hard | ⭐⭐⭐ Excellent |

---

## Option 1: Cloud-Based (Easiest - Recommended for Starting)

Uses Google's speech recognition and Gemini API. Requires internet but easiest to implement.

### Setup

**pubspec.yaml:**
```yaml
dependencies:
  speech_to_text: ^6.6.0
  google_generative_ai: ^0.4.0
  record: ^5.0.4  # Keep for audio recording
```

**Implementation:**

```dart
// lib/src/services/real_ai_implementations.dart

import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:logging/logging.dart';
import 'dart:convert';

/// Cloud-based STT using Google's speech_to_text
class GoogleSTTService {
  static final Logger _logger = Logger('GoogleSTTService');
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;

  Future<void> initialize() async {
    _isInitialized = await _speech.initialize(
      onError: (error) => _logger.warning('STT Error: $error'),
      onStatus: (status) => _logger.fine('STT Status: $status'),
    );
  }

  Future<String> transcribeFromFile(String audioFilePath) async {
    // Note: speech_to_text works with live audio, not files
    // For file transcription, you'd need to:
    // 1. Use Google Cloud Speech-to-Text API
    // 2. Or use a different package
    
    _logger.info('For file transcription, use Google Cloud API');
    throw UnimplementedError('Use live recording or Google Cloud API');
  }

  Future<String> transcribeLive() async {
    if (!_isInitialized) await initialize();
    
    final completer = Completer<String>();
    String transcript = '';

    await _speech.listen(
      onResult: (result) {
        transcript = result.recognizedWords;
        if (result.finalResult) {
          completer.complete(transcript);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: 'en_US',
      onSoundLevelChange: (level) => _logger.fine('Sound level: $level'),
    );

    return completer.future;
  }

  Future<void> stop() async {
    await _speech.stop();
  }
}

/// Cloud-based LLM using Google Gemini
class GeminiLLMService {
  static final Logger _logger = Logger('GeminiLLMService');
  late GenerativeModel _model;
  
  // Get API key from: https://makersuite.google.com/app/apikey
  final String apiKey;

  GeminiLLMService({required this.apiKey}) {
    _model = GenerativeModel(
      model: 'gemini-pro',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.3,
        maxOutputTokens: 256,
      ),
    );
  }

  Future<Map<String, dynamic>> extractTasks(String transcript) async {
    _logger.info('Extracting tasks with Gemini');

    final prompt = '''You are an information extraction engine.

Extract actionable tasks from the text below and return ONLY valid JSON.

Text: $transcript

Return JSON in this exact format:
{
  "tasks": [
    {
      "title": "task description",
      "due_time": "when it's due or null",
      "priority": "low|medium|high"
    }
  ]
}

JSON:'''
;

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      
      final text = response.text ?? '{"tasks":[]}';
      _logger.info('Gemini response: $text');
      
      // Extract JSON from response
      final jsonStr = _extractJson(text);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      _logger.severe('Gemini error: $e');
      return {'tasks': []};
    }
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1) return '{"tasks":[]}';
    return text.substring(start, end + 1);
  }
}
```

### Usage

```dart
// In your main app
void main() async {
  // STT
  final sttService = GoogleSTTService();
  await sttService.initialize();
  
  // Start recording
  final transcript = await sttService.transcribeLive();
  print('Transcript: $transcript');
  
  // LLM
  final llmService = GeminiLLMService(
    apiKey: 'YOUR_GEMINI_API_KEY', // Get from Google AI Studio
  );
  
  final tasks = await llmService.extractTasks(transcript);
  print('Tasks: $tasks');
}
```

### Pros & Cons

✅ **Pros:**
- Very accurate (Google's best models)
- Easy to implement
- No model files to download
- Works immediately

❌ **Cons:**
- Requires internet connection
- API costs (though Gemini has free tier)
- Privacy concerns (audio sent to cloud)
- Latency (network round-trip)

---

## Option 2: ONNX Runtime (Offline)

Run quantized ONNX models locally. Good balance of offline capability and ease.

### Setup

**pubspec.yaml:**
```yaml
dependencies:
  onnxruntime: ^1.3.1
  # For audio processing
  wav: ^1.3.0
```

**Download Models:**

1. **STT Model (Whisper):**
   ```bash
   # Download quantized Whisper model
   wget https://huggingface.co/openai/whisper-tiny/resolve/main/onnx/whisper-tiny.onnx
   # Place in: assets/models/whisper-tiny.onnx
   ```

2. **LLM Model (Phi-2/3):**
   ```bash
   # Download quantized Phi model
   wget https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/cpu-int4-rtn-block-32/phi3-mini-int4.onnx
   # Place in: assets/models/phi3-mini.onnx
   ```

**Implementation:**

```dart
// lib/src/services/onnx_ai_service.dart

import 'package:onnxruntime/onnxruntime.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:logging/logging.dart';

class ONNXInferenceService {
  static final Logger _logger = Logger('ONNXInferenceService');
  OrtSession? _sttSession;
  OrtSession? _llmSession;

  Future<void> loadModels() async {
    // Copy models from assets to device
    final whisperModel = await _loadModelAsset('assets/models/whisper-tiny.onnx');
    final phiModel = await _loadModelAsset('assets/models/phi3-mini.onnx');

    // Initialize ONNX sessions
    _sttSession = OrtSession.fromFile(whisperModel);
    _llmSession = OrtSession.fromFile(phiModel);

    _logger.info('ONNX models loaded');
  }

  Future<File> _loadModelAsset(String assetPath) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${assetPath.split('/').last}');
    
    if (!await file.exists()) {
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer.asUint8List());
    }
    
    return file;
  }

  Future<String> transcribeAudio(List<double> audioData) async {
    if (_sttSession == null) throw StateError('Models not loaded');

    // Prepare input tensor
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      audioData,
      [1, audioData.length],
    );

    // Run inference
    final outputs = _sttSession!.run(
      RunOptions(),
      {'input': inputTensor},
    );

    // Process output
    final outputTensor = outputs[0] as OrtValueTensor;
    final tokens = outputTensor.value as List<List<int>>;
    
    // Convert tokens to text (simplified)
    return _tokensToText(tokens[0]);
  }

  String _tokensToText(List<int> tokens) {
    // Token to text conversion logic
    // This is simplified - real implementation needs tokenizer
    return tokens.map((t) => String.fromCharCode(t)).join();
  }

  Future<String> generateText(String prompt) async {
    if (_llmSession == null) throw StateError('Models not loaded');

    // Tokenize input
    final inputIds = _tokenize(prompt);
    
    // Prepare tensor
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputIds,
      [1, inputIds.length],
    );

    // Run inference
    final outputs = _llmSession!.run(
      RunOptions(),
      {'input': inputTensor},
    );

    // Decode output
    final outputTensor = outputs[0] as OrtValueTensor;
    final outputIds = outputTensor.value as List<List<int>>;
    
    return _detokenize(outputIds[0]);
  }

  List<int> _tokenize(String text) {
    // Simplified tokenization
    // Real implementation needs actual tokenizer (BPE, SentencePiece, etc.)
    return text.codeUnits;
  }

  String _detokenize(List<int> tokens) {
    return String.fromCharCodes(tokens);
  }

  void dispose() {
    _sttSession?.release();
    _llmSession?.release();
  }
}
```

### Note on ONNX Models

Running ONNX models for NLP is complex because you need:
1. **Tokenizer**: Convert text ↔ tokens (usually BPE or SentencePiece)
2. **Pre/Post-processing**: Handle model-specific formats
3. **Quantized models**: Converted to INT4/INT8 for mobile

**Pre-converted ONNX Models:**
- Microsoft's ONNX Runtime has examples: https://github.com/microsoft/onnxruntime-inference-examples
- Hugging Face Optimum: https://huggingface.co/docs/optimum/index

---

## Option 3: Native FFI (True Offline - Advanced)

Direct bindings to whisper.cpp and llama.cpp. Best performance, most complex.

### Architecture

```
Flutter (Dart)
    ↓ FFI (dart:ffi)
Native Code (C/C++)
    ↓ JNI (Android) / Framework (iOS)
whisper.cpp / llama.cpp
    ↓
GGML Models (GGUF format)
```

### Setup

**1. Download Pre-built Libraries:**

For Android:
```bash
# Download whisper.cpp Android libraries
mkdir -p android/app/src/main/jniLibs/arm64-v8a
curl -L https://github.com/ggerganov/whisper.cpp/releases/download/v1.5.4/whisper-android-arm64-v8a.zip -o whisper.zip
unzip whisper.zip -d android/app/src/main/jniLibs/arm64-v8a/
```

For iOS:
```bash
# Build llama.cpp for iOS
# Follow: https://github.com/ggerganov/llama.cpp/blob/master/build.md
```

**2. pubspec.yaml:**
```yaml
dependencies:
  ffi: ^2.1.0
  path_provider: ^2.1.2
```

**3. Create FFI Bindings:**

```dart
// lib/src/native/whisper_bindings.dart

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';

// Load native library
DynamicLibrary _whisperLib = Platform.isAndroid
    ? DynamicLibrary.open('libwhisper.so')
    : DynamicLibrary.process();

// Function signatures
typedef WhisperInitNative = Pointer<Void> Function(Pointer<Utf8> model_path);
typedef WhisperInit = Pointer<Void> Function(Pointer<Utf8> model_path);

final whisperInit = _whisperLib
    .lookup<NativeFunction<WhisperInitNative>>('whisper_init_from_file')
    .asFunction<WhisperInit>();

// More bindings...
// Full implementation requires all whisper.cpp C API bindings
```

### Complete Native Integration

This requires:
1. **CMakeLists.txt** modifications
2. **Android.mk** for NDK
3. **Podfile** changes for iOS
4. **Dart FFI** bindings for all C functions

**Recommended: Use Existing Packages**

Instead of building from scratch, look for these community packages:

```yaml
# Check if these exist on pub.dev
dependencies:
  # Community packages (check pub.dev for availability)
  flutter_whisper: any  # Check if available
  flutter_llama: any    # Check if available
```

**If not available, use:**

**Platform Channels** (Easier than FFI):

```dart
// Call native code through platform channels
class NativeAIService {
  static const platform = MethodChannel('com.ai/native_models');

  Future<String> transcribeWithWhisper(String audioPath) async {
    final result = await platform.invokeMethod('transcribe', {
      'audioPath': audioPath,
      'modelPath': 'whisper-tiny.ggml',
    });
    return result as String;
  }

  Future<String> generateWithLlama(String prompt) async {
    final result = await platform.invokeMethod('generate', {
      'prompt': prompt,
      'modelPath': 'phi3-mini.gguf',
    });
    return result as String;
  }
}
```

**Android Native Implementation:**

```kotlin
// android/app/src/main/kotlin/.../NativeAIModels.kt

class NativeAIModels {
    private var whisperContext: Pointer? = null
    private var llamaContext: Pointer? = null

    fun loadWhisperModel(modelPath: String) {
        whisperContext = whisper_init_from_file(modelPath)
    }

    fun transcribe(audioPath: String): String {
        // Load audio file
        val audioData = File(audioPath).readBytes()
        
        // Run whisper inference
        val params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        whisper_full(whisperContext, params, audioData, audioData.size)
        
        // Extract text
        val nSegments = whisper_full_n_segments(whisperContext)
        val text = StringBuilder()
        
        for (i in 0 until nSegments) {
            text.append(whisper_full_get_segment_text(whisperContext, i))
        }
        
        return text.toString()
    }
}
```

---

## Recommended: Hybrid Approach

Start with **Option 1 (Cloud)**, add **Option 3 (Native)** later:

```dart
class AIService {
  bool useOfflineModels = false;
  
  Future<String> transcribe(String audioPath) async {
    if (useOfflineModels) {
      return await _nativeWhisper.transcribe(audioPath);
    } else {
      return await _googleSTT.transcribeFromFile(audioPath);
    }
  }
  
  Future<Map<String, dynamic>> extractTasks(String transcript) async {
    if (useOfflineModels) {
      return await _nativeLLM.extractTasks(transcript);
    } else {
      return await _gemini.extractTasks(transcript);
    }
  }
}
```

---

## Quick Start (Copy-Paste)

### 1. Add Dependencies

```bash
# Option 1: Cloud (Easiest)
flutter pub add speech_to_text google_generative_ai

# Option 2: Offline (Medium)
flutter pub add onnxruntime

# Option 3: Native (Hardest)
# Requires manual native setup
```

### 2. Get API Keys

**For Google Gemini:**
1. Go to https://makersuite.google.com/app/apikey
2. Create API key
3. Add to your app (use secure storage!)

```dart
const String geminiApiKey = 'YOUR_API_KEY_HERE';
```

### 3. Implement Service

Use the code from **Option 1** above.

### 4. Test

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final aiService = RealAIService(
    geminiApiKey: 'YOUR_KEY_HERE',
  );
  
  // Test STT
  await aiService.startListening();
  await Future.delayed(Duration(seconds: 5));
  final transcript = await aiService.stopListening();
  print('Transcript: $transcript');
  
  // Test LLM
  final tasks = await aiService.extractTasks(transcript);
  print('Tasks: $tasks');
}
```

---

## Model Recommendations

### STT Models

| Model | Size | Accuracy | Speed | Best For |
|-------|------|----------|-------|----------|
| **whisper-tiny** | 39MB | Good | Very Fast | Low-end devices |
| **whisper-base** | 74MB | Better | Fast | General use |
| **whisper-small** | 244MB | Excellent | Medium | High accuracy |
| Google Cloud STT | Cloud | Best | Fast | Maximum accuracy |

### LLM Models

| Model | Size | Format | Device |
|-------|------|--------|--------|
| **Phi-3 Mini** | 2-4GB | GGUF/Q4 | Mid-range phones (4GB+ RAM) |
| **TinyLlama** | 638MB | GGUF/Q4 | Low-end phones (2GB+ RAM) |
| **Gemma 2B** | 1.5GB | GGUF/Q4 | Mid-range phones |
| **Llama 3 8B** | 4-5GB | GGUF/Q4 | High-end phones (6GB+ RAM) |

---

## Performance Optimization

### 1. Model Quantization

```bash
# Convert to 4-bit quantization (75% size reduction)
python convert-to-q4.py \
  --input model-f32.gguf \
  --output model-q4.gguf \
  --quantization q4_0
```

### 2. Memory Management

```dart
// Load model
await model.load();

try {
  // Run inference
  final result = await model.process(audio);
} finally {
  // Always unload
  await model.unload();
  
  // Force garbage collection hint
  await Future.delayed(Duration.zero);
}
```

### 3. Batch Processing

```dart
// Process multiple audio files in one wake cycle
final results = await Future.wait([
  processAudio(file1),
  processAudio(file2),
  processAudio(file3),
]);
```

---

## Troubleshooting

### "Model file not found"
```bash
# Ensure models are in assets and listed in pubspec.yaml
flutter pub get
flutter clean
flutter build apk --release
```

### "Out of memory"
```dart
// Use smaller models
// Unload models immediately after use
// Process audio in chunks
```

### "Slow inference"
```bash
# Use quantized models (Q4 instead of F32)
# Enable GPU acceleration if available
# Reduce max tokens
```

---

## Next Steps

1. **Start with Option 1** (Cloud) to get working quickly
2. **Add Option 2** (ONNX) for offline capability
3. **Eventually implement Option 3** (Native) for best performance

**Need Help?**
- Join Flutter Discord: https://discord.gg/flutter
- ONNX Runtime examples: https://github.com/microsoft/onnxruntime-inference-examples
- whisper.cpp: https://github.com/ggerganov/whisper.cpp
- llama.cpp: https://github.com/ggerganov/llama.cpp
