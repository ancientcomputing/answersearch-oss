// swift-tools-version: 6.0
import Foundation
import PackageDescription

// AnswerSearch builds on the LocalLM Lab SDK (https://github.com/ancientcomputing/locallm).
// The SDK ships as binary xcframeworks on GitHub Releases; SwiftPM downloads and
// checksum-verifies them. To build against another SDK release, set LOCALLM_SDK_VERSION
// (and add its URLs + checksums below).

struct SDKRelease {
    let coreChecksum: String
    let remoteChecksum: String
}

let defaultSDKVersion = "2.3.0-GA"

let knownSDKReleases: [String: SDKRelease] = [
    "2.3.0-GA": SDKRelease(
        coreChecksum: "7821197d0cf5b4c92e36af5c537295e594afbb55d60d2f98b0773a3625403575",
        remoteChecksum: "dae65d45bea196f6cd2538328fad1a0e33eceae5fac5ee965183706ac942daaf"
    ),
]

func releaseAssetURL(_ name: String, version: String) -> String {
    "https://github.com/ancientcomputing/locallm/releases/download/v\(version)/\(name)-\(version).xcframework.zip"
}

let requestedSDKVersion = ProcessInfo.processInfo.environment["LOCALLM_SDK_VERSION"] ?? defaultSDKVersion
guard let sdk = knownSDKReleases[requestedSDKVersion] else {
    FileHandle.standardError.write(Data("""
    error: Unknown LOCALLM_SDK_VERSION "\(requestedSDKVersion)".
    Known versions: \(knownSDKReleases.keys.sorted().joined(separator: ", "))

    """.utf8))
    exit(1)
}

let package = Package(
    name: "AnswerSearch",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "AnswerSearch", targets: ["AnswerSearch"]),
    ],
    targets: [
        .binaryTarget(
            name: "LocalLMLabSDKCore",
            url: releaseAssetURL("LocalLMLabSDKCore", version: requestedSDKVersion),
            checksum: sdk.coreChecksum
        ),
        .binaryTarget(
            name: "LocalLMLabSDKRemote",
            url: releaseAssetURL("LocalLMLabSDKRemote", version: requestedSDKVersion),
            checksum: sdk.remoteChecksum
        ),
        // All app logic lives in a library so the test target can import it.
        .target(
            name: "AnswerSearchKit",
            dependencies: ["LocalLMLabSDKCore", "LocalLMLabSDKRemote"]
        ),
        .executableTarget(
            name: "AnswerSearch",
            dependencies: ["AnswerSearchKit"],
            linkerSettings: [
                // Bare SwiftPM executables get no LC_RPATH; SwiftPM puts the xcframework
                // slices next to the built binary.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path"]),
            ]
        ),
        .testTarget(
            name: "AnswerSearchTests",
            dependencies: ["AnswerSearchKit"]
        ),
    ]
)
