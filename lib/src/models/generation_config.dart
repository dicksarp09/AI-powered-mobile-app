/// Configuration for text generation parameters
/// 
/// Used to control the behavior of SLM generation, ensuring
/// deterministic and structured output.
class GenerationConfig {
  /// Controls randomness: 0 = deterministic, 1 = very random
  /// For structured extraction, keep low (0.2-0.4)
  final double temperature;
  
  /// Nucleus sampling: probability mass to consider
  final double topP;
  
  /// Maximum tokens to generate
  final int maxTokens;
  
  /// Penalize repetition (1.0 = no penalty)
  final double repetitionPenalty;
  
  /// Stop sequences to end generation
  final List<String> stopSequences;
  
  /// Top-k sampling: consider only top k tokens
  final int? topK;
  
  /// Number of tokens to predict ahead
  final int? nPredict;

  const GenerationConfig({
    this.temperature = 0.3,
    this.topP = 0.9,
    this.maxTokens = 256,
    this.repetitionPenalty = 1.1,
    this.stopSequences = const [],
    this.topK,
    this.nPredict,
  });

  /// Default config for structured JSON extraction
  static const GenerationConfig jsonExtraction = GenerationConfig(
    temperature: 0.3,
    topP: 0.9,
    maxTokens: 256,
    repetitionPenalty: 1.1,
    stopSequences: ['}'],
  );

  /// Conservative config for strict deterministic output
  static const GenerationConfig strict = GenerationConfig(
    temperature: 0.2,
    topP: 0.8,
    maxTokens: 128,
    repetitionPenalty: 1.2,
    stopSequences: ['}'],
  );

  /// Copy with modified values
  GenerationConfig copyWith({
    double? temperature,
    double? topP,
    int? maxTokens,
    double? repetitionPenalty,
    List<String>? stopSequences,
    int? topK,
    int? nPredict,
  }) {
    return GenerationConfig(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
      stopSequences: stopSequences ?? this.stopSequences,
      topK: topK ?? this.topK,
      nPredict: nPredict ?? this.nPredict,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'temperature': temperature,
      'top_p': topP,
      'max_tokens': maxTokens,
      'repetition_penalty': repetitionPenalty,
      'stop_sequences': stopSequences,
      if (topK != null) 'top_k': topK,
      if (nPredict != null) 'n_predict': nPredict,
    };
  }

  @override
  String toString() {
    return 'GenerationConfig(temperature: $temperature, topP: $topP, '
        'maxTokens: $maxTokens, repetitionPenalty: $repetitionPenalty)';
  }
}
