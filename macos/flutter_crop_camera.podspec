#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_crop_camera.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_crop_camera'
  s.version          = '0.5.0'
  s.summary          = 'A high-performance Flutter camera plugin with a built-in crop editor.'
  s.description      = <<-DESC
A high-performance Flutter camera plugin with a built-in crop editor, supporting custom aspect ratios, zoom, and orientation locking.
                       DESC
  s.homepage         = 'https://github.com/ShithinCherathuparambil/flutter_crop_camera'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Shithin' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.frameworks = 'AVFoundation'
end
