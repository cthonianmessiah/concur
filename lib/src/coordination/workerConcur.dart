import 'dart:async';
import 'dart:html';

import 'package:concur/concur.dart';
import 'package:concur/src/coordination/coordination.dart';

class WorkerConcur extends Concur {
  /// The name of this worker.
  final String _thisWorker;

  /// The set of all valid worker names.
  final Set<String> _validWorkers;

  final StreamController<MessageEvent> _loopbackController =
      StreamController<MessageEvent>();
  final Map<String, MessagePort> _receivePorts = <String, MessagePort>{};
  final Map<String, MessagePort> _sendPorts = <String, MessagePort>{};
  final Map<String, List<QueuedMessage>> _queues =
      <String, List<QueuedMessage>>{};

  final ControlBuffer _controlBuffer;

  @override
  Stream<MessageEvent> getChannel(String workerName) {
    if (!_validWorkers.contains(workerName)) {
      throw StateError(
          'Concur fatal error: Worker "$_thisWorker" tried to listen for '
          'messages from the nonexistent worker "$workerName".');
    }

    if (workerName == _thisWorker) {
      return _loopbackController.stream;
    }

    var receivePort = _receivePorts[workerName];
    if (receivePort != null) {
      return receivePort.onMessage;
    }

    var channel = MessageChannel();
    _receivePorts[workerName] = channel.port2;
    DedicatedWorkerGlobalScope.instance.postMessage({
      'type': 'port',
      'sender': workerName,
      'receiver': _thisWorker,
      'port': channel.port1
    }, [
      channel.port1
    ]);
    return channel.port2.onMessage;
  }

  /// Sets up control channel event handler
  void initialize() {
    // Add a handler for incoming sender ports
    _controlBuffer.addHandler('port', (x) {
      // Get message properties
      var sender = x.data['sender'] as String;
      var receiver = x.data['receiver'] as String;
      var port = x.data['port'] as MessagePort;

      if (sender != _thisWorker) {
        throw StateError(
            'Concur fatal error: Worker "$_thisWorker" received a sender port '
            'intended for worker "$sender".  This should be impossible, '
            'contact the library developer.');
      }

      // Port for sending from this worker, store in local ports
      _sendPorts[receiver] = port;

      // Flush any locally queued messages now that the port is available
      var queued = _queues[receiver];
      if (queued != null) {
        queued.forEach((x) => port.postMessage(x.message, x.transfer));
        _queues.remove(receiver);
      }
      return;
    });
  }

  @override
  void send(String workerName, message, [List<Object>? transfer]) {
    if (!_validWorkers.contains(workerName)) {
      throw StateError(
          'Concur fatal error: Worker "$_thisWorker" tried to send a message '
          'to the nonexistent worker "$workerName".');
    }

    if (workerName == _thisWorker) {
      _loopbackController.add(MessageEvent('message', data: message));
      return;
    }

    var sendPort = _sendPorts[workerName];
    if (sendPort == null) {
      var queued = _queues[workerName];
      if (queued == null) {
        queued = <QueuedMessage>[];
        _queues[workerName] = queued;
      }

      queued.add(QueuedMessage(message, transfer));

      return;
    }

    sendPort.postMessage(message, transfer);
  }

  WorkerConcur(this._thisWorker, Set<String> validWorkers, this._controlBuffer)
      : _validWorkers = Set<String>.unmodifiable(validWorkers);
}
