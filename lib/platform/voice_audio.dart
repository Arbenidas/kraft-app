import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cómo acabó el intento de encender el micrófono.
enum MicrophoneStart {
  ok,

  /// El usuario no dio permiso.
  denied,

  /// Este aparato no tiene el audio nativo de la conversación.
  unsupported,

  /// El motor de audio del sistema no pudo arrancar (micrófono ocupado, formato, etc.).
  failed,
}

/// Entrada de audio seleccionable. `system` deja que iPadOS/macOS elijan la
/// mejor ruta disponible y es segura cuando se desconecta un accesorio.
@immutable
class MicrophoneDevice {
  const MicrophoneDevice({required this.id, required this.name});

  static const system = MicrophoneDevice(
    id: 'system',
    name: 'Automático (recomendado)',
  );

  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is MicrophoneDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Micrófono (PCM 16 bits, 16 kHz) y altavoz (PCM 16 bits, 24 kHz) con cancelación de eco.
/// Ver `KraftVoiceAudio` en `AppDelegate.swift`.
abstract interface class VoiceAudio {
  /// Entradas disponibles ahora. La opción automática se añade en Dart.
  Future<List<MicrophoneDevice>> microphones();

  /// Pide permiso y arranca micrófono y altavoz.
  Future<MicrophoneStart> start({String? microphoneId});
  Future<void> stop();
  Stream<Uint8List> get microphone;
  Future<void> play(Uint8List pcm);

  /// Corta lo que está sonando (cuando el usuario interrumpe).
  Future<void> clear();
}

class ChannelVoiceAudio implements VoiceAudio {
  const ChannelVoiceAudio();

  static const _methods = MethodChannel('kraft/voice');
  static const _mic = EventChannel('kraft/voice/mic');

  @override
  Future<List<MicrophoneDevice>> microphones() async {
    try {
      final raw =
          await _methods.invokeMethod<List<Object?>>('listMicrophones') ??
          const [];
      return [
        for (final value in raw)
          if (value is Map && value['id'] != null)
            MicrophoneDevice(
              id: '${value['id']}',
              name: '${value['name'] ?? 'Micrófono'}',
            ),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<MicrophoneStart> start({String? microphoneId}) async {
    try {
      final started =
          await _methods.invokeMethod<bool>('start', {
            if (microphoneId != null &&
                microphoneId != MicrophoneDevice.system.id)
              'microphoneId': microphoneId,
          }) ??
          false;
      return started ? MicrophoneStart.ok : MicrophoneStart.denied;
    } on MissingPluginException {
      return MicrophoneStart.unsupported;
    } on PlatformException {
      return MicrophoneStart.failed;
    }
  }

  @override
  Future<void> stop() => _safe('stop');

  @override
  Stream<Uint8List> get microphone =>
      _mic.receiveBroadcastStream().map((data) => data as Uint8List);

  @override
  Future<void> play(Uint8List pcm) => _safe('play', pcm);

  @override
  Future<void> clear() => _safe('clear');

  Future<void> _safe(String method, [Object? args]) async {
    try {
      await _methods.invokeMethod<void>(method, args);
    } on MissingPluginException {
      return;
    }
  }
}
