import Foundation
import SwiftUI

@MainActor
final class PowerController: ObservableObject {
    @Published private(set) var status = PowerStatus.unknown
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    private let service = PowerService()

    var primaryActionTitle: String {
        if isBusy {
            return "Working..."
        }

        return status.isEnabled ? "Let Lid Close Sleep" : "Keep Awake on Lid Close"
    }

    func refresh() {
        guard !isBusy else { return }

        Task {
            await loadStatus(clearMessage: false)
        }
    }

    func toggle() {
        guard !isBusy else { return }

        let shouldEnable = !status.isEnabled
        isBusy = true
        message = shouldEnable ? "Waiting for macOS approval..." : "Restoring normal lid-close behavior..."
        messageIsError = false

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    if shouldEnable {
                        try self.service.enable()
                    } else {
                        try self.service.disable()
                    }
                }.value

                isBusy = false
                message = shouldEnable ? "Enabled." : "Disabled."
                messageIsError = false
                await loadStatus(clearMessage: false)
            } catch {
                isBusy = false
                message = PowerError.readableMessage(from: error)
                messageIsError = true
                await loadStatus(clearMessage: false)
            }
        }
    }

    private func loadStatus(clearMessage: Bool) async {
        do {
            let nextStatus = try await Task.detached(priority: .userInitiated) {
                try self.service.readStatus()
            }.value

            status = nextStatus
            if clearMessage {
                message = nil
                messageIsError = false
            }
        } catch {
            status = .unknown
            message = PowerError.readableMessage(from: error)
            messageIsError = true
        }
    }
}

