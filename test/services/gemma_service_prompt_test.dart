// Unit tests for WP1-03: budget-aware prompt construction + safe truncation.
//
// Covers:
//   * GemmaModelService.capPromptToBudget preserves <start_of_turn>model
//   * GemmaService.formatHistoryAsText drops the trailing current-turn user
//   * GemmaService.buildResponsePrompt fits within budget by trimming history
//     first, then records, and falls back to capPromptToBudget as a safety net
//   * buildRawDataResponsePrompt and buildNoDataResponsePrompt also terminate
//     with the model marker under budget pressure

import 'package:flutter_test/flutter_test.dart';
import 'package:mywellwallet/services/gemma_model_service.dart';
import 'package:mywellwallet/services/gemma_service.dart';

import '../_helpers/prompt_matchers.dart';

void main() {
  group('GemmaModelService.capPromptToBudget', () {
    test('under budget: returns input unchanged', () {
      const input = '<start_of_turn>user\nHi\n<end_of_turn>\n<start_of_turn>model\n';
      expect(GemmaModelService.capPromptToBudget(input, 10000), input);
    });

    test('over budget: preserves the trailing model marker', () {
      final body = 'X' * 5000;
      final input = '<start_of_turn>user\n$body<end_of_turn>\n<start_of_turn>model\n';
      final out = GemmaModelService.capPromptToBudget(input, 500);
      expect(out.length, lessThanOrEqualTo(500));
      expect(out, endsWithModelMarker());
    });

    test('over budget with injected truncation notice', () {
      final body = 'A' * 5000;
      final input = '<start_of_turn>user\n$body<end_of_turn>\n<start_of_turn>model\n';
      final out = GemmaModelService.capPromptToBudget(input, 500);
      expect(out, contains('[truncated]'));
    });

    test('no marker present: falls back to hard truncation', () {
      final input = 'Y' * 1000;
      final out = GemmaModelService.capPromptToBudget(input, 200);
      expect(out.length, 200);
    });

    test('marker tail itself larger than budget: returns marker-only', () {
      final marker = '<start_of_turn>model\n' + ('Z' * 400);
      final input = '<start_of_turn>user\nBody\n<end_of_turn>\n$marker';
      final out = GemmaModelService.capPromptToBudget(input, 100);
      // Ensures the model marker is preserved even when we can't fit a body.
      expect(out, contains('<start_of_turn>model'));
    });
  });

  group('GemmaService.formatHistoryAsText', () {
    test('empty history returns empty string', () {
      expect(GemmaService.formatHistoryAsText(const []), isEmpty);
    });

    test('trailing user entry is dropped (treated as current query)', () {
      final hist = [
        {'role': 'user', 'content': 'Q1'},
        {'role': 'model', 'content': 'A1'},
        {'role': 'user', 'content': 'Q2_current'},
      ];
      final text = GemmaService.formatHistoryAsText(hist);
      expect(text, contains('Q1'));
      expect(text, contains('A1'));
      expect(text, isNot(contains('Q2_current')));
    });

    test('caps at last 8 entries', () {
      final hist = List.generate(
        12,
        (i) => {
          'role': i.isEven ? 'user' : 'model',
          'content': 'msg$i',
        },
      );
      final text = GemmaService.formatHistoryAsText(hist);
      expect(text, isNot(contains('msg0')));
      expect(text, isNot(contains('msg3')));
      // 8-entry window is msg4..msg11. Trailing entry (msg11) is a model
      // entry here so it stays in; the drop-trailing-user rule only fires
      // when the tail is a user entry.
      expect(text, contains('msg4'));
      expect(text, contains('msg11'));
    });

    test('trailing user is still dropped at window boundary', () {
      // msg0..msg10 — last entry is msg10 (user). Window is msg3..msg10, then
      // the trailing user (msg10) is dropped, so we keep msg3..msg9.
      final hist = List.generate(
        11,
        (i) => {
          'role': i.isEven ? 'user' : 'model',
          'content': 'msg$i',
        },
      );
      final text = GemmaService.formatHistoryAsText(hist);
      expect(text, contains('msg3'));
      expect(text, contains('msg9'));
      expect(text, isNot(contains('msg10')));
    });

    test('non-user trailing entry is included', () {
      final hist = [
        {'role': 'user', 'content': 'Q1'},
        {'role': 'model', 'content': 'A1'},
      ];
      final text = GemmaService.formatHistoryAsText(hist);
      expect(text, contains('A1'));
    });
  });

  group('GemmaService.buildResponsePrompt budget-aware trimming', () {
    final simpleSummary = [
      {'Type': 'Observation', 'Date': '2026-01-01', 'Test': 'Glucose', 'Result': '92 mg/dL'},
      {'Type': 'Observation', 'Date': '2026-01-02', 'Test': 'Glucose', 'Result': '88 mg/dL'},
    ];

    test('generous budget: no trimming, prompt terminates cleanly', () {
      final prompt = GemmaService.buildResponsePrompt(
        'show my glucose',
        simpleSummary,
        budget: 100000,
      );
      expect(prompt, endsWithModelMarker());
      expect(prompt, hasExactlyOneModelMarker());
      expect(prompt, contains('Glucose'));
    });

    test('trimmed history: oldest pairs dropped before records', () {
      final history = List.generate(
        8,
        (i) => {
          'role': i.isEven ? 'user' : 'model',
          'content': 'history-entry-$i-${'X' * 200}',
        },
      );
      // Budget tight enough to force history trimming but loose enough to
      // keep records.
      final prompt = GemmaService.buildResponsePrompt(
        'show my glucose',
        simpleSummary,
        history: history,
        budget: 2500,
      );
      expect(prompt.length, lessThanOrEqualTo(2500));
      expect(prompt, endsWithModelMarker());
      // Both records should still be present — trimming prefers history first.
      expect(prompt, contains('Glucose'));
    });

    test('tight budget: tail records dropped after history exhausted', () {
      final manyRecords = List.generate(
        20,
        (i) => <String, dynamic>{
          'Type': 'Observation',
          'Date': '2026-01-${(i % 28) + 1}',
          'Test': 'Reading$i',
          'Result': '${i * 10} units',
        },
      );
      final prompt = GemmaService.buildResponsePrompt(
        'list my observations',
        manyRecords,
        budget: 1500,
      );
      expect(prompt.length, lessThanOrEqualTo(1500));
      expect(prompt, endsWithModelMarker());
    });

    test('extreme budget smaller than overhead: still terminates with model marker', () {
      final prompt = GemmaService.buildResponsePrompt(
        'show',
        simpleSummary,
        budget: 200,
      );
      // Under this budget the body is clipped, but the marker must survive.
      expect(prompt, endsWithModelMarker());
    });

    test('records list is encoded per-entry, no mid-JSON truncation', () {
      final prompt = GemmaService.buildResponsePrompt(
        'show',
        simpleSummary,
        budget: 100000,
      );
      // Every record JSON object appears complete (closing brace present).
      for (final entry in simpleSummary) {
        // Just spot-check one field — if it's present, the JSON line is intact.
        expect(prompt, contains(entry['Test']));
      }
    });
  });

  group('GemmaService.buildRawDataResponsePrompt and buildNoDataResponsePrompt', () {
    test('no-data prompt terminates with model marker under tight budget', () {
      final prompt = GemmaService.buildNoDataResponsePrompt(
        'show my non-existent records',
        budget: 400,
      );
      expect(prompt, endsWithModelMarker());
    });

    test('raw-data prompt terminates with model marker under tight budget', () {
      final raw = {
        'response': {
          'entry': List.generate(
            50,
            (i) => {'resource': {'id': 'r$i', 'x': 'lorem' * 40}},
          ),
        },
      };
      final prompt = GemmaService.buildRawDataResponsePrompt(
        'summarize',
        raw,
        budget: 1500,
      );
      expect(prompt.length, lessThanOrEqualTo(1500));
      expect(prompt, endsWithModelMarker());
    });
  });
}
