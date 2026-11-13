/// Who a keep-awake session belongs to, which decides what ends it.
public enum SessionOwner: Equatable, Sendable {
    /// Turned on from the panel, the menu, the shortcut, `macster on` or a URL. It lasts until the user turns it off,
    /// the timer ends, or a safety stops it.
    case user
    /// Turned on for running programs (`macster run`, `macster://on?pid=`). It also ends when the last one exits.
    case processes(Set<Int32>)

    /// The owner after a request to turn on. `current` is nil when nothing is keeping the Mac awake.
    ///
    /// A program joining a session the user started doesn't take it over: it ends when the user's session does. The
    /// user turning on during a session that programs started takes it over, so it no longer ends with them.
    public static func afterTurningOn(current: SessionOwner?, pid: Int32?) -> SessionOwner {
        switch (current, pid) {
        case (nil, let pid?):
            .processes([pid])
        case (.processes(let pids), let pid?):
            .processes(pids.union([pid]))
        case (.user, _), (_, nil):
            .user
        }
    }

    /// Whether this session waits for `pid`.
    public func isWaiting(for pid: Int32) -> Bool {
        if case .processes(let pids) = self { pids.contains(pid) } else { false }
    }

    /// Records that `pid` exited. Returns true when that was the last program the session was waiting for.
    public mutating func processExited(_ pid: Int32) -> Bool {
        guard case .processes(var pids) = self, pids.remove(pid) != nil else { return false }
        self = .processes(pids)
        return pids.isEmpty
    }
}
