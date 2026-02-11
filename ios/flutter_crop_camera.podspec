#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_crop_camera.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_crop_camera'
  s.version          = '0.0.1'
  s.summary          = 'A high-performance Flutter camera plugin with a built-in crop editor.'
  s.description      = <<-DESC
A high-performance Flutter camera plugin with a built-in crop editor, supporting custom aspect ratios, zoom, and orientation locking.
                       DESC
  s.homepage         = 'https://github.com/ShithinCherathuparambil/flutter_crop_camera'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Shithin' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_cam_cropper_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
