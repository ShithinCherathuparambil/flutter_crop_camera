// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_crop_camera",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "flutter-crop-camera", targets: ["flutter_crop_camera"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_crop_camera",
            dependencies: [],
            path: "Sources/flutter_crop_camera"
        )
    ]
)
