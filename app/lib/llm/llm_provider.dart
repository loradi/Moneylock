abstract class LlmProvider {
  Future<String> complete(
    String system,
    String user, {
    double temperature = 0.2,
  });
}

/// Optional performance hooks for local providers. Keeping them separate from
/// [LlmProvider] preserves compatibility with lightweight test and remote
/// providers.
abstract interface class FastLlmProvider implements LlmProvider {
  Future<String> completeFast(
    String system,
    String user, {
    double temperature = 0.0,
  });

  Future<void> warmUp();
}

extension LlmProviderPerformance on LlmProvider {
  /// Short deterministic calls for routing/extraction. Providers without a
  /// tuned path retain the regular, compatible implementation.
  Future<String> completeFast(
    String system,
    String user, {
    double temperature = 0.0,
  }) {
    final provider = this;
    if (provider is FastLlmProvider) {
      return provider.completeFast(system, user, temperature: temperature);
    }
    return complete(system, user, temperature: temperature);
  }

  /// Starts local inference early without penalizing providers that do not
  /// support preloading.
  Future<void> warmUp() {
    final provider = this;
    return provider is FastLlmProvider ? provider.warmUp() : Future.value();
  }
}
