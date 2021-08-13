@TestOn('browser')

import 'dart:async';
import 'dart:html';

import 'package:concur/concur.dart';
import 'package:test/test.dart';

/// Tests for the behavior when Concur.start() is launched with Web Workers.
void main() {
  print('test file started!');
  Concur.start({
    'main': (x) {
      test('worker self loopback sends message', () async {
        var completer = Completer<bool>();
        Future.delayed(Duration(milliseconds: 200), () {
          if (completer.isCompleted) return;
          completer.complete(false);
        });

        x.getChannel('main').listen((y) {
          if (completer.isCompleted) return;
          completer.complete(true);
        });
        x.send('main', null);

        expect(await completer.future, isTrue);
      });

      // I couldn't get this test to work because the worker code isn't starting
      // up.  I think this is because I can't reliably predict the correct
      // launchUrl value in the test environment.
      // This type of test does work when run via 'webdev serve -r'.
      /*
      test('main worker receives message from other worker', () async {
        var completer = Completer<bool>();
        Future.delayed(Duration(milliseconds: 200), () {
          if (completer.isCompleted) return;
          completer.complete(false);
        });

        x.getChannel('other').listen((y) {
          if (completer.isCompleted) return;
          completer.complete(true);
        });

        expect(await completer.future, isTrue);
      });
      */
    },
    'other': (x) {
      print('worker started!');
      x.send('main', null);
    }
  }, 'main', launchUrl: 'concur_worker_test.dart.browser_test.dart.js');
}
