import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

/// Exception thrown when storage operations fail
class StorageException implements Exception {
  final String message;
  final String? operation;
  StorageException(this.message, {this.operation});
  @override
  String toString() => 'StorageException: $message${operation != null ? ' (during $operation)' : ''}';
}

/// Represents a stored note with all metadata
class Note {
  final String noteId;
  final String transcript;
  final Map<String, dynamic> extractedJson;
  final String? audioFilePath;
  final DateTime timestamp;
  final Map<String, dynamic>? userEdits;
  final List<String> searchTokens;

  Note({
    required this.noteId,
    required this.transcript,
    required this.extractedJson,
    this.audioFilePath,
    required this.timestamp,
    this.userEdits,
    List<String>? searchTokens,
  }) : searchTokens = searchTokens ?? _generateSearchTokens(transcript);

  /// Converts Note to Map for Hive storage
  Map<String, dynamic> toMap() {
    return {
      'noteId': noteId,
      'transcript': transcript,
      'extractedJson': jsonEncode(extractedJson),
      'audioFilePath': audioFilePath,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'userEdits': userEdits != null ? jsonEncode(userEdits) : null,
      'searchTokens': searchTokens,
    };
  }

  /// Creates Note from Map (Hive storage)
  factory Note.fromMap(Map<dynamic, dynamic> map) {
    return Note(
      noteId: map['noteId'] as String,
      transcript: map['transcript'] as String,
      extractedJson: jsonDecode(map['extractedJson'] as String),
      audioFilePath: map['audioFilePath'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      userEdits: map['userEdits'] != null 
          ? jsonDecode(map['userEdits'] as String) 
          : null,
      searchTokens: (map['searchTokens'] as List?)?.cast<String>() ?? [],
    );
  }

  /// Converts to Map<String, dynamic> for public API
  Map<String, dynamic> toPublicMap() {
    return {
      'noteId': noteId,
      'transcript': transcript,
      'extractedJson': extractedJson,
      'audioFilePath': audioFilePath,
      'timestamp': timestamp.toIso8601String(),
      'userEdits': userEdits,
      'taskCount': (extractedJson['tasks'] as List?)?.length ?? 0,
    };
  }

  /// Generates search tokens from transcript for fast full-text search
  static List<String> _generateSearchTokens(String transcript) {
    // Normalize and split into tokens
    final normalized = transcript
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Split into words and remove common stop words
    final words = normalized.split(' ');
    final stopWords = {'the', 'a', 'an', 'and', 'or', 'but', 'to', 'of', 'in', 'on', 'at', 'for'};
    
    return words
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .toSet() // Remove duplicates
        .toList();
  }
}

/// Service for managing encrypted local storage of notes.
///
/// This service provides:
/// - Encrypted storage using Hive with AES-256
/// - Secure key management via platform secure storage (Keychain/Keystore)
/// - Fast full-text search on transcripts
/// - Audio file management
/// - CRUD operations for notes
///
/// All operations are async and non-blocking.
/// Zero cloud dependency by default.
///
/// Example usage:
/// ```dart
/// final storage = LocalStorageService();
/// await storage.initialize();
///
/// await storage.saveNote(
///   noteId: 'note123',
///   transcript: 'Remind me to call John',
///   extractedJson: {'tasks': [...]},
/// );
///
/// final note = await storage.getNote('note123');
/// final results = await storage.searchNotes('call John');
/// ```
class LocalStorageService {
  static final Logger _logger = Logger('LocalStorageService');
  static const String _encryptionKeyName = 'hive_encryption_key';
  static const String _notesBoxName = 'encrypted_notes';
  static const String _indexBoxName = 'search_index';
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accountName: 'ai_notes_encryption_key',
    ),
  );
  
  Box<Map>? _notesBox;
  Box<List>? _indexBox;
  bool _isInitialized = false;

  /// Whether the service is initialized and ready
  bool get isInitialized => _isInitialized;

  /// Gets the number of stored notes
  int get noteCount => _notesBox?.length ?? 0;

  /// Initializes the encrypted storage.
  ///
  /// Must be called before any other operations.
  /// Sets up Hive with encryption and opens boxes.
  Future<void> initialize() async {
    if (_isInitialized) {
      _logger.fine('Storage already initialized');
      return;
    }

    _logger.info('Initializing encrypted local storage...');

    try {
      // Initialize Hive
      await Hive.initFlutter();

      // Get or create encryption key
      final encryptionKey = await _getOrCreateEncryptionKey();
      
      _logger.info('Encryption key ready');

      // Open encrypted boxes
      _notesBox = await Hive.openBox<Map>(
        _notesBoxName,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );

      _indexBox = await Hive.openBox<List>(
        _indexBoxName,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );

      _isInitialized = true;
      _logger.info('Storage initialized successfully');
      _logger.info('  Notes stored: ${noteCount}');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize storage: $e', e, stackTrace);
      throw StorageException('Initialization failed: $e', operation: 'initialize');
    }
  }

  /// Gets existing encryption key or creates a new one.
  Future<List<int>> _getOrCreateEncryptionKey() async {
    // Try to read existing key
    String? keyString = await _secureStorage.read(key: _encryptionKeyName);
    
    if (keyString != null) {
      _logger.fine('Using existing encryption key');
      return base64Url.decode(keyString);
    }

    // Generate new key
    _logger.info('Generating new encryption key...');
    final key = Hive.generateSecureKey();
    keyString = base64Url.encode(key);
    
    // Store securely
    await _secureStorage.write(
      key: _encryptionKeyName,
      value: keyString,
    );
    
    _logger.info('New encryption key generated and stored securely');
    return key;
  }

  /// Saves a note to encrypted storage.
  ///
  /// [noteId]: Unique identifier for the note
  /// [transcript]: The cleaned transcript text
  /// [extractedJson]: Structured JSON from SLM extraction
  /// [audioFilePath]: Optional path to audio file
  /// [timestamp]: Optional timestamp (defaults to now)
  /// [userEdits]: Optional user edits to the extraction
  Future<void> saveNote({
    required String noteId,
    required String transcript,
    required Map<String, dynamic> extractedJson,
    String? audioFilePath,
    DateTime? timestamp,
    Map<String, dynamic>? userEdits,
  }) async {
    _ensureInitialized();
    _logger.info('Saving note: $noteId');

    try {
      final note = Note(
        noteId: noteId,
        transcript: transcript,
        extractedJson: extractedJson,
        audioFilePath: audioFilePath,
        timestamp: timestamp ?? DateTime.now(),
        userEdits: userEdits,
      );

      // Save note
      await _notesBox!.put(noteId, note.toMap());

      // Update search index
      await _updateSearchIndex(noteId, note.searchTokens);

      _logger.info('Note saved successfully: $noteId');
    } catch (e, stackTrace) {
      _logger.severe('Failed to save note: $e', e, stackTrace);
      throw StorageException('Failed to save note: $e', operation: 'saveNote');
    }
  }

  /// Retrieves a note by ID.
  ///
  /// Returns null if note not found.
  Future<Map<String, dynamic>?> getNote(String noteId) async {
    _ensureInitialized();
    _logger.fine('Getting note: $noteId');

    try {
      final noteMap = _notesBox!.get(noteId);
      
      if (noteMap == null) {
        _logger.fine('Note not found: $noteId');
        return null;
      }

      final note = Note.fromMap(noteMap);
      _logger.fine('Note retrieved: $noteId');
      
      return note.toPublicMap();
    } catch (e, stackTrace) {
      _logger.severe('Failed to get note: $e', e, stackTrace);
      return null;
    }
  }

  /// Searches notes by query string.
  ///
  /// Performs full-text search on transcripts using pre-computed tokens.
  /// Returns matching notes sorted by relevance.
  ///
  /// [query]: Search query string
  /// Returns list of matching notes
  Future<List<Map<String, dynamic>>> searchNotes(String query) async {
    _ensureInitialized();
    _logger.info('Searching notes: "$query"');

    if (query.trim().isEmpty) {
      return [];
    }

    try {
      // Generate search tokens from query
      final normalized = query
          .toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      
      final searchWords = normalized.split(' ')
          .where((w) => w.length > 2)
          .toList();

      if (searchWords.isEmpty) {
        return [];
      }

      // Score notes by token matches
      final Map<String, int> noteScores = {};

      for (final word in searchWords) {
        // Find all notes containing this token
        for (final entry in _indexBox!.toMap().entries) {
          final noteId = entry.key as String;
          final tokens = (entry.value as List).cast<String>();
          
          if (tokens.any((token) => token.contains(word))) {
            noteScores[noteId] = (noteScores[noteId] ?? 0) + 1;
          }
        }
      }

      // Sort by score (descending) and retrieve notes
      final sortedIds = noteScores.entries
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final results = <Map<String, dynamic>>[];
      
      for (final entry in sortedIds) {
        final note = await getNote(entry.key);
        if (note != null) {
          results.add(note);
        }
      }

      _logger.info('Search complete: ${results.length} results');
      return results;
    } catch (e, stackTrace) {
      _logger.severe('Search failed: $e', e, stackTrace);
      return [];
    }
  }

  /// Updates the search index for a note.
  Future<void> _updateSearchIndex(String noteId, List<String> tokens) async {
    await _indexBox!.put(noteId, tokens);
  }

  /// Deletes a note and optionally its audio file.
  ///
  /// [noteId]: ID of note to delete
  Future<void> deleteNote(String noteId) async {
    _ensureInitialized();
    _logger.info('Deleting note: $noteId');

    try {
      // Get note to check for audio file
      final noteMap = _notesBox!.get(noteId);
      
      if (noteMap != null) {
        final note = Note.fromMap(noteMap);
        
        // Delete audio file if exists
        if (note.audioFilePath != null) {
          await deleteAudio(noteId);
        }
      }

      // Delete from storage
      await _notesBox!.delete(noteId);
      await _indexBox!.delete(noteId);

      _logger.info('Note deleted: $noteId');
    } catch (e, stackTrace) {
      _logger.severe('Failed to delete note: $e', e, stackTrace);
      throw StorageException('Failed to delete note: $e', operation: 'deleteNote');
    }
  }

  /// Deletes the audio file associated with a note.
  ///
  /// [noteId]: ID of note whose audio should be deleted
  Future<void> deleteAudio(String noteId) async {
    _ensureInitialized();
    _logger.info('Deleting audio for note: $noteId');

    try {
      final noteMap = _notesBox!.get(noteId);
      
      if (noteMap == null) {
        _logger.warning('Note not found for audio deletion: $noteId');
        return;
      }

      final note = Note.fromMap(noteMap);
      
      if (note.audioFilePath != null) {
        final file = File(note.audioFilePath!);
        
        if (await file.exists()) {
          await file.delete();
          _logger.info('Audio file deleted: ${note.audioFilePath}');
          
          // Update note to remove audio path
          final updatedNote = Note(
            noteId: note.noteId,
            transcript: note.transcript,
            extractedJson: note.extractedJson,
            audioFilePath: null,
            timestamp: note.timestamp,
            userEdits: note.userEdits,
            searchTokens: note.searchTokens,
          );
          
          await _notesBox!.put(noteId, updatedNote.toMap());
        }
      }
    } catch (e, stackTrace) {
      _logger.severe('Failed to delete audio: $e', e, stackTrace);
      // Don't throw - audio deletion is not critical
    }
  }

  /// Gets all stored notes.
  ///
  /// Returns list of all notes sorted by timestamp (newest first).
  Future<List<Map<String, dynamic>>> getAllNotes() async {
    _ensureInitialized();
    _logger.fine('Getting all notes');

    try {
      final notes = <Map<String, dynamic>>[];
      
      for (final key in _notesBox!.keys) {
        final note = await getNote(key as String);
        if (note != null) {
          notes.add(note);
        }
      }

      // Sort by timestamp (newest first)
      notes.sort((a, b) {
        final aTime = DateTime.parse(a['timestamp'] as String);
        final bTime = DateTime.parse(b['timestamp'] as String);
        return bTime.compareTo(aTime);
      });

      return notes;
    } catch (e, stackTrace) {
      _logger.severe('Failed to get all notes: $e', e, stackTrace);
      return [];
    }
  }

  /// Clears all notes from storage.
  ///
  /// WARNING: This deletes all data permanently!
  Future<void> clearAllNotes() async {
    _ensureInitialized();
    _logger.warning('Clearing all notes...');

    try {
      // Delete all audio files first
      for (final key in _notesBox!.keys) {
        final noteMap = _notesBox!.get(key);
        if (noteMap != null) {
          final note = Note.fromMap(noteMap);
          if (note.audioFilePath != null) {
            final file = File(note.audioFilePath!);
            if (await file.exists()) {
              await file.delete();
            }
          }
        }
      }

      // Clear boxes
      await _notesBox!.clear();
      await _indexBox!.clear();

      _logger.warning('All notes cleared');
    } catch (e, stackTrace) {
      _logger.severe('Failed to clear notes: $e', e, stackTrace);
      throw StorageException('Failed to clear notes: $e', operation: 'clearAllNotes');
    }
  }

  /// Gets storage statistics.
  Future<Map<String, dynamic>> getStatistics() async {
    _ensureInitialized();

    try {
      int audioFileCount = 0;
      int totalAudioSize = 0;

      for (final key in _notesBox!.keys) {
        final noteMap = _notesBox!.get(key);
        if (noteMap != null) {
          final note = Note.fromMap(noteMap);
          if (note.audioFilePath != null) {
            final file = File(note.audioFilePath!);
            if (await file.exists()) {
              audioFileCount++;
              totalAudioSize += await file.length();
            }
          }
        }
      }

      return {
        'noteCount': noteCount,
        'audioFileCount': audioFileCount,
        'totalAudioSizeBytes': totalAudioSize,
        'totalAudioSizeMB': (totalAudioSize / 1024 / 1024).toStringAsFixed(2),
      };
    } catch (e) {
      return {
        'noteCount': noteCount,
        'error': e.toString(),
      };
    }
  }

  /// Ensures the service is initialized.
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StorageException(
        'Storage not initialized. Call initialize() first.',
        operation: 'access',
      );
    }
  }

  /// Closes the storage and releases resources.
  Future<void> dispose() async {
    _logger.info('Disposing LocalStorageService...');
    
    await _notesBox?.close();
    await _indexBox?.close();
    
    _isInitialized = false;
    _notesBox = null;
    _indexBox = null;
    
    _logger.info('LocalStorageService disposed');
  }
}
