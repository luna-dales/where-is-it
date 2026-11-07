
import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class SpeechRecognitionService: ObservableObject {

    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private let speechRecognizer = SFSpeechRecognizer(
        locale: Locale(identifier: "en-US")
    )

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func startListening() async {
        guard !isListening else { return }

        errorMessage = nil
        transcript = ""

        // Request speech recognition permission.
        let speechAuthorized = await requestSpeechPermission()

        guard speechAuthorized else {
            errorMessage = "Speech recognition permission was denied."
            return
        }

        // Request microphone permission.
        let microphoneAuthorized = await requestMicrophonePermission()

        guard microphoneAuthorized else {
            errorMessage = "Microphone permission was denied."
            return
        }

        guard let speechRecognizer,
              speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is currently unavailable."
            return
        }

        stopListening()

        do {
            let audioSession = AVAudioSession.sharedInstance()

            try audioSession.setCategory(
                .record,
                mode: .measurement,
                options: [.duckOthers]
            )

            try audioSession.setActive(
                true,
                options: .notifyOthersOnDeactivation
            )

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            recognitionRequest = request

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: recordingFormat
            ) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true

            recognitionTask = speechRecognizer.recognitionTask(
                with: request
            ) { [weak self] result, error in

                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let result {
                        self.transcript = result.bestTranscription
                            .formattedString

                        if result.isFinal {
                            self.stopListening()
                        }
                    }

                    if let error, self.isListening {
                        self.errorMessage = error.localizedDescription
                        self.stopListening()
                    }
                }
            }

        } catch {
            errorMessage = "Unable to start listening: \(error.localizedDescription)"
            stopListening()
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionTask = nil
        recognitionRequest = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func requestSpeechPermission() async -> Bool {
        let status = await withCheckedContinuation {
            (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in

            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        return status == .authorized
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Bool, Never>) in

            AVAudioSession.sharedInstance()
                .requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
        }
    }
}
