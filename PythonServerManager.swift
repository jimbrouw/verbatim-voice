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
        
        let basePath = "/Users/standard/Developer/verbatim-voice"
        let pythonPath = "\(basePath)/venv/bin/python"
        let scriptPath = "\(basePath)/mlx_server.py"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [scriptPath]
        process.currentDirectoryURL = URL(fileURLWithPath: basePath)
        process.environment = ProcessInfo.processInfo.environment.merging([
            "VERBATIM_MLX_PORT": String(Self.port),
            "PATH": "/usr/local/bin:/opt/homebrew/bin:/opt/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]) { _, new in new }
        
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
            print("🟢 Python MLX Server started at \(pythonPath) on port \(Self.port)")
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
}
