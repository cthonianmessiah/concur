import 'dart:async';
import 'dart:html';

import 'package:concur/concur.dart';

class LocalConcur extends Concur {
  final String _thisWorker;
  final Set<String> _validWorkers;
  final Map<String, Map<String, StreamController<MessageEvent>>> _controllers;

  @override
  Stream<MessageEvent> getChannel(String workerName) {
    if (!_validWorkers.contains(workerName)) {
      throw StateError(
          'Concur fatal error: Worker tried to listen for messages from the '
          'nonexistent worker "$workerName".');
    }

    return _getController(workerName, _thisWorker).stream;
  }

  @override
  void send(String workerName, dynamic message, [List<Object>? transfer]) {
    if (!_validWorkers.contains(workerName)) {
      throw StateError(
          'Concur fatal error: Worker tried to send a message to the '
          'nonexistent worker "$workerName".');
    }

    _getController(_thisWorker, workerName)
        .add(MessageEvent('message', data: message));
  }

  StreamController<MessageEvent> _getController(String from, String to) {
    var toMap = _controllers[from];
    if (toMap == null) {
      toMap = <String, StreamController<MessageEvent>>{};
      _controllers[from] = toMap;
    }

    var controller = toMap[to];
    if (controller == null) {
      controller = StreamController<MessageEvent>();
      toMap[to] = controller;
    }

    return controller;
  }

  LocalConcur(this._thisWorker, Set<String> validWorkers, this._controllers)
      : _validWorkers = Set<String>.unmodifiable(validWorkers);
}

/**
 * Defect!
 * 
 * What is supposed to happen is that 'send' and 'listen' both refer to the
 * worker being communicated with and they implicitly carry the identity of the
 * caller.
 * 
 * The local Concur instance, because it is a single instance, can only do this
 * correctly for loopback.
 * 
 * What is needed is to make the local flavor of the class take an identity
 * argument and then all instances can depend on the same underlying collection
 * of channels.
 */
