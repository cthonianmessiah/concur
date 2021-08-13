import 'dart:async';
import 'dart:html';

import 'package:concur/src/coordination/workerConcur.dart';
import 'package:js/js.dart';

import 'package:concur/concur.dart';
import 'package:concur/src/coordination/coordination.dart';

// ignore: missing_js_lib_annotation
@JS('window')
external dynamic get jsWindow;

/// Manages the creation of concurrent workers and communication between them.
///
abstract class Concur extends Object {
  /// True if the current thread is a Web Worker with no DOM access
  static final bool isWorkerThread = jsWindow == null;

  /// Opens a communication channel receiving data from the named worker.
  /// The named worker must exist in the domain of workers passed to
  /// `Concur.start()`.
  ///
  /// For info about the events in this stream, see:
  /// https://developer.mozilla.org/en-US/docs/Web/API/MessageEvent
  Stream<MessageEvent> getChannel(String workerName);

  /// Sends a message to the named worker.  The message can consist of any data
  /// you could put into a JSON object, plus [MessagePort] (although if you're
  /// using this library, you may want to let it worry about port sharing).
  ///
  /// If the target worker hasn't invoked [getChannel] for this worker yet, the
  /// message will queue up locally and wait for a channel to be opened.  This
  /// can cause memory leaks, so make sure to open communication channels and
  /// start consuming messages from them as soon as you can in each worker!
  ///
  /// For info about how the underlying messaging works in Web Workers, see:
  /// https://developer.mozilla.org/en-US/docs/Web/API/MessagePort/postMessage
  void send(String workerName, dynamic message, [List<Object>? transfer]);

  /// Starts the provided set of named workers and passes each one an instance
  /// of Concur that is capable of communicating with the other workers.
  /// The named main worker is the only worker guaranteed to have access to the
  /// DOM.
  ///
  /// Set [useWorkers] to false to run everything in the main thread instead of
  /// using Web Workers.  This option is there to make it easier to run your
  /// application with 'webdev serve'.  Don't forget to set it back to true for
  /// a release, or you won't actually use multiple threads, which is the whole
  /// reason you downloaded this package in the first place!
  /// Workers will only work correctly in a single-threaded environment if they
  /// all avoid blocking the event loop.
  ///
  /// Concur is designed to run all workers from the same source, and normally
  /// that source is 'main.dart.js'.  If your main source file has a different
  /// name, you can override the [launchUrl] parameter to specify this.
  static void start(Map<String, WorkLauncher> workers, String mainWorkerName,
      {bool useWorkers = true, String launchUrl = 'main.dart.js'}) {
    if (!workers.containsKey(mainWorkerName)) {
      throw ArgumentError(
          'Concur fatal error: Main worker "$mainWorkerName" has no launcher '
          'in the workers collection.  You must provide a launcher so that the '
          'main worker has something to do.');
    }

    // Use the keys of the worker map to validate later invocations to the
    // Concur object.
    var validWorkers = workers.keys.toSet();

    // Only try to use workers if asked to do so and they are supported.
    if (useWorkers && Worker.supported) {
      // Web Workers enabled, this is where it gets interesting!
      // This block runs for each worker, but we use magic to figure out which
      // one is on the main thread and which ones need to wait for an identity
      // to be assigned to them.
      if (isWorkerThread) {
        // This is a worker thread because the window object is null.
        // Set up a control buffer to allow us to defer some message handlers
        // until the worker Concur instance is initialized.
        var controlBuffer =
            ControlBuffer(DedicatedWorkerGlobalScope.instance.onMessage);

        // Listen for an identity message to tell this worker which task it runs
        // before actually trying to start it.
        controlBuffer.addHandler('identity', (x) {
          var identity = x.data['identity'] as String;

          // We now know which worker we are implementing, create the worker
          // Concur instance and initialize it.
          var workerConcur =
              WorkerConcur(identity, validWorkers, controlBuffer);
          workerConcur.initialize();

          // Launch the worker task with this Concur instance.
          workers[identity]!(workerConcur);
        });
        return;
      }

      // This is the main thread because the window object is not null.
      // Allocate workers for each child.
      var childWorkers = {
        for (var x in workers.keys.where((x) => x != mainWorkerName))
          x: Worker(launchUrl)
      };

      // Set up the main Concur instance that relays control messages between
      // itself and the child workers.  It will also assign child worker
      // identities.
      var mainConcur = MainConcur(mainWorkerName, validWorkers, childWorkers);
      mainConcur.initialize();

      // Launch the main worker task using the main Concur instance.
      workers[mainWorkerName]!(mainConcur);
      return;
    }

    // Not using Web Workers, set up a single global message exchange that will
    // use local Streams to share data.
    var controllers = <String, Map<String, StreamController<MessageEvent>>>{};

    // Each local Concur instance shares the same stream controller lookup,
    // which is safe since we're single-threaded here.
    workers.keys.forEach((x) {
      var localConcur = LocalConcur(x, validWorkers, controllers);
      Future.microtask(() => workers[x]!(localConcur));
    });
  }
}
