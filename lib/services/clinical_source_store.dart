import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/oneup_config.dart';

/// Which clinical chart the app reads: the FHIR MCP server, or 1up.
///
/// Stored on the device as `clinical_record_source`. Default is `mcp`.
/// A production build ([OneUpConfig.lockToOneUp]) forces `oneup` and ignores writes.
class ClinicalSourceStore extends ChangeNotifier {
  ClinicalSourceStore._();

  static final ClinicalSourceStore instance = ClinicalSourceStore._();

  static const preferenceKey = 'clinical_record_source';

  String _source = 'mcp';
  bool _loaded = false;

  bool get isLoaded => _loaded;

  bool get usesOneUp => OneUpConfig.lockToOneUp || _source == 'oneup';

  bool get usesMcp => !usesOneUp;

  bool get showsToggle => !OneUpConfig.lockToOneUp;

  bool get showsFetchData => usesMcp;

  /// `mcp` or `oneup`, after the production lock is applied.
  String get value => usesOneUp ? 'oneup' : 'mcp';

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(preferenceKey);
    if (stored == 'oneup' || stored == 'mcp') {
      _source = stored!;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setSource(String source) async {
    if (OneUpConfig.lockToOneUp) return;
    if (source != 'mcp' && source != 'oneup') return;
    if (_source == source && _loaded) return;
    _source = source;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, source);
    notifyListeners();
  }
}
