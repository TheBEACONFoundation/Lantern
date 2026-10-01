import AVFoundation
import Foundation
import Speech

/// The operating-system boundary, replaceable in tests without opening a device.
protocol OathSpeechInput: AnyObject {
    func requestSpeechAuthorization(_ completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void)
    func requestMicrophoneAccess(_ completion: @escaping (Bool) -> Void)
    func start(_ receive: @escaping (String?, Bool, Bool) -> Void) throws
    func stop()
}

final class SystemOathSpeechInput: OathSpeechInput {
    private var recognizer: SFSpeechRecognizer?
    private var engine: AVAudioEngine?
    private var tappedInput: AVAudioInputNode?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func requestSpeechAuthorization(_ completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }

    func requestMicrophoneAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    private struct Unavailable: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func start(_ receive: @escaping (String?, Bool, Bool) -> Void) throws {
        stop()
        let recognizer = self.recognizer ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        self.recognizer = recognizer
        guard let recognizer, recognizer.isAvailable else {
            throw Unavailable(message: "Speech recognition isn't available right now.")
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw Unavailable(message: "On-device speech recognition isn't available for en-US on this Mac. Refusing to fall back to server recognition, which would send audio to Apple.")
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.contextualStrings = OathListener.contextualStrings
        request = req

        let engine = self.engine ?? AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stop()
            throw Unavailable(message: "No usable audio input device.")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        tappedInput = input
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw Unavailable(message: "Couldn't start audio input: \(error.localizedDescription)")
        }

        task = recognizer.recognitionTask(with: req) { result, error in
            receive(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if engine?.isRunning == true { engine?.stop() }
        // Do not ask an unused engine for its inputNode merely to remove a tap.
        // That creates audio hardware even during a stop-before-start or a test.
        tappedInput?.removeTap(onBus: 0)
        tappedInput = nil
        request?.endAudio()
        request = nil
    }
}
