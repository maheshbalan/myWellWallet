// Unit tests for WP1-12: stream timeout user signal.

import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/services/gemma_service.dart';

import '../_helpers/fake_gemma_model.dart';

void main() {
  group('GemmaService.applyTimeoutAndFallback', () {
    const fastTimeout = Duration(milliseconds: 100);

    test('Scenario A: partial stream then timeout → partial tokens + '
        'truncation notice yielded; recorded turn excludes the notice',
        () async {
      String? recorded;
      final out = <String>[];

      final script = scriptedTokenStream(
        ['Here', ' is', ' a'],
        hangAfter: true,
      );

      await for (final chunk in GemmaService.applyTimeoutAndFallback(
        tokens: script,
        timeout: fastTimeout,
        summary: const [],
        noRecordsMessage: 'n/a',
        recordModelTurn: (text) => recorded = text,
      )) {
        out.add(chunk);
      }

      // Tokens are yielded as they arrive; the truncation notice shows
      // up at the end.
      expect(out.take(3).toList(), ['Here', ' is', ' a']);
      expect(out.last, GemmaService.truncationNotice);

      // Recorded turn is the trimmed real response — notice NOT included.
      expect(recorded, 'Here is a');
      expect(recorded, isNot(contains('truncated')));
    });

    test('Scenario B: zero tokens + timeout → structured fallback yielded, '
        'recordModelTurn NOT called', () async {
      var recordCalled = false;
      final out = <String>[];

      await for (final chunk in GemmaService.applyTimeoutAndFallback(
        tokens: silentHangingStream(),
        timeout: fastTimeout,
        summary: const [
          {'Type': 'Observation', 'Date': '2026-01-01', 'Test': 'Glucose', 'Result': '92'},
        ],
        noRecordsMessage: 'n/a',
        recordModelTurn: (_) => recordCalled = true,
      )) {
        out.add(chunk);
      }

      expect(recordCalled, isFalse,
          reason: 'Zero-token path should not record a model turn');
      expect(out, hasLength(1));
      // Falls back to formatSummaryAsMarkdown output
      expect(out.first, contains('### Observation'));
      expect(out.first, contains('Glucose'));
    });

    test('Scenario C: stream completes normally → tokens yielded verbatim, '
        'no truncation notice, recorded turn matches', () async {
      String? recorded;
      final out = <String>[];

      await for (final chunk in GemmaService.applyTimeoutAndFallback(
        tokens: scriptedTokenStream(['A', 'B', 'C']),
        timeout: fastTimeout,
        summary: const [],
        noRecordsMessage: 'n/a',
        recordModelTurn: (text) => recorded = text,
      )) {
        out.add(chunk);
      }

      expect(out, ['A', 'B', 'C']);
      expect(recorded, 'ABC');
      expect(out, isNot(contains(GemmaService.truncationNotice)));
    });

    test('Scenario D: zero tokens + empty summary → emits noRecordsMessage',
        () async {
      final out = <String>[];
      await for (final chunk in GemmaService.applyTimeoutAndFallback(
        tokens: silentHangingStream(),
        timeout: fastTimeout,
        summary: const [],
        noRecordsMessage: 'Nothing to show',
        recordModelTurn: (_) {},
      )) {
        out.add(chunk);
      }
      expect(out, ['Nothing to show']);
    });
  });

  group('GemmaService.formatSummaryAsMarkdown', () {
    test('renders basic fields as sections + bullets', () {
      final md = GemmaService.formatSummaryAsMarkdown(const [
        {
          'Type': 'Immunization',
          'Date': '2024-03-01',
          'Vaccine': 'Flu',
          'Status': 'Completed',
        },
      ]);
      expect(md, contains('### Immunization (2024-03-01)'));
      expect(md, contains('**Vaccine**: Flu'));
      expect(md, contains('**Status**: Completed'));
    });
  });
}
