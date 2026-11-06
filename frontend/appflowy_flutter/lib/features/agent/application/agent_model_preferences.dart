import 'package:shared_preferences/shared_preferences.dart';

class AgentModelPreferences {
  static const levels = ['off', 'minimal', 'low', 'medium', 'high'];
  static const labels = ['关闭', '极低', '低', '中', '高'];
  static const _key = 'ponynotes.agent.thinking';

  static Future<String> loadThinking() async {
    final value = (await SharedPreferences.getInstance()).getString(_key);
    return levels.contains(value) ? value! : 'off';
  }

  static Future<void> saveThinking(String value) async {
    if (!levels.contains(value)) throw ArgumentError.value(value);
    await (await SharedPreferences.getInstance()).setString(_key, value);
  }
}
