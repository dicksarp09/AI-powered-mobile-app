import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Manages STT model downloads and storage
/// 
/// This utility helps download Whisper models from HuggingFace or other sources
/// and manages them in the app's documents directory.
class STTModelManager {
  static final Logger _logger = Logger('STTModelManager');
  
  static const String _modelsDirectory = 'stt_models';
  
  // Pre-configured Whisper models available for download
  static const Map<String, ModelInfo> availableModels = {
    'tiny': ModelInfo(
      name: 'tiny',
      description: 'Tiny model - fastest, lowest accuracy (39 MB)',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
      sizeBytes: 39000000,
    ),
    'tiny.en': ModelInfo(
      name: 'tiny.en',
      description: 'Tiny English model - optimized for English (39 MB)',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin',
      sizeBytes: 39000000,
    ),
    'base': ModelInfo(
      name: 'base',
      description: 'Base model - good balance of speed and accuracy (74 MB)',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
      sizeBytes: 74000000,
    ),
    'base.en': ModelInfo(
      name: 'base.en',
      description: 'Base English model - optimized for English (74 MB)',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin',
      sizeBytes: 74000000,
    ),
    'small': ModelInfo(
      name: 'small',
      description: 'Small model - better accuracy, slower (244 MB)',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
      sizeBytes: 244000000,
    ),
    'small.en': ModelInfo(
      name: 'small.en',
      description: 'Small English model - optimized for English (244 MB)',
      url: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin',
      sizeBytes: 244000000,
    ),
    'distil-small.en': ModelInfo(
      name: 'distil-small.en',
      description: 'Distilled Small English - very fast and accurate (66 MB)',
      url: 'https://huggingface.co/distil-whisper/distil-small.en/resolve/main/ggml-model.bin',
      sizeBytes: 66000000,
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
    return path.join(dir.path, 'ggml-$modelName.bin');
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

    _logger.info('Downloading model: ${info.name}');
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
      if (entity is File && entity.path.endsWith('.bin')) {
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
  /// - RAM < 4GB: tiny.en (fastest, smallest)
  /// - RAM 4-8GB: base.en (good balance)
  /// - RAM > 8GB: small.en or distil-small.en (best accuracy)
  String recommendModel(double ramGB) {
    if (ramGB < 4.0) {
      return 'tiny.en';
    } else if (ramGB <= 8.0) {
      return 'base.en';
    } else {
      return 'distil-small.en';
    }
  }
}

/// Information about an available model
class ModelInfo {
  final String name;
  final String description;
  final String url;
  final int sizeBytes;

  const ModelInfo({
    required this.name,
    required this.description,
    required this.url,
    required this.sizeBytes,
  });
}
