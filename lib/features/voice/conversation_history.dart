import 'dart:convert';

import 'package:flutter/foundation.dart';

@immutable
class ConversationEntry {
  const ConversationEntry({required this.user, required this.text});

  final bool user;
  final String text;

  Map<String, Object?> toJson() => {'user': user, 'text': text};

  static ConversationEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<Object?, Object?>();
    final text = '${json['text'] ?? ''}'.trim();
    if (text.isEmpty) return null;
    return ConversationEntry(user: json['user'] == true, text: text);
  }
}

@immutable
class ConversationThread {
  const ConversationThread({
    required this.id,
    required this.title,
    required this.engineId,
    required this.modelId,
    required this.updatedAt,
    required this.entries,
  });

  final String id;
  final String title;
  final String engineId;
  final String modelId;
  final DateTime updatedAt;
  final List<ConversationEntry> entries;

  ConversationThread copyWith({
    String? title,
    String? engineId,
    String? modelId,
    DateTime? updatedAt,
    List<ConversationEntry>? entries,
  }) => ConversationThread(
    id: id,
    title: title ?? this.title,
    engineId: engineId ?? this.engineId,
    modelId: modelId ?? this.modelId,
    updatedAt: updatedAt ?? this.updatedAt,
    entries: entries ?? this.entries,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'engine': engineId,
    'model': modelId,
    'updatedAt': updatedAt.toIso8601String(),
    'entries': [for (final entry in entries) entry.toJson()],
  };

  static ConversationThread? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = raw.cast<Object?, Object?>();
    final id = '${json['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    final entries = (json['entries'] as List? ?? const [])
        .map(ConversationEntry.fromJson)
        .whereType<ConversationEntry>()
        .toList(growable: false);
    return ConversationThread(
      id: id,
      title: '${json['title'] ?? 'Conversación'}',
      engineId: '${json['engine'] ?? 'gemini'}',
      modelId: '${json['model'] ?? ''}',
      updatedAt:
          DateTime.tryParse('${json['updatedAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      entries: entries,
    );
  }
}

@immutable
class ConversationArchive {
  const ConversationArchive({required this.activeId, required this.threads});

  final String? activeId;
  final List<ConversationThread> threads;

  String encode() => jsonEncode({
    'version': 1,
    'activeId': activeId,
    'threads': [for (final thread in threads) thread.toJson()],
  });

  static ConversationArchive decode(String? source) {
    if (source == null || source.isEmpty) {
      return const ConversationArchive(activeId: null, threads: []);
    }
    try {
      final raw = jsonDecode(source);
      if (raw is! Map) throw const FormatException();
      final json = raw.cast<Object?, Object?>();
      return ConversationArchive(
        activeId: json['activeId'] as String?,
        threads: (json['threads'] as List? ?? const [])
            .map(ConversationThread.fromJson)
            .whereType<ConversationThread>()
            .toList(growable: false),
      );
    } on Object {
      return const ConversationArchive(activeId: null, threads: []);
    }
  }
}
