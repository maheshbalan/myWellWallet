import 'dart:async';
import 'dart:convert';

import 'database_service.dart';
import 'gemma_model_service.dart';
import 'log_service.dart';
import 'sql_guard.dart';
import 'sqlite_query_prompt.dart';
import 'clinical_source_store.dart';
import 'local_health_answers.dart';

/// Turns a question into a SQLite SELECT by asking MedGemma, using the schema
/// in the system prompt. Preset resource-type plans are not used.
class GemmaRAGService {
  GemmaRAGService({required DatabaseService databaseService})
      : _databaseService = databaseService;

  final DatabaseService _databaseService;
  final List<Map<String, String>> _conversationHistory = [];
  bool _initialized = false;

  /// On-device prompt budget for the schema plus the question.
  /// Stays under the iOS context window (2048 tokens) with room to answer.
  static const int sqlPromptBudget = 4500;

  Future<void> initialize() async {
    if (_initialized) return;
    unawaited(GemmaModelService.instance.ensureInitialized());
    _initialized = true;
  }

  Future<Map<String, dynamic>> processQuery(
    String query, {
    String? userId,
  }) async {
    if (!_initialized) await initialize();
    addToHistory('user', query);

    final direct = await LocalHealthAnswers.tryAnswer(
      database: _databaseService,
      question: query,
      userId: userId,
    );
    if (direct != null) return direct;

    final gemma = GemmaModelService.instance;
    if (!gemma.isReady) {
      return {
        'type': 'message',
        'message':
            'MedGemma is still loading on this phone. Ask again when the model is ready. '
            'It writes the database query from the schema.',
      };
    }

    await ClinicalSourceStore.instance.ensureLoaded();
    final patientIds = await _databaseService.listFhirPatientIds();
    final prompt = buildSqliteQueryPrompt(
      question: query,
      clinicalSource: ClinicalSourceStore.instance.value,
      userId: userId ?? '',
      patientIds: patientIds,
      history: _recentHistory(),
    );

    String? response;
    try {
      response = await gemma
          .generate(prompt, promptCharBudget: sqlPromptBudget)
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      LogService.log('GemmaRAGService: SQL generation failed: $e');
      response = null;
    }
    if (response == null || response.trim().isEmpty) {
      return {
        'type': 'message',
        'message': 'MedGemma did not return a query. Try asking again in a moment.',
      };
    }

    final parsed = _parseModelJson(response);
    if (parsed != null && parsed['needsClarification'] == true) {
      final question = parsed['question'];
      return {
        'type': 'clarification',
        'question': question is String && question.isNotEmpty
            ? question
            : 'Could you say a bit more about what you want to look up?',
        'options': null,
      };
    }

    final sql = _sqlFromResponse(response, parsed);
    if (sql == null) {
      LogService.log('GemmaRAGService: model reply was not a SELECT.');
      return {
        'type': 'message',
        'message': 'I could not turn that into a database read. Try asking about a lab, a vital, a medication, or a visit.',
      };
    }
    LogService.log('GemmaRAGService: MedGemma SELECT ready.');
    return {'type': 'sql', 'sql': sql};
  }

  Future<Map<String, dynamic>> executeSql(String sql) async {
    try {
      final rows = await _runSql(sql);
      if (rows.isEmpty) {
        return {
          'type': 'noResults',
          'message':
              'I looked through the records on this phone and did not find a match. '
              'If this should be clinic data, connect a provider or fetch your chart first.',
        };
      }
      return {
        'type': 'success',
        'resources': _forAnswer(rows),
        'count': rows.length,
      };
    } on SqlGuardException catch (e) {
      LogService.log('GemmaRAGService: rejected SQL: $e');
      return {
        'type': 'message',
        'message': 'I could not use that database query. Try rephrasing the question.',
      };
    } catch (e) {
      LogService.log('GemmaRAGService: SQL execution failed: $e');
      return {
        'type': 'message',
        'message': 'The database read failed. Try rephrasing the question.',
      };
    }
  }

  Future<List<Map<String, dynamic>>> _runSql(String sql) async {
    final first = repairModelSql(sql);
    try {
      return await _databaseService.runReadOnlySelect(first);
    } catch (e) {
      final second = repairModelSql(first, sqliteError: e.toString());
      if (second == first) rethrow;
      LogService.log('GemmaRAGService: retrying repaired SQL after $e');
      return _databaseService.runReadOnlySelect(second);
    }
  }

  /// Prefer decoded FHIR JSON when the row is a stored resource.
  List<Map<String, dynamic>> _forAnswer(List<Map<String, dynamic>> rows) {
    return [for (final row in rows) _decodeResourceRow(row)];
  }

  Map<String, dynamic> _decodeResourceRow(Map<String, dynamic> row) {
    final raw = row['resource_data'];
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return row;
  }

  Map<String, dynamic>? _parseModelJson(String response) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    try {
      final decoded = jsonDecode(response.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      LogService.log('GemmaRAGService: JSON parse failed: $e');
    }
    return null;
  }

  String? _sqlFromResponse(String response, Map<String, dynamic>? parsed) {
    final fromJson = parsed?['sql'];
    if (fromJson is String && fromJson.trim().isNotEmpty) return fromJson.trim();
    final match = RegExp(r'select\b[\s\S]+', caseSensitive: false).firstMatch(response.trim());
    final sql = match?.group(0)?.trim();
    if (sql == null || sql.isEmpty) return null;
    return sql;
  }

  String _recentHistory() {
    if (_conversationHistory.length < 2) return '';
    final prior = _conversationHistory.sublist(0, _conversationHistory.length - 1);
    final tail = prior.length > 2 ? prior.sublist(prior.length - 2) : prior;
    final text = tail
        .map((turn) => '${turn['role']}: ${turn['content'] ?? ''}')
        .join('\n');
    if (text.length <= 400) return text;
    return text.substring(text.length - 400);
  }

  void addToHistory(String role, String content) {
    _conversationHistory.add({'role': role, 'content': content});
    if (_conversationHistory.length > 10) {
      _conversationHistory.removeAt(0);
    }
  }

  void clearHistory() {
    _conversationHistory.clear();
  }
}
