import SpeakboardCore
import Testing

/// The nearest-key hit-test (KEY-24): every point of the keyboard below the suggestion strip belongs to a key.
@Suite("Keyboard layout: hit targets (the nearest key)")
struct HitTargetTests {
    /// A grid of points over the whole view, including its edges, below and in the strip.
    static func grid(_ layout: KeyboardLayout, columns: Int = 120, rows: Int = 60) -> [LayoutPoint] {
        var points: [LayoutPoint] = []
        for column in 0..<columns {
            for row in 0..<rows {
                points.append(
                    LayoutPoint(
                        x: layout.size.width * Double(column) / Double(columns),
                        y: layout.size.height * Double(row) / Double(rows)))
            }
        }
        return points
    }

    @Test(
        "Every point below the strip resolves to a key; every point in the strip to none",
        arguments: DeviceClass.allCases)
    func everyPointResolves(_ deviceClass: DeviceClass) throws {
        for orientation in Orientation.allCases {
            let layout = try englishLayout(deviceClass, orientation)
            let context = "\(deviceClass) \(orientation)"
            var resolved = 0
            for point in Self.grid(layout) {
                let index = layout.keyIndex(nearest: point)
                if point.y < layout.suggestionStrip.maxY {
                    #expect(index == nil, "\(context): a point in the strip at \(point)")
                } else {
                    #expect(index != nil, "\(context): no key at \(point)")
                    resolved += 1
                }
            }
            #expect(resolved > 0)
            // The view's last row and column of points, and its bottom right corner, just inside.
            let corner = LayoutPoint(x: layout.size.width.nextDown, y: layout.size.height.nextDown)
            #expect(layout.keyIndex(nearest: corner) == layout.keys.count - 1, "\(context): the return key's corner")
            let topLeft = LayoutPoint(x: 0, y: layout.suggestionStrip.maxY)
            #expect(layout.key(nearest: topLeft)?.kind == .letter("q"), "\(context)")
        }
    }

    @Test("A point inside a key resolves to that key, as the exact hit-test does", arguments: DeviceClass.allCases)
    func insideAKey(_ deviceClass: DeviceClass) throws {
        let inside = 1e-6
        for orientation in Orientation.allCases {
            let layout = try englishLayout(deviceClass, orientation)
            for (index, key) in layout.keys.enumerated() {
                let frame = key.frame
                for point in [
                    frame.center, LayoutPoint(x: frame.minX, y: frame.minY),
                    LayoutPoint(x: frame.maxX - inside, y: frame.maxY - inside),
                    LayoutPoint(x: frame.minX, y: frame.maxY - inside),
                    LayoutPoint(x: frame.maxX - inside, y: frame.minY),
                ] {
                    #expect(layout.keyIndex(nearest: point) == index, "\(deviceClass) \(orientation) \(key.kind)")
                    #expect(layout.keyIndex(at: point) == index)
                    #expect(layout.key(nearest: point) == key)
                }
            }
        }
    }

    /// For each gap and margin: a point in it, the key it should resolve to, and what kind of gap it is. Every
    /// point is a quarter of the way across its gap from the expected key, or in a margin or inset beside it.
    static func gapCases(_ layout: KeyboardLayout) -> [(name: String, point: LayoutPoint, expected: Key)] {
        let rows = rows(layout)
        var cases: [(String, LayoutPoint, Key)] = []
        // Between two keys in a row: a quarter of the way from each side.
        for row in rows {
            for (left, right) in zip(row, row.dropFirst()) {
                let gap = right.frame.minX - left.frame.maxX
                let y = left.frame.center.y
                cases.append(("gap \(left.kind)|\(right.kind)", LayoutPoint(x: left.frame.maxX + gap / 4, y: y), left))
                cases.append(
                    ("gap \(left.kind)|\(right.kind)", LayoutPoint(x: right.frame.minX - gap / 4, y: y), right))
            }
        }
        // Between two rows: a quarter of the way down from the upper key, and up from the lower key.
        for (upper, lower) in zip(rows, rows.dropFirst()) {
            let gap = lower[0].frame.minY - upper[0].frame.maxY
            for key in upper {
                cases.append(
                    ("below \(key.kind)", LayoutPoint(x: key.frame.center.x, y: key.frame.maxY + gap / 4), key))
            }
            for key in lower {
                cases.append(
                    ("above \(key.kind)", LayoutPoint(x: key.frame.center.x, y: key.frame.minY - gap / 4), key))
            }
        }
        // The margins beside the row that starts with "a", which does not reach the key area's edges.
        let middle = rows[1]
        let a = middle[0]
        let l = middle[middle.count - 1]
        cases.append(("left of a, mid-height", LayoutPoint(x: a.frame.minX / 2, y: a.frame.center.y), a))
        cases.append(("left of a, at the key area's edge", LayoutPoint(x: layout.keyArea.minX, y: a.frame.minY), a))
        cases.append(("left of a, low", LayoutPoint(x: a.frame.minX - 1, y: a.frame.maxY - 1e-6), a))
        cases.append(
            ("right of l", LayoutPoint(x: (l.frame.maxX + layout.size.width) / 2, y: l.frame.center.y), l))
        // The insets: above the top row, below the bottom row, and beside each row's ends at the screen's edges.
        for key in rows[0] {
            cases.append(
                ("top inset over \(key.kind)", LayoutPoint(x: key.frame.center.x, y: layout.suggestionStrip.maxY), key))
        }
        for key in rows[3] {
            cases.append(
                (
                    "bottom inset under \(key.kind)",
                    LayoutPoint(x: key.frame.center.x, y: layout.size.height.nextDown), key
                ))
        }
        for row in rows {
            let first = row[0]
            let last = row[row.count - 1]
            cases.append(("screen's left edge by \(first.kind)", LayoutPoint(x: 0, y: first.frame.center.y), first))
            cases.append(
                (
                    "screen's right edge by \(last.kind)",
                    LayoutPoint(x: layout.size.width.nextDown, y: last.frame.center.y), last
                ))
        }
        return cases
    }

    @Test("Each kind of gap and margin resolves to the expected neighbour, where the exact hit-test finds none")
    func gapsAndMargins() throws {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            let cases = Self.gapCases(layout)
            #expect(cases.count > 60)
            for (name, point, expected) in cases {
                let context = "\(deviceClass) \(orientation) \(name) at \(point)"
                #expect(
                    layout.key(nearest: point) == expected,
                    "\(context): got \(String(describing: layout.key(nearest: point)?.kind))")
                // The old, exact hit-test types nothing here: this is what KEY-24 changes.
                #expect(layout.key(at: point) == nil, "\(context): the point is not in a gap")
                #expect(layout.keyIndex(at: point, by: .exact) == nil)
                #expect(layout.keyIndex(at: point, by: .nearest) == layout.keyIndex(nearest: point))
            }
        }
    }

    @Test("Ties go to the upper row and the left key, every time")
    func ties() throws {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            let rows = rows(layout)
            let context = "\(deviceClass) \(orientation)"
            // The middle of every gap, between keys and between rows, gets the same answer every time.
            for row in rows {
                for (left, right) in zip(row, row.dropFirst()) {
                    let point = LayoutPoint(x: (left.frame.maxX + right.frame.minX) / 2, y: left.frame.center.y)
                    let first = layout.keyIndex(nearest: point)
                    #expect(first != nil)
                    for _ in 0..<3 {
                        #expect(layout.keyIndex(nearest: point) == first, "\(context): the same answer every time")
                    }
                }
            }
            // The exact middle of each gap between two keys goes to the left key, whenever the two distances are
            // equal as doubles.
            for row in rows {
                for (left, right) in zip(row, row.dropFirst()) {
                    let x = (left.frame.maxX + right.frame.minX) / 2
                    guard x - left.frame.maxX == right.frame.minX - x else { continue }
                    #expect(layout.key(nearest: LayoutPoint(x: x, y: left.frame.center.y)) == left, "\(context)")
                }
            }
            // The exact middle of each gap between rows goes to the upper row.
            for (upper, lower) in zip(rows, rows.dropFirst()) {
                let y = (upper[0].frame.maxY + lower[0].frame.minY) / 2
                guard y - upper[0].frame.maxY == lower[0].frame.minY - y else { continue }
                for key in upper {
                    #expect(layout.key(nearest: LayoutPoint(x: key.frame.center.x, y: y)) == key, "\(context)")
                }
            }
        }
    }

    @Test("Exact middles of gaps exist on some layout, so the tie rule is exercised")
    func tiesAreReached() throws {
        var rowTies = 0
        var keyTies = 0
        for (deviceClass, orientation) in allClassesAndOrientations {
            let rows = rows(try englishLayout(deviceClass, orientation))
            for (upper, lower) in zip(rows, rows.dropFirst()) {
                let y = (upper[0].frame.maxY + lower[0].frame.minY) / 2
                if y - upper[0].frame.maxY == lower[0].frame.minY - y { rowTies += 1 }
            }
            for row in rows {
                for (left, right) in zip(row, row.dropFirst()) {
                    let x = (left.frame.maxX + right.frame.minX) / 2
                    if x - left.frame.maxX == right.frame.minX - x { keyTies += 1 }
                }
            }
        }
        #expect(rowTies > 0 && keyTies > 0, "row ties \(rowTies), key ties \(keyTies)")
    }

    @Test(
        "The rule, checked point by point on a grid: the nearest row by vertical distance, then the nearest key in it")
    func ruleOnAGrid() throws {
        func distance(_ value: Double, _ low: Double, _ high: Double) -> Double {
            max(low - value, value - high, 0)
        }
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            let rows = rows(layout)
            for point in Self.grid(layout, columns: 90, rows: 45) where point.y >= layout.suggestionStrip.maxY {
                let key = try #require(layout.key(nearest: point))
                if let exact = layout.key(at: point) {
                    #expect(key == exact)
                    continue
                }
                let rowIndex = try #require(rows.firstIndex { $0.contains(key) })
                let chosen = distance(point.y, key.frame.minY, key.frame.maxY)
                for (index, row) in rows.enumerated() {
                    let other = distance(point.y, row[0].frame.minY, row[0].frame.maxY)
                    #expect(index < rowIndex ? chosen < other : chosen <= other, "\(point): row \(index) is nearer")
                }
                let across = distance(point.x, key.frame.minX, key.frame.maxX)
                for other in rows[rowIndex] where other != key {
                    let otherAcross = distance(point.x, other.frame.minX, other.frame.maxX)
                    let earlier = other.frame.minX < key.frame.minX
                    #expect(earlier ? across < otherAcross : across <= otherAcross, "\(point): \(other.kind) is nearer")
                }
            }
        }
    }

    @Test("The strip, points off the view and points that are not numbers resolve to no key")
    func misses() throws {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            let q = layout.keys[0].frame.center
            let strip = layout.suggestionStrip
            for point in [
                LayoutPoint(x: q.x, y: 0), LayoutPoint(x: q.x, y: strip.maxY.nextDown), strip.center,
                LayoutPoint(x: -1e-9, y: q.y), LayoutPoint(x: layout.size.width, y: q.y),
                LayoutPoint(x: q.x, y: layout.size.height), LayoutPoint(x: q.x, y: -1),
                LayoutPoint(x: .nan, y: q.y), LayoutPoint(x: q.x, y: .nan), LayoutPoint(x: .infinity, y: q.y),
                LayoutPoint(x: q.x, y: -.infinity),
            ] {
                #expect(layout.keyIndex(nearest: point) == nil, "\(deviceClass) \(orientation) at \(point)")
                #expect(layout.key(nearest: point) == nil)
            }
        }
    }
}
