import 'package:concur/concur.dart';

/// Starting up a web application using Concur is simple!
void main() {
  // Start your workers up using Concur.start() as shown here.  Each worker
  // method will be invoked once in a separate threading context.
  Concur.start({
    'main': (x) {
      // This is the main thread, because the second argument to Concur.start()
      // was 'main'.

      // The getChannel() method establishes communication with the named sender
      // and returns a stream of MessageEvents that you can parse and process.
      // This is a single-consumer stream, you'll need to wrap it if you want
      // multiple consumers.
      // Subsequent invocations will return the same stream, which will probably
      // already have a consumer attached.  If you want more than one channel
      // between the same pair of workers, you can multiplex over a single
      // channel by sending JSON graphs with a property labeling their purpose.
      x.getChannel('other').listen((x) => print(x.data));

      // Workers can also send messages to themselves!
      x.getChannel('main').listen((x) => print(x.data));

      // Loopback messages like this will be handled in an asynchronous
      // microtask without blocking the sender.
      x.send('main', 'loopback');
    },
    'other': (x) {
      // This is the worker thread, you can create as many of these as you like
      // by adding more elements to the map with different names.

      // The send() method sends the provided payload in the 'data' property of
      // the MessageEvent received by the other worker.  You can generally send
      // any type of data that fits in a JSON object.
      x.send('main', 'fnord');
    }
  }, 'main');

  // If this is the main worker then the worker method is invoked synchronously,
  // so this block runs after the main worker method returns, but before any
  // message handlers have a chance to run.
  // If this is a worker instance, this block will be run before the worker
  // callback because the worker is actually waiting on a control message from
  // the main thread that tells it which worker method it is running.
  print('Concur initialization complete!');
}

// Output of this example will be the messages 'fnord' and 'loopback' printed
// from the main thread.