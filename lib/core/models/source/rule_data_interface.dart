/// RuleDataInterface - 規則上下文數據介面
/// (原 Android model/analyzeRule/RuleDataInterface.kt)
abstract class RuleDataInterface {
  Map<String, String> get variableMap;

  void putVariable(String key, String? value);
  String getVariable(String key);
}
