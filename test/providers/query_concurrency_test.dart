// Unit tests for WP1-05 concurrency guards.

import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/providers/query_concurrency.dart';

void main() {
  group('shouldAcceptNewQuery', () {
    test('accepts a normal query when idle', () {
      expect(
        shouldAcceptNewQuery(
          isStreaming: false,
          isProcessing: false,
          query: 'show my medications',
        ),
        isTrue,
      );
    });

    test('rejects an empty query', () {
      expect(
        shouldAcceptNewQuery(
          isStreaming: false,
          isProcessing: false,
          query: '',
        ),
        isFalse,
      );
    });

    test('rejects a whitespace-only query', () {
      expect(
        shouldAcceptNewQuery(
          isStreaming: false,
          isProcessing: false,
          query: '   \n\t',
        ),
        isFalse,
      );
    });

    test('rejects while streaming', () {
      expect(
        shouldAcceptNewQuery(
          isStreaming: true,
          isProcessing: false,
          query: 'another',
        ),
        isFalse,
      );
    });

    test('rejects while provider is still processing', () {
      expect(
        shouldAcceptNewQuery(
          isStreaming: false,
          isProcessing: true,
          query: 'another',
        ),
        isFalse,
      );
    });

    test('rejects when both flags are set', () {
      expect(
        shouldAcceptNewQuery(
          isStreaming: true,
          isProcessing: true,
          query: 'another',
        ),
        isFalse,
      );
    });
  });

  group('isInputLocked', () {
    test('idle: unlocked', () {
      expect(
        isInputLocked(isStreaming: false, isProcessing: false),
        isFalse,
      );
    });

    test('streaming: locked', () {
      expect(
        isInputLocked(isStreaming: true, isProcessing: false),
        isTrue,
      );
    });

    test('processing: locked', () {
      expect(
        isInputLocked(isStreaming: false, isProcessing: true),
        isTrue,
      );
    });

    test('both: locked', () {
      expect(
        isInputLocked(isStreaming: true, isProcessing: true),
        isTrue,
      );
    });
  });
}
