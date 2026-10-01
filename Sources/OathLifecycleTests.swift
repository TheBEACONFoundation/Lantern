import Foundation
import Speech

/// Runs the listener through delayed OS callbacks without requesting permissions
/// or opening an audio device. Keeping delivery and timers manual makes races
/// reproducible rather than dependent on microphone or run-loop timing.
enum OathLifecycleTests {
    private final class Input: OathSpeechInput {
        var speechPermissions: [(SFSpeechRecognizerAuthorizationStatus) -> Void] = []
        var microphonePermissions: [(Bool) -> Void] = []
        var sessions: [(String?, Bool, Bool) -> Void] = []
        var stopCount = 0
        var startError: Error?
        var cancellationEvent: (session: Int, text: String?, finalised: Bool, failed: Bool)?

        func requestSpeechAuthorization(_ completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
            speechPermissions.append(completion)
        }

        func requestMicrophoneAccess(_ completion: @escaping (Bool) -> Void) {
            microphonePermissions.append(completion)
        }

        func start(_ receive: @escaping (String?, Bool, Bool) -> Void) throws {
            if let startError { throw startError }
            sessions.append(receive)
        }

        func stop() {
            stopCount += 1
            if let event = cancellationEvent {
                cancellationEvent = nil
                emit(event.text, finalised: event.finalised, failed: event.failed, session: event.session)
            }
        }

        func authorize(_ status: SFSpeechRecognizerAuthorizationStatus, attempt: Int? = nil) {
            let index = attempt ?? (speechPermissions.count - 1)
            guard speechPermissions.indices.contains(index) else { return }
            speechPermissions[index](status)
        }

        func grantMicrophone(_ granted: Bool, attempt: Int? = nil) {
            let index = attempt ?? (microphonePermissions.count - 1)
            guard microphonePermissions.indices.contains(index) else { return }
            microphonePermissions[index](granted)
        }

        func emit(_ text: String?, finalised: Bool = false, failed: Bool = false, session: Int? = nil) {
            let index = session ?? (sessions.count - 1)
            guard sessions.indices.contains(index) else { return }
            sessions[index](text, finalised, failed)
        }
    }

    private final class Harness {
        let input = Input()
        var pending: [() -> Void] = []
        var scheduled: [(delay: TimeInterval, work: DispatchWorkItem)] = []
        var accepted: [LanternGlyph.Emblem] = []
        lazy var listener = OathListener(
            input: input,
            deliver: { [weak self] callback in self?.pending.append(callback) },
            schedule: { [weak self] delay, work in self?.scheduled.append((delay, work)) }
        )

        init() {
            listener.onAccepted = { [weak self] oath in self?.accepted.append(oath.corps) }
        }

        func flush() {
            while !pending.isEmpty { pending.removeFirst()() }
        }

        func startAuthorized() {
            listener.start()
            input.authorize(.authorized)
            flush()
            input.grantMicrophone(true)
            flush()
        }

        func restart(_ index: Int = 0) {
            guard scheduled.indices.contains(index) else { return }
            scheduled[index].work.perform()
            flush()
        }
    }

    static func run(check: (Bool, String) -> Void) {
        let green = OathListener.oaths.first { $0.corps == .green }!.text

        let permissions = Harness()
        permissions.listener.start()
        permissions.listener.start()
        check(permissions.listener.state == .requestingPermission &&
              permissions.input.speechPermissions.count == 1 && permissions.input.sessions.isEmpty,
              "starting twice requests permission once and starts no device early")
        permissions.input.authorize(.authorized)
        permissions.flush()
        check(permissions.input.microphonePermissions.count == 1 && permissions.input.sessions.isEmpty,
              "speech permission must precede microphone permission")
        permissions.input.grantMicrophone(true)
        permissions.flush()
        check(permissions.listener.state == .listening && permissions.input.sessions.count == 1,
              "both permissions start a recognition session")

        for status in [SFSpeechRecognizerAuthorizationStatus.denied, .restricted, .notDetermined] {
            let denied = Harness()
            denied.listener.start()
            denied.input.authorize(status)
            denied.flush()
            let deniedState: Bool
            if case .denied = denied.listener.state { deniedState = true } else { deniedState = false }
            check(deniedState && !denied.listener.isListening &&
                  denied.input.microphonePermissions.isEmpty && denied.input.sessions.isEmpty,
                  "speech permission \(status.rawValue) stops without starting microphone input")
        }

        let micDenied = Harness()
        micDenied.listener.start()
        micDenied.input.authorize(.authorized)
        micDenied.flush()
        micDenied.input.grantMicrophone(false)
        micDenied.flush()
        let microphoneDeniedState: Bool
        if case .denied = micDenied.listener.state { microphoneDeniedState = true } else { microphoneDeniedState = false }
        check(microphoneDeniedState && !micDenied.listener.isListening && micDenied.input.sessions.isEmpty,
              "denied microphone access stops without opening an input")

        let oldSpeech = Harness()
        oldSpeech.listener.start()
        oldSpeech.input.authorize(.authorized, attempt: 0) // queued before stopping
        oldSpeech.listener.stop()
        oldSpeech.listener.start()
        oldSpeech.flush()
        check(oldSpeech.listener.state == .requestingPermission && oldSpeech.input.microphonePermissions.isEmpty,
              "queued authorization from a stopped attempt cannot request microphone access")
        oldSpeech.input.authorize(.denied, attempt: 0)
        oldSpeech.flush()
        check(oldSpeech.listener.isListening && oldSpeech.listener.state == .requestingPermission,
              "an old permission denial cannot stop a newer attempt")
        oldSpeech.input.authorize(.authorized, attempt: 1)
        oldSpeech.flush()
        oldSpeech.input.grantMicrophone(true)
        oldSpeech.flush()
        check(oldSpeech.input.sessions.count == 1 && oldSpeech.listener.state == .listening,
              "the current permission attempt still starts normally")

        let oldMicrophone = Harness()
        oldMicrophone.listener.start()
        oldMicrophone.input.authorize(.authorized)
        oldMicrophone.flush()
        oldMicrophone.listener.stop()
        oldMicrophone.startAuthorized()
        oldMicrophone.input.grantMicrophone(true, attempt: 0)
        oldMicrophone.input.grantMicrophone(false, attempt: 0)
        oldMicrophone.flush()
        check(oldMicrophone.input.sessions.count == 1 && oldMicrophone.listener.state == .listening,
              "late microphone grant and denial cannot alter a newer session")

        let oldRecognition = Harness()
        oldRecognition.startAuthorized()
        oldRecognition.input.emit(green, finalised: true, session: 0) // queued before stopping
        oldRecognition.listener.stop()
        oldRecognition.startAuthorized()
        oldRecognition.input.emit(nil, failed: true, session: 0)
        oldRecognition.flush()
        check(oldRecognition.accepted.isEmpty && oldRecognition.scheduled.isEmpty &&
              oldRecognition.listener.state == .listening && oldRecognition.input.sessions.count == 2,
              "queued transcripts and late errors from a stopped session are ignored")

        let paused = Harness()
        paused.startAuthorized()
        paused.input.emit("in blackest day in brightest night", finalised: true)
        paused.flush()
        check(paused.scheduled.count == 1 && paused.scheduled.first?.delay == 0.3,
              "a completed fragment schedules one recognition restart")
        paused.input.emit(green, finalised: true, session: 0)
        paused.input.emit(nil, failed: true, session: 0)
        paused.flush()
        check(paused.accepted.isEmpty && paused.scheduled.count == 1,
              "the retired session is ignored during the restart delay")
        paused.restart()
        check(paused.input.sessions.count == 2 && paused.listener.state == .listening,
              "the scheduled restart opens a replacement session")
        paused.input.emit(green, session: 0)
        paused.input.emit(nil, failed: true, session: 0)
        paused.flush()
        check(paused.accepted.isEmpty && paused.scheduled.count == 1 && paused.listener.state == .listening,
              "old transcripts and errors cannot accept or restart the replacement session")
        paused.input.emit("burn like my power sinestros might", finalised: true, session: 1)
        paused.flush()
        check(paused.accepted == [.sinestro] && paused.scheduled.count == 2 &&
              paused.scheduled.last?.delay == 1.0,
              "a fragment from the replacement session completes the carried oath")
        paused.input.emit("burn like my power sinestros might", finalised: true, session: 1)
        paused.flush()
        check(paused.accepted == [.sinestro] && paused.scheduled.count == 2,
              "duplicate final results accept once and schedule once")

        let cancelledRestart = Harness()
        cancelledRestart.startAuthorized()
        cancelledRestart.input.emit(nil, failed: true)
        cancelledRestart.flush()
        cancelledRestart.listener.stop()
        cancelledRestart.restart()
        check(cancelledRestart.listener.state == .off && cancelledRestart.input.sessions.count == 1,
              "stopping cancels a pending recognition restart")

        let stoppedOnAcceptance = Harness()
        stoppedOnAcceptance.listener.onAccepted = { oath in
            stoppedOnAcceptance.accepted.append(oath.corps)
            stoppedOnAcceptance.listener.stop()
        }
        stoppedOnAcceptance.startAuthorized()
        stoppedOnAcceptance.input.emit(green, finalised: true)
        stoppedOnAcceptance.flush()
        check(stoppedOnAcceptance.accepted == [.green] && stoppedOnAcceptance.listener.state == .off &&
              stoppedOnAcceptance.scheduled.isEmpty,
              "an acceptance handler can stop listening without scheduling a restart")

        let restartedOnAcceptance = Harness()
        restartedOnAcceptance.listener.onAccepted = { oath in
            restartedOnAcceptance.accepted.append(oath.corps)
            restartedOnAcceptance.listener.stop()
            restartedOnAcceptance.listener.start()
        }
        restartedOnAcceptance.startAuthorized()
        restartedOnAcceptance.input.emit(green, finalised: true)
        restartedOnAcceptance.flush()
        check(restartedOnAcceptance.accepted == [.green] &&
              restartedOnAcceptance.listener.state == .requestingPermission &&
              restartedOnAcceptance.input.speechPermissions.count == 2 &&
              restartedOnAcceptance.scheduled.isEmpty,
              "a synchronous acceptance restart owns its new permission attempt")

        let cancellation = Harness()
        cancellation.startAuthorized()
        cancellation.input.cancellationEvent = (0, green, true, true)
        cancellation.listener.stop()
        cancellation.flush()
        check(cancellation.accepted.isEmpty && cancellation.listener.state == .off &&
              cancellation.scheduled.isEmpty,
              "a callback delivered by cancellation cannot resurrect listening")

        let unavailable = Harness()
        unavailable.input.startError = NSError(domain: "OathLifecycleTests", code: 1,
                                              userInfo: [NSLocalizedDescriptionKey: "Input unavailable"])
        unavailable.startAuthorized()
        check(unavailable.listener.state == .unavailable("Input unavailable") &&
              !unavailable.listener.isListening && unavailable.input.stopCount >= 2,
              "failed input startup reports unavailable and stops its session")

        let stoppedWhileRequesting = Harness()
        stoppedWhileRequesting.listener.onStateChange = { state in
            if state == .requestingPermission { stoppedWhileRequesting.listener.stop() }
        }
        stoppedWhileRequesting.listener.start()
        check(stoppedWhileRequesting.listener.state == .off &&
              stoppedWhileRequesting.input.speechPermissions.isEmpty,
              "a state observer stopping permission setup prevents the request")

        let stoppedWhileStarting = Harness()
        stoppedWhileStarting.listener.onStateChange = { state in
            if state == .listening { stoppedWhileStarting.listener.stop() }
        }
        stoppedWhileStarting.startAuthorized()
        check(stoppedWhileStarting.listener.state == .off && stoppedWhileStarting.input.sessions.isEmpty,
              "a state observer stopping session setup prevents audio startup")

        let restartedOnPartial = Harness()
        restartedOnPartial.listener.onStateChange = { state in
            if case .heard = state {
                restartedOnPartial.listener.stop()
                restartedOnPartial.listener.start()
            }
        }
        restartedOnPartial.startAuthorized()
        restartedOnPartial.input.emit("ordinary speech", finalised: true)
        restartedOnPartial.flush()
        check(restartedOnPartial.listener.state == .requestingPermission &&
              restartedOnPartial.input.speechPermissions.count == 2 && restartedOnPartial.scheduled.isEmpty,
              "a state observer restart cannot be replaced by the old final callback")
    }
}
