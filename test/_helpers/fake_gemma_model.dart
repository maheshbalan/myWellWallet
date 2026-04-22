// Test helper: scripted token streams for exercising GemmaService
// without loading the real MedGemma model. WP1-12.
//
// Uses StreamController-backed streams instead of async* + Completer so
// that when the consumer's timeout fires and cancels the subscription,
// the source cleans up deterministically and doesn't leave a pending
// async* body pinned on the test-runner's event loop.

import 'dart:async';

/// Emits [tokens] in order with [delayBetween] between them. If
/// [hangAfter] is true, the stream stays open with no more events until
/// its subscription is canceled (e.g. by a downstream `.timeout` closing
/// its sink); otherwise it completes cleanly.
Stream<String> scriptedTokenStream(
  List<String> tokens, {
  Duration delayBetween = const Duration(milliseconds: 5),
  bool hangAfter = false,
}) {
  final controller = StreamController<String>();
  Timer? ticker;
  var index = 0;

  void emitNext() {
    if (controller.isClosed) return;
    if (index >= tokens.length) {
      if (!hangAfter) controller.close();
      return;
    }
    controller.add(tokens[index++]);
    ticker = Timer(delayBetween, emitNext);
  }

  controller
    ..onListen = () {
      ticker = Timer(delayBetween, emitNext);
    }
    ..onCancel = () {
      ticker?.cancel();
    };

  return controller.stream;
}

/// Never yields anything and never closes until its subscription is
/// canceled. Simulates a model that never produces a first token so the
/// consumer's timeout fires on an empty stream.
Stream<String> silentHangingStream() {
  final controller = StreamController<String>();
  // No onListen body — we simply never add an event. onCancel lets the
  // subscriber (e.g. timeout transformer closing its sink) tear down
  // cleanly.
  controller.onCancel = () {};
  return controller.stream;
}
