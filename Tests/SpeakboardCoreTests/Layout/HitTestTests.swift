import SpeakboardCore
import Testing

@Suite("Keyboard layout: hit-testing")
struct HitTestTests {
    @Test("A touch at a key's centre returns that key", arguments: DeviceClass.allCases)
    func centres(_ deviceClass: DeviceClass) throws {
        for orientation in Orientation.allCases {
            let layout = try englishLayout(deviceClass, orientation)
            for key in layout.keys {
                #expect(layout.key(at: key.frame.center) == key, "\(deviceClass) \(orientation) \(key.kind)")
            }
        }
    }

    @Test(
        "A key's left and top edges are inside it, its right and bottom edges outside", arguments: DeviceClass.allCases)
    func edges(_ deviceClass: DeviceClass) throws {
        let inside = 1e-6
        for orientation in Orientation.allCases {
            let layout = try englishLayout(deviceClass, orientation)
            for key in layout.keys {
                let frame = key.frame
                let context = "\(deviceClass) \(orientation) \(key.kind)"
                let corners = [
                    LayoutPoint(x: frame.minX, y: frame.minY),
                    LayoutPoint(x: frame.maxX - inside, y: frame.minY),
                    LayoutPoint(x: frame.minX, y: frame.maxY - inside),
                    LayoutPoint(x: frame.maxX - inside, y: frame.maxY - inside),
                ]
                for corner in corners {
                    #expect(layout.key(at: corner) == key, "\(context) at \(corner)")
                }
                let middle = frame.center
                for outside in [
                    LayoutPoint(x: frame.minX - inside, y: middle.y), LayoutPoint(x: frame.maxX, y: middle.y),
                    LayoutPoint(x: middle.x, y: frame.minY - inside), LayoutPoint(x: middle.x, y: frame.maxY),
                ] {
                    #expect(layout.key(at: outside) != key, "\(context) at \(outside)")
                }
            }
        }
    }

    @Test("Gaps, insets, the strip and points off the keyboard hit no key")
    func misses() throws {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            let context = "\(deviceClass) \(orientation)"
            let rows = rows(layout)
            // The middle of each horizontal gap between two keys in a row.
            for row in rows {
                for (left, right) in zip(row, row.dropFirst()) {
                    let point = LayoutPoint(x: (left.frame.maxX + right.frame.minX) / 2, y: left.frame.center.y)
                    #expect(layout.key(at: point) == nil, "\(context) between \(left.kind) and \(right.kind)")
                }
            }
            // The middle of each vertical gap between rows, and the top and bottom insets.
            let q = rows[0][0].frame
            for (upper, lower) in zip(rows, rows.dropFirst()) {
                let y = (upper[0].frame.maxY + lower[0].frame.minY) / 2
                #expect(layout.key(at: LayoutPoint(x: q.center.x, y: y)) == nil, "\(context) between rows")
            }
            let insetTop = LayoutPoint(x: q.center.x, y: (layout.keyArea.minY + q.minY) / 2)
            let insetBottom = LayoutPoint(x: q.center.x, y: (rows[3][0].frame.maxY + layout.keyArea.maxY) / 2)
            let insetLeft = LayoutPoint(x: layout.keyArea.minX / 2, y: q.center.y)
            for point in [insetTop, insetBottom, insetLeft] {
                #expect(layout.key(at: point) == nil, "\(context) in an inset at \(point)")
            }
            for point in [
                LayoutPoint(x: q.center.x, y: 1), LayoutPoint(x: -1, y: q.center.y),
                LayoutPoint(x: layout.size.width + 1, y: q.center.y), LayoutPoint(x: q.center.x, y: layout.size.height),
                LayoutPoint(x: .nan, y: q.center.y), LayoutPoint(x: q.center.x, y: .infinity),
            ] {
                #expect(layout.key(at: point) == nil, "\(context) at \(point)")
            }
        }
    }

    @Test("No two keys overlap, so a touch is never inside two keys")
    func noOverlaps() throws {
        for (deviceClass, orientation) in allClassesAndOrientations {
            let layout = try englishLayout(deviceClass, orientation)
            for (index, key) in layout.keys.enumerated() {
                for other in layout.keys[(index + 1)...] {
                    let apart =
                        key.frame.maxX <= other.frame.minX || other.frame.maxX <= key.frame.minX
                        || key.frame.maxY <= other.frame.minY || other.frame.maxY <= key.frame.minY
                    #expect(apart, "\(deviceClass) \(orientation): \(key.kind) overlaps \(other.kind)")
                }
            }
        }
    }
}
