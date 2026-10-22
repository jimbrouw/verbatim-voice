import Foundation

public struct SummaryResult: Equatable {
    public let tldr: String
    public let keyPoints: [String]
    public let raw: String
    public let latency: Double
    public let model: String
}

public class DyslexiaTranslator: ObservableObject {
    public static let shared = DyslexiaTranslator()
    
    private struct ServerResponse: Codable {
        let tldr: String
        let keyPoints: [String]
        let raw: String
        let latency: Double?
        let model: String?
        
        enum CodingKeys: String, CodingKey {
            case tldr
            case keyPoints = "key_points"
            case raw
            case latency
            case model
        }
    }
    
    public init() {}
    
    /// Translates dense or jargon-heavy text into plain English TL;DR and key points
    public func summarize(text: String, completion: @escaping (Result<SummaryResult, Error>) -> Void) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(NSError(domain: "Voice&", code: 400, userInfo: [NSLocalizedDescriptionKey: "Text is empty."])))
            return
        }
        
        let serverPort = PythonServerManager.port
        let endpoint = URL(string: "http://127.0.0.1:\(serverPort)/summarize")!
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "text": text,
            "max_tokens": 300,
            "temperature": 0.1
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(.failure(error))
            return
        }
        
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "Voice&", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received from MLX server."])))
                }
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(ServerResponse.self, from: data)
                let result = SummaryResult(
                    tldr: decoded.tldr,
                    keyPoints: decoded.keyPoints,
                    raw: decoded.raw,
                    latency: decoded.latency ?? 0.0,
                    model: decoded.model ?? "Llama-3.2-1B-Instruct-4bit"
                )
                DispatchQueue.main.async {
                    completion(.success(result))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        task.resume()
    }
    
    public func summarize(text: String) async throws -> SummaryResult {
        try await withCheckedThrowingContinuation { continuation in
            summarize(text: text) { result in
                switch result {
                case .success(let summary):
                    continuation.resume(returning: summary)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
