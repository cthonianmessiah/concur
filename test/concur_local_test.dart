@TestOn('browser')

import 'dart:async';

import 'package:concur/concur.dart';
import 'package:test/test.dart';

/// Tests for the behavior when Concur.start() is launched without using Web
/// Workers.
void main() {
  test('local self loopback sends message', () async {
    var completer = Completer<bool>();
    Future.delayed(
        Duration(milliseconds: 200), () => completer.complete(false));
    Concur.start({
      'main': (x) {
        x.getChannel('main').listen((y) => completer.complete(true));
        x.send('main', null);
      }
    }, 'main', useWorkers: false);

    expect(await completer.future, isTrue);
  });

  test('local main to other sends message', () async {
    var completer = Completer<bool>();
    Future.delayed(
        Duration(milliseconds: 200), () => completer.complete(false));
    Concur.start({
      'main': (x) {
        x.send('other', null);
      },
      'other': (x) {
        x.getChannel('main').listen((y) => completer.complete(true));
      }
    }, 'main', useWorkers: false);

    expect(await completer.future, isTrue);
  });
}
