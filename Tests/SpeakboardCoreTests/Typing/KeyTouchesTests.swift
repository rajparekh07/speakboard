import SpeakboardCore
import Testing

/// The fingers on the keyboard (KEY-24): which key events each touch makes, and when.
@Suite("Typing: touches, hit targets and rollover")
struct KeyTouchesTests {
    /// The English layout of one class, and touches on it, with the events they make in order.
    struct Board {
        let layout: KeyboardLayout
        var touches: KeyTouches
        var events: [KeyEvent] = []

        init(_ deviceClass: DeviceClass = .iphone402x874, hitTesting: HitTesting = .nearest) throws {
            layout = try englishLayout(deviceClass, .portrait)
            touches = KeyTouches(hitTesting: hitTesting)
        }

        func key(_ kind: KeyKind) throws -> Key {
            try #require(layout.keys.first { $0.kind == kind })
        }

        func centre(_ kind: KeyKind) throws -> LayoutPoint {
            try key(kind).frame.center
        }

        mutating func record(_ new: KeyEvents) {
            if let first = new.first { events.append(first) }
            if let second = new.second { events.append(second) }
        }

        mutating func down(_ id: Int, _ point: LayoutPoint) {
            record(touches.began(id, at: point, in: layout))
        }

        mutating func move(_ id: Int, _ point: LayoutPoint) {
            _ = touches.moved(id, to: point, in: layout)
        }

        mutating func up(_ id: Int, _ point: LayoutPoint) {
            record(touches.ended(id, at: point, in: layout))
        }

        mutating func cancel(_ id: Int) {
            record(touches.cancelled(id))
        }

        /// The characters the events type, in order.
        var typed: String {
            var text = ""
            for event in events {
                switch event {
                case .character(let scalar): text.unicodeScalars.append(scalar)
                case .space: text += " "
                case .returnKey: text += "\n"
                default: break
                }
            }
            return text
        }
    }

    static func letter(_ character: Character) -> KeyKind {
        .letter(character.unicodeScalars.first ?? "a")
    }

    @Test("One tap: a letter types on lift; Shift acts on landing; Delete deletes on landing and stops on lift")
    func oneFinger() throws {
        var board = try Board()
        let g = try board.centre(Self.letter("g"))
        board.down(1, g)
        #expect(board.events.isEmpty, "a letter waits for the lift")
        #expect(board.touches.holds(try #require(board.layout.keys.firstIndex { $0.kind == Self.letter("g") })))
        board.up(1, g)
        #expect(board.events == [.character("g")])
        #expect(board.touches.touches.isEmpty)

        board.events = []
        board.down(2, try board.centre(.shift))
        #expect(board.events == [.shift])
        board.up(2, try board.centre(.shift))
        #expect(board.events == [.shift])

        board.events = []
        board.down(3, try board.centre(.delete))
        #expect(board.events == [.deleteDown])
        board.up(3, try board.centre(.delete))
        #expect(board.events == [.deleteDown, .deleteUp])

        board.events = []
        for kind in [KeyKind.space, .returnKey, .modeSwitch, .emoji] {
            board.down(4, try board.centre(kind))
            board.up(4, try board.centre(kind))
        }
        #expect(board.events == [.space, .returnKey], "123 and emoji type nothing")
    }

    @Test("A tap in a gap types the nearest key; with the exact hit-test it types nothing", arguments: [true, false])
    func gapTap(nearest: Bool) throws {
        var board = try Board(hitTesting: nearest ? .nearest : .exact)
        let layout = board.layout
        for (name, point, expected) in HitTargetTests.gapCases(layout) {
            board.events = []
            board.down(1, point)
            board.up(1, point)
            let want: [KeyEvent]
            switch expected.kind {
            case .letter(let scalar): want = [.character(scalar)]
            case .space: want = [.space]
            case .returnKey: want = [.returnKey]
            case .shift: want = [.shift]
            case .delete: want = [.deleteDown, .deleteUp]
            case .modeSwitch, .emoji, .globe, .dictation: want = []
            }
            #expect(board.events == (nearest ? want : []), "\(name) at \(point)")
        }
    }

    @Test("A finger that lands on a key and lifts in the gap types the key; with the exact hit-test it types nothing")
    func liftInAGap() throws {
        for nearest in [true, false] {
            var board = try Board(hitTesting: nearest ? .nearest : .exact)
            let g = try board.key(Self.letter("g")).frame
            let gap = LayoutPoint(x: g.center.x, y: g.maxY + 1)
            let a = try board.key(Self.letter("a")).frame
            let margin = LayoutPoint(x: a.minX - 1, y: a.center.y)
            board.down(1, g.center)
            board.move(1, gap)
            board.up(1, gap)
            board.down(2, a.center)
            board.up(2, margin)
            #expect(board.typed == (nearest ? "ga" : ""), "nearest: \(nearest)")
            #expect(board.layout.key(at: gap) == nil && board.layout.key(at: margin) == nil)
        }
    }

    @Test("A finger follows the key under it, and types the one it lifts on; a slide into the strip types nothing")
    func slide() throws {
        var board = try Board()
        board.down(1, try board.centre(Self.letter("q")))
        board.move(1, try board.centre(Self.letter("w")))
        board.up(1, try board.centre(Self.letter("w")))
        #expect(board.typed == "w")
        board.down(2, try board.centre(Self.letter("e")))
        board.up(2, board.layout.suggestionStrip.center)
        #expect(board.typed == "w")
    }

    @Test("Shift and Delete keep their key when the finger moves; a letter slid onto them types nothing")
    func shiftAndDeleteStay() throws {
        var board = try Board()
        board.down(1, try board.centre(.delete))
        board.move(1, try board.centre(Self.letter("m")))
        board.up(1, try board.centre(Self.letter("m")))
        #expect(board.events == [.deleteDown, .deleteUp])
        board.events = []
        board.down(2, try board.centre(Self.letter("m")))
        board.move(2, try board.centre(.delete))
        board.up(2, try board.centre(.delete))
        board.down(3, try board.centre(Self.letter("z")))
        board.move(3, try board.centre(.shift))
        board.up(3, try board.centre(.shift))
        #expect(board.events.isEmpty, "\(board.events)")
    }

    /// Every order of `count` items.
    static func permutations(_ count: Int) -> [[Int]] {
        guard count > 1 else { return [[0]] }
        var result: [[Int]] = []
        for rest in permutations(count - 1) {
            for position in 0...rest.count {
                var order = rest
                order.insert(count - 1, at: position)
                result.append(order)
            }
        }
        return result
    }

    @Test("Three overlapping fingers type in the order they landed, whatever order they lift in")
    func rollover() throws {
        let orders = Self.permutations(3)
        #expect(orders.count == 6)
        for order in orders {
            var board = try Board()
            let points = try "the".map { try board.centre(Self.letter($0)) }
            for (id, point) in points.enumerated() { board.down(id, point) }
            #expect(board.typed == "th", "each landing commits the finger before it")
            #expect(board.touches.touches.count == 3)
            for id in order { board.up(id, points[id]) }
            #expect(board.typed == "the", "lifts in the order \(order)")
            #expect(board.events.count == 3, "once each")
            #expect(board.touches.touches.isEmpty)
        }
    }

    @Test("Overlapping fingers that slide: an earlier finger's key is fixed when the next one lands")
    func rolloverWithSlides() throws {
        var board = try Board()
        board.down(1, try board.centre(Self.letter("a")))
        board.move(1, try board.centre(Self.letter("s")))
        board.down(2, try board.centre(Self.letter("o")))
        board.move(1, try board.centre(Self.letter("d")))
        board.up(1, try board.centre(Self.letter("d")))
        board.up(2, try board.centre(Self.letter("o")))
        #expect(board.typed == "so")
    }

    @Test("Every finger down holds its key for drawing, finished or not")
    func heldKeys() throws {
        var board = try Board()
        let layout = board.layout
        let t = try #require(layout.keys.firstIndex { $0.kind == Self.letter("t") })
        let h = try #require(layout.keys.firstIndex { $0.kind == Self.letter("h") })
        board.down(1, layout.keys[t].frame.center)
        board.down(2, layout.keys[h].frame.center)
        #expect(board.touches.holds(t) && board.touches.holds(h))
        #expect(board.touches.touches.map(\.isOpen) == [false, true])
        board.up(1, layout.keys[t].frame.center)
        #expect(!board.touches.holds(t) && board.touches.holds(h))
        board.up(2, layout.keys[h].frame.center)
        #expect(!board.touches.holds(h))
    }

    @Test("Shift held as a modifier is not modelled: the engine has only a Shift tap (the recorded gap)")
    func shiftHeld() throws {
        var board = try Board()
        board.down(1, try board.centre(.shift))
        board.down(2, try board.centre(Self.letter("a")))
        board.up(2, try board.centre(Self.letter("a")))
        board.down(3, try board.centre(Self.letter("b")))
        board.up(3, try board.centre(Self.letter("b")))
        board.up(1, try board.centre(.shift))
        #expect(board.events == [.shift, .character("a"), .character("b")], "Shift's lift sends nothing: no Shift up")
    }

    @Test("Delete held while another finger types: the hold ends when the finger lands, once, and the letter types")
    func deleteHeldWhileTyping() throws {
        for liftDeleteFirst in [true, false] {
            var board = try Board()
            board.down(1, try board.centre(.delete))
            board.down(2, try board.centre(Self.letter("x")))
            #expect(board.events == [.deleteDown, .deleteUp])
            if liftDeleteFirst {
                board.up(1, try board.centre(.delete))
                board.up(2, try board.centre(Self.letter("x")))
            } else {
                board.up(2, try board.centre(Self.letter("x")))
                board.up(1, try board.centre(.delete))
            }
            #expect(board.events == [.deleteDown, .deleteUp, .character("x")])
        }
    }

    @Test("A letter held while Delete lands: the letter types first, then Delete deletes and repeats until it lifts")
    func letterThenDelete() throws {
        var board = try Board()
        board.down(1, try board.centre(Self.letter("x")))
        board.down(2, try board.centre(.delete))
        board.up(1, try board.centre(Self.letter("x")))
        #expect(board.events == [.character("x"), .deleteDown])
        board.up(2, try board.centre(.delete))
        #expect(board.events == [.character("x"), .deleteDown, .deleteUp])
    }

    @Test("A cancelled finger among several: nothing lost, doubled or left repeating")
    func cancelAmongSeveral() throws {
        var board = try Board()
        let points = try "the".map { try board.centre(Self.letter($0)) }
        for (id, point) in points.enumerated() { board.down(id, point) }
        board.cancel(2)
        #expect(board.typed == "th", "the open finger types nothing; the finished ones are kept")
        board.up(0, points[0])
        board.up(1, points[1])
        #expect(board.typed == "th")
        #expect(board.touches.touches.isEmpty)

        // A finished finger cancelled: nothing changes.
        board.events = []
        board.down(5, points[0])
        board.down(6, points[1])
        board.cancel(5)
        board.up(6, points[1])
        #expect(board.typed == "th")

        // Delete open, cancelled while a finished letter is still down: the hold ends, once.
        board.events = []
        board.down(7, points[2])
        board.down(8, try board.centre(.delete))
        board.cancel(8)
        board.up(7, points[2])
        #expect(board.events == [.character("e"), .deleteDown, .deleteUp])
    }

    @Test("Everything ends at once: no letter types, a Delete hold ends; unknown fingers do nothing")
    func endAll() throws {
        var board = try Board()
        board.down(1, try board.centre(Self.letter("q")))
        board.down(2, try board.centre(.delete))
        board.record(board.touches.endAll())
        #expect(board.events == [.character("q"), .deleteDown, .deleteUp])
        #expect(board.touches.touches.isEmpty)
        board.up(1, try board.centre(Self.letter("q")))
        board.up(2, try board.centre(.delete))
        board.cancel(3)
        board.move(4, try board.centre(Self.letter("w")))
        #expect(board.events == [.character("q"), .deleteDown, .deleteUp])

        var quiet = try Board()
        quiet.down(1, try quiet.centre(Self.letter("q")))
        quiet.record(quiet.touches.endAll())
        #expect(quiet.events.isEmpty)
    }

    @Test("A finger that lands again with the same identity (its lift was lost) replaces the old one")
    func staleIdentity() throws {
        var board = try Board()
        board.down(1, try board.centre(Self.letter("q")))
        board.down(1, try board.centre(Self.letter("w")))
        #expect(board.touches.touches.count == 1)
        board.up(1, try board.centre(Self.letter("w")))
        #expect(board.typed == "qw")
    }

    @Test("Through the engine: overlapping fingers type into a field in landing order")
    func throughTheEngine() throws {
        for order in Self.permutations(3) {
            var board = try Board()
            var engine = try #require(TypingEngine(locale: .english))
            var text = ""
            var time = 10.0
            func apply(_ events: KeyEvents) {
                for event in [events.first, events.second].compactMap({ $0 }) {
                    let output = engine.handle(
                        event, at: time, in: TypingContext(textBeforeCursor: text, autocapitalization: .sentences))
                    text.removeLast(min(output.deleteCount, text.count))
                    text += output.insertion
                }
            }
            _ = engine.handle(.contextChanged, at: time, in: TypingContext(autocapitalization: .sentences))
            let points = try "the".map { try board.centre(Self.letter($0)) }
            for (id, point) in points.enumerated() {
                apply(board.touches.began(id, at: point, in: board.layout))
                time += 0.03
            }
            for id in order {
                apply(board.touches.ended(id, at: points[id], in: board.layout))
                time += 0.03
            }
            #expect(text == "The", "lifts in the order \(order)")
        }
    }
}
