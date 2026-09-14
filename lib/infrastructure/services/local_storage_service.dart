import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../presentation/models/chat_message.dart';
import '../../presentation/models/peer_model.dart';

/// Service managing persistent storage of node identity, conversations,
/// and peer directories across app restarts, with zero-trace panic wipe.
class LocalStorageService {
  final Directory? _customDir;
  bool _inMemoryOnly;
  final Map<String, String> _inMemoryStore = {};

  LocalStorageService({Directory? customDir, bool inMemoryOnly = false})
      : _customDir = customDir,
        _inMemoryOnly = inMemoryOnly;

  static const String identityFileName = 'identity.json';
  static const String conversationsFileName = 'conversations.json';
  static const String peersFileName = 'peers.json';

  Future<Directory?> _getDirectory() async {
    if (_inMemoryOnly) return null;
    if (_customDir != null) {
      if (!await _customDir!.exists()) {
        await _customDir!.create(recursive: true);
      }
      return _customDir;
    }

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final appDir = Directory('${docDir.path}/dec_chat');
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
      return appDir;
    } catch (_) {
      // In headless unit tests or unsupported environments, fall back to memory
      _inMemoryOnly = true;
      return null;
    }
  }

  Future<File?> _getFile(String fileName) async {
    final dir = await _getDirectory();
    if (dir == null) return null;
    return File('${dir.path}/$fileName');
  }

  Future<void> _writeString(String fileName, String content) async {
    _inMemoryStore[fileName] = content;
    final file = await _getFile(fileName);
    if (file != null) {
      try {
        await file.writeAsString(content, flush: true);
        return;
      } catch (_) {}
    }
  }

  Future<String?> _readString(String fileName) async {
    if (_inMemoryStore.containsKey(fileName)) {
      return _inMemoryStore[fileName];
    }
    final file = await _getFile(fileName);
    if (file != null && await file.exists()) {
      try {
        final content = await file.readAsString();
        _inMemoryStore[fileName] = content;
        return content;
      } catch (_) {}
    }
    return null;
  }

  Future<void> _secureDelete(String fileName) async {
    _inMemoryStore.remove(fileName);
    final file = await _getFile(fileName);
    if (file != null && await file.exists()) {
      try {
        final length = await file.length();
        if (length > 0) {
          final zeros = Uint8List(length);
          await file.writeAsBytes(zeros, flush: true);
        }
        await file.delete();
      } catch (_) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  // --- Identity ---

  Future<void> saveIdentity(Map<String, dynamic> json) async {
    final encoded = jsonEncode(json);
    await _writeString(identityFileName, encoded);
  }

  Future<Map<String, dynamic>?> loadIdentity() async {
    final raw = await _readString(identityFileName);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  Future<void> deleteIdentity() async {
    await _secureDelete(identityFileName);
  }

  // --- Timeline / Conversations ---

  Future<void> saveTimeline(Map<String, List<ChatMessage>> messagesByChannel) async {
    final serialized = <String, dynamic>{};
    for (final entry in messagesByChannel.entries) {
      serialized[entry.key] = entry.value.map((m) => m.toJson()).toList();
    }
    final encoded = jsonEncode(serialized);
    await _writeString(conversationsFileName, encoded);
  }

  Future<Map<String, List<ChatMessage>>?> loadTimeline() async {
    final raw = await _readString(conversationsFileName);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final result = <String, List<ChatMessage>>{};
        for (final entry in decoded.entries) {
          if (entry.value is List) {
            result[entry.key] = (entry.value as List)
                .whereType<Map<String, dynamic>>()
                .map((m) => ChatMessage.fromJson(m))
                .toList();
          }
        }
        return result;
      }
    } catch (_) {}
    return null;
  }

  Future<void> deleteTimeline() async {
    await _secureDelete(conversationsFileName);
  }

  // --- Peers Directory ---

  Future<void> savePeers(List<PeerModel> peers) async {
    final serialized = peers.map((p) => p.toJson()).toList();
    final encoded = jsonEncode(serialized);
    await _writeString(peersFileName, encoded);
  }

  Future<List<PeerModel>?> loadPeers() async {
    final raw = await _readString(peersFileName);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((m) => PeerModel.fromJson(m))
            .toList();
      }
    } catch (_) {}
    return null;
  }

  Future<void> deletePeers() async {
    await _secureDelete(peersFileName);
  }

  // --- Emergency Panic Wipe ---

  /// Overwrites and deletes all persisted files and in-memory caches.
  Future<void> wipeAll() async {
    _inMemoryStore.clear();
    await _secureDelete(identityFileName);
    await _secureDelete(conversationsFileName);
    await _secureDelete(peersFileName);

    // Also attempt to remove directory if empty
    final dir = await _getDirectory();
    if (dir != null && await dir.exists()) {
      try {
        final list = await dir.list().toList();
        if (list.isEmpty) {
          await dir.delete();
        }
      } catch (_) {}
    }
  }
}

/// Global provider for local persistent storage service.
final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  return LocalStorageService();
});
