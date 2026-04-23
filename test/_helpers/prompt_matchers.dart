// Custom matchers for Gemma prompt structure invariants.
// Shared across WP1-03 (prompt truncation) and WP1-06 (prompt sanitization).

import 'package:flutter_test/flutter_test.dart';

/// Matches a prompt whose final non-whitespace content ends with the Gemma
/// model-turn marker (`<start_of_turn>model`). This catches truncation bugs
/// that would otherwise leave the user turn un-terminated.
Matcher endsWithModelMarker() {
  return predicate<String>(
    (s) {
      final trimmed = s.trimRight();
      return trimmed.endsWith('<start_of_turn>model');
    },
    'ends with the Gemma <start_of_turn>model marker',
  );
}

/// Matches a prompt that contains exactly one `<start_of_turn>model` marker.
/// A user query that injects control markers is caught here.
Matcher hasExactlyOneModelMarker() {
  return predicate<String>(
    (s) {
      const marker = '<start_of_turn>model';
      var count = 0;
      var idx = 0;
      while (true) {
        final next = s.indexOf(marker, idx);
        if (next < 0) break;
        count++;
        idx = next + marker.length;
      }
      return count == 1;
    },
    'contains exactly one <start_of_turn>model marker',
  );
}

/// Matches a prompt that contains no unescaped Gemma control markers in the
/// body (i.e. the only markers are the canonical wrapping pair). Useful for
/// asserting that a sanitizer stripped injected markers out of user input.
Matcher hasNoExtraTurnMarkers() {
  return predicate<String>(
    (s) {
      // Expect exactly one `<start_of_turn>user` and exactly one `<end_of_turn>`
      // and exactly one `<start_of_turn>model` — the canonical wrapping set.
      final userCount = _count(s, '<start_of_turn>user');
      final endCount = _count(s, '<end_of_turn>');
      final modelCount = _count(s, '<start_of_turn>model');
      return userCount == 1 && endCount == 1 && modelCount == 1;
    },
    'has exactly one canonical turn marker of each kind',
  );
}

int _count(String s, String needle) {
  var count = 0;
  var idx = 0;
  while (true) {
    final next = s.indexOf(needle, idx);
    if (next < 0) break;
    count++;
    idx = next + needle.length;
  }
  return count;
}
