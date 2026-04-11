import 'package:shared_preferences/shared_preferences.dart';

abstract class KeyValueStorage {
  Future<void> set(String key, String value);
  Future<String?> get(String key);
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  );
  Future<void> remove(String key);
  Future<void> clear();
}

class DartKeyValue implements KeyValueStorage {
  SharedPreferences? _sharedPreferences;
  SharedPreferences get sharedPreferences => _sharedPreferences!;

  @override
  Future<String?> get(String key) async {
    await _initSharedPreferencesIfNeeded();

    if (_sharedPreferences == null) {
      return null;
    }

    final value = _sharedPreferences!.getString(key);
    if (value != null) {
      return value;
    }
    return null;
  }

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = await get(key);
    if (value == null) {
      return null;
    }
    return formatter(value);
  }

  @override
  Future<void> remove(String key) async {
    await _initSharedPreferencesIfNeeded();

    if (_sharedPreferences != null) {
      await _sharedPreferences!.remove(key);
    }
  }

  @override
  Future<void> set(String key, String value) async {
    await _initSharedPreferencesIfNeeded();

    if (_sharedPreferences != null) {
      await _sharedPreferences!.setString(key, value);
    }
  }

  @override
  Future<void> clear() async {
    await _initSharedPreferencesIfNeeded();

    if (_sharedPreferences != null) {
      await _sharedPreferences!.clear();
    }
  }

  Future<void> _initSharedPreferencesIfNeeded() async {
    if (_sharedPreferences == null) {
      try {
        _sharedPreferences = await SharedPreferences.getInstance();
      } catch (e) {
        // 处理SharedPreferences初始化失败的情况
        // 此时_sharedPreferences仍然为null，后续的get/set操作会返回null或什么都不做
      }
    }
  }
}
