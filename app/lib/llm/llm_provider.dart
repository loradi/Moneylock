abstract class LlmProvider {
  Future<String> complete(String system, String user, {double temperature = 0.2});
}
