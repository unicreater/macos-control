import AVFoundation
import DeckKit
import Speech
import SwiftUI
import UIKit

/// A deck tile that records speech and sends the transcript to the Mac.
/// Tap to start recording, tap again to send. Shows live waveform while recording.
struct VoiceTile: View {
    let isEnabled: Bool
    let onTranscript: (String) -> Void

    @StateObject private var recognizer = SpeechRecognizer()

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()

            if recognizer.isRecording {
                recognizer.stop()
                if !recognizer.transcript.isEmpty {
                    onTranscript(recognizer.transcript)
                }
            } else {
                recognizer.start()
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Pulsing ring when recording
                    if recognizer.isRecording {
                        Circle()
                            .stroke(DeckColor.red.opacity(0.3), lineWidth: 2)
                            .frame(width: 64, height: 64)
                            .scaleEffect(recognizer.isRecording ? 1.2 : 1)
                            .opacity(recognizer.isRecording ? 0 : 1)
                            .animation(
                                .easeOut(duration: 1).repeatForever(autoreverses: false),
                                value: recognizer.isRecording
                            )

                        Circle()
                            .fill(DeckColor.red.opacity(0.15))
                            .frame(width: 52, height: 52)
                    }

                    Image(systemName: recognizer.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(recognizer.isRecording ? DeckColor.red : DeckColor.inkMuted)
                        .symbolEffect(.pulse, isActive: recognizer.isRecording)
                }
                .frame(width: 72, height: 72)

                if recognizer.isRecording && !recognizer.transcript.isEmpty {
                    Text(recognizer.transcript)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DeckColor.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                } else {
                    Text(recognizer.isRecording ? "LISTENING..." : "VOICE")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(recognizer.isRecording ? DeckColor.red : DeckColor.inkMuted)
                        .textCase(.uppercase)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: recognizer.isRecording
                        ? [Color(hex: 0x2A1616), Color(hex: 0x1A1010)]
                        : [Color(hex: 0x1E1E1E), Color(hex: 0x161616)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        recognizer.isRecording ? DeckColor.red.opacity(0.4) : Color(hex: 0x2A2A2A),
                        lineWidth: 1
                    )
            }
        }
        .buttonStyle(TileButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.38)
    }
}
