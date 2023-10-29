import Foundation
import PackagePlugin

enum SwiftLintPluginErrors: Error {
    case lintNotFound
    case unknown(String)
}

// From https://stackoverflow.com/a/50035059/9376340
@discardableResult
func safeShell(_ command: String) throws -> String {
    let task = Process()
    let pipe = Pipe()

    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.standardInput = nil

    try task.run()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8)!
    let outputNoLF = output.trimmingCharacters(in: ["\n"])
    if task.terminationStatus != 0 {
        if outputNoLF == "swiftlint not found" {
            throw SwiftLintPluginErrors.LintNotFound
        } else {
            throw SwiftLintPluginErrors.Unknown(outputNoLF)
        }
    }
    return outputNoLF
}

func getSwiftLint() throws -> Path {
    let commandPath = try safeShell("PATH=\"/opt/homebrew/bin:$PATH\" which swiftlint")
    return Path(String(commandPath))
}

@main
struct SwiftLintPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }
        do {
            return try createBuildCommands(
                inputFiles: sourceTarget.sourceFiles(withSuffix: "swift").map(\.path),
                packageDirectory: context.package.directory,
                workingDirectory: context.pluginWorkDirectory,
                tool: getSwiftLint()
            )
        } catch {
            switch error {
            case SwiftLintPluginErrors.lintNotFound:
                Diagnostics.warning("SwiftLint not installed, download from https://github.com/realm/SwiftLint")
                return []
            case SwiftLintPluginErrors.unknown(let err):
                Diagnostics.error(err)
                return []
            default:
                throw error
            }
        }
    }

    private func createBuildCommands(
        inputFiles: [Path],
        packageDirectory: Path,
        workingDirectory: Path,
        tool: Path
    ) -> [Command] {
        if inputFiles.isEmpty {
            // Don't lint anything if there are no Swift source files in this target
            return []
        }

        var arguments = [
            "lint",
            "--quiet",
            // We always pass all of the Swift source files in the target to the tool,
            // so we need to ensure that any exclusion rules in the configuration are
            // respected.
            "--force-exclude",
            "--cache-path", "\(workingDirectory)"
        ]

        // Manually look for configuration files, to avoid issues when the plugin does not execute our tool from the
        // package source directory.
        if let configuration = packageDirectory.firstConfigurationFileInParentDirectories() {
            arguments.append(contentsOf: ["--config", "\(configuration.string)"])
        }
        arguments += inputFiles.map(\.string)

        // We are not producing output files and this is needed only to not include cache files into bundle
        let outputFilesDirectory = workingDirectory.appending("Output")

        return [
            .prebuildCommand(
                displayName: "SwiftLint",
                executable: tool,
                arguments: arguments,
                outputFilesDirectory: outputFilesDirectory
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension SwiftLintPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let inputFilePaths = target.inputFiles
            .filter { $0.type == .source && $0.path.extension == "swift" }
            .map(\.path)
        do {
            return try createBuildCommands(
                inputFiles: inputFilePaths,
                packageDirectory: context.xcodeProject.directory,
                workingDirectory: context.pluginWorkDirectory,
                tool: getSwiftLint()
            )
        } catch {
            switch error {
            case SwiftLintPluginErrors.lintNotFound:
                Diagnostics.warning("SwiftLint not installed, download from https://github.com/realm/SwiftLint")
                return []
            case SwiftLintPluginErrors.unknown(let err):
                Diagnostics.error(err)
                return []
            default:
                throw error
            }
        }
    }
}
#endif
