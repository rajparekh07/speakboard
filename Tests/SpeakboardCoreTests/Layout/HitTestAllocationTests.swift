import AllocationCounter
import SpeakboardCore
import Testing

/// The keystroke path allocates nothing (MANIFESTO.md, Budgets). Hit-testing is on it.
///
/// AllocationCounter counts every call to the C allocator on the calling thread, by defining malloc and its
/// relatives in the test executable (Tests/AllocationCounter/AllocationCounter.c). It works on Linux with glibc,
/// which is where `make check` runs (rung 1). Nothing here is awaited, so each test stays on one thread.
@Suite("Keyboard layout: hit-testing allocates nothing")
struct HitTestAllocationTests {
    /// Keeps a value alive so the compiler cannot drop the work that made it.
    @inline(never)
    static func keep<T>(_ value: T) -> T { value }

    @Test("The counter works: it is available on Linux, and it counts an allocation it is shown")
    func counterCounts() throws {
        #if os(Linux)
            #expect(allocation_counter_available())
        #endif
        try #require(allocation_counter_available(), "the allocation counter works on Linux with glibc only")

        allocation_counter_start()
        let array = Self.keep([Int](repeating: 7, count: 64))
        let object = Self.keep(Box(value: array.count))
        let count = allocation_counter_stop()
        #expect(object.value == 64)
        #expect(count >= 2, "an array and an object allocate, but the counter saw \(count)")

        allocation_counter_start()
        let none = allocation_counter_stop()
        #expect(none == 0, "nothing ran, but the counter saw \(none)")
    }

    @Test("Many hit-tests on every layout make zero heap allocations")
    func hitTestsAllocateNothing() throws {
        try #require(allocation_counter_available(), "the allocation counter works on Linux with glibc only")

        // Everything the loop reads is built before counting starts: the layouts, and a grid of touch points
        // across each keyboard, plus every key's centre, so the loop runs hits and misses alike.
        var layouts: [KeyboardLayout] = []
        var points: [[LayoutPoint]] = []
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            var grid: [LayoutPoint] = layout.keys.map(\.frame.center)
            for column in 0..<40 {
                for row in 0..<20 {
                    grid.append(
                        LayoutPoint(
                            x: layout.size.width * Double(column) / 39, y: layout.size.height * Double(row) / 19))
                }
            }
            layouts.append(layout)
            points.append(grid)
        }

        var hits = 0
        var misses = 0
        var checksum = 0.0
        let rounds = 10

        // The loop indexes with `while`, not `for`-`in`: in a debug build a `for`-`in` loop over an array or a
        // range allocates once per element (the unspecialised `IndexingIterator.next()`), and that is the test's
        // own cost, not the hit-test's.
        allocation_counter_start()
        var round = 0
        while round < rounds {
            var index = 0
            while index < layouts.count {
                let layout = layouts[index]
                let grid = points[index]
                var pointIndex = 0
                while pointIndex < grid.count {
                    if let key = layout.key(at: grid[pointIndex]) {
                        hits &+= 1
                        checksum += key.frame.minX
                    } else {
                        misses &+= 1
                    }
                    pointIndex += 1
                }
                index += 1
            }
            round += 1
        }
        let allocations = allocation_counter_stop()

        let total = hits + misses
        #expect(total == rounds * points.reduce(0) { $0 + $1.count }, "the loop did not run every hit-test")
        #expect(hits > 0 && misses > 0 && Self.keep(checksum) > 0)
        #expect(allocations == 0, "\(total) hit-tests made \(allocations) heap allocations")
    }
}

/// A class instance, which the Swift runtime allocates on the heap.
final class Box {
    let value: Int
    init(value: Int) { self.value = value }
}
