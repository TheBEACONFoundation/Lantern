import Foundation
import Speech

/// Listens for the corps oaths and reports which one has been recited.
///
/// Recognition is forced on-device (`requiresOnDeviceRecognition`), so no audio
/// leaves the Mac. If the on-device model isn't available the listener reports
/// `unavailable` rather than quietly falling back to Apple's servers.
final class OathListener {

    enum State: Equatable {
        case off
        case requestingPermission
        case denied(String)
        case unavailable(String)
        case listening
        case heard(String)      // partial transcript, for feedback
        case accepted(String)   // the corps sworn to
    }

    /// One corps' oath, and how to recognise it.
    ///
    /// Matching is phrase-coverage rather than exact text: speech recognition
    /// mangles the awkward clauses reliably, and nobody recites any of these
    /// identically twice.
    struct Oath {
        let corps: LanternGlyph.Emblem
        /// The corps' name, for the menu.
        let name: String
        /// The oath as written, for the menu and the README.
        let text: String
        /// A proper noun the corps is named for, matched loosely — see
        /// `heardName`. Recognition has never heard of a Sinestro and offers
        /// "sinistro", "synestro" or "sin estro" instead. nil where an oath
        /// needs no name.
        let spokenName: String?
        /// At least one of these must appear, or the name must be heard. It
        /// stops a stray phrase from tripping the gate, and it is what tells
        /// the corps' oaths apart when recognition garbles the rest.
        ///
        /// None of them may be a proper noun on its own: an oath that hangs on
        /// a word the recogniser doesn't know can't be said at all.
        let clinchers: [String]
        /// Distinctive fragments, normalised the way `normalize` spells them.
        let phrases: [String]
        /// How many of `phrases` must appear.
        let required: Int
        /// A word the oath says over and over, and how often it must be heard.
        ///
        /// The Orange Lantern oath is almost entirely one word repeated, so
        /// there are no six distinct phrases to cover. Counting the refrain is
        /// the test that actually fits it — and it is mandatory, which is what
        /// stops the ordinary words it's made of from tripping the gate.
        struct Refrain {
            let word: String
            let atLeast: Int
        }
        var refrain: Refrain?
    }

    static let oaths: [Oath] = [
        Oath(corps: .green,
             name: "Green Lantern Corps",
             text: """
                 In brightest day, in blackest night, no evil shall escape my \
                 sight. Let those who worship evil's might beware my power — \
                 Green Lantern's light!
                 """,
             spokenName: nil,   // two ordinary words; recognition gets them
             // `normalize` drops the apostrophe, so the written "Lantern's" arrives
             // as "lanterns"; recognition often drops the possessive altogether.
             clinchers: ["green lantern", "green lanterns"],
             phrases: ["brightest day", "blackest night", "escape my sight",
                       "evils might", "beware my power", "green lantern", "green lanterns"],
             required: 4),

        // Two things conspire against this one. Its opening inverts the Green
        // oath's — "blackest day, brightest night" — which recognition likes to
        // "correct" back to the familiar order, costing it both those phrases.
        // And its corps is a proper noun no recogniser knows, so the name comes
        // back mangled or not at all.
        //
        // So the oath does not depend on the name: its clinchers are the
        // ordinary words in its middle two lines, which nothing else says in
        // that order, and the name only adds to the count when it is heard.
        Oath(corps: .sinestro,
             name: "Sinestro Corps",
             text: """
                 In blackest day, in brightest night, beware your fears made \
                 into light. Let those who try to stop what's right, burn like \
                 my power — Sinestro's might!
                 """,
             spokenName: "sinestro",
             clinchers: ["beware your fears", "made into light",
                         "stop whats right", "burn like my power"],
             phrases: ["blackest day", "brightest night", "beware your fears",
                       "made into light", "stop whats right", "burn like my power"],
             required: 4),

        // The Red Lantern oath never names its corps, so it has no single
        // clincher. Three of its lines stand in: nothing else anyone is likely
        // to say near this Mac contains them, and all three would have to be
        // garbled at once for the oath to be missed.
        Oath(corps: .red,
             name: "Red Lantern Corps",
             text: """
                 With blood and rage of crimson red, ripped from a corpse so \
                 freshly dead, together with our hellish hate, we'll burn you \
                 all — that is your fate!
                 """,
             spokenName: nil,   // it never names its corps
             clinchers: ["crimson red", "hellish hate", "blood and rage"],
             phrases: ["blood and rage", "crimson red", "freshly dead",
                       "hellish hate", "burn you all", "your fate"],
             required: 4),

        // Avarice has no poetry to cover: the oath is "mine" seven times over.
        // So the refrain carries it — five of them must be heard — and the
        // phrases only have to confirm the shape around it. Nothing else the
        // Mac is likely to overhear says "mine" five times in one breath.
        Oath(corps: .orange,
             name: "Orange Lantern Corps",
             text: """
                 What's mine is mine, and mine, and mine. And mine and mine \
                 and mine! Not yours!
                 """,
             spokenName: nil,   // it never names its corps either
             clinchers: ["whats mine is mine", "mine and mine", "not yours"],
             phrases: ["whats mine is mine", "mine and mine and mine", "not yours"],
             required: 2,
             refrain: Oath.Refrain(word: "mine", atLeast: 5)),

        // This one opens on "the blackest night", which is also a Green
        // Lantern phrase — but the Green oath needs its own clincher, and
        // "green lantern" is nowhere in this. Nothing here is a proper noun
        // either, so there is no word for recognition to founder on.
        Oath(corps: .black,
             name: "Black Lantern Corps",
             text: """
                 The Blackest Night falls from the skies, the darkness grows as \
                 all light dies. We crave your hearts and your demise, by my \
                 Black Hand, the dead shall rise!
                 """,
             spokenName: nil,
             clinchers: ["black hand", "dead shall rise", "crave your hearts",
                         "darkness grows"],
             phrases: ["falls from the skies", "darkness grows", "all light dies",
                       "crave your hearts", "black hand", "dead shall rise"],
             required: 4),

        // This one opens on "in brightest day", which the Green Lantern oath
        // also says, and closes on light the way the Sinestro oath does. Its
        // own clinchers are the two lines in the middle that nothing else has.
        Oath(corps: .white,
             name: "White Lantern Corps",
             text: """
                 In brightest day, there will be light. To cleanse the soul and \
                 set wrongs right. When darkness falls, look to the skies. A new \
                 dawn comes — let there be light.
                 """,
             spokenName: nil,
             clinchers: ["cleanse the soul", "set wrongs right", "new dawn comes",
                         "let there be light"],
             phrases: ["cleanse the soul", "set wrongs right", "darkness falls",
                       "look to the skies", "new dawn comes", "let there be light"],
             required: 4),

        // Its "look to the stars" is a step from the White oath's "look to the
        // skies", and it ends on light as that one does. Its own clinchers are
        // lines neither of them has.
        Oath(corps: .blue,
             name: "Blue Lantern Corps",
             text: """
                 In fearful day, in raging night, with strong hearts full, our \
                 souls ignite. When all seems lost in the War of Light, look to \
                 the stars — for hope burns bright!
                 """,
             spokenName: nil,
             clinchers: ["war of light", "souls ignite", "hope burns bright",
                         "strong hearts full"],
             phrases: ["fearful day", "raging night", "souls ignite",
                       "war of light", "look to the stars", "hope burns bright"],
             required: 4),

        // This one says "in blackest night", which the Green oath and the
        // Black one both lean on, and "hearts", which the Blue and Black ones
        // use. Its clinchers are its last line and its own middle two.
        Oath(corps: .sapphire,
             name: "Star Sapphire Corps",
             text: """
                 For hearts long lost and full of fright, for those alone in \
                 blackest night. Accept our ring and join our fight, love \
                 conquers all with violet light!
                 """,
             spokenName: nil,
             clinchers: ["love conquers all", "violet light", "accept our ring",
                         "hearts long lost"],
             phrases: ["hearts long lost", "full of fright", "accept our ring",
                       "join our fight", "love conquers all", "violet light"],
             required: 4),

        // Most of this oath is invented language. Require an explicit closing
        // variant plus a recognisable word from its earlier line. The closing
        // alone can be ordinary speech ("tomorrow, sir"), and must not swear.
        Oath(corps: .indigo,
             name: "Indigo Tribe",
             text: """
                 Tor lorek san, bor nakka mur, Natromo faan tornek wot ur. Ter \
                 lantern ker lo Abin Sur, taan lek lek nok — Formorrow Sur!
                 """,
             spokenName: nil,
             clinchers: ["formorrow", "for morrow", "tomorrow", "for tomorrow"].flatMap { first in
                 ["sir", "sur", "sure"].map { first + " " + $0 }
             },
             phrases: ["lantern", "abin sur"],
             required: 1),
    ]

    var onAccepted: ((Oath) -> Void)?
    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .off {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    private let input: OathSpeechInput
    private let now: () -> TimeInterval
    private let deliver: (@escaping () -> Void) -> Void
    private let schedule: (TimeInterval, DispatchWorkItem) -> Void
    private var wantsToListen = false
    private var restartWork: DispatchWorkItem?
    // A callback belongs to one permission attempt, recognition session, or
    // pending restart. Invalidating it precedes cancellation, which can itself
    // deliver a callback from the old task.
    private var generation: UInt = 0

    init(input: OathSpeechInput = SystemOathSpeechInput(),
         // CLOCK_MONOTONIC keeps counting while the Mac sleeps; `systemUptime`
         // doesn't, which would let a fragment outlive its window across a sleep.
         now: @escaping () -> TimeInterval = {
             TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
         },
         deliver: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) },
         schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = {
             DispatchQueue.main.asyncAfter(deadline: .now() + $0, execute: $1)
         }) {
        self.input = input
        self.now = now
        self.deliver = deliver
        self.schedule = schedule
    }

    var isListening: Bool { wantsToListen }

    // MARK: - Matching

    static func normalize(_ text: String) -> String {
        let folded = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        // Apostrophes are dropped rather than turned into spaces, so possessives
        // collapse the way the phrase list spells them: "evil's might" has to
        // normalise to "evils might", not "evil s might".
        let deapostrophised = folded.filter { $0 != "'" && $0 != "\u{2019}" && $0 != "\u{02BC}" }
        let stripped = deapostrophised.map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : " " }
        return String(stripped).split(separator: " ").joined(separator: " ")
    }

    /// The corps' name, for anything that has only the emblem to hand.
    static func name(of corps: LanternGlyph.Emblem) -> String {
        oaths.first { $0.corps == corps }?.name ?? "Lantern"
    }

    /// Words the recogniser is told to expect. "Sinestro" is in no ordinary
    /// vocabulary, and without this hint it comes back as something else
    /// entirely. Kept short: the bias works best on a handful of terms.
    static let contextualStrings = [
        "Sinestro", "Sinestro Corps", "Green Lantern Corps", "Red Lantern Corps",
        "blackest day", "brightest night", "crimson red", "hellish hate",
        "Abin Sur", "Formorrow Sur",
    ]

    /// True when some word, or some pair of adjacent words, is within a couple
    /// of edits of `name`. That covers "sinistro", "synestro" and "cinestro",
    /// and — via the pair — "sin estro", which is what a recogniser does with a
    /// word it has never met.
    ///
    /// Being generous is safe here: hearing the name only contributes a hit and
    /// satisfies the clincher, and an oath still needs `required` phrases of
    /// its own before it lands.
    static func heardName(_ name: String, in normalized: String) -> Bool {
        let target = Array(name)
        let limit = target.count >= 8 ? 2 : 1
        let words = normalized.split(separator: " ").map(String.init)
        for (i, word) in words.enumerated() {
            // Short words reach too much by accident to be worth testing alone.
            if word.count >= 4, editDistance(Array(word), target, limit: limit) <= limit {
                return true
            }
            if i + 1 < words.count,
               editDistance(Array(word + words[i + 1]), target, limit: limit) <= limit {
                return true
            }
        }
        return false
    }

    /// Levenshtein distance, abandoned once it passes `limit` — the caller only
    /// needs to know whether it falls within that limit.
    private static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var best = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                best = min(best, current[j])
            }
            if best > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Count complete words, not fragments such as "mine" inside "examine".
    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.split(separator: " ").filter { $0 == needle }.count
    }

    /// Whole words only: "green lantern" is not in "green lanternfish". Any
    /// alternative spelling belongs in the oath's own lists, not here.
    private static func containsPhrase(_ phrase: String, in normalized: String) -> Bool {
        (" " + normalized + " ").contains(" " + phrase + " ")
    }

    /// How much of an oath a transcript covers: its phrases, plus its name if
    /// that was heard at all.
    private static func hits(_ oath: Oath, in normalized: String) -> Int {
        var count = oath.phrases.filter { containsPhrase($0, in: normalized) }.count
        if let spoken = oath.spokenName, heardName(spoken, in: normalized) { count += 1 }
        return count
    }

    /// Which oath, if any, the transcript satisfies. Exposed so the match rule
    /// can be exercised without a microphone.
    ///
    /// Every oath is scored, not just the first that clears its bar: a garbled
    /// recitation can trip two of them, and the one it covers best is the one
    /// the speaker meant.
    static func match(_ transcript: String) -> Oath? {
        let n = normalize(transcript)
        var best: (oath: Oath, hits: Int)?
        for oath in oaths {
            if let refrain = oath.refrain,
               occurrences(of: refrain.word, in: n) < refrain.atLeast { continue }
            let named = oath.spokenName.map { heardName($0, in: n) } ?? false
            guard named || oath.clinchers.contains(where: { containsPhrase($0, in: n) }) else { continue }
            let score = hits(oath, in: n)
            guard score >= oath.required else { continue }
            if score > (best?.hits ?? 0) { best = (oath, score) }
        }
        return best?.oath
    }

    /// Text from sessions that have already finished, and when it was set
    /// aside. Recognition ends a session after a beat of silence, so an oath
    /// recited with pauses between its lines arrives in pieces; each piece is
    /// kept for a short while and matched together with what follows, so the
    /// oath still lands as one thing.
    private struct Fragment {
        let text: String
        let recordedAt: TimeInterval
    }
    private var carried: [Fragment] = []
    /// How long a piece stays worth carrying. Long enough to finish an oath
    /// around a pause, short enough that half an oath can't combine with
    /// something said minutes later.
    private static let carryWindow: TimeInterval = 25

    private func clearCarried() {
        carried.removeAll()
    }

    /// Feeds a transcript through the matcher and, if it lands, swears to that
    /// oath. `finalised` marks the last text of a session, which is the piece
    /// worth carrying into the next one.
    ///
    /// Split out of the recognition callback so the accept path — carrying
    /// included — can be exercised without a microphone.
    @discardableResult
    func consider(_ transcript: String, finalised: Bool = false) -> Oath? {
        let time = now()
        carried.removeAll { time - $0.recordedAt >= Self.carryWindow || time < $0.recordedAt }
        let whole = (carried.map(\.text) + [transcript]).joined(separator: " ")
        guard let oath = Self.match(whole) else {
            if finalised, !transcript.isEmpty {
                // Bounded, so a long spell of talking near the Mac can't grow
                // without limit — an oath is far shorter than this.
                carried.append(Fragment(text: String(transcript.suffix(400)), recordedAt: time))
                while carried.map({ $0.text.count + 1 }).reduce(0, +) > 401 {
                    carried.removeFirst()
                }
            }
            return nil
        }
        clearCarried()
        state = .accepted(oath.name)
        onAccepted?(oath)
        return oath
    }

    // MARK: - Lifecycle

    private func isCurrent(_ token: UInt) -> Bool {
        wantsToListen && generation == token
    }

    func start() {
        guard !wantsToListen else { return }
        generation &+= 1
        let token = generation
        wantsToListen = true
        state = .requestingPermission
        guard isCurrent(token) else { return }

        input.requestSpeechAuthorization { [weak self] auth in
            self?.deliver { [weak self] in
                guard let self, self.isCurrent(token) else { return }
                switch auth {
                case .authorized:
                    self.requestMicrophone(token: token)
                case .denied:
                    self.fail(.denied("Speech recognition was denied. Enable it in System Settings › Privacy & Security › Speech Recognition."))
                case .restricted:
                    self.fail(.denied("Speech recognition is restricted on this Mac."))
                case .notDetermined:
                    self.fail(.denied("Speech recognition permission wasn't granted."))
                @unknown default:
                    self.fail(.denied("Speech recognition is unavailable."))
                }
            }
        }
    }

    func stop() {
        endListening()
        state = .off
    }

    private func endListening() {
        generation &+= 1
        wantsToListen = false
        restartWork?.cancel()
        restartWork = nil
        input.stop()
        clearCarried()
    }

    private func fail(_ s: State) {
        endListening()
        state = s
    }

    private func requestMicrophone(token: UInt) {
        input.requestMicrophoneAccess { [weak self] granted in
            self?.deliver { [weak self] in
                guard let self, self.isCurrent(token) else { return }
                guard granted else {
                    self.fail(.denied("Microphone access was denied. Enable it in System Settings › Privacy & Security › Microphone."))
                    return
                }
                self.beginSession()
            }
        }
    }

    // MARK: - Recognition session

    private func beginSession() {
        generation &+= 1
        let token = generation
        restartWork?.cancel()
        restartWork = nil
        input.stop()
        guard isCurrent(token) else { return }
        state = .listening
        guard isCurrent(token) else { return }
        do {
            try input.start { [weak self] text, finalised, failed in
                self?.deliver { [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    if let text {
                        if self.consider(text, finalised: finalised) != nil {
                            // The acceptance handler may have stopped or restarted
                            // listening synchronously. It owns the resulting session.
                            if self.isCurrent(token) { self.scheduleRestart(after: 1.0) }
                            return
                        }
                        if !text.isEmpty { self.state = .heard(text) }
                    }
                    if self.isCurrent(token), failed || finalised {
                        self.scheduleRestart(after: 0.3)
                    }
                }
            }
        } catch {
            if isCurrent(token) { fail(.unavailable(error.localizedDescription)) }
        }
    }

    private func scheduleRestart(after delay: TimeInterval) {
        // Retire the completed session immediately, not when its replacement
        // starts. Duplicate final results and cancellation errors are obsolete.
        generation &+= 1
        let token = generation
        restartWork?.cancel()
        input.stop()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.beginSession()
        }
        restartWork = work
        schedule(delay, work)
    }
}
