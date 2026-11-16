import Foundation
import Testing

@testable import SpeakboardCore

/// Randomised tests over awkward text (KEY-22 review rounds 2 and 3). Each seed builds a field from scalars that make
/// character boundaries hard, drives random key events through it, and checks every output against a forward model
/// of the documented rules, built on `Array(context)` (Swift's forward grapheme breaking), not on the engine's
/// backward index steps:
/// - a space types a full stop exactly when the model says so, and otherwise a plain space;
/// - each Delete touch-down deletes one character, and each tick deletes what the model's repeats delete;
/// - `nextTick` is the model's next repeat time;
/// - after a key that makes the engine reread the text, Shift (unless locked) is what the model's autocapitalization
///   says.
/// It does not check what a typed character or Return inserts, nor Shift after `.contextChanged`: ShiftTests and
/// the other example tests cover those.
/// It also checks what holds whatever Apple does: no trap, no key but Delete removes text except the full stop's one
/// plain space, a delete count never exceeds the context's characters plus one, and a replay gives the same outputs.
///
/// The seeds are fixed, so every run is the same. A failed expectation names its seed. A trap kills the test
/// process before any expectation is recorded: to find its seed, run the suite with `TYPING_PROPERTY_TRACE=1` in
/// the environment (for example `swift test --no-parallel --filter TypingPropertyTests` inside the Swift image), and
/// each run prints its seed to standard error before it starts; the last seed printed is the one that trapped.
@Suite("Typing: properties over awkward text")
struct TypingPropertyTests {
    /// Scalars that make character boundaries hard, and the ordinary ones the rules read.
    static let pool: [Unicode.Scalar] = [
        // Prepend: joins the character after it, a space included (grapheme rule GB9b).
        "\u{600}", "\u{605}", "\u{6DD}", "\u{70F}", "\u{890}", "\u{8E2}", "\u{D4E}", "\u{110BD}",
        // Combining marks, zero width joiner, variation selector, emoji modifier, keycap mark.
        "\u{301}", "\u{308}", "\u{200D}", "\u{FE0F}", "\u{1F3FD}", "\u{20E3}",
        // Regional indicators (flags), emoji.
        "\u{1F1FA}", "\u{1F1F8}", "\u{1F44D}", "\u{1F468}",
        // CR and LF, Hangul jamo (L, V, T), no-break space.
        "\r", "\n", "\u{1100}", "\u{1161}", "\u{11A8}", "\u{A0}",
        // Letters, digits, spaces, closers, openers, terminators.
        "a", "z", "é", "1", "7", " ", " ", " ", ")", "\"", "\u{201D}", "(", "\u{201C}", ".", "!", "?",
    ]

    static let trace = ProcessInfo.processInfo.environment["TYPING_PROPERTY_TRACE"] != nil

    /// How far the runs reached, so the test fails if the script stops exercising a path.
    struct Reach {
        var wordRepeats = 0
        var characterRepeats = 0
        var lateTicks = 0
        var fullStops = 0
        var joinedSpaceContexts = 0
        var longContexts = 0
        var markedSpaces = 0
        var shiftChecks = 0

        mutating func add(_ other: Reach) {
            wordRepeats += other.wordRepeats
            characterRepeats += other.characterRepeats
            lateTicks += other.lateTicks
            fullStops += other.fullStops
            joinedSpaceContexts += other.joinedSpaceContexts
            longContexts += other.longContexts
            markedSpaces += other.markedSpaces
            shiftChecks += other.shiftChecks
        }
    }

    /// The model of Delete's hold: the documented schedule and what each repeat deletes.
    struct HoldModel {
        var next: Double
        var done: Int
    }

    /// A run of events from one seed.
    struct Run {
        let seed: UInt64
        var random: TypingAllocationTests.Random
        var engine: TypingEngine
        let timings: TypingTimings
        var field = Field()
        var time = 0.0
        var log: [(KeyEvent, Double, TypingContext, TypingOutput)] = []
        var problems: [String] = []
        var reach = Reach()
        /// Whether this seed uses long texts.
        let long: Bool

        // The model's state.
        var lastSpace: Double?
        var hold: HoldModel?

        init(seed: UInt64) {
            self.seed = seed
            random = TypingAllocationTests.Random(state: seed)
            // A quarter of the seeds delete words from the first repeat, a quarter from the second, so word
            // repeats run over awkward text; the rest use the estimates.
            var timings = TypingTimings.estimated
            switch seed % 4 {
            case 0: timings.deleteCharacterRepeats = 1
            case 1: timings.deleteCharacterRepeats = 2
            default: break
            }
            self.timings = timings
            long = seed % 5 == 0
            guard let engine = TypingEngine(locale: .english, timings: timings) else {
                preconditionFailure("no English rules")
            }
            self.engine = engine
        }

        mutating func awkwardText() -> String {
            var text = ""
            let length = long ? 100 + random.below(500) : random.below(10)
            for _ in 0..<length { text.unicodeScalars.append(random.pick(TypingPropertyTests.pool)) }
            return text
        }

        /// The context: the whole text, or a partial one that starts anywhere, even inside a character.
        mutating func context() -> TypingContext {
            var context = field.context
            if random.below(3) == 0 {
                let scalars = field.text.unicodeScalars
                let drop = random.below(scalars.count + 1)
                context.textBeforeCursor = String(String.UnicodeScalarView(scalars.dropFirst(drop)))
            }
            return context
        }

        // MARK: The model, forward over characters

        static func first(_ character: Character) -> Unicode.Scalar {
            character.unicodeScalars[character.unicodeScalars.startIndex]
        }

        /// The documented full-stop rule: the last character is exactly " ", and before it, past any closers, a
        /// character whose first scalar is a letter or digit.
        static func followsAWord(_ text: String, closers: [Unicode.Scalar]) -> Bool {
            let characters = Array(text)
            guard let last = characters.last, last == " " else { return false }
            var index = characters.count - 1
            while index > 0 {
                let first = Self.first(characters[index - 1])
                if closers.contains(first) {
                    index -= 1
                    continue
                }
                return first.properties.isAlphabetic || first.properties.numericType != nil
            }
            return false
        }

        /// The documented autocapitalisation rule, read backward over the scalars of `text` (TypingEngine's
        /// `capitalizes`), with the default settings.
        static func capitalizes(_ text: String, _ type: Autocapitalization, rules: TypingRules) -> Bool {
            switch type {
            case .none: return false
            case .allCharacters: return true
            case .words, .sentences: break
            }
            let scalars = Array(text.unicodeScalars)
            var index = scalars.count
            func peek() -> Unicode.Scalar? { index > 0 ? scalars[index - 1] : nil }
            while let scalar = peek(), rules.openers.contains(scalar) { index -= 1 }
            guard let first = peek() else { return true }
            guard first.properties.isWhitespace else { return false }
            if type == .words { return true }
            while let scalar = peek(), scalar.properties.isWhitespace {
                if [0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029].contains(scalar.value) { return true }
                index -= 1
            }
            guard peek() != nil else { return true }
            while let scalar = peek(), rules.closers.contains(scalar) { index -= 1 }
            guard let last = peek() else { return false }
            return rules.sentenceTerminators.contains(last)
        }

        /// What a tick at `time` deletes, by the documented schedule, over `text`'s characters.
        mutating func tickModel(_ text: String, at time: Double) -> Int {
            guard var model = hold, model.next <= time else { return 0 }
            let characters = Array(text)
            let characterRepeats = max(1, timings.deleteCharacterRepeats)
            func interval(after done: Int) -> Double {
                done < characterRepeats ? timings.deleteRepeatInterval : timings.deleteWordRepeatInterval
            }
            func isSpace(_ index: Int) -> Bool { Self.first(characters[index]).properties.isWhitespace }
            var position = characters.count
            var count = 0
            var usedExtra = false
            var repeats = 0
            while model.next <= time {
                if usedExtra && position == 0 {
                    model.next = time + interval(after: model.done)
                    break
                }
                var deleted = 0
                if model.done < characterRepeats {
                    if position > 0 {
                        position -= 1
                        deleted = 1
                    }
                    reach.characterRepeats += 1
                } else {
                    while position > 0 && isSpace(position - 1) {
                        position -= 1
                        deleted += 1
                    }
                    while position > 0 && !isSpace(position - 1) {
                        position -= 1
                        deleted += 1
                    }
                    if deleted > 0 { reach.wordRepeats += 1 }
                }
                if deleted == 0 && !usedExtra {
                    usedExtra = true
                    deleted = 1
                }
                count += deleted
                model.done += 1
                model.next += interval(after: model.done)
                repeats += 1
            }
            if repeats > 1 { reach.lateTicks += 1 }
            hold = model
            return count
        }

        // MARK: Driving

        mutating func send(_ event: KeyEvent, after gap: Double) {
            time += gap
            let context = context()
            let before = context.textBeforeCursor
            if before.unicodeScalars.count >= 100 { reach.longContexts += 1 }
            let output = engine.handle(event, at: time, in: context)
            log.append((event, time, context, output))
            let describe = "\(event) at \(time) after \(before.unicodeScalars.map { String($0.value, radix: 16) })"

            // The model's expected output.
            var expectedDelete = 0
            var expectedInsertion: String?
            // Whether the event makes the engine read autocapitalisation again from the text after its output.
            var rereads = false
            switch event {
            case .character:
                lastSpace = nil
                hold = nil
                rereads = true
            case .shift, .returnKey, .deleteUp:
                lastSpace = nil
                hold = nil
            case .space:
                hold = nil
                rereads = true
                let scalars = before.unicodeScalars
                if let last = scalars.last, last == " ", Array(before).last != " " {
                    reach.joinedSpaceContexts += 1
                }
                if let last = Array(before).last, last.unicodeScalars.first == " ", last != " " {
                    reach.markedSpaces += 1
                }
                if let last = lastSpace, time - last >= 0, time - last <= timings.doubleSpaceWindow,
                    Self.followsAWord(before, closers: engine.rules.closers)
                {
                    expectedDelete = 1
                    expectedInsertion = engine.rules.doubleSpaceInsertion
                    lastSpace = nil
                    reach.fullStops += 1
                } else {
                    expectedInsertion = " "
                    lastSpace = time
                }
            case .deleteDown:
                lastSpace = nil
                hold = HoldModel(next: time + timings.deleteInitialDelay, done: 0)
                expectedDelete = 1
                rereads = true
            case .tick:
                let due = hold.map { $0.next <= time } ?? false
                expectedDelete = tickModel(before, at: time)
                rereads = due
            case .contextChanged:
                break
            }
            if output.deleteCount != expectedDelete {
                problems.append("\(describe): deletes \(output.deleteCount), the model \(expectedDelete)")
            }
            if let expected = expectedInsertion, output.insertion != expected {
                problems.append("\(describe): types \(output.insertion.debugDescription), the model \(expected)")
            }
            if output.nextTick != hold?.next {
                problems.append(
                    "\(describe): next tick \(String(describing: output.nextTick)), the model \(String(describing: hold?.next))"
                )
            }

            // What holds whatever the model says.
            switch event {
            case .deleteDown, .tick:
                if output.deleteCount > before.count + 1 {
                    problems.append("\(describe): deletes \(output.deleteCount), more than the context and one")
                }
            case .space:
                if output.deleteCount != 0 && !(output.deleteCount == 1 && Array(before).last == " ") {
                    problems.append("\(describe): deletes \(output.deleteCount), not one plain trailing space")
                }
            default:
                if output.deleteCount != 0 {
                    problems.append("\(describe): a key that is not Delete deletes \(output.deleteCount)")
                }
            }
            if case .returnKey = event, !output.insertion.isEmpty { rereads = true }
            if rereads && engine.shiftState != .locked {
                // The text after the output, as the engine reads it: the context less the deleted characters, then
                // the insertion.
                let after = String(Array(before).dropLast(output.deleteCount)) + output.insertion
                let capital = Self.capitalizes(after, context.autocapitalization, rules: engine.rules)
                if engine.shiftState != (capital ? .automatic : .off) {
                    problems.append(
                        "\(describe): Shift \(engine.shiftState), the model \(capital ? "automatic" : "off")")
                }
                reach.shiftChecks += 1
            }
            if !(output.nextTick.map { $0 >= time } ?? true) {
                problems.append("\(describe): asks for a tick in the past")
            }
            field.apply(output)
        }

        mutating func run(events: Int) {
            if TypingPropertyTests.trace {
                FileHandle.standardError.write(Data("TypingPropertyTests seed \(seed)\n".utf8))
            }
            field.text = awkwardText()
            field.autocapitalization = random.pick(Autocapitalization.allCases)
            send(.contextChanged, after: 0)
            let quick = timings.doubleSpaceWindow / 2
            while log.count < events {
                switch random.below(11) {
                case 10:
                    // A word, closers sometimes, then two quick spaces: the full stop's path.
                    for _ in 0...random.below(3) { send(.character(random.pick(["a", "é", "7"])), after: 1) }
                    if random.below(3) == 0 { send(.character(random.pick([")", "\""])), after: 1) }
                    send(.space, after: 1)
                    if random.below(3) == 0 {
                        // The app adds a mark to the space before the second one: the space is no longer alone.
                        field.text.unicodeScalars.append(random.pick(["\u{301}", "\u{308}", "\u{FE0F}", "\u{200D}"]))
                        send(.contextChanged, after: quick / 2)
                        send(.space, after: quick / 2)
                    } else {
                        send(.space, after: quick)
                    }
                case 0..<2: send(.character(random.pick(TypingPropertyTests.pool)), after: random.pick([quick, 1]))
                case 2..<5: send(.space, after: random.pick([quick, quick, 1]))
                case 5: send(.shift, after: random.pick([0, quick, 1]))
                case 6: send(.returnKey, after: 1)
                case 7..<9:
                    send(.deleteDown, after: 1)
                    for _ in 0..<random.below(timings.deleteCharacterRepeats + 6) {
                        guard let due = log.last?.3.nextTick else { break }
                        switch random.below(4) {
                        // Early: nothing is due yet.
                        case 0: send(.tick, after: due.nextDown - time)
                        // Late: several repeats are due at once.
                        case 1:
                            let late = Double(1 + random.below(30)) * timings.deleteWordRepeatInterval
                            send(.tick, after: due + late - time)
                        default: send(.tick, after: due - time)
                        }
                    }
                    send(.deleteUp, after: 0)
                default:
                    field.text = awkwardText()
                    send(.contextChanged, after: 1)
                }
            }
        }
    }

    static let seeds: [UInt64] = Array(1...400)

    @Test("Space, Delete and Shift match the model of the documented rules over awkward text, and the properties hold")
    func properties() {
        var reach = Reach()
        var index = 0
        while index < Self.seeds.count {
            var run = Run(seed: Self.seeds[index])
            run.run(events: 60)
            #expect(run.problems.isEmpty, "seed \(Self.seeds[index]): \(run.problems.prefix(3))")
            reach.add(run.reach)
            index += 1
        }
        print(
            "TypingPropertyTests reach: \(reach.wordRepeats) word repeats, \(reach.characterRepeats) character"
                + " repeats, \(reach.lateTicks) late ticks, \(reach.fullStops) full stops,"
                + " \(reach.joinedSpaceContexts) joined-space contexts, \(reach.markedSpaces) marked spaces,"
                + " \(reach.longContexts) long contexts, \(reach.shiftChecks) Shift checks")
        #expect(reach.wordRepeats >= 1000 && reach.lateTicks >= 500 && reach.fullStops >= 100)
        #expect(reach.joinedSpaceContexts >= 50 && reach.longContexts >= 1000)
        #expect(reach.markedSpaces >= 50 && reach.shiftChecks >= 5000)
    }

    @Test("The same events in the same contexts give the same outputs on a fresh engine")
    func replay() throws {
        var index = 0
        while index < Self.seeds.count {
            var run = Run(seed: Self.seeds[index])
            run.run(events: 60)
            var engine = try #require(TypingEngine(locale: .english, timings: run.timings))
            var differences = 0
            for (event, time, context, output) in run.log where engine.handle(event, at: time, in: context) != output {
                differences += 1
            }
            #expect(differences == 0, "seed \(Self.seeds[index]): \(differences) outputs differ on replay")
            index += 1
        }
    }
}
