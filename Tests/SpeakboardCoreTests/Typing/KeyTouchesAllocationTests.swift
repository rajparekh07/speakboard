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
        let (operations, reachedCapacity, reuses) = Self.script(for: layout, seed: 24)
        #expect(reachedCapacity, "the script never had 16 fingers down")
        #expect(reuses > 50, "the script reused an identity still down \(reuses) times")

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
        let stale = Self.staleLandings(operations, in: layout, showsInputModeSwitchKey: true)
        #expect(stale == reuses, "\(stale) landings found their identity still down, of \(reuses) reuses")
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
        let (operations, reachedCapacity, reuses) = Self.script(for: layout, seed: 66, around: globe.frame)
        #expect(reachedCapacity, "the script never had 16 fingers down")
        #expect(reuses > 50, "the script reused an identity still down \(reuses) times")
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
        let stale = Self.staleLandings(operations, in: layout, showsInputModeSwitchKey: false)
        #expect(stale == reuses, "\(stale) landings found their identity still down, of \(reuses) reuses")
    }

    /// A script of 5,000 random touch changes over `layout`, reaching 16 fingers down, whether it did, and how many
    /// landings reuse an identity that is still down. With `around`, a quarter of the points fall in that rectangle
    /// grown by its own size on each side.
    ///
    /// A reused identity is a lift UIKit never delivered, then the `UITouch` object's address reused for a new finger
    /// (KEY-67): `KeyTouches.began` drops the stale finger first. About one landing in eight with a finger down is one.
    static func script(for layout: KeyboardLayout, seed: UInt64, around focus: LayoutRect? = nil) -> (
        [Operation], Bool, Int
    ) {
        var random = TypingAllocationTests.Random(state: seed)
        var operations: [Operation] = []
        var down: [Int] = []
        var nextID = 1
        var reachedCapacity = false
        var reuses = 0
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
            if roll < 4 && !down.isEmpty && random.below(8) == 0 {
                // The identity stays down: the stale finger is replaced by this one.
                operations.append(.down(down[random.below(down.count)], point()))
                reuses += 1
            } else if roll < 4 && down.count < KeyTouches.capacity {
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
        return (operations, reachedCapacity, reuses)
    }

    /// Replays `operations` on a fresh value, not counted, and returns how many landings found a finger with the
    /// same identity still down: the branch of `KeyTouches.began` that drops a stale finger.
    static func staleLandings(
        _ operations: [Operation], in layout: KeyboardLayout, showsInputModeSwitchKey: Bool
    ) -> Int {
        var touches = KeyTouches()
        touches.showsInputModeSwitchKey = showsInputModeSwitchKey
        var stale = 0
        for operation in operations {
            switch operation {
            case .down(let id, let point):
                if touches.touches.contains(where: { $0.id == id }) { stale += 1 }
                _ = touches.began(id, at: point, in: layout)
            case .move(let id, let point): _ = touches.moved(id, to: point, in: layout)
            case .up(let id, let point): _ = touches.ended(id, at: point, in: layout)
            case .cancel(let id): _ = touches.cancelled(id)
            case .endAll: _ = touches.endAll()
            }
        }
        return stale
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
