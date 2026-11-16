import Testing

@testable import SpeakboardCore

/// Randomised tests over awkward text: properties that hold whatever Apple's keyboard does, checked on contexts built
/// from scalars that make character boundaries hard (KEY-22 review round 2). The seeds are fixed, so a failure
/// names its seed and is repeatable.
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
        "a", "z", "é", "1", "7", " ", " ", ")", "\"", "\u{201D}", "(", "\u{201C}", ".", "!", "?",
    ]

    /// A run of events from one seed, on a field that starts with awkward text.
    struct Run {
        var random: TypingAllocationTests.Random
        var engine: TypingEngine
        var field = Field()
        var time = 0.0
        /// Every event with the context it was sent in, and the output, for the replay.
        var log: [(KeyEvent, Double, TypingContext, TypingOutput)] = []
        var problems: [String] = []

        init(seed: UInt64) {
            random = TypingAllocationTests.Random(state: seed)
            guard let engine = TypingEngine(locale: .english) else { preconditionFailure("no English rules") }
            self.engine = engine
        }

        mutating func awkwardText() -> String {
            var text = ""
            for _ in 0..<random.below(8) { text.unicodeScalars.append(random.pick(TypingPropertyTests.pool)) }
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

        mutating func send(_ event: KeyEvent, after gap: Double) {
            time += gap
            let context = context()
            let before = context.textBeforeCursor
            let output = engine.handle(event, at: time, in: context)
            log.append((event, time, context, output))

            let describe = "\(event) after \(before.unicodeScalars.map { String($0.value, radix: 16) })"
            switch event {
            case .deleteDown, .tick:
                if output.deleteCount > before.count + 1 {
                    problems.append("\(describe): deletes \(output.deleteCount), more than the context and one")
                }
            case .space:
                if output.deleteCount != 0 && !(output.deleteCount == 1 && before.last == " ") {
                    problems.append("\(describe): deletes \(output.deleteCount), not one plain trailing space")
                }
            default:
                if output.deleteCount != 0 {
                    problems.append("\(describe): a key that is not Delete deletes \(output.deleteCount)")
                }
            }
            if !(output.nextTick.map { $0 >= time } ?? true) {
                problems.append("\(describe): asks for a tick in the past")
            }
            // The field applies the output to its whole text, as iOS does to the document.
            field.apply(output)
        }

        mutating func run(events: Int) {
            field.text = awkwardText()
            field.autocapitalization = random.pick(Autocapitalization.allCases)
            send(.contextChanged, after: 0)
            let quick = timings.doubleSpaceWindow / 2
            while log.count < events {
                switch random.below(10) {
                case 0..<3: send(.character(random.pick(TypingPropertyTests.pool)), after: random.pick([quick, 1]))
                case 3..<6: send(.space, after: random.pick([quick, quick, 1]))
                case 6: send(.shift, after: random.pick([0, quick, 1]))
                case 7: send(.returnKey, after: 1)
                case 8:
                    send(.deleteDown, after: 1)
                    for _ in 0..<random.below(timings.deleteCharacterRepeats + 4) {
                        guard let due = log.last?.3.nextTick else { break }
                        send(.tick, after: due - time)
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

    @Test("No trap, no key but Delete removes text but the full stop's one plain space, deletes are bounded")
    func properties() {
        var index = 0
        while index < Self.seeds.count {
            var run = Run(seed: Self.seeds[index])
            run.run(events: 60)
            #expect(run.problems.isEmpty, "seed \(Self.seeds[index]): \(run.problems.prefix(3))")
            index += 1
        }
    }

    @Test("The same events in the same contexts give the same outputs on a fresh engine")
    func replay() throws {
        var index = 0
        while index < Self.seeds.count {
            var run = Run(seed: Self.seeds[index])
            run.run(events: 60)
            var engine = try #require(TypingEngine(locale: .english))
            var differences = 0
            for (event, time, context, output) in run.log where engine.handle(event, at: time, in: context) != output {
                differences += 1
            }
            #expect(differences == 0, "seed \(Self.seeds[index]): \(differences) outputs differ on replay")
            index += 1
        }
    }
}
