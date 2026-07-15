import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrogram/core/constants.dart';
import 'package:spectrogram/models/app_settings.dart';

/// Persists [AppSettings] as a JSON blob in shared_preferences.
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsRepository(prefs);
  }

  AppSettings load() {
    final json = _prefs.getString(AppConstants.settingsStorageKey);
    if (json == null || json.isEmpty) {
      return AppSettings.defaults;
    }
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        return AppSettings.fromMap(decoded);
      }
      if (decoded is Map) {
        return AppSettings.fromMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Fall through to defaults.
    }
    return AppSettings.defaults;
  }

  Future<void> save(AppSettings settings) async {
    await _prefs.setString(
      AppConstants.settingsStorageKey,
      jsonEncode(settings.toMap()),
    );
  }

  Future<void> resetToDefaults() async {
    await _prefs.remove(AppConstants.settingsStorageKey);
  }
}
