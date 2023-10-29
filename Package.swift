// swift-tools-version:5.9
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftLintPlugin",
    products: [
        .plugin(name: "SwiftLintPlugin", targets: ["SwiftLintPlugin"])
    ],
    targets: [
        .plugin(
            name: "SwiftLintPlugin",
            capability: .buildTool()
        )
    ]
)
