import 'dart:async';
import 'dart:html';

import 'package:concur/concur.dart';
import 'package:concur/src/coordination/coordination.dart';

class MainConcur extends Concur {
  /// Identifies which worker is on the main thread.
  final String _thisWorker;

  /// The set of child workers managed by the main worker.
  final Map<String, Worker> _workers;

  /// The set of all valid worker names.
  final Set<String> _validWorkers;

  final StreamController<MessageEvent> _loopbackController =
      StreamController<MessageEvent>();
  final Map<String, MessagePort> _receivePorts = <String, MessagePort>{};
  final Map<String, MessagePort> _sendPorts = <String, MessagePort>{};

  final Map<String, List<QueuedMessage>> _queues =
      <String, List<QueuedMessage>>{};

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

    var worker = _workers[workerName];
    if (worker == null) {
      throw StateError(
          'Concur fatal error: Worker "$_thisWorker" tried to get a channel '
          'for the nonexistent worker "$workerName".');
    }

    var channel = MessageChannel();
    _receivePorts[workerName] = channel.port2;
    worker.postMessage({
      'type': 'port',
      'sender': workerName,
      'receiver': _thisWorker,
      'port': channel.port1
    }, [
      channel.port1
    ]);
    return channel.port2.onMessage;
  }

  /// Performs initial messaging on worker control channels to assign identities
  /// and sets up control message handlers.
  void initialize() {
    _workers.forEach((k, v) {
      // Handle control messages from this worker
      v.onMessage.listen((x) {
        // For now the only control message coming from workers is port
        if (x.data['type'] != 'port') return;

        // Get message properties
        var sender = x.data['sender'] as String;
        var port = x.data['port'] as MessagePort;

        if (sender == _thisWorker) {
          // Port for sending from this worker, store in local ports
          _sendPorts[k] = port;

          // Flush any locally queued messages now that the port is available
          var queued = _queues[k];
          if (queued != null) {
            queued.forEach((x) => port.postMessage(x.message, x.transfer));
            _queues.remove(k);
          }
          return;
        }

        // Get the worker that sends messages to this port
        var worker = _workers[sender];
        if (worker == null) {
          throw StateError(
              'Concur fatal error: Main thread received a communication port '
              'with an invalid sender name "$sender" from the receiver "$k".  '
              'The worker must have invoked Concur.getChannel() with an '
              'invalid worker name.');
        }

        // Relay the port to the worker
        worker.postMessage(
            {'type': 'port', 'sender': sender, 'receiver': k, 'port': port},
            [port]);
      });
      // Assign the worker's identity, which will allow it to start running
      v.postMessage({'type': 'identity', 'identity': k});
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

  MainConcur(
      this._thisWorker, Set<String> validWorkers, Map<String, Worker> workers)
      : _validWorkers = Set<String>.unmodifiable(validWorkers),
        _workers = Map<String, Worker>.unmodifiable(workers);
}
