// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Verbatim",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Verbatim", targets: ["Verbatim"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7")
    ],
    targets: [
        .executableTarget(
            name: "Verbatim",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: ".",
            exclude: [
                "README.md",
                "Plan for Verbatim.md",
                "verbatim_prd_market_analysis.md",
                "PARAKEET_MLX_NATIVE_MAC_PLAN.md",
                "VERBATIM_CLONE_BUILD_PLAN.md",
                "DYSLEXIA_ACCESSIBILITY_PLAN.md",
                "dictionary.json",
                "__pycache__",
                "mlx_server.py",
                "requirements.txt",
                "Info.plist",
                "venv",
                "scripts",
                "dist",
                "assets",
                "PythonServerManager.swift",
                "MLXTranscriber.swift",
                "WhisperManager.swift"
            ]
        )
    ]
)
