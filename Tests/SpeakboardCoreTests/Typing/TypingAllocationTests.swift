import AllocationCounter
import Testing

@testable import SpeakboardCore

/// Handling a key event allocates nothing (MANIFESTO.md, Budgets: "Allocations in the keystroke path: zero").
///
/// The test records a long script of key events, each with its time, its context and the settings, by typing into
/// a simulated field. Then it replays the script on a fresh engine while AllocationCounter counts every call to the
/// C allocator on this thread, and checks that every output matches the recording and that the count is zero.
/// Everything the replay reads (the script and the recorded outputs) is built before counting starts, and the
/// replay loop indexes with `while`, so the count is the engine's own.
///
/// What the counter sees and does not see is in Tests/AllocationCounter/AllocationCounter.c: every malloc,
/// calloc, realloc and aligned allocation on this thread, which is how the Swift runtime allocates every class
/// instance, closure context, box and array or string buffer. It does not see the stack, memory mapped directly,
/// or other threads (the engine starts none). It runs on Linux in a debug build, which is stricter than a release
/// build for generic code, and it cannot see what iOS does when the context is a string bridged from UIKit: the
/// extension's adapter is checked on a device (rung 4).
@Suite("Typing: handling a key event allocates nothing")
struct TypingAllocationTests {
    static let counterAvailable = allocation_counter_available()

    /// One recorded event: what the replay sends, and what the engine returned when it was recorded.
    struct Step {
        let event: KeyEvent
        let time: Double
        let context: TypingContext
        let settings: TypingSettings
        let output: TypingOutput
        let shiftAfter: ShiftState
    }

    /// How often the recording reached each behaviour, so the test fails if the script stops reaching one.
    struct Coverage {
        var uppercase = 0
        var lowercase = 0
        var manualShift = 0
        var automaticShift = 0
        var capsLock = 0
        var doubleSpaceStops = 0
        var plainSpaces = 0
        var returns = 0
        var disabledReturns = 0
        var characterRepeats = 0
        var wordRepeats = 0
        var emptyTicks = 0
        var deletesAtStart = 0
        var contextChanges = 0
        var autocapitalization: Set<String> = []
        var returnKinds: Set<String> = []
        var settings: Set<String> = []
    }

    /// A small deterministic random number generator (SplitMix64), so the script is the same on every run.
    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
        mutating func pick<T>(_ values: [T]) -> T { values[below(values.count)] }
    }

    /// Records `count` events, or a few more to finish a delete hold.
    static func record(count: Int) throws -> ([Step], Coverage) {
        var random = Random(state: 22)
        var engine = try #require(TypingEngine(locale: KeyboardLocale(identifier: "en-US")))
        var field = Field()
        var time = 0.0
        var steps: [Step] = []
        var coverage = Coverage()
        let letters =
            Array("abcdefghijklmnopqrstuvwxyzéß".unicodeScalars) + ["\u{1F44D}", "7", ",", "(", ")", "\"", "."]

        /// iOS shares only part of the text: the context is the last 40 characters, or all of it.
        func context() -> TypingContext {
            var context = field.context
            if random.below(2) == 0 { context.textBeforeCursor = String(field.text.suffix(40)) }
            return context
        }

        func send(_ event: KeyEvent, at newTime: Double) {
            time = newTime
            let before = engine.shiftState
            let eventContext = context()
            let output = engine.handle(event, at: time, in: eventContext)
            field.apply(output)
            steps.append(
                Step(
                    event: event, time: time, context: eventContext, settings: engine.settings, output: output,
                    shiftAfter: engine.shiftState))

            switch event {
            case .character:
                if output.insertion != output.insertion.lowercased() { coverage.uppercase += 1 }
                if output.insertion != output.insertion.uppercased() { coverage.lowercase += 1 }
            case .space:
                if output.deleteCount == 1 { coverage.doubleSpaceStops += 1 } else { coverage.plainSpaces += 1 }
            case .returnKey:
                if output.insertion.isEmpty { coverage.disabledReturns += 1 } else { coverage.returns += 1 }
            case .tick:
                if output.deleteCount == 1 { coverage.characterRepeats += 1 }
                if output.deleteCount > 1 { coverage.wordRepeats += 1 }
                if output.deleteCount == 0 { coverage.emptyTicks += 1 }
            case .deleteDown:
                if eventContext.textBeforeCursor.isEmpty { coverage.deletesAtStart += 1 }
            case .contextChanged:
                if before != engine.shiftState { coverage.contextChanges += 1 }
            case .shift, .deleteUp: break
            }
            switch engine.shiftState {
            case .manual: coverage.manualShift += 1
            case .automatic: coverage.automaticShift += 1
            case .locked: coverage.capsLock += 1
            case .off: break
            }
            coverage.autocapitalization.insert("\(eventContext.autocapitalization)")
            coverage.returnKinds.insert("\(eventContext.returnKeyType)")
            coverage.settings.insert("\(engine.settings)")
        }

        // Gaps: inside a window, at a window's end, past it, no time at all, and time going backwards.
        let gaps = [
            timings.shiftDoubleTapWindow / 2, timings.shiftDoubleTapWindow, timings.doubleSpaceWindow / 2,
            timings.doubleSpaceWindow, timings.doubleSpaceWindow * 3, 0, -timings.shiftDoubleTapWindow / 2,
        ]
        send(.contextChanged, at: 0)
        while steps.count < count {
            let gap = random.pick(gaps)
            switch random.below(100) {
            case 0..<40: send(.character(random.pick(letters)), at: time + gap)
            case 40..<55: send(.space, at: time + gap)
            case 55..<65: send(.shift, at: time + gap)
            case 65..<70: send(.returnKey, at: time + gap)
            case 70..<80:
                // A hold: sometimes short, sometimes long enough to delete words, with early and late ticks.
                send(.deleteDown, at: time + 1)
                var next = steps.last?.output.nextTick
                let repeats = random.below(timings.deleteCharacterRepeats + 8)
                var done = 0
                while done < repeats, let due = next {
                    switch random.below(6) {
                    case 0: send(.tick, at: due.nextDown)
                    case 1: send(.tick, at: due + timings.deleteRepeatInterval * 3)
                    default: send(.tick, at: due)
                    }
                    next = steps.last?.output.nextTick
                    done += 1
                }
                send(.deleteUp, at: time + timings.deleteRepeatInterval / 2)
                send(.tick, at: time + timings.deleteInitialDelay)
            case 80..<88:
                // The cursor moves, or the app changes the text.
                switch random.below(4) {
                case 0: field.text = ""
                case 1: field.text += random.pick(["Hello. ", "\n", "e.g. ", "\u{201C}Hi.\u{201D} ", "word"])
                case 2: field.text = String(field.text.dropLast(random.below(10)))
                default: field.textAfterCursor = random.pick(["", "after"])
                }
                send(.contextChanged, at: time + gap)
            case 88..<95:
                field.autocapitalization = random.pick(Autocapitalization.allCases)
                field.returnKeyType = random.pick(ReturnKeyType.allCases)
                field.enablesReturnKeyAutomatically = random.below(3) == 0
                send(.contextChanged, at: time + 1)
            default:
                engine.settings = TypingSettings(
                    autoCapitalization: random.below(4) != 0, capsLock: random.below(4) != 0,
                    periodShortcut: random.below(4) != 0)
                send(.contextChanged, at: time + 1)
            }
            // Keep the document short enough that the empty field comes up often.
            if field.text.count > 200 { field.text = String(field.text.suffix(20)) }
        }
        return (steps, coverage)
    }

    @Test("The script reaches every behaviour in scope")
    func scriptCoversEveryBehaviour() throws {
        let (steps, coverage) = try Self.record(count: 20_000)
        #expect(steps.count >= 20_000)
        #expect(coverage.uppercase > 0 && coverage.lowercase > 0)
        #expect(coverage.manualShift > 0 && coverage.automaticShift > 0 && coverage.capsLock > 0)
        #expect(coverage.doubleSpaceStops > 0 && coverage.plainSpaces > 0)
        #expect(coverage.returns > 0 && coverage.disabledReturns > 0)
        #expect(coverage.characterRepeats > 0 && coverage.wordRepeats > 0 && coverage.emptyTicks > 0)
        #expect(coverage.deletesAtStart > 0 && coverage.contextChanges > 0)
        #expect(coverage.autocapitalization.count == Autocapitalization.allCases.count)
        #expect(coverage.returnKinds.count == ReturnKeyType.allCases.count)
        #expect(coverage.settings.count == 8, "every combination of the three settings")
    }

    @Test(
        "Replaying a long, varied script makes zero heap allocations",
        .enabled(
            if: counterAvailable,
            """
            Skipped: no heap allocation counter on this platform. Tests/AllocationCounter works on Linux with \
            glibc only. macOS CI (T5) must provide a macOS counter before this test proves anything there.
            """))
    func handlingAllocatesNothing() throws {
        let (steps, _) = try Self.record(count: 20_000)
        var engine = try #require(TypingEngine(locale: KeyboardLocale(identifier: "en-US")))
        var mismatches = 0
        var deleted = 0
        var inserted = 0

        allocation_counter_start()
        var index = 0
        while index < steps.count {
            let step = steps[index]
            engine.settings = step.settings
            let output = engine.handle(step.event, at: step.time, in: step.context)
            if output != step.output || engine.shiftState != step.shiftAfter { mismatches += 1 }
            deleted &+= output.deleteCount
            inserted &+= output.insertion.utf8.count
            index += 1
        }
        let allocations = allocation_counter_stop()

        #expect(mismatches == 0, "the replay differs from the recording at \(mismatches) events")
        #expect(deleted > 0 && inserted > 0)
        #expect(allocations == 0, "\(steps.count) key events made \(allocations) heap allocations")
    }
}
