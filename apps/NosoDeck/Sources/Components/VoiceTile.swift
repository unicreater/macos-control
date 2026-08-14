import AVFoundation
import DeckKit
import Speech
import SwiftUI
import UIKit

/// A deck tile that records speech and sends the transcript to the Mac.
/// The tile itself just shows mic state. Live transcript is shown via
/// the `VoiceOverlay` added at the DeckView level.
struct VoiceTile: View {
    let isEnabled: Bool
    @ObservedObject var recognizer: SpeechRecognizer
    let onTranscript: (String) -> Void

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()

            if recognizer.isRecording {
                recognizer.stop()
                // Don't auto-send — user taps "Send to Mac" in the overlay

            } else {
                recognizer.start()
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
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

                Text(recognizer.isRecording ? "LISTENING..." : "VOICE")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(recognizer.isRecording ? DeckColor.red : DeckColor.inkMuted)
                    .textCase(.uppercase)
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

/// Fullscreen overlay showing live voice transcription with cleanup.
struct VoiceOverlay: View {
    @ObservedObject var recognizer: SpeechRecognizer
    let onSend: () -> Void

    private var isVisible: Bool {
        recognizer.isRecording || !recognizer.sendableText.isEmpty
    }

    var body: some View {
        if isVisible {
            ZStack {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer()

                    if recognizer.isRecording {
                        recordingView
                    } else {
                        reviewView
                    }

                    Spacer()
                }
                .padding(.horizontal, 40)
            }
            .transition(.opacity)
        }
    }

    private var recordingView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(DeckColor.red)
                    .frame(width: 10, height: 10)
                Text("LISTENING")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(DeckColor.red)
            }

            if recognizer.transcript.isEmpty {
                Text("Speak now...")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(DeckColor.inkMuted)
            } else {
                Text(recognizer.transcript)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(DeckColor.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(8)
            }

            HStack(spacing: 16) {
                Button { recognizer.stop() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("DONE")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(DeckColor.onMint)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(DeckColor.mint, in: Capsule())
                }
                .buttonStyle(.plain)

                Button { dismiss() } label: {
                    Text("Close")
                        .font(.system(size: 14))
                        .foregroundStyle(DeckColor.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var reviewView: some View {
        VStack(spacing: 16) {
            Text("READY TO SEND")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(DeckColor.mint)

            Text(recognizer.sendableText)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(DeckColor.ink)
                .multilineTextAlignment(.center)
                .lineLimit(8)

            if recognizer.sendableText != recognizer.transcript {
                Text("Cleaned up filler words")
                    .font(.system(size: 11))
                    .foregroundStyle(DeckColor.inkFaint)
            }

            HStack(spacing: 16) {
                Button {
                    onSend()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13))
                        Text("SEND TO MAC")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(DeckColor.onMint)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(DeckColor.mint, in: Capsule())
                }
                .buttonStyle(.plain)

                Button { dismiss() } label: {
                    Text("Close")
                        .font(.system(size: 14))
                        .foregroundStyle(DeckColor.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dismiss() {
        recognizer.clear()
    }
}
