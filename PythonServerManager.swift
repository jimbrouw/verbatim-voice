import Foundation

class PythonServerManager {
    static let shared = PythonServerManager()
    static let port = 8765
    private var process: Process?
    
    func startServer() {
        guard process?.isRunning != true else {
            print("🟢 Python MLX Server already running.")
            return
        }
        
        if isServerHealthy() {
            print("🟢 Existing Python MLX Server is healthy on port \(Self.port).")
            return
        }
        
        let launchConfig = resolveLaunchConfig()
        
        let process = Process()
        process.executableURL = launchConfig.executableURL
        process.arguments = launchConfig.arguments
        process.currentDirectoryURL = launchConfig.workingDirectory
        var environment = ProcessInfo.processInfo.environment
        var pathEntries = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        if let resourceURL = Bundle.main.resourceURL {
            pathEntries.insert(resourceURL.appendingPathComponent("bin").path, at: 0)
        }
        
        environment.merge([
            "VERBATIM_MLX_PORT": String(Self.port),
            "PATH": pathEntries.joined(separator: ":")
        ]) { _, new in new }
        process.environment = environment
        
        // Redirect output for debugging
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.count > 0, let str = String(data: data, encoding: .utf8) {
                print("[MLX Server] \(str)", terminator: "")
            }
        }
        
        do {
            try process.run()
            self.process = process
            print("🟢 Python MLX Server started at \(launchConfig.executableURL.path) on port \(Self.port)")
        } catch {
            print("🔴 Failed to start Python MLX Server: \(error)")
        }
    }
    
    func stopServer() {
        if process?.isRunning == true {
            process?.terminate()
            print("🛑 Python MLX Server stopped.")
        }
    }
    
    private func isServerHealthy() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(Self.port)/health") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        
        let semaphore = DispatchSemaphore(value: 0)
        var healthy = false
        
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                healthy = (200..<300).contains(httpResponse.statusCode)
            }
            semaphore.signal()
        }.resume()
        
        _ = semaphore.wait(timeout: .now() + 0.75)
        return healthy
    }
    
    private struct LaunchConfig {
        let executableURL: URL
        let arguments: [String]
        let workingDirectory: URL
    }
    
    private func resolveLaunchConfig() -> LaunchConfig {
        if let resourceURL = Bundle.main.resourceURL {
            let helperURL = resourceURL.appendingPathComponent("VerbatimMLXHelper")
            if FileManager.default.isExecutableFile(atPath: helperURL.path) {
                return LaunchConfig(
                    executableURL: helperURL,
                    arguments: [],
                    workingDirectory: resourceURL
                )
            }
            
            let bundledPythonURL = resourceURL.appendingPathComponent("venv/bin/python")
            let bundledScriptURL = resourceURL.appendingPathComponent("mlx_server.py")
            if FileManager.default.isExecutableFile(atPath: bundledPythonURL.path),
               FileManager.default.fileExists(atPath: bundledScriptURL.path) {
                return LaunchConfig(
                    executableURL: bundledPythonURL,
                    arguments: [bundledScriptURL.path],
                    workingDirectory: resourceURL
                )
            }
        }
        
        let devBaseURL = URL(fileURLWithPath: "/Users/standard/Developer/verbatim-voice")
        return LaunchConfig(
            executableURL: devBaseURL.appendingPathComponent("venv/bin/python"),
            arguments: [devBaseURL.appendingPathComponent("mlx_server.py").path],
            workingDirectory: devBaseURL
        )
    }
}
