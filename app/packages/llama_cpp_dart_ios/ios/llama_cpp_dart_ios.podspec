Pod::Spec.new do |s|
  s.name                  = 'llama_cpp_dart_ios'
  s.version               = '0.2.2'
  s.summary               = 'Vendored Llama.xcframework (llama.cpp) for llama_cpp_dart'
  s.description           = <<-DESC
  llama_cpp_dart does not declare itself a Flutter plugin, so its ios/llama_cpp_dart.podspec
  is never picked up by pod install. This shim declares a plugin with pluginClass: none and
  vendors the same Llama.xcframework so the native llama.cpp symbols are linked and embedded
  into the app.
                       DESC
  s.homepage              = 'https://github.com/netdur/llama_cpp_dart'
  s.license               = { :type => 'MIT', :file => 'LICENSE' }
  s.authors               = { 'Moneylock' => 'dev@moneylock.app' }
  s.source                = { :path => '.' }
  s.platform              = :ios, '16.4'
  s.swift_version         = '5.9'
  s.source_files          = ['LlamaCppDartIosPlugin.h', 'LlamaCppDartIosPlugin.m']
  s.vendored_frameworks   = 'Llama.xcframework'
  s.dependency 'Flutter'
end