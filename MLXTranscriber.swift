import Foundation

class MLXTranscriber: ObservableObject {
    @Published var isProcessing = false
    
    func transcribe(audioURL: URL, completion: @escaping (String?) -> Void) {
        let serverURL = URL(string: "http://127.0.0.1:\(PythonServerManager.port)/transcribe")!
        var request = URLRequest(url: serverURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Form field for file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        
        do {
            let audioData = try Data(contentsOf: audioURL)
            body.append(audioData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            print("🚀 Sending audio to MLX Server...")
            
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 300
            configuration.timeoutIntervalForResource = 600
            let session = URLSession(configuration: configuration)
            
            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("❌ MLX API Error: \(error)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse,
                   !(200..<300).contains(httpResponse.statusCode) {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    print("❌ MLX API HTTP \(httpResponse.statusCode): \(body)")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                guard let data = data else {
                    print("❌ MLX API Error: No data received")
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        if let text = json["text"] as? String {
                            // Filter slop
                            let fullText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            let slopPhrases = ["Thank you.", "THANK YOU.", "Subtitles by", "subtitle by", "Please subscribe", "subscribe to", "Amara.org", "*Noises*", "you're great", "(mimics sounds)"]
                            let isSlop = slopPhrases.contains(where: { fullText.contains($0) })
                            
                            let isWrapped = (fullText.hasPrefix("(") && fullText.hasSuffix(")")) ||
                                            (fullText.hasPrefix("[") && fullText.hasSuffix("]")) ||
                                            (fullText.hasPrefix("*") && fullText.hasSuffix("*"))
                            
                            if (isSlop || isWrapped) && fullText.count < 50 {
                                print("🗑️ Filtered out MLX hallucination: \(fullText)")
                                DispatchQueue.main.async { completion("") }
                            } else {
                                DispatchQueue.main.async { completion(fullText) }
                            }
                        } else if let err = json["error"] as? String {
                            print("❌ MLX Transcription Error: \(err)")
                            DispatchQueue.main.async { completion(nil) }
                        } else if let detail = json["detail"] as? [String: Any] {
                            print("❌ MLX Transcription Error: \(detail)")
                            DispatchQueue.main.async { completion(nil) }
                        } else {
                            print("❌ MLX Transcription Error: Unexpected response \(json)")
                            DispatchQueue.main.async { completion(nil) }
                        }
                    }
                } catch {
                    print("❌ MLX API JSON Parse Error: \(error)")
                    if let str = String(data: data, encoding: .utf8) {
                        print("   Raw response: \(str)")
                    }
                    DispatchQueue.main.async { completion(nil) }
                }
            }
            task.resume()
            
        } catch {
            print("❌ Failed to read audio file for MLX: \(error)")
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
