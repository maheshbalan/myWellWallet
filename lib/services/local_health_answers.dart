import 'package:intl/intl.dart' hide TextDirection;

import 'package:flutter/foundation.dart';

import 'clinical_source_store.dart';
import 'database_service.dart';
import 'local_query_service.dart';

/// Answers the home screen's standard questions and blood-glucose questions
/// from SQLite directly. MedGemma still answers everything else.
class LocalHealthAnswers {
  static Future<Map<String, dynamic>?> tryAnswer({
    required DatabaseService database,
    required String question,
    String? userId,
  }) async {
    final q = question.toLowerCase();
    await ClinicalSourceStore.instance.ensureLoaded();
    final oneUp = ClinicalSourceStore.instance.usesOneUp;

    if (_isGlucose(q)) {
      return _glucose(database, q, userId);
    }
    final namedLab = await _namedLab(database, q, userId, oneUp);
    if (namedLab != null) return namedLab;
    if (_has(q, ['recent visit', 'my visits', 'visit', 'appointment', 'encounter'])) {
      return _fhir(
        database,
        const ['Encounter'],
        oneUp,
        'I could not find visits on this phone.',
      );
    }
    if (_has(q, ['immunization', 'vaccine', 'vaccination', 'shot'])) {
      return _fhir(
        database,
        const ['Immunization'],
        oneUp,
        'I could not find immunizations on this phone.',
      );
    }
    if (_has(q, ['test result', 'lab result', 'diagnostic'])) {
      return _labs(database, userId, oneUp);
    }
    if (_has(q, ['medication', 'medicine', 'prescription', 'drug'])) {
      return _fhir(
        database,
        const ['MedicationRequest', 'MedicationStatement', 'MedicationDispense'],
        oneUp,
        'I could not find medications on this phone.',
      );
    }
    if (_has(q, ['condition', 'diagnosis', 'diagnosed'])) {
      return _fhir(
        database,
        const ['Condition'],
        oneUp,
        'I could not find conditions on this phone.',
      );
    }
    if (_has(q, ['allerg'])) {
      return _fhir(
        database,
        const ['AllergyIntolerance'],
        oneUp,
        'I could not find allergies on this phone.',
      );
    }
    return null;
  }

  static bool _isGlucose(String q) {
    if (q.contains('blood pressure')) return false;
    return q.contains('blood sugar') ||
        q.contains('blood glucose') ||
        q.contains('glucose') ||
        q.contains('cgm');
  }

  static bool _has(String q, List<String> keys) => keys.any(q.contains);

  static const _labStopwords = {
    'latest', 'recent', 'last', 'levels', 'level', 'what', 'show', 'blood',
    'test', 'tests', 'result', 'results', 'value', 'values', 'reading',
    'readings', 'have', 'from', 'about', 'please', 'labs', 'laboratory',
    'panel', 'current', 'today', 'yesterday', 'week', 'month', 'much',
    'many', 'does', 'did', 'was', 'were', 'this', 'that', 'with', 'your',
    'mine', 'tell', 'give', 'need', 'want', 'know', 'personal', 'records',
    'record', 'number', 'numbers', 'when', 'where', 'which', 'could',
    'would', 'should', 'there', 'their', 'been', 'being', 'into', 'over',
    'under', 'than', 'then', 'just', 'only', 'also', 'some', 'more', 'most',
    'high', 'low', 'normal', 'abnormal', 'range', 'ranges', 'phone', 'data',
  };

  static const _shortLabWords = {
    'a1c', 'ldl', 'hdl', 'tsh', 'bun', 'inr', 'egfr', 'psa', 'wbc', 'rbc',
    'alt', 'ast', 'ggt', 'crp', 'mcv', 'mch', 'plt',
  };

  /// Words in the question that can name a lab, such as creatinine.
  @visibleForTesting
  static List<String> labTokens(String question) {
    final words = RegExp(r'[a-z0-9]+').allMatches(question.toLowerCase()).map((m) => m.group(0)!);
    final tokens = <String>[];
    for (final word in words) {
      if (_labStopwords.contains(word)) continue;
      if (word.length >= 5 || _shortLabWords.contains(word) || LocalQueryService.medicalTermLoincCodes.containsKey(word)) {
        if (!tokens.contains(word)) tokens.add(word);
      }
    }
    return tokens.take(4).toList();
  }

  @visibleForTesting
  static bool labRowMatches(Map<String, dynamic> row, List<String> tokens) {
    final name = (row['name'] as String? ?? '').toLowerCase();
    final loinc = (row['loinc_code'] as String?)?.trim() ?? '';
    for (final token in tokens) {
      if (RegExp('\\b${RegExp.escape(token)}\\b').hasMatch(name)) return true;
      final codes = LocalQueryService.medicalTermLoincCodes[token];
      if (codes != null && loinc.isNotEmpty && codes.contains(loinc)) return true;
    }
    return false;
  }

  static bool _asksForOwnRecord(String q) {
    return q.contains('my ') ||
        q.contains('latest') ||
        q.contains('last ') ||
        q.contains('current') ||
        q.contains('level') ||
        q.contains('result') ||
        q.contains('value');
  }

  static Future<Map<String, dynamic>?> _namedLab(
    DatabaseService database,
    String q,
    String? userId,
    bool oneUp,
  ) async {
    final tokens = labTokens(q);
    if (tokens.isEmpty) return null;
    final hits = <_LabHit>[];
    if (userId != null && userId.isNotEmpty) {
      final labs = await database.getHealthLabResults(userId, limit: 2000);
      for (final row in labs.where((row) => labRowMatches(row, tokens))) {
        hits.add(_LabHit.fromLab(row));
      }
    }
    if (hits.isEmpty) {
      for (final token in tokens) {
        final fhir = await database.searchFhirByText(needle: token, oneUpOnly: oneUp);
        for (final row in fhir) {
          final hit = _LabHit.fromFhir(row, tokens);
          if (hit != null) hits.add(hit);
        }
      }
    }
    if (hits.isEmpty) {
      final namedTest = tokens.any(
        (token) =>
            _shortLabWords.contains(token) ||
            LocalQueryService.medicalTermLoincCodes.containsKey(token),
      );
      if (namedTest && _asksForOwnRecord(q)) {
        return {
          'type': 'message',
          'message': 'I could not find ${tokens.join(' / ')} in the records on this phone.',
        };
      }
      return null;
    }
    hits.sort((a, b) => (b.at ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(a.at ?? DateTime.fromMillisecondsSinceEpoch(0)));
    final latestOnly = q.contains('latest') || q.contains('last ') || q.contains('current') || q.contains('most recent');
    final grouped = <String, List<_LabHit>>{};
    for (final hit in hits) {
      grouped.putIfAbsent(hit.name.toLowerCase(), () => []).add(hit);
    }
    final buffer = StringBuffer();
    final names = grouped.keys.toList();
    for (final key in names.take(6)) {
      final rows = grouped[key]!;
      final shown = latestOnly ? rows.take(4).toList() : rows.take(6).toList();
      buffer.writeln('**${rows.first.name}**');
      for (var i = 0; i < shown.length; i++) {
        final label = i == 0 ? 'Latest' : 'Earlier';
        buffer.writeln('* **$label:** ${shown[i].line}');
      }
      buffer.writeln();
    }
    return {'type': 'message', 'message': buffer.toString().trim()};
  }

  static Duration _window(String q) {
    if (q.contains('yesterday') || q.contains('last day') || q.contains('today') || q.contains('past day')) {
      return const Duration(days: 1);
    }
    if (q.contains('last month') || q.contains('past month') || q.contains('30 day')) {
      return const Duration(days: 30);
    }
    if (q.contains('last week') || q.contains('past week') || q.contains('7 day')) {
      return const Duration(days: 7);
    }
    return const Duration(days: 7);
  }

  static String _windowLabel(Duration window) {
    if (window.inDays <= 1) return 'the last day';
    if (window.inDays <= 7) return 'the last week';
    return 'the last month';
  }

  static Future<Map<String, dynamic>> _glucose(
    DatabaseService database,
    String q,
    String? userId,
  ) async {
    if (userId == null || userId.isEmpty) {
      return {
        'type': 'message',
        'message': 'Sign in before asking about blood glucose.',
      };
    }
    final window = _window(q);
    final cutoff = DateTime.now().subtract(window);
    final rows = await database.getHealthGlucose(userId, limit: 20000);
    final matched = rows.where((row) {
      final at = row['recorded_at'];
      return at is DateTime && !at.isBefore(cutoff);
    }).toList();
    if (matched.isEmpty) {
      return {
        'type': 'message',
        'message': 'I could not find blood glucose readings for ${_windowLabel(window)} on this phone.',
      };
    }
    final values = [for (final row in matched) (row['value'] as num).toDouble()];
    final avg = values.reduce((a, b) => a + b) / values.length;
    final high = values.reduce((a, b) => a > b ? a : b);
    final low = values.reduce((a, b) => a < b ? a : b);
    final recent = matched.take(8).map((row) {
      final unit = row['unit'] ?? 'mg/dL';
      return '* ${_when(row['recorded_at'])} — ${(row['value'] as num).toStringAsFixed(0)} $unit';
    }).join('\n');
    return {
      'type': 'message',
      'message':
          '**Blood glucose, ${_windowLabel(window)}** (${values.length} readings)\n\n'
          '* **Average:** ${avg.toStringAsFixed(0)} mg/dL\n'
          '* **High:** ${high.toStringAsFixed(0)} mg/dL\n'
          '* **Low:** ${low.toStringAsFixed(0)} mg/dL\n\n'
          'Recent readings:\n$recent',
    };
  }

  static Future<Map<String, dynamic>> _fhir(
    DatabaseService database,
    List<String> types,
    bool oneUpOnly,
    String emptyMessage,
  ) async {
    final rows = await database.fhirResourcesByTypes(
      resourceTypes: types,
      oneUpOnly: oneUpOnly,
    );
    if (rows.isEmpty) return {'type': 'message', 'message': emptyMessage};
    final title = types.length == 1 ? types.first : types.join(', ');
    final lines = rows.take(20).map((row) => '* ${_resourceLine(row)}').join('\n');
    final extra = rows.length > 20 ? '\n\nShowing 20 of ${rows.length}.' : '';
    return {
      'type': 'message',
      'message': '**$title** (${rows.length})\n\n$lines$extra',
    };
  }

  static Future<Map<String, dynamic>> _labs(
    DatabaseService database,
    String? userId,
    bool oneUpOnly,
  ) async {
    final clinic = await database.fhirResourcesByTypes(
      resourceTypes: const ['DiagnosticReport'],
      oneUpOnly: oneUpOnly,
      laboratoryObservations: true,
    );
    final resources = <Map<String, dynamic>>[...clinic];
    if (userId != null && userId.isNotEmpty) {
      final labs = await database.getHealthLabLatestPerTest(userId);
      resources.addAll(labs.take(20).map(_labAsObservation));
    }
    if (resources.isEmpty) {
      return {
        'type': 'message',
        'message': 'I could not find test results on this phone.',
      };
    }
    final lines = resources.take(20).map((row) => '* ${_resourceLine(row)}').join('\n');
    final extra = resources.length > 20 ? '\n\nShowing 20 of ${resources.length}.' : '';
    return {
      'type': 'message',
      'message': '**Test results** (${resources.length})\n\n$lines$extra',
    };
  }

  static String _when(dynamic value) {
    DateTime? at;
    if (value is DateTime) at = value;
    if (value is String) at = DateTime.tryParse(value);
    if (at == null) return 'Undated';
    return DateFormat.yMMMd().add_jm().format(at.toLocal());
  }

  static String displayText(dynamic node) => _text(node);

  static String _text(dynamic node) {
    if (node is String && node.trim().isNotEmpty) return node.trim();
    if (node is Map) {
      final text = node['text'];
      if (text is String && text.trim().isNotEmpty) return text.trim();
      final coding = node['coding'];
      if (coding is List && coding.isNotEmpty && coding.first is Map) {
        final display = (coding.first as Map)['display'];
        if (display is String && display.trim().isNotEmpty) return display.trim();
      }
    }
    if (node is List && node.isNotEmpty) return _text(node.first);
    return '';
  }

  static String _resourceLine(Map<String, dynamic> row) {
    final type = (row['resourceType'] ?? 'Record').toString();
    final when = _when(
      row['effectiveDateTime'] ??
          row['occurrenceDateTime'] ??
          row['issued'] ??
          row['date'] ??
          (row['period'] is Map ? (row['period'] as Map)['start'] : null),
    );
    switch (type) {
      case 'Encounter':
        final reason = _text(row['reasonCode']).isNotEmpty
            ? _text(row['reasonCode'])
            : _text(row['type']);
        return '$when — ${reason.isEmpty ? 'Visit' : reason}';
      case 'Immunization':
        final vaccine = _text(row['vaccineCode']);
        return '$when — ${vaccine.isEmpty ? 'Immunization' : vaccine}';
      case 'DiagnosticReport':
        final name = _text(row['code']);
        return '$when — ${name.isEmpty ? 'Report' : name}';
      case 'Observation':
        final name = _text(row['code']);
        final quantity = row['valueQuantity'];
        final value = quantity is Map
            ? '${quantity['value'] ?? ''} ${quantity['unit'] ?? ''}'.trim()
            : (row['valueString'] ?? '').toString();
        return '$when — ${name.isEmpty ? 'Result' : name}${value.isEmpty ? '' : ': $value'}';
      default:
        final name = _text(row['code']);
        return '$when — ${name.isEmpty ? type : name}';
    }
  }

  static Map<String, dynamic> _labAsObservation(Map<String, dynamic> row) {
    final numeric = row['value_numeric'];
    final text = row['value_string'] as String?;
    return {
      'resourceType': 'Observation',
      'code': {'text': row['name'] ?? 'Lab test', 'coding': [
        if (row['loinc_code'] != null) {'code': row['loinc_code']},
      ]},
      'valueQuantity': numeric == null
          ? null
          : {'value': numeric, 'unit': row['unit']},
      'valueString': text,
      'effectiveDateTime': (row['recorded_at'] as DateTime).toIso8601String(),
    };
  }
}

/// Rewrites the SQL mistakes MedGemma commonly emits for this schema.
String repairModelSql(String raw, {String? sqliteError}) {
  var sql = raw.trim();
  if (sql.startsWith('```')) {
    sql = sql.replaceFirst(RegExp(r'^```(?:sql)?', caseSensitive: false), '');
    sql = sql.replaceFirst(RegExp(r'```$'), '').trim();
  }
  sql = sql.replaceAllMapped(
    RegExp(
      r"(?<!['\w])([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?!['\w])",
    ),
    (m) => "'${m.group(1)}'",
  );
  sql = sql.replaceAll(RegExp(r'\bNOW\(\)', caseSensitive: false), "datetime('now')");
  sql = sql.replaceAllMapped(
    RegExp(r"INTERVAL\s+'?(\d+)'?\s+DAYS?", caseSensitive: false),
    (m) => "datetime('now', '-${m.group(1)} days')",
  );
  final error = sqliteError?.toLowerCase() ?? '';
  if (error.contains('no such column: value') && sql.toLowerCase().contains('health_glucose')) {
    sql = sql.replaceAll(RegExp(r'\bvalue\b'), 'value_real');
  }
  if (error.contains('no such column: date') && sql.toLowerCase().contains('health_glucose')) {
    sql = sql.replaceAll(RegExp(r'\bdate\b'), 'recorded_at');
  }
  return sql;
}

class _LabHit {
  _LabHit({required this.name, required this.line, this.at});

  final String name;
  final String line;
  final DateTime? at;

  factory _LabHit.fromLab(Map<String, dynamic> row) {
    final numeric = row['value_numeric'];
    final value = numeric is num ? _trim(numeric) : '${row['value_string'] ?? ''}'.trim();
    final unit = '${row['unit'] ?? ''}'.trim();
    final range = (row['reference_range_text'] as String?)?.trim();
    final source = (row['source_name'] as String?)?.trim();
    final at = row['recorded_at'] is DateTime ? row['recorded_at'] as DateTime : null;
    return _LabHit(
      name: (row['name'] as String?)?.trim().isNotEmpty == true ? (row['name'] as String).trim() : 'Lab',
      line: _line(value, unit, at, range, source),
      at: at,
    );
  }

  static _LabHit? fromFhir(Map<String, dynamic> row, List<String> tokens) {
    final name = LocalHealthAnswers.displayText(row['code']);
    if (name.isEmpty) return null;
    final haystack = name.toLowerCase();
    final loinc = _loinc(row);
    final matches = tokens.any((token) {
      if (RegExp('\\b${RegExp.escape(token)}\\b').hasMatch(haystack)) return true;
      final codes = LocalQueryService.medicalTermLoincCodes[token];
      return codes != null && loinc.isNotEmpty && codes.contains(loinc);
    });
    if (!matches) return null;
    final quantity = row['valueQuantity'];
    final value = quantity is Map
        ? '${quantity['value'] ?? ''}'.trim()
        : '${row['valueString'] ?? ''}'.trim();
    final unit = quantity is Map ? '${quantity['unit'] ?? ''}'.trim() : '';
    final at = DateTime.tryParse('${row['effectiveDateTime'] ?? row['issued'] ?? ''}');
    return _LabHit(name: name, line: _line(value, unit, at, null, null), at: at);
  }

  static String _loinc(Map<String, dynamic> row) {
    final coding = row['code'];
    if (coding is! Map) return '';
    final list = coding['coding'];
    if (list is! List) return '';
    for (final item in list) {
      if (item is Map && '${item['system'] ?? ''}'.contains('loinc')) {
        return '${item['code'] ?? ''}'.trim();
      }
    }
    return '';
  }

  static String _line(String value, String unit, DateTime? at, String? range, String? source) {
    final bits = <String>[
      [value, unit].where((part) => part.isNotEmpty).join(' '),
      if (at != null) 'on ${DateFormat.yMMMd().format(at.toLocal())}',
      if (range != null && range.isNotEmpty) 'reference $range',
      if (source != null && source.isNotEmpty) source,
    ].where((part) => part.isNotEmpty);
    return bits.join(' · ');
  }

  static String _trim(num value) {
    final text = value.toStringAsFixed(2);
    return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}
