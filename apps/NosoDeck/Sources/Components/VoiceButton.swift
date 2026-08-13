import AVFoundation
import DeckKit
import Speech
import SwiftUI

/// Mic button that streams speech-to-text and sends it to the Mac.
struct VoiceButton: View {
    let isEnabled: Bool
    let onTranscript: (String) -> Void

    @StateObject private var recognizer = SpeechRecognizer()

    var body: some View {
        Button {
            if recognizer.isRecording {
                recognizer.stop()
                if !recognizer.transcript.isEmpty {
                    onTranscript(recognizer.transcript)
                }
            } else {
                recognizer.start()
            }
        } label: {
            ZStack {
                if recognizer.isRecording {
                    // Pulsing ring while recording
                    Circle()
                        .fill(DeckColor.red.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .scaleEffect(recognizer.isRecording ? 1.3 : 1)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: recognizer.isRecording)
                }

                Image(systemName: recognizer.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(recognizer.isRecording ? DeckColor.red : DeckColor.inkMuted)
                    .frame(width: 36, height: 36)
                    .background(
                        recognizer.isRecording ? DeckColor.redBackground : Color(hex: 0x1C1C1C),
                        in: RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DeckRadius.control, style: .continuous)
                            .strokeBorder(
                                recognizer.isRecording ? DeckColor.red : Color(hex: 0x2C2C2C),
                                lineWidth: 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
        .accessibilityLabel(recognizer.isRecording ? "Stop dictation" : "Start dictation")
        .overlay(alignment: .bottom) {
            // Live transcript preview
            if recognizer.isRecording && !recognizer.transcript.isEmpty {
                Text(recognizer.transcript)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DeckColor.ink)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DeckColor.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(DeckColor.strokeSubtle, lineWidth: 1)
                    }
                    .frame(maxWidth: 200)
                    .offset(y: 44)
            }
        }
    }
}

/// Wraps SFSpeechRecognizer for live transcription.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    func start() {
        guard !isRecording else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else { return }
                self?.beginRecording()
            }
        }
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        isRecording = false
    }

    private func beginRecording() {
        transcript = ""

        let speechRecognizer = SFSpeechRecognizer()
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self?.stop()
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            self.audioEngine = engine
            self.recognitionRequest = request
            self.isRecording = true
        } catch {
            stop()
        }
    }
}
