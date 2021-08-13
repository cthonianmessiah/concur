import 'dart:async';
import 'dart:html';

import 'package:concur/src/coordination/coordination.dart';

/// Buffers incoming control messages to allow handlers to bind after messages
/// are sent without dropping anything.
class ControlBuffer extends Object {
  /// Maps message types to their handlers.
  /// Each incoming message is expected to be a JSON object with a 'type'
  /// property that indicates which handler should be used.
  final Map<String, ControlMessageHandler> _controlHandlers;

  /// Stores messages that arrived before their handler was registered.
  final Map<String, List<MessageEvent>> _controlBuffers;

  /// The subscription to message events that are being buffered.
  final StreamSubscription<MessageEvent> _subscription;

  /// Adds a handler to the specified message type if one doesn't already exist.
  void addHandler(String type, ControlMessageHandler handler) {
    if (_controlHandlers.containsKey(type)) return;

    _controlHandlers[type] = handler;

    // Invoke the handler on buffered messages of this type, if any
    var buffer = _controlBuffers[type];
    if (buffer == null) return;

    buffer.forEach((x) => Future.microtask(() => handler(x)));
    _controlBuffers.remove(type);
  }

  // Cancels the message subscription allocated to this control buffer.
  void dispose() async {
    await _subscription.cancel();
  }

  ControlBuffer._internal(
      this._controlBuffers, this._controlHandlers, this._subscription);

  factory ControlBuffer(Stream<MessageEvent> stream) {
    var controlHandlers = <String, ControlMessageHandler>{};
    var controlBuffers = <String, List<MessageEvent>>{};
    var subscription = stream.listen((x) {
      var type = x.data['type'];
      var handler = controlHandlers[type];
      if (handler != null) {
        handler(x);
        return;
      }

      var buffer = controlBuffers[type];
      if (buffer == null) {
        buffer = <MessageEvent>[];
        controlBuffers[type] = buffer;
      }

      buffer.add(x);
    });

    return ControlBuffer._internal(
        controlBuffers, controlHandlers, subscription);
  }
}
