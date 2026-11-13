import Foundation
import MacsterCore

/// Everything the panel shows. Built from `AppModel`, or by hand for previews and snapshots.
struct PanelState: Equatable {
    enum Power: Equatable {
        case off
        case turningOn
        case on(until: Date?)
        case turningOff

        /// The position the switch shows: where things are, or where they're headed.
        var isOnOrTurningOn: Bool {
            switch self {
            case .on, .turningOn: true
            case .off, .turningOff: false
            }
        }

        var isChanging: Bool {
            self == .turningOn || self == .turningOff
        }

        var keepsMacAwake: Bool {
            switch self {
            case .on, .turningOff: true
            case .off, .turningOn: false
            }
        }
    }

    enum Setup: Equatable {
        case checking
        case ready
        case needed(updatingOldVersion: Bool)
        case inProgress(updatingOldVersion: Bool)
    }

    var power: Power
    var setup: Setup
    var notice: Notice?
    /// The timer the switch uses, or the running session's own timer.
    var autoOff: AutoOff
    var batteryCutoff: BatteryCutoff
    var heatGuard: Bool
    var showsBatteryCutoff: Bool
    var screenOffWhenClosed: Bool
    var showsLidOptions: Bool
    var launchAtLogin: Bool
    var loginItemNeedsApproval: Bool
    /// "⌃⌥⌘L", or nil when there's no shortcut.
    var shortcut: String?
    var isRecordingShortcut: Bool
    var version: String
}

/// What the panel's controls do.
struct PanelActions {
    var setOn: @MainActor (Bool) -> Void = { _ in }
    var setUp: @MainActor () -> Void = {}
    var setAutoOff: @MainActor (AutoOff) -> Void = { _ in }
    var setBatteryCutoff: @MainActor (BatteryCutoff) -> Void = { _ in }
    var setHeatGuard: @MainActor (Bool) -> Void = { _ in }
    var setScreenOffWhenClosed: @MainActor (Bool) -> Void = { _ in }
    var setLaunchAtLogin: @MainActor (Bool) -> Void = { _ in }
    var openLoginItemSettings: @MainActor () -> Void = {}
    /// Starts recording a shortcut, or stops if already recording.
    var recordShortcut: @MainActor () -> Void = {}
    var clearShortcut: @MainActor () -> Void = {}
    var showAbout: @MainActor () -> Void = {}
    var removeAccess: @MainActor () -> Void = {}
    var quit: @MainActor () -> Void = {}
}

extension AppModel {
    var panelState: PanelState {
        let power: PanelState.Power = switch phase {
        case .off: .off
        case .turningOn: .turningOn
        case .on: .on(until: autoOffDeadline)
        case .turningOff: .turningOff
        }
        let setup: PanelState.Setup = switch access {
        case .checking: .checking
        case .ready: .ready
        case .needsSetup: .needed(updatingOldVersion: legacy.isPresent)
        case .settingUp: .inProgress(updatingOldVersion: legacy.isPresent)
        }
        return PanelState(
            power: power,
            setup: setup,
            notice: notice,
            autoOff: effectiveAutoOff,
            batteryCutoff: batteryCutoff,
            heatGuard: heatGuard,
            showsBatteryCutoff: hasBattery,
            screenOffWhenClosed: screenOffWhenClosed,
            showsLidOptions: hasLid,
            launchAtLogin: launchAtLogin,
            loginItemNeedsApproval: loginItemNeedsApproval,
            shortcut: toggleShortcut?.title,
            isRecordingShortcut: isRecordingShortcut,
            version: AppInfo.version
        )
    }
}
