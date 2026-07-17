import 'package:flutter/foundation.dart';

/// Kinds of structured dependency-container events.
enum LxDiEventType { register, create, find, duplicate, remove, dispose, reset }

/// A structured, value-safe dependency-container lifecycle event.
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

  /// Formats this event without invoking dependency instance `toString()`.
  String format() =>
      '[LemonX][$scope] ${type.name.toUpperCase()} $dependencyType'
      '${tag == null ? '' : ' tag=${_safeTag(tag!)}'}'
      '${instanceIdentity == null ? '' : '#$instanceIdentity'}';

  static String _safeTag(Object tag) => switch (tag) {
    String() || num() || bool() || Enum() || Symbol() => '$tag',
    _ => '${tag.runtimeType}#${identityHashCode(tag)}',
  };
}

/// Controls optional dependency-container diagnostics.
class LxDiagnostics {
  LxDiagnostics._();

  static bool enabled = kDebugMode;
  static bool logFind = false;
  static void Function(LxDiEvent event)? onEvent;

  /// Updates diagnostics configuration.
  static void configure({
    bool? enabled,
    bool? logFind,
    void Function(LxDiEvent event)? onEvent,
  }) {
    if (enabled != null) LxDiagnostics.enabled = enabled;
    if (logFind != null) LxDiagnostics.logFind = logFind;
    if (onEvent != null) LxDiagnostics.onEvent = onEvent;
  }

  /// Delivers [event] to the configured listener or debug console.
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
