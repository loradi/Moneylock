#import "LlamaCppDartIosPlugin.h"

@implementation LlamaCppDartIosPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  // No-op: this plugin exists only to vendor Llama.xcframework
  // (llama_cpp_dart does not declare itself a Flutter plugin).
}

@end