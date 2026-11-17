import AllocationCounter
import SpeakboardCore
import Testing

/// The touch bookkeeping (KEY-24) is on the keystroke path, so it allocates nothing while at most
/// `KeyTouches.capacity` fingers are down. Counted as the hit-test and the engine are (HitTestAllocationTests,
/// TypingAllocationTests): on Linux, in a debug build, with everything the replay reads built before counting.
@Suite("Typing: touch bookkeeping allocates nothing")
struct KeyTouchesAllocationTests {
    static let counterAvailable = allocation_counter_available()

    enum Operation {
        case down(Int, LayoutPoint)
        case move(Int, LayoutPoint)
        case up(Int, LayoutPoint)
        case cancel(Int)
        case endAll
    }

    @Test(
        "Many landings, moves, lifts and cancels, with up to 16 fingers down, make zero heap allocations",
        .enabled(
            if: counterAvailable,
            """
            Skipped: no heap allocation counter on this platform. Tests/AllocationCounter works on Linux with \
            glibc only.
            """))
    func touchesAllocateNothing() throws {
        let layout = try englishLayout(.iphone402x874, .portrait)
        var random = TypingAllocationTests.Random(state: 24)
        var operations: [Operation] = []
        var down: [Int] = []
        var nextID = 1
        var reachedCapacity = false
        func point() -> LayoutPoint {
            LayoutPoint(
                x: layout.size.width * Double(random.below(1000)) / 1000,
                y: layout.size.height * Double(random.below(1000)) / 1000)
        }
        for _ in 0..<5000 {
            let roll = random.below(10)
            if roll < 4 && down.count < KeyTouches.capacity {
                operations.append(.down(nextID, point()))
                down.append(nextID)
                nextID += 1
                if down.count == KeyTouches.capacity { reachedCapacity = true }
            } else if roll < 6 && !down.isEmpty {
                operations.append(.move(down[random.below(down.count)], point()))
            } else if roll < 9 && !down.isEmpty {
                let id = down.remove(at: random.below(down.count))
                operations.append(.up(id, point()))
            } else if !down.isEmpty {
                if random.below(10) == 0 {
                    operations.append(.endAll)
                    down = []
                } else {
                    operations.append(.cancel(down.remove(at: random.below(down.count))))
                }
            } else {
                operations.append(.move(nextID + 1000, point()))
            }
        }
        #expect(reachedCapacity, "the script never had 16 fingers down")

        // The replay runs twice, on a fresh value each time, and only the second run is counted. The first run makes
        // the Swift runtime build the type metadata the code uses (for `Optional<KeyEvent>` and the rest), which it
        // does once per process, on first use: a first, uncounted run allocated 15 times here, and the same run again
        // allocated nothing. That is a one-time cost, not a keystroke's.
        var warmUp = KeyTouches()
        _ = Self.replay(operations, on: &warmUp, in: layout)
        var touches = KeyTouches()
        allocation_counter_start()
        let (events, changes, held) = Self.replay(operations, on: &touches, in: layout)
        let allocations = allocation_counter_stop()

        #expect(events > 1000 && changes > 100 && held > 0, "events \(events), changes \(changes), held \(held)")
        #expect(allocations == 0, "\(operations.count) touch changes made \(allocations) heap allocations")
    }

    /// Sends every operation to `touches`, indexing with `while` (a `for`-`in` loop allocates in a debug build), and
    /// returns how many events, key changes and held keys it saw.
    static func replay(
        _ operations: [Operation], on touches: inout KeyTouches, in layout: KeyboardLayout
    ) -> (events: Int, changes: Int, held: Int) {
        var events = 0
        var changes = 0
        var held = 0
        var index = 0
        while index < operations.count {
            switch operations[index] {
            case .down(let id, let point): events &+= touches.began(id, at: point, in: layout).count
            case .move(let id, let point): if touches.moved(id, to: point, in: layout) { changes &+= 1 }
            case .up(let id, let point): events &+= touches.ended(id, at: point, in: layout).count
            case .cancel(let id): events &+= touches.cancelled(id).count
            case .endAll: events &+= touches.endAll().count
            }
            if touches.holds(index % layout.keys.count) { held &+= 1 }
            index += 1
        }
        return (events, changes, held)
    }
}
