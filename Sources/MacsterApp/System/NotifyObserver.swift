import Dispatch
import notify

/// Calls a handler on the main actor whenever a Darwin notification (`notify(3)`) is posted.
final class NotifyObserver {
    private let token: Int32

    init?(_ name: String, handler: @escaping @MainActor () -> Void) {
        var token: Int32 = 0
        let status = notify_register_dispatch(name, &token, .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        guard status == NOTIFY_STATUS_OK else { return nil }
        self.token = token
    }

    deinit {
        notify_cancel(token)
    }
}
