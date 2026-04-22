// WP1-09 verification: only one GemmaService() is constructed in lib/.
//
// Before WP1-09, both QueryProvider and HomeScreen constructed their own
// GemmaService instance, which meant conversation history diverged. This
// regression test scans the source tree and asserts that exactly one
// `GemmaService()` invocation exists under lib/, preventing the pattern
// from reappearing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GemmaService is constructed in exactly one place under lib/', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: 'lib/ must exist when this test runs');

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    // Match `GemmaService(` only in construction contexts — preceded by
    // `= ` or `new `. This avoids counting the class's own constructor
    // signature in lib/services/gemma_service.dart and any type
    // references in field/param declarations.
    final ctorPattern = RegExp(r'(?:=\s*|new\s+)GemmaService\(');

    final hits = <String>[];
    for (final file in dartFiles) {
      final content = file.readAsStringSync();
      for (final match in ctorPattern.allMatches(content)) {
        // Capture the line containing the match for a useful failure message.
        final prefix = content.substring(0, match.start);
        final lineNumber = prefix.split('\n').length;
        hits.add('${file.path}:$lineNumber');
      }
    }

    expect(hits, hasLength(1),
        reason:
            'Expected exactly one GemmaService() construction site after '
            'WP1-09 consolidation. Found ${hits.length}: $hits');
    expect(hits.single, endsWith('query_provider.dart:16'),
        reason: 'The canonical construction site should be in '
            'lib/providers/query_provider.dart line 16. Actual: ${hits.single}');
  });
}
