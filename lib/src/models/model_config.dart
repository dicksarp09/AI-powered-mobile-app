/// Represents the AI model configuration based on device capabilities.
/// 
/// This configuration determines which models to load, their quantization
/// levels, and processing parameters based on the device's profile.
class ModelConfig {
  /// Speech-to-Text model variant to use
  /// Examples: "moonshine-tiny", "distil-small-int8", "distil-medium-int8"
  final String sttModel;
  
  /// Small Language Model variant to use
  /// Examples: "tinyllama-q4", "phi3-mini-q4", "phi3-mini-q8"
  final String slmModel;
  
  /// Quantization level for model inference
  /// Either "4bit" or "8bit"
  final String quantization;
  
  /// Maximum number of tokens for generation
  final int maxTokens;
  
  /// Processing mode - "batch" for conservative processing,
  /// "live" for real-time processing
  final String mode;

  const ModelConfig({
    required this.sttModel,
    required this.slmModel,
    required this.quantization,
    required this.maxTokens,
    required this.mode,
  });

  /// Creates a fallback configuration for the lowest-end devices
  /// or when errors occur during profiling
  factory ModelConfig.fallback() {
    return const ModelConfig(
      sttModel: 'moonshine-tiny',
      slmModel: 'tinyllama-q4',
      quantization: '4bit',
      maxTokens: 128,
      mode: 'batch',
    );
  }

  /// Creates a ModelConfig from a map (useful for caching/persistence)
  factory ModelConfig.fromMap(Map<String, dynamic> map) {
    return ModelConfig(
      sttModel: map['stt_model'] as String,
      slmModel: map['slm_model'] as String,
      quantization: map['quantization'] as String,
      maxTokens: map['max_tokens'] as int,
      mode: map['mode'] as String,
    );
  }

  /// Converts this configuration to a map
  Map<String, dynamic> toMap() {
    return {
      'stt_model': sttModel,
      'slm_model': slmModel,
      'quantization': quantization,
      'max_tokens': maxTokens,
      'mode': mode,
    };
  }

  @override
  String toString() {
    return 'ModelConfig(sttModel: $sttModel, slmModel: $slmModel, '
        'quantization: $quantization, maxTokens: $maxTokens, mode: $mode)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModelConfig &&
        other.sttModel == sttModel &&
        other.slmModel == slmModel &&
        other.quantization == quantization &&
        other.maxTokens == maxTokens &&
        other.mode == mode;
  }

  @override
  int get hashCode {
    return sttModel.hashCode ^
        slmModel.hashCode ^
        quantization.hashCode ^
        maxTokens.hashCode ^
        mode.hashCode;
  }
}
