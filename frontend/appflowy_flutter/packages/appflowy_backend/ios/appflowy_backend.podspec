#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint appflowy_backend.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'appflowy_backend'
  s.version          = '0.0.1'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AppFlowy' => 'annie@appflowy.io' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '8.0'

  s.swift_version = '5.0'
  s.static_framework = true
  s.vendored_libraries = "libdart_ffi.a"
  s.library = "c++"
  # Flutter.framework does not contain a i386 slice.
  # Force-load libdart_ffi.a 以确保 Rust FFI 符号（如 rust_log）不被链接器
  # 的死代码裁剪丢弃。这些符号只通过 dlsym() 在运行时查找，链接器无法静态
  # 分析到引用关系，必须强制保留整个库。
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '-force_load ${SRCROOT}/../packages/appflowy_backend/ios/libdart_ffi.a'
  }
end
