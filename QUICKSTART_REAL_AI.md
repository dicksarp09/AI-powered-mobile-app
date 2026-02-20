# 🚀 Quick Start - Real AI Integration

Get your AI-powered app working with real models in **5 minutes**.

## Option 1: Cloud AI (Fastest - Start Here!)

### Step 1: Get API Key (1 minute)

1. Go to https://makersuite.google.com/app/apikey
2. Click "Create API Key"
3. Copy your key (starts with `AIza...`)

### Step 2: Add Dependencies (1 minute)

```bash
cd "C:\Users\USER\Desktop\Workspace\AI-powered app"

# Add real AI packages
flutter pub add speech_to_text google_generative_ai

# Get dependencies
flutter pub get
```

### Step 3: Update pubspec.yaml (30 seconds)

Uncomment these lines in `pubspec.yaml`:

```yaml
dependencies:
  # ... other dependencies ...
  
  # AI Model Integration - Option 1: Cloud-based (Google)
  speech_to_text: ^6.6.0  # Google's speech recognition
  google_generative_ai: ^0.4.0  # Gemini API
```

### Step 4: Use Real AI (2 minutes)

Replace your main.dart or use this in your widget:

```dart
import 'package:flutter/material.dart';
import 'package:device_profiler/device_profiler.dart';
// After adding packages, also import:
// import 'package:speech_to_text/speech_to_text.dart' as stt;
// import 'package:google_generative_ai/google_generative_ai.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Notes',
      home: VoiceRecorderScreen(),
    );
  }
}

class VoiceRecorderScreen extends StatefulWidget {
  @override
  _VoiceRecorderScreenState createState() => _VoiceRecorderScreenState();
}

class _VoiceRecorderScreenState extends State<VoiceRecorderScreen> {
  // Use the real AI service (uncomment imports above first)
  // final RealAIService _aiService = RealAIService(
  //   geminiApiKey: 'YOUR_API_KEY_HERE', // <-- PASTE YOUR KEY HERE
  // );
  
  String _transcript = '';
  Map<String, dynamic> _tasks = {};
  bool _isRecording = false;

  Future<void> _startRecording() async {
    setState(() => _isRecording = true);
    
    // await _aiService.startRecording();
    
    // For demo without API key, use mock:
    await Future.delayed(Duration(seconds: 3));
    setState(() {
      _transcript = 'Remind me to call John tomorrow at 3pm';
      _isRecording = false;
    });
  }

  Future<void> _extractTasks() async {
    // final result = await _aiService.extractTasks(_transcript);
    
    // Mock result for demo:
    final result = {
      'tasks': [
        {
          'title': 'Call John',
          'due_time': 'tomorrow at 3pm',
          'priority': 'medium'
        }
      ]
    };
    
    setState(() => _tasks = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI Voice Notes')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Record Button
            ElevatedButton.icon(
              onPressed: _isRecording ? null : _startRecording,
              icon: Icon(_isRecording ? Icons.mic_off : Icons.mic),
              label: Text(_isRecording ? 'Recording...' : 'Tap to Record'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.blue,
                minimumSize: Size(double.infinity, 60),
              ),
            ),
            
            SizedBox(height: 20),
            
            // Transcript
            if (_transcript.isNotEmpty) ...[
              Text('Transcript:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_transcript),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: _extractTasks,
                child: Text('Extract Tasks'),
              ),
            ],
            
            SizedBox(height: 20),
            
            // Tasks
            if (_tasks.isNotEmpty) ...[
              Text('Extracted Tasks:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...(_tasks['tasks'] as List).map((task) => Card(
                child: ListTile(
                  title: Text(task['title']),
                  subtitle: Text('Due: ${task['due_time'] ?? 'Not specified'}'),
                  trailing: Chip(
                    label: Text(task['priority']),
                    backgroundColor: task['priority'] == 'high' 
                        ? Colors.red.shade100 
                        : Colors.blue.shade100,
                  ),
                ),
              )).toList(),
            ],
          ],
        ),
      ),
    );
  }
}
```

### Step 5: Run (30 seconds)

```bash
flutter run
```

Tap the microphone button → Speak → See transcription → Tap "Extract Tasks" → See structured tasks!

---

## 🎯 What You Get

### With Real AI (Cloud):
- ✅ **Accurate speech recognition** (Google's best models)
- ✅ **Smart task extraction** (Gemini understands context)
- ✅ **Works immediately** (no model downloads)
- ❌ **Requires internet** (cloud API calls)
- ❌ **API costs** (free tier: 60 requests/minute)

### Current State (Stubs):
- ✅ **Compiles and runs**
- ✅ **Tests pass**
- ✅ **Architecture complete**
- ❌ **Mock AI responses** (not real transcription/extraction)

---

## 🔧 Troubleshooting

### "Package not found"
```bash
flutter clean
flutter pub get
```

### "API key invalid"
- Check you copied the full key (starts with `AIza`)
- Ensure key has "Generative Language API" enabled
- Get new key if needed

### "Speech recognition not working"
- Android: Add to `AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  <uses-permission android:name="android.permission.INTERNET" />
  ```
- iOS: Add to `Info.plist`:
  ```xml
  <key>NSMicrophoneUsageDescription</key>
  <string>Need microphone for speech recognition</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Need speech recognition for voice notes</string>
  ```

### "Build errors after adding packages"
```bash
flutter clean
flutter pub get
cd android && ./gradlew clean && cd ..
flutter run
```

---

## 📚 Next Steps

### To Make It Real (Replace Stubs):

1. **Open** `lib/src/services/real_ai_service.dart`
2. **Uncomment** the imports at the top:
   ```dart
   import 'package:speech_to_text/speech_to_text.dart' as stt;
   import 'package:google_generative_ai/google_generative_ai.dart';
   ```
3. **Uncomment** the real implementation code (marked with `// In real implementation:`)
4. **Replace** `'YOUR_API_KEY_HERE'` with your actual Gemini API key
5. **Remove** the mock/demo code

### For Offline AI (Advanced):

See `AI_INTEGRATION_GUIDE.md` for:
- ONNX Runtime setup
- Native whisper.cpp integration
- Local LLM deployment

---

## 💡 Pro Tips

1. **Start with Cloud**: Get it working first, then add offline capability
2. **Secure API Key**: Don't commit your key to GitHub! Use environment variables
3. **Test on Real Device**: Simulators don't support microphone well
4. **Handle Errors**: Wrap API calls in try-catch blocks
5. **Rate Limiting**: Free tier has limits, add retry logic

---

## 🎓 Learning Path

**Beginner:**
1. ✅ Current state (stubs + architecture)
2. ➡️ Add cloud AI (this guide)
3. ➡️ Build complete UI
4. ➡️ Add local storage

**Advanced:**
1. ➡️ Integrate native models (whisper.cpp)
2. ➡️ Run LLMs locally (llama.cpp)
3. ➡️ Optimize for low-end devices
4. ➡️ Production deployment

---

## 🆘 Need Help?

- **Flutter Issues**: https://flutter.dev/docs
- **Gemini API**: https://ai.google.dev/tutorials
- **Speech Package**: https://pub.dev/packages/speech_to_text

**You're 5 minutes away from a working AI-powered app! 🚀**
