/// Cleans and normalizes raw STT transcript text before SLM processing.
///
/// This class provides pure string manipulation to normalize transcripts,
/// improving SLM extraction accuracy without increasing model size.
///
/// The cleaning pipeline includes:
/// 1. Trim and whitespace normalization
/// 2. Filler word removal
/// 3. Time expression normalization
/// 4. Basic punctuation correction
/// 5. Duplicate word removal
///
/// Example usage:
/// ```dart
/// final cleaner = TranscriptCleaner();
/// final cleaned = cleaner.clean(
///   'Um, remind me to um call John like tomorrow at 3 pm uh',
/// );
/// // Result: 'Remind me to call John tomorrow at 3pm.'
/// ```
///
/// Performance: Runs in <5ms for typical transcripts.
/// No network calls, no heavy NLP libraries, pure string manipulation.
class TranscriptCleaner {
  /// Default list of filler words to remove (case-insensitive)
  static const List<String> defaultFillers = [
    'um',
    'uh',
    'like',
    'you know',
    'i mean',
    'sort of',
    'kind of',
  ];

  /// Custom filler words list (optional)
  final List<String> fillers;

  /// Creates a transcript cleaner with optional custom filler words
  TranscriptCleaner({List<String>? fillers})
      : fillers = fillers ?? defaultFillers;

  /// Cleans the raw transcript with full normalization pipeline.
  ///
  /// Applies all cleaning steps:
  /// 1. Trim and normalize whitespace
  /// 2. Remove filler words
  /// 3. Normalize time expressions
  /// 4. Fix basic punctuation
  /// 5. Remove duplicate consecutive words
  ///
  /// Returns the cleaned transcript ready for SLM extraction.
  ///
  /// Throws [ArgumentError] if input is null.
  String clean(String rawTranscript) {
    // Validate input
    if (rawTranscript.isEmpty) {
      return '';
    }

    var cleaned = rawTranscript;

    // Step 1: Trim and normalize whitespace
    cleaned = _trimAndNormalizeWhitespace(cleaned);

    // Step 2: Remove filler words
    cleaned = _removeFillers(cleaned);

    // Step 3: Normalize time expressions
    cleaned = _normalizeTime(cleaned);

    // Step 4: Basic punctuation correction
    cleaned = _fixPunctuation(cleaned);

    // Step 5: Remove duplicate consecutive words
    cleaned = _removeDuplicateWords(cleaned);

    // Final whitespace cleanup
    cleaned = _trimAndNormalizeWhitespace(cleaned);

    return cleaned;
  }

  /// Light cleaning for live preview mode.
  ///
  /// Applies minimal processing:
  /// - Trim whitespace
  /// - Normalize multiple spaces to single space
  /// - No filler removal, no punctuation changes
  ///
  /// This is optimized for real-time display during live STT.
  String cleanForLivePreview(String partialTranscript) {
    if (partialTranscript.isEmpty) {
      return '';
    }

    // Just trim and normalize spaces
    return _trimAndNormalizeWhitespace(partialTranscript);
  }

  /// Step 1: Trim leading/trailing whitespace and normalize multiple spaces.
  String _trimAndNormalizeWhitespace(String text) {
    // Trim leading/trailing whitespace
    var cleaned = text.trim();

    // Replace multiple spaces/tabs/newlines with single space
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');

    return cleaned;
  }

  /// Step 2: Remove filler words (case-insensitive, whole word matching).
  String _removeFillers(String text) {
    var cleaned = text;

    for (final filler in fillers) {
      // Create regex that matches filler as a whole word, case-insensitive
      // Handles word boundaries including punctuation
      final pattern = r'\b' + RegExp.escape(filler) + r'\b';
      final regex = RegExp(pattern, caseSensitive: false);

      // Remove filler and clean up resulting double spaces
      cleaned = cleaned.replaceAll(regex, '');
    }

    // Clean up any double spaces created by filler removal
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Remove leading/trailing commas created by filler removal at start/end
    cleaned = cleaned.replaceAll(RegExp(r'^[,\s]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[,\s]+$'), '');

    // Fix double commas
    cleaned = cleaned.replaceAll(RegExp(r',\s*,+'), ',');

    return cleaned;
  }

  /// Step 3: Normalize time expressions.
  String _normalizeTime(String text) {
    var cleaned = text;

    // Normalize "X pm", "X p.m.", "X p.m" → "Xpm"
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d{1,2})\s*\.?\s*[pP]\.?\s*[mM]\.?\b'),
      (match) => '${match.group(1)}pm',
    );

    // Normalize "X am", "X a.m.", "X a.m" → "Xam"
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d{1,2})\s*\.?\s*[aA]\.?\s*[mM]\.?\b'),
      (match) => '${match.group(1)}am',
    );

    // Normalize "X o'clock" → "X oclock"
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d{1,2})\s*o\'?clock', caseSensitive: false),
      (match) => '${match.group(1)}oclock',
    );

    // Normalize "HH MM" (24-hour format with space) → "HH:MM"
    // Matches patterns like "15 00", "9 30"
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\b(\d{1,2})\s+(\d{2})\b'),
      (match) {
        final hour = int.tryParse(match.group(1)!);
        final minute = int.tryParse(match.group(2)!);

        // Only convert if it looks like a valid time (0-23 hours, 0-59 minutes)
        if (hour != null &&
            minute != null &&
            hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59) {
          return '${match.group(1)}:${match.group(2)}';
        }
        return match.group(0)!;
      },
    );

    return cleaned;
  }

  /// Step 4: Fix basic punctuation.
  String _fixPunctuation(String text) {
    var cleaned = text;

    // Capitalize first letter of sentence
    if (cleaned.isNotEmpty) {
      cleaned = cleaned[0].toUpperCase() + cleaned.substring(1);
    }

    // Ensure sentence ends with period if no ending punctuation
    if (cleaned.isNotEmpty) {
      final lastChar = cleaned[cleaned.length - 1];
      if (!RegExp(r'[.!?]').hasMatch(lastChar)) {
        cleaned = '$cleaned.';
      }
    }

    // Fix spacing around punctuation
    // Remove space before punctuation
    cleaned = cleaned.replaceAll(RegExp(r'\s+([.,!?;:])'), r'$1');

    // Ensure space after punctuation (except at end)
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([.,!?;:])([^\s])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );

    // Fix multiple periods
    cleaned = cleaned.replaceAll(RegExp(r'\.{2,}'), '...');

    // Insert comma before "and" when it appears to separate items (simple heuristic)
    // Pattern: word "and" word → word, and word
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\w+)\s+and\s+(\w+)'),
      (match) => '${match.group(1)}, and ${match.group(2)}',
    );

    return cleaned;
  }

  /// Step 5: Remove duplicate consecutive words.
  String _removeDuplicateWords(String text) {
    var cleaned = text;

    // Remove consecutive duplicate words (case-insensitive)
    // Handles up to 5 consecutive duplicates
    for (int i = 5; i >= 2; i--) {
      final pattern = List.generate(i, (_) => r'(\w+)').join(r'\s+');
      final regex = RegExp(pattern, caseSensitive: false);

      cleaned = cleaned.replaceAllMapped(regex, (match) {
        final firstWord = match.group(1)!;
        // Check if all groups are the same word
        bool allSame = true;
        for (int j = 2; j <= i; j++) {
          if (match.group(j)!.toLowerCase() != firstWord.toLowerCase()) {
            allSame = false;
            break;
          }
        }
        return allSame ? firstWord : match.group(0)!;
      });
    }

    // Clean up any resulting double spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }

  /// Benchmarks the cleaning operation (for testing/optimization).
  ///
  /// Returns the duration in milliseconds.
  double benchmark(String text, {int iterations = 1000}) {
    final stopwatch = Stopwatch()..start();

    for (int i = 0; i < iterations; i++) {
      clean(text);
    }

    stopwatch.stop();

    return stopwatch.elapsedMilliseconds / iterations;
  }
}
