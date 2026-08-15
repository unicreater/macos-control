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

/// Wraps SFSpeechRecognizer for live transcription with text cleanup.
@MainActor
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var cleanedTranscript = ""
    @Published var isRecording = false

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    /// The cleaned-up version ready to send.
    var sendableText: String { cleanedTranscript.isEmpty ? transcript : cleanedTranscript }

    private var authStatus: SFSpeechRecognizerAuthorizationStatus?

    /// Call on deck load to pre-authorize and avoid cold start lag on first tap.
    func warmUp() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { self?.authStatus = status }
        }
    }

    func start() {
        guard !isRecording else { return }

        if let status = authStatus {
            guard status == .authorized else { return }
            beginRecording()
        } else {
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    self?.authStatus = status
                    guard status == .authorized else { return }
                    self?.beginRecording()
                }
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
        // Set cleaned text BEFORE clearing isRecording so the overlay
        // transitions to review state without disappearing.
        cleanedTranscript = Self.cleanup(transcript)
        isRecording = false
    }

    func clear() {
        transcript = ""
        cleanedTranscript = ""
    }

    /// Cleans up raw speech transcript:
    /// - Removes filler words (um, uh, like, you know, I mean, basically, actually, literally)
    /// - Removes repeated words ("the the" → "the")
    /// - Capitalizes first letter of sentences
    /// - Trims extra whitespace
    static func cleanup(_ raw: String) -> String {
        var text = raw

        // Filler words/phrases to remove (case-insensitive, whole word)
        let fillers = [
            "\\bum\\b", "\\buh\\b", "\\buhh\\b", "\\bumm\\b",
            "\\blike\\b,?", "\\byou know\\b,?", "\\bi mean\\b,?",
            "\\bbasically\\b,?", "\\bactually\\b,?", "\\bliterally\\b,?",
            "\\bso\\b,?(?= (?:um|uh|like|I))",  // "so" before another filler
            "\\bkind of\\b", "\\bsort of\\b",
            "\\bright\\b\\??,?(?= (?:so|and|but))",  // "right" as filler
        ]

        for pattern in fillers {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
        }

        // Remove repeated words ("the the" → "the")
        if let regex = try? NSRegularExpression(pattern: "\\b(\\w+)\\s+\\1\\b", options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1")
        }

        // Collapse multiple spaces
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }

        // Collapse multiple commas/periods
        text = text.replacingOccurrences(of: ", ,", with: ",")
        text = text.replacingOccurrences(of: ",,", with: ",")
        text = text.replacingOccurrences(of: " ,", with: ",")

        text = text.trimmingCharacters(in: .whitespaces)

        // Capitalize first letter
        if let first = text.first, first.isLowercase {
            text = first.uppercased() + text.dropFirst()
        }

        // Capitalize after periods
        if let regex = try? NSRegularExpression(pattern: "\\. (\\w)") {
            let mutable = NSMutableString(string: text)
            regex.replaceMatches(in: mutable, range: NSRange(location: 0, length: mutable.length), withTemplate: ". $1")
            // Uppercase the captured letter
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            var result = text
            for match in matches.reversed() {
                if let range = Range(match.range(at: 1), in: result) {
                    result.replaceSubrange(range, with: result[range].uppercased())
                }
            }
            text = result
        }

        // Convert to bullet points if multiple ideas are detected
        text = bulletize(text)

        return text
    }

    /// Detects sentence breaks and pointer keywords, formats as bullet list.
    private static func bulletize(_ text: String) -> String {
        // Split on sentence-ending punctuation and pointer keywords
        let pointerPatterns = [
            "\\. ",                          // Period + space
            "(?i)\\b(?:first|firstly)\\b[,:]?\\s*",
            "(?i)\\b(?:second|secondly)\\b[,:]?\\s*",
            "(?i)\\b(?:third|thirdly)\\b[,:]?\\s*",
            "(?i)\\b(?:fourth|fourthly)\\b[,:]?\\s*",
            "(?i)\\b(?:next|then|also|additionally|finally|lastly)\\b[,:]?\\s*",
            "(?i)\\b(?:another thing|one more thing|on top of that)\\b[,:]?\\s*",
            "(?i)\\bnumber (?:one|two|three|four|five|six|seven|eight)\\b[,:]?\\s*",
        ]

        var segments: [String] = [text]
        for pattern in pointerPatterns {
            var newSegments: [String] = []
            for segment in segments {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let parts = regex.stringByReplacingMatches(
                        in: segment,
                        range: NSRange(segment.startIndex..., in: segment),
                        withTemplate: "\n@@SPLIT@@"
                    ).components(separatedBy: "\n@@SPLIT@@")
                    newSegments.append(contentsOf: parts)
                } else {
                    newSegments.append(segment)
                }
            }
            segments = newSegments
        }

        // Clean up segments
        let points = segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Only bulletize if there are 2+ distinct points
        guard points.count >= 2 else { return text }

        return points.map { point in
            var p = point
            // Capitalize first letter
            if let first = p.first, first.isLowercase {
                p = first.uppercased() + p.dropFirst()
            }
            // Remove trailing period (bullets don't need them)
            if p.hasSuffix(".") { p = String(p.dropLast()) }
            return "• \(p)"
        }.joined(separator: "\n")
    }

    private func beginRecording() {
        transcript = ""

        let speechRecognizer = SFSpeechRecognizer()
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Bias recognition toward product/tech terms it might not know
        request.contextualStrings = [
            "NosoDeck", "Noso Deck", "ChocLift",
            "Warp", "SwiftUI", "Xcode", "macOS",
            "Bonjour", "Claude", "ChatGPT"
        ]

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
