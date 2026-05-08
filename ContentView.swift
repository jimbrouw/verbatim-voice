import SwiftUI

struct ContentView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: recordingManager.isRecording ? "mic.fill" : "mic")
                .font(.system(size: 40))
                .foregroundColor(recordingManager.isRecording ? .red : .blue)
                .symbolEffect(.pulse, isActive: recordingManager.isRecording)
            
            Text(recordingManager.isRecording ? "Recording..." : (recordingManager.isProcessing ? "Transcribing..." : "Hold Option to Record"))
                .font(.headline)
            
            if recordingManager.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }
            
            if !recordingManager.lastTranscription.isEmpty && !recordingManager.isProcessing {
                Text(recordingManager.lastTranscription)
                    .font(.body)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .frame(width: 300, height: 250)
        .padding()
    }
}
