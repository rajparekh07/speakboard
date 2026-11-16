// The typing engine's timings, in one value, so a device ticket can replace
// them in one place once they are measured.
//
// Apple documents none of them, and nobody on this project has measured them
// on an iPhone yet (rung 4). Every value is an estimate, marked with where it
// comes from. Tests read them from here and do not depend on the numbers.

/// The time windows and the delete-repeat schedule of the typing engine, in seconds.
public struct TypingTimings: Equatable, Sendable {
    /// The longest time from one tap on Shift to the next for the second to turn on caps lock.
    public var shiftDoubleTapWindow: Double
    /// The longest time from one tap on the space bar to the next for the second to type a full stop.
    public var doubleSpaceWindow: Double
    /// The time from Delete's touch-down, which deletes one character at once, to its first repeat.
    public var deleteInitialDelay: Double
    /// The time between repeats while each repeat deletes one character.
    public var deleteRepeatInterval: Double
    /// How many repeats delete one character each. Every later repeat deletes a word. At least 1.
    public var deleteCharacterRepeats: Int
    /// The time between repeats once each repeat deletes a word.
    public var deleteWordRepeatInterval: Double

    /// Timings. `deleteCharacterRepeats` below 1 is read as 1.
    public init(
        shiftDoubleTapWindow: Double, doubleSpaceWindow: Double, deleteInitialDelay: Double,
        deleteRepeatInterval: Double, deleteCharacterRepeats: Int, deleteWordRepeatInterval: Double
    ) {
        self.shiftDoubleTapWindow = shiftDoubleTapWindow
        self.doubleSpaceWindow = doubleSpaceWindow
        self.deleteInitialDelay = deleteInitialDelay
        self.deleteRepeatInterval = deleteRepeatInterval
        self.deleteCharacterRepeats = max(1, deleteCharacterRepeats)
        self.deleteWordRepeatInterval = deleteWordRepeatInterval
    }

    /// Estimates. Each value is a guess from memory of Apple's keyboard: not measured, and not from any
    /// documentation. A device ticket (rung 4) replaces them.
    public static let estimated = TypingTimings(
        // Estimate, not measured: about the speed of a double tap elsewhere in iOS.
        shiftDoubleTapWindow: 0.35,
        // Estimate, not measured. It is not known whether Apple's keyboard has a time window for the double-space
        // full stop at all: this assumes it has one.
        doubleSpaceWindow: 0.6,
        // Estimate, not measured: the repeat starts about half a second into the hold.
        deleteInitialDelay: 0.5,
        // Estimate, not measured: about ten characters a second.
        deleteRepeatInterval: 0.1,
        // Estimate, not measured: words start about two seconds into the hold. The 16 character repeats are at
        // 0.5 s to 0.5 + 15 × 0.1 = 2.0 s after touch-down, and the first word repeat 0.25 s later, at 2.25 s.
        deleteCharacterRepeats: 16,
        // Estimate, not measured: words go slower than characters.
        deleteWordRepeatInterval: 0.25)
}
