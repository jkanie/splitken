import 'package:shared_preferences/shared_preferences.dart';

/// Where the app keeps its groups between runs: a plain string store, such
/// that tests can swap in [MemoryKeyValueStore].
abstract class KeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Keeps strings in the device's shared preferences.
class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore(this._prefs);

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> delete(String key) => _prefs.remove(key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
