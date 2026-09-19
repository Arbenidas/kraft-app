import 'dart:async';

import 'package:flutter/services.dart';

/// Acción preferida configurada por el usuario en Ajustes › Apple Pencil.
enum PencilAction {
  ignore,
  switchEraser,
  switchPrevious,
  showColorPalette,
  showInkAttributes,
  showContextualPalette,
  runSystemShortcut;

  static PencilAction parse(Object? raw) => PencilAction.values.firstWhere(
    (a) => a.name == raw,
    orElse: () => PencilAction.switchEraser,
  );
}

enum PencilGesture { doubleTap, squeeze }

class PencilEvent {
  const PencilEvent(this.gesture, this.action);

  final PencilGesture gesture;
  final PencilAction action;
}

/// Doble toque y apretón del Apple Pencil, recibidos desde `UIPencilInteraction` (ver `AppDelegate.swift`).
abstract final class ApplePencil {
  static const channel = MethodChannel('kraft/pencil');

  static final _events = StreamController<PencilEvent>.broadcast();
  static bool _bound = false;

  static Stream<PencilEvent> get events {
    if (!_bound) {
      _bound = true;
      channel.setMethodCallHandler((call) async {
        final args = call.arguments is Map ? call.arguments as Map : const {};
        final action = PencilAction.parse(args['action']);
        switch (call.method) {
          case 'tap':
            _events.add(PencilEvent(PencilGesture.doubleTap, action));
          case 'squeeze':
            _events.add(PencilEvent(PencilGesture.squeeze, action));
        }
      });
    }
    return _events.stream;
  }
}
