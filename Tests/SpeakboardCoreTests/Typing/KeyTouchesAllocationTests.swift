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
        let (operations, reachedCapacity) = Self.script(for: layout, seed: 24)
        #expect(reachedCapacity, "the script never had 16 fingers down")

        // One uncounted `endAll()` on a scratch value first. The first `endAll()` in a process allocates (17 to 23
        // times, measured in a fresh process, debug build, Linux: in `removeAll(keepingCapacity:)`), and a second one
        // allocates nothing. Nothing else allocates on first use: in a fresh process the first landing, move, lift,
        // commit by a landing, Delete landing and cancel each counted 0 (KEY-24 review round 1, reproduced by the
        // builder). `endAll()` is not on the keystroke path: the adapter calls it when the keyboard appears or goes
        // away and when the layout changes. So the counted replay below is the process's first use of everything else.
        var warmUp = KeyTouches()
        _ = warmUp.endAll()
        var touches = KeyTouches()
        allocation_counter_start()
        let (events, changes, held) = Self.replay(operations, on: &touches, in: layout)
        let allocations = allocation_counter_stop()

        #expect(events > 1000 && changes > 100 && held > 0, "events \(events), changes \(changes), held \(held)")
        #expect(allocations == 0, "\(operations.count) touch changes made \(allocations) heap allocations")
    }

    @Test(
        "With the next-keyboard key hidden, as the extension runs, on a home-button layout: zero heap allocations",
        .enabled(
            if: counterAvailable,
            """
            Skipped: no heap allocation counter on this platform. Tests/AllocationCounter works on Linux with \
            glibc only.
            """))
    func hiddenKeyTouchesAllocateNothing() throws {
        // The extension runs with `showsInputModeSwitchKey` false (macOS CI logs `switchKey=false`), so this is the
        // path real keystrokes take. On the home-button class the globe key exists, so hiding it does real work: a
        // quarter of the script's points are on or around it.
        let layout = try englishLayout(.iphone375x667, .portrait)
        let globe = try #require(layout.keys.first { $0.kind == .globe })
        let (operations, reachedCapacity) = Self.script(for: layout, seed: 66, around: globe.frame)
        #expect(reachedCapacity, "the script never had 16 fingers down")
        let onGlobe = operations.filter {
            switch $0 {
            case .down(_, let point), .move(_, let point), .up(_, let point): return globe.frame.contains(point)
            case .cancel, .endAll: return false
            }
        }.count
        #expect(onGlobe > 100, "\(onGlobe) touch changes on the globe key")

        var warmUp = KeyTouches()
        _ = warmUp.endAll()
        var touches = KeyTouches()
        touches.showsInputModeSwitchKey = false
        allocation_counter_start()
        let (events, changes, held) = Self.replay(operations, on: &touches, in: layout)
        let allocations = allocation_counter_stop()

        #expect(events > 1000 && changes > 100 && held > 0, "events \(events), changes \(changes), held \(held)")
        #expect(allocations == 0, "\(operations.count) touch changes made \(allocations) heap allocations")
        let globeIndex = try #require(layout.keys.firstIndex(of: globe))
        #expect(!touches.holds(globeIndex))
    }

    /// A script of 5,000 random touch changes over `layout`, reaching 16 fingers down, and whether it did. With
    /// `around`, a quarter of the points fall in that rectangle grown by its own size on each side.
    static func script(for layout: KeyboardLayout, seed: UInt64, around focus: LayoutRect? = nil) -> (
        [Operation], Bool
    ) {
        var random = TypingAllocationTests.Random(state: seed)
        var operations: [Operation] = []
        var down: [Int] = []
        var nextID = 1
        var reachedCapacity = false
        func point() -> LayoutPoint {
            if let focus, random.below(4) == 0 {
                return LayoutPoint(
                    x: focus.minX - focus.width + 3 * focus.width * Double(random.below(1000)) / 1000,
                    y: focus.minY - focus.height + 3 * focus.height * Double(random.below(1000)) / 1000)
            }
            return LayoutPoint(
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
        return (operations, reachedCapacity)
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
