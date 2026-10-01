import Foundation
import Speech

/// Exercises the oath matcher without a microphone.
/// Run with `Lantern --test-oath`.
enum OathMatchTests {

    private typealias Corps = LanternGlyph.Emblem
    private static var executedCases = 0

    /// `expect` is the corps the transcript should swear the lantern to, or
    /// nil for a transcript that must not trip any oath.
    private static let cases: [(text: String, expect: Corps?, note: String)] = [
        // MARK: Green Lantern — the proper oath, as written.
        ("In brightest day, in blackest night, no evil shall escape my sight. Let those who worship evil's might beware my power — Green Lantern's light!",
         .green, "green: canonical"),
        ("In brightest day, in blackest night, no evil shall escape my sight. Let those who worship evil\u{2019}s might beware my power, Green Lantern\u{2019}s light!",
         .green, "green: curly apostrophes"),
        ("in brightest day in blackest night no evil shall escape my sight let those who worship evils might beware my power green lanterns light",
         .green, "green: no punctuation"),
        ("in brightest day in blackest night no evil shall escape my sight let those you worship evils light beware my power green lanterns light",
         .green, "green: \"evils light\" variant"),
        ("in brightest day in blackest night no evil shall escape my sight let those who worship evil smite beware my power green lanterns light",
         .green, "green: ASR hears \"evil smite\""),
        ("IN BRIGHTEST DAY IN BLACKEST NIGHT NO EVIL SHALL ESCAPE MY SIGHT BEWARE MY POWER GREEN LANTERN",
         .green, "green: shouted, clause dropped"),

        // MARK: Sinestro Corps.
        ("In blackest day, in brightest night, beware your fears made into light. Let those who try to stop what's right, burn like my power — Sinestro's might!",
         .sinestro, "sinestro: canonical"),
        ("in blackest day in brightest night beware your fears made into light let those who try to stop whats right burn like my power sinestros might",
         .sinestro, "sinestro: no punctuation"),
        // Recognition loves to "correct" the inverted opening back to the
        // Green Lantern order. That costs two phrases; four must still carry it.
        ("In brightest day, in blackest night, beware your fears made into light. Let those who try to stop what's right, burn like my power, Sinestro's might!",
         .sinestro, "sinestro: opening \"corrected\" to the green order"),
        ("in blackest day in brightest night beware your fears made into light burn like my power sinestro",
         .sinestro, "sinestro: middle clause dropped"),

        // MARK: Sinestro when the recogniser mangles the name.
        // It has never heard of a Sinestro, so it offers something adjacent —
        // or splits it in two. The oath must not hang on the word at all.
        ("in blackest day in brightest night beware your fears made into light let those who try to stop whats right burn like my power sinistros might",
         .sinestro, "sinestro: heard as \"sinistro\""),
        ("in blackest day in brightest night beware your fears made into light let those who try to stop whats right burn like my power synestros might",
         .sinestro, "sinestro: heard as \"synestro\""),
        ("in blackest day in brightest night beware your fears made into light let those who try to stop whats right burn like my power sin estros might",
         .sinestro, "sinestro: split into \"sin estro\""),
        ("in blackest day in brightest night beware your fears made into light let those who try to stop whats right burn like my power cinestros might",
         .sinestro, "sinestro: heard as \"cinestro\""),
        // The name lost entirely — the reported failure.
        ("in blackest day in brightest night beware your fears made into light let those who try to stop whats right burn like my power sinister might",
         .sinestro, "sinestro: name lost to a common word"),
        ("in blackest day in brightest night beware your fears made into light let those who try to stop whats right burn like my power my might",
         .sinestro, "sinestro: name dropped altogether"),
        // The worst realistic case: the opening "corrected" AND the name lost.
        ("in brightest day in blackest night beware your fears made into light let those who try to stop whats right burn like my power sinister might",
         .sinestro, "sinestro: opening corrected and name lost"),

        // MARK: Red Lantern Corps — an oath that never names its corps.
        ("With blood and rage of crimson red, ripped from a corpse so freshly dead, together with our hellish hate, we'll burn you all — that is your fate!",
         .red, "red: canonical"),
        ("with blood and rage of crimson red ripped from a corpse so freshly dead together with our hellish hate well burn you all that is your fate",
         .red, "red: no punctuation"),
        ("with blood and rage of crimson read ripped from a corpse so freshly dead together with our hellish hate we'll burn you all that is your fate",
         .red, "red: ASR hears \"crimson read\""),

        // MARK: Orange Lantern Corps — an oath that is one word repeated.
        ("What's mine is mine, and mine, and mine. And mine and mine and mine! Not yours!",
         .orange, "orange: canonical"),
        ("whats mine is mine and mine and mine and mine and mine and mine not yours",
         .orange, "orange: no punctuation"),
        ("what is mine is mine and mine and mine and mine and mine and mine not yours",
         .orange, "orange: \"what is\" rather than \"what's\""),
        ("whats mine is mine and mine and mine and mine and mine and mine",
         .orange, "orange: the last line dropped"),
        ("mine and mine and mine and mine and mine not yours",
         .orange, "orange: opening lost, refrain and close intact"),

        // MARK: Black Lantern Corps.
        ("The Blackest Night falls from the skies, the darkness grows as all light dies. We crave your hearts and your demise, by my Black Hand, the dead shall rise!",
         .black, "black: canonical"),
        ("the blackest night falls from the skies the darkness grows as all light dies we crave your hearts and your demise by my black hand the dead shall rise",
         .black, "black: no punctuation"),
        ("the blackest night falls from the skies the darkness grows we crave your hearts by my black hand the dead shall rise",
         .black, "black: a line dropped"),
        // Its opening is a Green Lantern phrase; the Green oath's clincher
        // keeps it from answering.
        ("the blackest night falls from the skies the darkness grows as all light dies by my black hand the dead shall rise",
         .black, "black: opens on a phrase green also uses"),

        // MARK: White Lantern Corps.
        ("In brightest day, there will be light. To cleanse the soul and set wrongs right. When darkness falls, look to the skies. A new dawn comes — let there be light.",
         .white, "white: canonical"),
        ("in brightest day there will be light to cleanse the soul and set wrongs right when darkness falls look to the skies a new dawn comes let there be light",
         .white, "white: no punctuation"),
        ("to cleanse the soul and set wrongs right when darkness falls look to the skies let there be light",
         .white, "white: opening dropped"),
        // It opens on a Green Lantern line and ends on light, like Sinestro's.
        ("in brightest day there will be light to cleanse the soul and set wrongs right a new dawn comes let there be light",
         .white, "white: opens on a line green also says"),

        // MARK: Blue Lantern Corps.
        ("In fearful day, in raging night, with strong hearts full, our souls ignite. When all seems lost in the War of Light, look to the stars — for hope burns bright!",
         .blue, "blue: canonical"),
        ("in fearful day in raging night with strong hearts full our souls ignite when all seems lost in the war of light look to the stars for hope burns bright",
         .blue, "blue: no punctuation"),
        ("with strong hearts full our souls ignite in the war of light look to the stars for hope burns bright",
         .blue, "blue: opening dropped"),
        // "look to the stars" is a step from the White oath's "look to the
        // skies", and both oaths end on light.
        ("in fearful day in raging night our souls ignite in the war of light look to the skies for hope burns bright",
         .blue, "blue: \"stars\" misheard as the white oath's \"skies\""),

        // MARK: Star Sapphire Corps.
        ("For hearts long lost and full of fright, for those alone in blackest night. Accept our ring and join our fight, love conquers all with violet light!",
         .sapphire, "sapphire: canonical"),
        ("for hearts long lost and full of fright for those alone in blackest night accept our ring and join our fight love conquers all with violet light",
         .sapphire, "sapphire: no punctuation"),
        ("for those alone in blackest night accept our ring and join our fight love conquers all with violet light",
         .sapphire, "sapphire: opening dropped"),
        // It says "in blackest night" — the Green oath's phrase and the Black
        // oath's opening — and "hearts", which the Blue and Black ones use.
        ("for hearts long lost and full of fright in blackest night love conquers all with violet light",
         .sapphire, "sapphire: leans on lines three other oaths use"),

        // MARK: Indigo Tribe — an oath with no English in it but its last line.
        ("Tor lorek san, bor nakka mur, Natromo faan tornek wot ur. Ter lantern ker lo Abin Sur, taan lek lek nok — Formorrow Sur!",
         .indigo, "indigo: canonical"),
        // What a recogniser actually returns, the alien words as noise.
        ("tore lore ex an bore knock a mur not romo fon tornic what er ter lantern curl oh abin sur tan lek lek nok for morrow sir",
         .indigo, "indigo: the alien words heard as noise"),
        ("lantern for morrow sir", .indigo, "indigo: closing plus an earlier word"),
        ("abin sur for tomorrow sir", .indigo, "indigo: \"formorrow\" heard as \"tomorrow\""),
        ("lantern formorrow sur", .indigo, "indigo: run together, spelled \"sur\""),
        ("lantern for morrow sure", .indigo, "indigo: \"sur\" heard as \"sure\""),

        // MARK: No oath must answer for another.
        ("In brightest day, in blackest night, no evil shall escape my sight. Let those who worship evil's might beware my power — Green Lantern's light!",
         .green, "green text is not sinestro's"),
        ("In blackest day, in brightest night, beware your fears made into light. Let those who try to stop what's right, burn like my power — Sinestro's might!",
         .sinestro, "sinestro text is not green's"),
        ("With blood and rage of crimson red, ripped from a corpse so freshly dead, together with our hellish hate, we'll burn you all — that is your fate!",
         .red, "red text is neither of the others"),

        // MARK: Not enough of any oath.
        ("green lantern", nil, "green: clincher alone"),
        ("in brightest day in blackest night", nil, "green: opening only"),
        ("beware my power green lantern", nil, "green: two phrases"),
        ("in brightest day in blackest night no evil shall escape my sight", nil, "green: no clincher"),
        ("what's the weather like in brightest day", nil, "incidental phrase"),
        ("let those who worship evil's might", nil, "green: clause alone"),
        ("sinestro", nil, "sinestro: name alone"),
        ("in blackest day in brightest night sinestro", nil, "sinestro: three hits"),
        ("in blackest day in brightest night", nil, "sinestro: opening alone, no clincher"),
        ("the sinistro building is on brightest street", nil, "a near-miss name in idle speech"),
        ("crimson red", nil, "red: clincher alone"),
        ("with blood and rage of crimson red that is your fate", nil, "red: three phrases"),
        ("ripped from a corpse so freshly dead we'll burn you all", nil, "red: no clincher"),
        ("that's mine", nil, "orange: one \"mine\""),
        ("whats mine is mine", nil, "orange: the opening alone"),
        ("not yours", nil, "orange: the close alone"),
        ("the coal mine and the gold mine and the salt mine are not yours", nil,
         "orange: \"mine\" three times in ordinary speech"),
        ("the blackest night", nil, "black: its opening words alone"),
        ("by my black hand", nil, "black: clincher alone"),
        ("the darkness grows and the dead shall rise", nil, "black: two phrases"),
        ("in brightest day there will be light", nil, "white: its opening alone"),
        ("let there be light", nil, "white: clincher alone"),
        ("when darkness falls look to the skies", nil, "white: two phrases"),
        ("in fearful day in raging night", nil, "blue: its opening alone"),
        ("the war of light", nil, "blue: clincher alone"),
        ("look to the stars for hope burns bright", nil, "blue: two phrases"),
        ("for those alone in blackest night", nil, "sapphire: a line it shares, alone"),
        ("love conquers all", nil, "sapphire: clincher alone"),
        ("accept our ring and join our fight", nil, "sapphire: two phrases"),
        // Indigo needs an explicit closing variant and earlier oath evidence.
        ("tomorrow", nil, "indigo: \"tomorrow\" on its own"),
        ("see you tomorrow then", nil, "indigo: \"tomorrow\" in ordinary speech"),
        ("good morrow", nil, "indigo: \"morrow\" without what follows it"),
        ("ter lantern ker lo abin sur", nil, "indigo: the line before it, alone"),
        ("for morrow sir", nil, "indigo: closing alone lacks earlier oath evidence"),
        ("for tomorrow sir", nil, "indigo: an ordinary closing phrase alone"),
        ("Tomorrow surely will be better.", nil, "indigo: surely is not sure"),
        ("I have an appointment tomorrow surgery starts at nine.", nil,
         "indigo: surgery is not sur"),
        ("the lantern will arrive tomorrow surely", nil,
         "indigo: earlier evidence must not relax closing word boundaries"),
        ("lantern formorrow surface", nil, "indigo: surface is not sur"),
        ("mine and mine and mine not yours determine examine", nil,
         "orange: fragments inside other words do not count as mine"),
        ("mine and mine and mine not yours mines miners", nil,
         "orange: plural and suffixed forms are not the refrain"),
        ("brightest day blackest night escape my sight green lanternfish", nil,
         "green: an arbitrary suffix cannot supply the clincher"),
    ]

    /// Normalisation has to collapse possessives the way the phrase lists spell
    /// them, or those clauses silently never match.
    private static let normalisationCases: [(String, String)] = [
        ("evil's might", "evils might"),
        ("evil\u{2019}s might", "evils might"),
        ("Green Lantern's light!", "green lanterns light"),
        ("stop what's right", "stop whats right"),
        ("Sinestro\u{2019}s might!", "sinestros might"),
        ("we'll burn you all—that is your fate!", "well burn you all that is your fate"),
        ("  In brightest  day, ", "in brightest day"),
    ]

    static func run() -> Int {
        executedCases = 0
        var failures = 0

        print("normalisation")
        for (input, expected) in normalisationCases {
            let got = OathListener.normalize(input)
            let ok = got == expected
            executedCases += 1
            if !ok { failures += 1 }
            print("  \(ok ? "ok  " : "FAIL") \"\(input)\" -> \"\(got)\"\(ok ? "" : "  (expected \"\(expected)\")")")
        }

        print("\nmatching")
        for c in cases {
            let got = OathListener.match(c.text)?.corps
            let ok = got == c.expect
            executedCases += 1
            if !ok { failures += 1 }
            print("  \(ok ? "ok  " : "FAIL") expect=\(describe(c.expect)) got=\(describe(got))  \(c.note)")
        }

        // Every oath's own written text must swear to its own corps. This is
        // what stops the phrase lists drifting away from the words in the menu.
        print("\nthe oaths as written")
        for oath in OathListener.oaths {
            let got = OathListener.match(oath.text)?.corps
            let ok = got == oath.corps
            executedCases += 1
            if !ok { failures += 1 }
            print("  \(ok ? "ok  " : "FAIL") \(oath.name) -> \(describe(got))")
        }

        print("\nhearing the name")
        for (text, expected, note) in nameCases {
            let got = OathListener.heardName("sinestro", in: OathListener.normalize(text))
            let ok = got == expected
            executedCases += 1
            if !ok { failures += 1 }
            print("  \(ok ? "ok  " : "FAIL") expect=\(expected) got=\(got)  \(note)")
        }

        print("\nthe accept path")
        let acceptFailures = runAccept()
        failures += acceptFailures

        print("\nwhat the charge alone can reach")
        let batteryFailures = runBattery()
        failures += batteryFailures

        print("\nthe gate")
        let gateFailures = runGate()
        failures += gateFailures

        print("\nspeech lifecycle")
        failures += runLifecycle()

        let total = executedCases
        print(failures == 0 ? "\nall \(total) cases pass" : "\n\(failures) of \(total) FAILED")
        return failures
    }

    /// The loose name match, which is what lets the Sinestro oath survive a
    /// recogniser that has never heard the word.
    private static let nameCases: [(String, Bool, String)] = [
        ("burn like my power sinestros might", true, "exact"),
        ("burn like my power sinistros might", true, "sinistro"),
        ("burn like my power synestro might", true, "synestro"),
        ("burn like my power cinestro might", true, "cinestro"),
        ("burn like my power sin estro might", true, "split into two words"),
        ("burn like my power sinestra might", true, "sinestra"),
        ("this is a sentence about nothing", false, "ordinary speech"),
        ("the minister said so", false, "minister is not close enough"),
        ("sin", false, "a fragment on its own"),
    ]

    /// The path the microphone drives: a transcript goes in, and an oath that
    /// lands fires `onAccepted` exactly once with the corps it swore to.
    /// Anything short of an oath must fire nothing at all.
    private static func runAccept() -> Int {
        var failures = 0
        func check(_ ok: Bool, _ note: String) {
            executedCases += 1
            if !ok { failures += 1 }
            print("  \(ok ? "ok  " : "FAIL") \(note)")
        }

        for oath in OathListener.oaths {
            let listener = OathListener()
            var heard: [Corps] = []
            listener.onAccepted = { heard.append($0.corps) }
            let returned = listener.consider(oath.text)?.corps
            check(heard == [oath.corps] && returned == oath.corps,
                  "\(oath.name): fires once, swearing to its own corps")
        }

        let listener = OathListener()
        var fired = false
        listener.onAccepted = { _ in fired = true }
        let returned = listener.consider("what's the weather like in brightest day")
        check(!fired && returned == nil, "a transcript that is no oath fires nothing")

        // Recognition ends a session after a beat of silence, so an oath said
        // with pauses arrives in pieces. Neither half is an oath; together
        // they are.
        let paused = OathListener()
        var sworn: [Corps] = []
        paused.onAccepted = { sworn.append($0.corps) }
        let opening = "in blackest day in brightest night"
        let closing = "burn like my power sinestros might"
        check(OathListener.match(opening) == nil && OathListener.match(closing) == nil,
              "both split-oath halves individually fall short")
        let first = paused.consider(opening, finalised: true)
        check(first == nil && sworn.isEmpty, "half an oath alone lands nothing")
        let second = paused.consider(closing, finalised: true)
        check(second?.corps == .sinestro && sworn == [.sinestro],
              "the rest of it, after a pause, completes the oath")

        // A later fragment cannot refresh the age of earlier speech.
        var time: TimeInterval = 0
        let expiring = OathListener(now: { time })
        expiring.consider("brightest day blackest night", finalised: true)
        time = 20
        expiring.consider("yes", finalised: true)
        time = 40
        expiring.consider("yes", finalised: true)
        time = 60
        check(expiring.consider("escape my sight green lantern", finalised: true) == nil,
              "unrelated speech cannot preserve a minute-old oath fragment")

        time = 0
        let boundary = OathListener(now: { time })
        boundary.consider(opening, finalised: true)
        time = 25
        check(boundary.consider(closing) == nil, "fragments expire at 25 seconds")

        time = 0
        let fresh = OathListener(now: { time })
        fresh.consider(opening, finalised: true)
        time = 24.9
        check(fresh.consider(closing)?.corps == .sinestro,
              "fragments just within 25 seconds still combine")

        time = 0
        let mixedAges = OathListener(now: { time })
        mixedAges.consider("irrelevant", finalised: true)
        time = 20
        mixedAges.consider(opening, finalised: true)
        time = 30
        check(mixedAges.consider(closing)?.corps == .sinestro,
              "expiring an older segment preserves newer useful speech")

        // And what was carried must not survive being switched off.
        let reset = OathListener()
        reset.consider("in blackest day in brightest night", finalised: true)
        reset.stop()
        let afterStop = reset.consider("burn like my power sinestros might", finalised: true)
        check(afterStop == nil, "switching off drops what was carried")
        return failures
    }

    /// The charge picks its battery tiers. Orange is reachable by
    /// swearing its oath and by nothing else — including a battery at any
    /// level, charging or not.
    private static func runBattery() -> Int {
        var failures = 0
        func check(_ ok: Bool, _ note: String) {
            executedCases += 1
            if !ok { failures += 1 }
            print("  \(ok ? "ok  " : "FAIL") \(note)")
        }
        check(LanternGlyph.corps(level: 0.9, charging: false) == .green, "90% is green")
        check(LanternGlyph.corps(level: 1.0, charging: false) == .white, "100% is White Lantern")
        check(LanternGlyph.corps(level: 1.0, charging: true) == .white,
              "100% is White Lantern on the charger too")
        check(LanternGlyph.corps(level: 0.97, charging: false) == .green, "97% is still green")
        check(LanternGlyph.corps(level: 0.15, charging: false) == .sinestro, "15% is Sinestro")
        check(LanternGlyph.corps(level: 0.05, charging: false) == .red, "5% is Red Lantern")
        // The black threshold is written against the shown percentage, so it
        // must turn on exactly when the caption reads 1%.
        check(LanternGlyph.corps(level: 0.01, charging: false) == .black, "1% is Black Lantern")
        check(LanternGlyph.corps(level: 0.0, charging: false) == .black, "0% is Black Lantern")
        check(LanternGlyph.corps(level: 0.02, charging: false) == .red, "2% is still Red Lantern")
        check(LanternGlyph.corps(level: 0.01, charging: true) == .green,
              "charging at 1% is green, like every other tier")

        // Every level, charging and not — orange must never come back.
        var reached: Set<String> = []
        for step in 0...1000 {
            for charging in [false, true] {
                reached.insert(describe(LanternGlyph.corps(level: Double(step) / 1000,
                                                           charging: charging)))
            }
        }
        check(!reached.contains("orange"), "no charge, at any level, reaches orange")
        check(!reached.contains("blue"), "nor, at any level, blue")
        check(!reached.contains("sapphire"), "nor Star Sapphire")
        check(!reached.contains("indigo"), "nor the Indigo Tribe")

        let charge = ChargeController()
        charge.swear(to: .orange)
        check(LanternGlyph.palette(level: 0.5, charging: false, sworn: charge.sworn).emblem
                == .orange, "swearing its oath is the way in")
        return failures
    }

    /// What an oath does to the lantern, and what sealing undoes: swearing
    /// overrides the corps the charge would choose, and sealing hands it back.
    private static func runGate() -> Int {
        var failures = 0
        func check(_ ok: Bool, _ note: String) {
            executedCases += 1
            if !ok { failures += 1 }
            print("  \(ok ? "ok  " : "FAIL") \(note)")
        }

        let charge = ChargeController()
        check(charge.gate == .sealed && charge.sworn == nil, "starts sealed, sworn to nobody")

        charge.swear(to: .sinestro)
        check(charge.gate == .open && charge.sworn == .sinestro, "the Sinestro oath opens and swears")

        // A full battery would be the White Lantern's; the oath overrides it.
        check(LanternGlyph.palette(level: 1.0, charging: false, sworn: charge.sworn).emblem
                == .sinestro, "sworn Sinestro beats a full charge")

        charge.swear(to: .red)
        check(charge.gate == .open && charge.sworn == .red, "a second oath swears to that corps instead")

        charge.set(.sealed)
        check(charge.gate == .sealed && charge.sworn == nil, "sealing releases the corps")

        // Back on the battery's terms.
        check(LanternGlyph.palette(level: 0.9, charging: false, sworn: charge.sworn).emblem
                == .green, "released, a 90% charge is green again")
        check(LanternGlyph.palette(level: 0.05, charging: false, sworn: charge.sworn).emblem
                == .red, "released, a flat charge is red again")
        charge.swear(to: .blue)
        let plugged = BatteryInfo(hasBattery: true, isPluggedIn: true)
        let unplugged = BatteryInfo(hasBattery: true, isPluggedIn: false)
        charge.batteryChanged(from: plugged, to: plugged)
        check(charge.gate == .open && charge.sworn == .blue,
              "battery updates while plugged in preserve the oath")
        charge.batteryChanged(from: plugged, to: unplugged)
        check(charge.gate == .sealed && charge.sworn == nil, "unplugging releases the oath")
        charge.batteryChanged(from: unplugged, to: plugged)
        check(charge.gate == .sealed && charge.sworn == nil, "replugging requires a new oath")
        return failures
    }

    private static func runLifecycle() -> Int {
        var failures = 0
        OathLifecycleTests.run { ok, note in
            executedCases += 1
            if !ok { failures += 1 }
            print("  \(ok ? "ok  " : "FAIL") \(note)")
        }
        return failures
    }

    private static func describe(_ corps: Corps?) -> String {
        guard let corps else { return "none" }
        switch corps {
        case .green: return "green"
        case .sinestro: return "sinestro"
        case .red: return "red"
        case .orange: return "orange"
        case .black: return "black"
        case .white: return "white"
        case .blue: return "blue"
        case .sapphire: return "sapphire"
        case .indigo: return "indigo"
        }
    }
}
