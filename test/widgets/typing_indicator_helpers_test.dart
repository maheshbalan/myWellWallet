// Unit tests for WP1-04: identity-based typing indicator handling.

import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/widgets/typing_indicator_helpers.dart';

void main() {
  group('buildTypingIndicator', () {
    test('has the identity tag', () {
      final m = buildTypingIndicator();
      expect(m[kTypingIndicatorKey], isTrue);
      expect(isTypingIndicator(m), isTrue);
    });

    test('is not flagged as a user message', () {
      final m = buildTypingIndicator();
      expect(m['isUser'], isFalse);
    });
  });

  group('removeTypingIndicator', () {
    test('happy path: removes a tagged message that is currently the tail', () {
      final messages = <Map<String, dynamic>>[
        {'isUser': true, 'message': 'Q1'},
        buildTypingIndicator(),
      ];
      removeTypingIndicator(messages);
      expect(messages, hasLength(1));
      expect(messages.first['isUser'], isTrue);
    });

    test('tail interleaving: removes the indicator even if another message '
        'was appended after it', () {
      final messages = <Map<String, dynamic>>[
        {'isUser': true, 'message': 'Q1'},
        buildTypingIndicator(),
        // Simulate an unexpected appended message between add and remove.
        {'isUser': false, 'message': 'interloper'},
      ];
      removeTypingIndicator(messages);
      expect(messages.map((m) => m['message']), ['Q1', 'interloper']);
    });

    test('no-op when no indicator is present', () {
      final messages = <Map<String, dynamic>>[
        {'isUser': true, 'message': 'Q1'},
        {'isUser': false, 'message': 'A1'},
      ];
      removeTypingIndicator(messages);
      expect(messages, hasLength(2));
    });

    test('removes every indicator if the list somehow contains more than one', () {
      final messages = <Map<String, dynamic>>[
        buildTypingIndicator(),
        {'isUser': true, 'message': 'Q1'},
        buildTypingIndicator(),
      ];
      removeTypingIndicator(messages);
      expect(messages, hasLength(1));
      expect(messages.first['message'], 'Q1');
    });

    test('does not mistake a non-tagged message containing the word "typing" '
        'for the indicator', () {
      final messages = <Map<String, dynamic>>[
        {'isUser': true, 'message': 'i was typing something'},
        buildTypingIndicator(),
      ];
      removeTypingIndicator(messages);
      expect(messages, hasLength(1));
      expect(messages.first['message'], 'i was typing something');
    });
  });
}
