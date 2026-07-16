import 'package:flutter/foundation.dart';

enum LxDiEventType {
  register,
  create,
  find,
  duplicate,
  replace,
  remove,
  dispose,
  reset,
}

@immutable
class LxDiEvent {
  const LxDiEvent({
    required this.type,
    required this.scope,
    required this.dependencyType,
    this.tag,
    this.instanceIdentity,
    required this.timestamp,
  });

  final LxDiEventType type;
  final String scope;
  final Type dependencyType;
  final Object? tag;
  final int? instanceIdentity;
  final DateTime timestamp;

  String format() =>
      '[LemonX][$scope] ${type.name.toUpperCase()} $dependencyType'
      '${tag == null ? '' : ' tag=$tag'}'
      '${instanceIdentity == null ? '' : '#$instanceIdentity'}';
}

class LxDiagnostics {
  LxDiagnostics._();

  static bool enabled = kDebugMode;
  static bool logFind = false;
  static void Function(LxDiEvent event)? onEvent;

  static void configure({
    bool? enabled,
    bool? logFind,
    void Function(LxDiEvent event)? onEvent,
  }) {
    if (enabled != null) LxDiagnostics.enabled = enabled;
    if (logFind != null) LxDiagnostics.logFind = logFind;
    if (onEvent != null) LxDiagnostics.onEvent = onEvent;
  }

  static void emit(LxDiEvent event) {
    if (!enabled || (event.type == LxDiEventType.find && !logFind)) return;
    final listener = onEvent;
    if (listener != null) {
      listener(event);
    } else if (kDebugMode) {
      debugPrint(event.format());
    }
  }
}
