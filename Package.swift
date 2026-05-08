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
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Verbatim",
            dependencies: [
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ],
            path: ".",
            exclude: [
                "README.md",
                "Plan for Verbatim.md",
                "verbatim_prd_market_analysis.md",
                "PARAKEET_MLX_NATIVE_MAC_PLAN.md",
                "mlx_server.py",
                "requirements.txt",
                "Info.plist",
                "__pycache__",
                "venv"
            ]
        )
    ]
)
