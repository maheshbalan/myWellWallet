/// Lets MedGemma run a single read against the local database.
///
/// The model chooses the SELECT from the schema prompt. This guard only
/// rejects writes and tables that are not part of the health record.
class SqlGuardException implements Exception {
  SqlGuardException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SqlGuard {
  static const allowedTables = <String>{
    'users',
    'fhir_patients',
    'fhir_resources',
    'fetch_summaries',
    'health_glucose',
    'health_heart_rate',
    'health_steps',
    'health_blood_pressure',
    'health_lab_results',
    'health_sync_settings',
    'oneup_connections',
  };

  static const _forbidden = <String>{
    'insert',
    'update',
    'delete',
    'drop',
    'alter',
    'attach',
    'detach',
    'pragma',
    'replace',
    'vacuum',
    'create',
    'reindex',
    'trigger',
    'grant',
    'begin',
    'commit',
    'rollback',
  };

  /// Returns a single SELECT, with a row cap when the model omitted LIMIT.
  static String prepare(String raw) {
    var sql = raw.trim();
    if (sql.endsWith(';')) {
      sql = sql.substring(0, sql.length - 1).trim();
    }
    if (sql.isEmpty) {
      throw SqlGuardException('The query was empty.');
    }
    if (sql.contains(';')) {
      throw SqlGuardException('Only one statement is allowed.');
    }
    if (sql.contains('--') || sql.contains('/*') || sql.contains('*/')) {
      throw SqlGuardException('Comments are not allowed in a generated query.');
    }
    if (!RegExp(r'^select\b', caseSensitive: false).hasMatch(sql)) {
      throw SqlGuardException('Only a SELECT can be run.');
    }
    if (RegExp(r'\bfhir_bundle\b', caseSensitive: false).hasMatch(sql)) {
      throw SqlGuardException('Select columns from fhir_resources, not the full bundle.');
    }

    final words = RegExp(r'[A-Za-z_]+').allMatches(sql).map((m) => m.group(0)!.toLowerCase());
    for (final word in words) {
      if (_forbidden.contains(word)) {
        throw SqlGuardException('That statement is not a read.');
      }
    }

    final tables = <String>{};
    final tablePattern = RegExp(
      r'\b(?:from|join)\s+([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false,
    );
    for (final match in tablePattern.allMatches(sql)) {
      tables.add(match.group(1)!.toLowerCase());
    }
    if (tables.isEmpty) {
      throw SqlGuardException('The query did not name a table.');
    }
    for (final table in tables) {
      if (!allowedTables.contains(table)) {
        throw SqlGuardException('That table is not part of the health record.');
      }
    }

    final limit = RegExp(r'\blimit\s+(\d+)\b', caseSensitive: false).firstMatch(sql);
    if (limit == null) {
      return '$sql LIMIT 50';
    }
    final n = int.tryParse(limit.group(1)!);
    if (n == null || n < 1 || n > 100) {
      throw SqlGuardException('LIMIT must be between 1 and 100.');
    }
    return sql;
  }
}
