import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Manages SLM (Small Language Model) downloads and storage
/// 
/// This utility helps download quantized models from HuggingFace or other sources
/// and manages them in the app's documents directory.
class SlmModelManager {
  static final Logger _logger = Logger('SlmModelManager');
  
  static const String _modelsDirectory = 'slm_models';
  
  // Pre-configured SLM models available for download
  static const Map<String, SlmModelInfo> availableModels = {
    // Phi-3 Mini models - best balance of size and quality
    'phi3-mini-Q4': SlmModelInfo(
      name: 'phi3-mini-Q4',
      description: 'Phi-3 Mini Q4 - 3.8B params, 2.3GB, good quality',
      url: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q4.gguf',
      sizeBytes: 2300000000,
      quantLevel: 'Q4',
      parameters: '3.8B',
    ),
    'phi3-mini-Q8': SlmModelInfo(
      name: 'phi3-mini-Q8',
      description: 'Phi-3 Mini Q8 - 3.8B params, 4.1GB, best quality',
      url: 'https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q8.gguf',
      sizeBytes: 4100000000,
      quantLevel: 'Q8',
      parameters: '3.8B',
    ),
    // TinyLlama - smallest, fastest
    'tinyllama-Q4': SlmModelInfo(
      name: 'tinyllama-Q4',
      description: 'TinyLlama Q4 - 1.1B params, 638MB, very fast',
      url: 'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
      sizeBytes: 638000000,
      quantLevel: 'Q4',
      parameters: '1.1B',
    ),
    // Gemma 2B - Google's small model
    'gemma-2b-Q4': SlmModelInfo(
      name: 'gemma-2b-Q4',
      description: 'Gemma 2B Q4 - 2B params, 1.5GB, good for extraction',
      url: 'https://huggingface.co/lmstudio-community/gemma-2b-it-GGUF/resolve/main/gemma-2b-it-Q4_K_M.gguf',
      sizeBytes: 1500000000,
      quantLevel: 'Q4',
      parameters: '2B',
    ),
    // Llama 3 8B - larger but very capable
    'llama3-8b-Q4': SlmModelInfo(
      name: 'llama3-8b-Q4',
      description: 'Llama 3 8B Q4 - 8B params, 4.7GB, very capable',
      url: 'https://huggingface.co/lmstudio-community/Meta-Llama-3-8B-Instruct-GGUF/resolve/main/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf',
      sizeBytes: 4700000000,
      quantLevel: 'Q4',
      parameters: '8B',
    ),
  };

  /// Gets the directory where models are stored
  Future<Directory> get modelsDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory(path.join(appDir.path, _modelsDirectory));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  /// Checks if a model is already downloaded
  Future<bool> isModelDownloaded(String modelName) async {
    final modelPath = await getModelPath(modelName);
    if (modelPath == null) return false;
    return File(modelPath).existsSync();
  }

  /// Gets the local path for a model
  Future<String?> getModelPath(String modelName) async {
    final info = availableModels[modelName];
    if (info == null) return null;
    
    final dir = await modelsDirectory;
    return path.join(dir.path, '${info.name}.gguf');
  }

  /// Downloads a model with progress reporting
  /// 
  /// [modelName] must be one of the keys in [availableModels]
  /// [onProgress] is called with download progress (0.0 to 1.0)
  Future<String> downloadModel(
    String modelName, {
    void Function(double progress)? onProgress,
  }) async {
    final info = availableModels[modelName];
    if (info == null) {
      throw ArgumentError('Unknown model: $modelName');
    }

    _logger.info('Downloading SLM model: ${info.name}');
    _logger.info('  URL: ${info.url}');
    _logger.info('  Size: ${(info.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB');

    final modelPath = await getModelPath(modelName);
    if (modelPath == null) {
      throw StateError('Could not determine model path');
    }

    // Check if already downloaded
    if (await File(modelPath).exists()) {
      _logger.info('Model already downloaded: $modelPath');
      return modelPath;
    }

    try {
      final request = http.Request('GET', Uri.parse(info.url));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download model: HTTP ${response.statusCode}',
          uri: Uri.parse(info.url),
        );
      }

      final contentLength = response.contentLength ?? info.sizeBytes;
      final file = File(modelPath);
      final sink = file.openWrite();

      var receivedBytes = 0;
      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          final progress = receivedBytes / contentLength;
          onProgress?.call(progress);
          _logger.fine('Download progress: ${(progress * 100).toStringAsFixed(1)}%');
        },
        onDone: () async {
          await sink.close();
          _logger.info('Model downloaded successfully: $modelPath');
        },
        onError: (error) async {
          await sink.close();
          await file.delete();
          throw error;
        },
        cancelOnError: true,
      ).asFuture();

      return modelPath;
    } catch (e) {
      _logger.severe('Failed to download model: $e');
      // Clean up partial download
      final file = File(modelPath);
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  /// Deletes a downloaded model
  Future<void> deleteModel(String modelName) async {
    final modelPath = await getModelPath(modelName);
    if (modelPath == null) return;

    final file = File(modelPath);
    if (await file.exists()) {
      await file.delete();
      _logger.info('Deleted model: $modelName');
    }
  }

  /// Lists all downloaded models
  Future<List<String>> listDownloadedModels() async {
    final dir = await modelsDirectory;
    if (!await dir.exists()) return [];

    final models = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.gguf')) {
        final name = path.basename(entity.path);
        models.add(name);
      }
    }
    return models;
  }

  /// Gets the total size of all downloaded models
  Future<int> getTotalModelSize() async {
    final dir = await modelsDirectory;
    if (!await dir.exists()) return 0;

    var totalSize = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// Recommends a model based on device capabilities
  /// 
  /// - RAM < 4GB: tinyllama-Q4 (fastest, smallest)
  /// - RAM 4-8GB: phi3-mini-Q4 (good balance)
  /// - RAM > 8GB: phi3-mini-Q8 (best quality)
  String recommendModel(double ramGB) {
    if (ramGB < 4.0) {
      return 'tinyllama-Q4';
    } else if (ramGB <= 8.0) {
      return 'phi3-mini-Q4';
    } else {
      return 'phi3-mini-Q8';
    }
  }
}

/// Information about an available SLM model
class SlmModelInfo {
  final String name;
  final String description;
  final String url;
  final int sizeBytes;
  final String quantLevel;
  final String parameters;

  const SlmModelInfo({
    required this.name,
    required this.description,
    required this.url,
    required this.sizeBytes,
    required this.quantLevel,
    required this.parameters,
  });
}
