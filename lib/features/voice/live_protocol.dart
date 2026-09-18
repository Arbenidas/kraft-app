import 'dart:convert';
import 'dart:typed_data';

/// Mensajes de la Live API de Gemini (WebSocket `BidiGenerateContent`).
abstract final class LiveProtocol {
  static const defaultModel = 'gemini-3.8-live';

  static Uri endpoint(
    String apiKey, {
    bool extendedThinking = false,
  }) => Uri.parse(
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.${extendedThinking ? 'v1alpha' : 'v1beta'}.GenerativeService.BidiGenerateContent'
    '?key=${Uri.encodeQueryComponent(apiKey)}',
  );

  static Map<String, Object?> setup({
    required String model,
    required String systemInstruction,
    required List<Map<String, Object?>> tools,
  }) => {
    'setup': {
      'model': model.startsWith('models/') ? model : 'models/$model',
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        if (model.endsWith('-extended-thinking'))
          'thinkingConfig': {'thinkingLevel': 'HIGH'},
      },
      'systemInstruction': {
        'parts': [
          {'text': systemInstruction},
        ],
      },
      if (tools.isNotEmpty)
        'tools': [
          {
            'functionDeclarations': [
              for (final t in tools)
                {
                  ...declaration(t),
                  if (model.endsWith('-extended-thinking'))
                    'behavior': 'NON_BLOCKING',
                },
            ],
          },
        ],
      'inputAudioTranscription': <String, Object?>{},
      'outputAudioTranscription': <String, Object?>{},
    },
  };

  static Map<String, Object?> audio(Uint8List pcm16k) => {
    'realtimeInput': {
      'audio': {
        'data': base64Encode(pcm16k),
        'mimeType': 'audio/pcm;rate=16000',
      },
    },
  };

  static Map<String, Object?> text(String text) => {
    'realtimeInput': {'text': text},
  };

  static Map<String, Object?> toolResponse(
    List<({String id, String name, Map<String, Object?> response})> responses,
  ) => {
    'toolResponse': {
      'functionResponses': [
        for (final r in responses)
          {'id': r.id, 'name': r.name, 'response': r.response},
      ],
    },
  };

  /// Herramienta en formato JSON Schema (como las del MCP) → declaración de función de Gemini:
  /// tipos en mayúsculas y sin las claves que la API no acepta.
  static Map<String, Object?> declaration(Map<String, Object?> tool) => {
    'name': tool['name'],
    'description': tool['description'],
    if (tool['inputSchema'] case final Map<String, Object?> schema
        when (schema['properties'] as Map?)?.isNotEmpty ?? false)
      'parameters': schemaFor(schema),
  };

  static const _allowedKeys = {
    'type',
    'description',
    'enum',
    'required',
    'items',
    'properties',
    'nullable',
    'format',
  };

  static Map<String, Object?> schemaFor(Map<String, Object?> schema) => {
    for (final MapEntry(:key, :value) in schema.entries)
      if (_allowedKeys.contains(key))
        key: switch (key) {
          'type' => '$value'.toUpperCase(),
          'items' => schemaFor((value! as Map).cast()),
          'properties' => {
            for (final MapEntry(key: name, value: sub)
                in (value! as Map).cast<String, Object?>().entries)
              name: schemaFor((sub! as Map).cast()),
          },
          _ => value,
        },
  };

  /// Interpreta un mensaje del servidor.
  static List<LiveEvent> parse(Map<String, Object?> message) {
    final events = <LiveEvent>[];
    if (message.containsKey('setupComplete')) events.add(const LiveReady());
    if (message['serverContent'] case final Map<String, Object?> content) {
      if (content['inputTranscription'] case {'text': final String text})
        events.add(LiveTranscript(user: true, text: text));
      if (content['outputTranscription'] case {'text': final String text})
        events.add(LiveTranscript(user: false, text: text));
      if (content['modelTurn'] case {'parts': final List<Object?> parts}) {
        for (final part in parts) {
          if (part case {'inlineData': {'data': final String data}})
            events.add(LiveAudio(base64Decode(data)));
        }
      }
      if (content['interrupted'] == true) events.add(const LiveInterrupted());
      if (content['turnComplete'] == true) events.add(const LiveTurnComplete());
    }
    final interaction =
        message['interactionStatus'] ??
        (message['serverContent'] as Map?)?['interactionStatus'];
    if (interaction == 'IN_PROGRESS' || interaction == 'IDLE') {
      events.add(LiveInteractionStatus(interaction == 'IN_PROGRESS'));
    }
    if (message['toolCall'] case {'functionCalls': final List<Object?> calls}) {
      for (final call in calls) {
        if (call case {'id': final String id, 'name': final String name}) {
          events.add(
            LiveToolCall(
              id: id,
              name: name,
              args:
                  ((call as Map)['args'] as Map?)?.cast<String, Object?>() ??
                  const {},
            ),
          );
        }
      }
    }
    if (message['toolCallCancellation'] case {'ids': final List<Object?> ids}) {
      events.add(LiveToolCancelled([for (final id in ids) '$id']));
    }
    if (message['goAway'] != null) events.add(const LiveGoAway());
    return events;
  }
}

sealed class LiveEvent {
  const LiveEvent();
}

class LiveReady extends LiveEvent {
  const LiveReady();
}

class LiveAudio extends LiveEvent {
  const LiveAudio(this.pcm);
  final Uint8List pcm;
}

class LiveTranscript extends LiveEvent {
  const LiveTranscript({required this.user, required this.text});
  final bool user;
  final String text;
}

class LiveInterrupted extends LiveEvent {
  const LiveInterrupted();
}

class LiveTurnComplete extends LiveEvent {
  const LiveTurnComplete();
}

class LiveToolCall extends LiveEvent {
  const LiveToolCall({
    required this.id,
    required this.name,
    required this.args,
  });
  final String id;
  final String name;
  final Map<String, Object?> args;
}

class LiveToolCancelled extends LiveEvent {
  const LiveToolCancelled(this.ids);
  final List<String> ids;
}

class LiveGoAway extends LiveEvent {
  const LiveGoAway();
}

class LiveInteractionStatus extends LiveEvent {
  const LiveInteractionStatus(this.inProgress);
  final bool inProgress;
}
