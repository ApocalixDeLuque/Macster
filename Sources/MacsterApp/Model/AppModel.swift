import AppKit
import MacsterCore
import Observation
import os

/// A message shown under the main switch until the panel closes.
struct Notice: Equatable {
    enum Kind: Equatable { case info, error }

    var kind: Kind
    var message: String

    static func info(_ message: String) -> Notice { Notice(kind: .info, message: message) }
    static func error(_ message: String) -> Notice { Notice(kind: .error, message: message) }
}

/// Macster's state and everything that changes it.
///
/// The system is the source of truth. `phase` mirrors the kernel's `SleepDisabled` flag: it's re-read after every
/// change Macster makes (a change only counts once the kernel reports it) and whenever power settings change
/// elsewhere. While sleep is disabled and Macster has permission, Macster owns that state — `reconcile()` keeps a
/// watchdog armed so sleep comes back if Macster dies, runs the auto-off timer and safety checks, and quitting turns
/// it off.
///
/// Everything that turns Macster on or off goes through `requestOn` and `requestOff`: the panel, the menu, the
/// keyboard shortcut, `macster://` URLs and the `macster` command.
@Observable
final class AppModel {
    enum Phase: Equatable {
        case off, turningOn, on, turningOff

        var isChanging: Bool { self == .turningOn || self == .turningOff }
    }

    enum Access: Equatable { case checking, ready, needsSetup, settingUp }

    private(set) var phase = Phase.off
    private(set) var access = Access.checking
    private(set) var legacy = LegacyInstall.none
    private(set) var notice: Notice?
    private(set) var autoOffDeadline: Date?
    private(set) var hasBattery = false
    /// False on desktop Macs: no lid, so no lid options.
    private(set) var hasLid = false
    private(set) var launchAtLogin = false
    private(set) var loginItemNeedsApproval = false
    private(set) var toggleShortcut: KeyboardShortcut?
    private(set) var isRecordingShortcut = false

    /// The saved "Turn off after" setting. Change it with `chooseAutoOff(_:)`.
    private(set) var autoOff: AutoOff {
        didSet { defaults.set(autoOff.minutes, forKey: Keys.autoOffMinutes) }
    }

    /// This session's timer when it differs from the saved setting: `macster on 2h`, the menu's durations, a URL, or
    /// a program's session, which has no timer.
    private(set) var sessionAutoOff: AutoOff?

    /// The timer the current session runs on.
    var effectiveAutoOff: AutoOff { sessionAutoOff ?? autoOff }

    var batteryCutoff: BatteryCutoff {
        didSet {
            defaults.set(batteryCutoff.percent, forKey: Keys.lowBatteryPercent)
            evaluateSafety()
        }
    }

    var heatGuard: Bool {
        didSet {
            defaults.set(heatGuard, forKey: Keys.heatGuard)
            evaluateSafety()
        }
    }

    /// Turn the screens off when the lid closes while Macster keeps the Mac awake.
    var screenOffWhenClosed: Bool {
        didSet { defaults.set(screenOffWhenClosed, forKey: Keys.screenOffWhenClosed) }
    }

    /// Set by the status item so the model can bring the panel back, for example after the password prompt.
    @ObservationIgnored var showPanel: (() -> Void)?
    /// True when a command arrived before Macster finished starting: it was launched to run it, not to show itself.
    @ObservationIgnored private(set) var launchedForCommand = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let rootDomain = RootDomain()
    @ObservationIgnored private let powerSources = PowerSourceMonitor()
    @ObservationIgnored private let notifier = Notifier()
    @ObservationIgnored private let hotKey = GlobalHotKey()
    @ObservationIgnored private let lidMonitor = LidMonitor()
    /// Set when Macster turned the screens off for a closed lid, so opening it turns them back on.
    @ObservationIgnored private var turnedScreensOff = false
    @ObservationIgnored private var watchdog: Watchdog?
    @ObservationIgnored private var owner: SessionOwner?
    @ObservationIgnored private var processWatchers: [Int32: any DispatchSourceProcess] = [:]
    @ObservationIgnored private var autoOffTask: Task<Void, Never>?
    @ObservationIgnored private var safetyPoll: Task<Void, Never>?
    @ObservationIgnored private var pendingSync: Task<Void, Never>?
    @ObservationIgnored private var pendingCommands: [MacsterCommand] = []
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isPanelVisible = false
    @ObservationIgnored private var lastWatchdogFailure: ContinuousClock.Instant?
    @ObservationIgnored private var systemObservers: [Any] = []
    @ObservationIgnored private var isFirstLaunch = false
    @ObservationIgnored private let log = Logger(subsystem: "io.github.macster", category: "power")

    /// Also read by the `macster` command (see `CommandLineTool.safetyStopReason`).
    enum Keys {
        static let autoOffMinutes = "autoOffMinutes"
        static let lowBatteryPercent = "lowBatteryPercent"
        static let heatGuard = "heatGuard"
        static let screenOffWhenClosed = "screenOffWhenClosed"
        static let toggleShortcut = "toggleShortcut"
        static let sessionActive = "sessionActive"
        static let hasLaunched = "hasLaunched"
        /// Before the battery level became a choice, the safety was a switch at 10%.
        static let legacyLowBatteryGuard = "lowBatteryGuard"
    }

    init(defaults: UserDefaults = .standard) {
        Self.migrate(defaults)
        defaults.register(defaults: [
            Keys.lowBatteryPercent: BatteryCutoff.standard.percent,
            Keys.heatGuard: true,
            Keys.screenOffWhenClosed: true,
        ])
        self.defaults = defaults
        autoOff = AutoOff(minutes: defaults.integer(forKey: Keys.autoOffMinutes))
        batteryCutoff = BatteryCutoff(percent: defaults.integer(forKey: Keys.lowBatteryPercent))
        heatGuard = defaults.bool(forKey: Keys.heatGuard)
        screenOffWhenClosed = defaults.bool(forKey: Keys.screenOffWhenClosed)
        toggleShortcut = defaults.data(forKey: Keys.toggleShortcut)
            .flatMap { try? JSONDecoder().decode(KeyboardShortcut.self, from: $0) }
    }

    private static func migrate(_ defaults: UserDefaults) {
        guard let enabled = defaults.object(forKey: Keys.legacyLowBatteryGuard) as? Bool else { return }
        if defaults.object(forKey: Keys.lowBatteryPercent) == nil {
            defaults.set(enabled ? BatteryCutoff.standard.percent : 0, forKey: Keys.lowBatteryPercent)
        }
        defaults.removeObject(forKey: Keys.legacyLowBatteryGuard)
    }

    // MARK: - Lifecycle

    func start() async {
        isFirstLaunch = !defaults.bool(forKey: Keys.hasLaunched)
        defaults.set(true, forKey: Keys.hasLaunched)
        hasBattery = PowerSourceMonitor.currentReading() != nil
        hasLid = rootDomain.isLidClosed != nil
        refreshLoginItem()
        observeSystem()
        notifier.onOpen = { [weak self] in self?.showPanel?() }
        notifier.prepare()
        registerShortcut()

        phase = rootDomain.isSleepDisabled ? .on : .off
        log.notice("Started; sleep is \(self.phase == .on ? "disabled" : "enabled", privacy: .public)")
        await refreshAccess()

        let hadSession = defaults.bool(forKey: Keys.sessionActive)
        if phase == .on, access == .ready, hadSession {
            // Macster was keeping the Mac awake and never got to turn it off: power loss, a kernel panic, or a
            // watchdog that couldn't run. That session is over.
            log.notice("Sleep is still disabled from a session that didn't end normally")
            await turnOff(reason: .leftOverSession)
        } else {
            if phase == .off, hadSession {
                // The watchdog did its job after a crash or a force quit.
                notice = .info("Macster quit unexpectedly last time. Its safety helper turned normal sleep back on.")
            }
            reconcile()
        }

        hasStarted = true
        let commands = pendingCommands
        pendingCommands = []
        commands.forEach(perform)
    }

    /// Show the panel at launch unless Macster probably started at login, or to run a command, and has nothing to say.
    var shouldShowPanelAtLaunch: Bool {
        !launchedForCommand && (isFirstLaunch || access == .needsSetup || !launchAtLogin)
    }

    var needsCleanupBeforeQuit: Bool {
        access == .ready && phase != .off
    }

    /// Turns sleep back on before Macster quits. If that fails, the watchdog stays armed and retries once Macster exits.
    func prepareToQuit() async {
        _ = await settled()
        await turnOff(reason: nil, timeout: .seconds(5))
    }

    func panelWillAppear() {
        isPanelVisible = true
        syncWithSystem()
        refreshLoginItem()
        hasBattery = PowerSourceMonitor.currentReading() != nil
    }

    func panelDidDisappear() {
        isPanelVisible = false
        notice = nil
        cancelRecordingShortcut()
    }

    // MARK: - Actions

    /// The panel's switch and the menu's toggle.
    func setOn(_ on: Bool) {
        guard access == .ready else {
            if on { setUp() }
            return
        }
        if on {
            requestOn(minutes: nil, pid: nil)
        } else {
            requestOff()
        }
    }

    /// A `macster://` URL, the `macster` command, the menu's durations, or the keyboard shortcut.
    func perform(_ command: MacsterCommand) {
        guard hasStarted else {
            launchedForCommand = true
            pendingCommands.append(command)
            return
        }
        log.notice("Command: \(command.description, privacy: .public)")
        switch command {
        case .open:
            showPanel?()
        case .off:
            requestOff()
        case .toggle:
            if phase == .off || phase == .turningOff {
                perform(.on(minutes: nil, pid: nil))
            } else {
                requestOff()
            }
        case .on(let minutes, let pid):
            // Setup needs the user and a password prompt; never start it from a command.
            guard access == .ready else {
                showPanel?()
                return
            }
            requestOn(minutes: minutes, pid: pid)
        }
    }

    /// The "Turn off after" menu: saves the setting and applies it to the session that's running.
    func chooseAutoOff(_ choice: AutoOff) {
        autoOff = choice
        sessionAutoOff = nil
        if phase == .on { scheduleAutoOff() }
    }

    func setUp() {
        guard access == .needsSetup else { return }
        access = .settingUp
        notice = nil
        Task { await completeSetUp() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
        } catch {
            notice = .error("Couldn't change Open at Login: \(error.localizedDescription)")
        }
        refreshLoginItem()
    }

    func removeAccess() {
        Task {
            await turnOff(reason: nil)
            do {
                _ = try await SleepControl.runPrivileged(RemovalPlan.privilegedScript)
                await refreshAccess()
                notice = .info("Removed Macster’s permission to change sleep.")
            } catch let error as SleepControlError where error == .setupCanceled {
                // Nothing changed; nothing to report.
            } catch {
                show(error)
            }
            showPanel?()
        }
    }

    // MARK: - Keyboard shortcut

    /// While recording, the current shortcut is off, so pressing it records it instead of toggling.
    func beginRecordingShortcut() {
        isRecordingShortcut = true
        notice = nil
        hotKey.unregister()
    }

    func cancelRecordingShortcut() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        registerShortcut()
    }

    /// Saves `shortcut` if it can be a global shortcut. Returns whether recording is done.
    func recordShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        guard shortcut.problem == nil else {
            notice = .error("Use two or more modifier keys, including ⌘ or ⌃, like ⌃⌥⌘L.")
            return false
        }
        guard hotKey.register(shortcut, action: { [weak self] in self?.shortcutPressed() }) else {
            notice = .error("\(shortcut.title) is already in use. Try another one.")
            return false
        }
        toggleShortcut = shortcut
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Keys.toggleShortcut)
        }
        isRecordingShortcut = false
        notice = nil
        log.notice("Keyboard shortcut set to \(shortcut.title, privacy: .public)")
        return true
    }

    func clearShortcut() {
        hotKey.unregister()
        toggleShortcut = nil
        isRecordingShortcut = false
        defaults.removeObject(forKey: Keys.toggleShortcut)
    }

    private func registerShortcut() {
        guard let toggleShortcut else {
            hotKey.unregister()
            return
        }
        if !hotKey.register(toggleShortcut, action: { [weak self] in self?.shortcutPressed() }) {
            log.error("macOS refused the keyboard shortcut \(toggleShortcut.title, privacy: .public)")
        }
    }

    private func shortcutPressed() {
        guard access == .ready else {
            showPanel?()
            return
        }
        perform(.toggle)
    }

    // MARK: - Turning on and off

    /// Starts a session, or adjusts the one that's running. `minutes` sets this session's timer; `pid` ties the
    /// session to a program (see `SessionOwner`).
    private func requestOn(minutes: Int?, pid: Int32?) {
        if phase.isChanging {
            Task {
                guard await settled() else { return }
                requestOn(minutes: minutes, pid: pid)
            }
            return
        }
        guard access == .ready else { return }
        if let pid, !Self.isRunning(pid) {
            log.notice("Process \(pid, privacy: .public) already exited; nothing to stay awake for")
            return
        }

        let isRunning = phase == .on
        let previous = isRunning ? owner : nil
        let next = SessionOwner.afterTurningOn(current: previous, pid: pid)
        owner = next
        if let pid, next.isWaiting(for: pid) {
            watch(pid)
        }

        var timerChanged = false
        if let minutes {
            sessionAutoOff = AutoOff(minutes: minutes)
            timerChanged = true
        } else if previous == nil, case .processes = next {
            sessionAutoOff = .never // A program's session lasts as long as the program.
        } else if case .processes? = previous, next == .user {
            sessionAutoOff = nil // The user took over: their timer applies.
            timerChanged = true
        }

        if isRunning {
            if timerChanged { scheduleAutoOff() }
        } else {
            phase = .turningOn
            notice = nil
            Task { await completeTurnOn() }
        }
    }

    private func requestOff() {
        switch phase {
        case .on:
            phase = .turningOff
            notice = nil
            Task { await completeTurnOff(reason: nil) }
        case .turningOn:
            Task {
                guard await settled() else { return }
                requestOff()
            }
        case .off, .turningOff:
            break
        }
    }

    private func completeTurnOn() async {
        if let reason = safetyStop() {
            phase = .off
            reconcile()
            notice = .error(reason.refusal)
            notifyIfHidden(title: "Macster didn’t turn on", body: reason.refusal)
            return
        }
        do {
            // Armed before anything changes, so even a crash right now leaves sleep working.
            try armWatchdog()
            try await SleepControl.setSleepDisabled(true)
            guard await waitForSystem(sleepDisabled: true) else { throw SleepControlError.notApplied }
            log.notice("Turned on")
            phase = .on
            reconcile()
        } catch {
            log.error("Couldn't turn on: \(error.localizedDescription, privacy: .public)")
            phase = rootDomain.isSleepDisabled ? .on : .off
            reconcile()
            show(error)
        }
    }

    private func turnOff(reason: TurnOffReason?, timeout: Duration = .seconds(15)) async {
        guard phase == .on, access == .ready else { return }
        phase = .turningOff
        await completeTurnOff(reason: reason, timeout: timeout)
    }

    private func completeTurnOff(reason: TurnOffReason?, timeout: Duration = .seconds(15)) async {
        do {
            try await SleepControl.setSleepDisabled(false, timeout: timeout)
            guard await waitForSystem(sleepDisabled: false) else { throw SleepControlError.notApplied }
            log.notice("\(reason?.message ?? "Turned off", privacy: .public)")
            phase = .off
            reconcile()
            if let reason {
                notice = .info(reason.message)
                if let body = reason.notificationBody {
                    notifyIfHidden(title: "Your Mac can sleep again", body: body)
                }
            }
        } catch {
            log.error("Couldn't turn off: \(error.localizedDescription, privacy: .public)")
            phase = rootDomain.isSleepDisabled ? .on : .off
            reconcile()
            show(error)
        }
    }

    /// `pmset` returns before the kernel flag flips, so a change counts only once the kernel reports it.
    private func waitForSystem(sleepDisabled expected: Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(3)
        while rootDomain.isSleepDisabled != expected {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return true
    }

    /// Waits for a change in flight to finish. False if it's still going after a few seconds.
    private func settled() async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while phase.isChanging {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// powerd posts its change notification a few milliseconds before the kernel flag flips, so a read right away
    /// sees the old value. Look shortly after, then again in case the system is busy.
    private func syncSoon() {
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            for delay in [Duration.milliseconds(100), .milliseconds(400), .milliseconds(1500)] {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                self?.syncWithSystem()
            }
        }
    }

    /// Follows changes made outside Macster: Terminal, another app, or the watchdog.
    func syncWithSystem() {
        guard access != .settingUp else { return }
        switch (phase, rootDomain.isSleepDisabled) {
        case (.off, true):
            log.notice("Sleep was disabled outside Macster")
            phase = .on
            reconcile()
        case (.on, false):
            log.notice("Sleep was turned back on outside Macster")
            phase = .off
            reconcile()
        default:
            break
        }
    }

    /// Makes the watchdog, timer, safety checks, program watchers and crash marker match `phase` and `access`.
    private func reconcile() {
        switch phase {
        case .on where access == .ready:
            if owner == nil { owner = .user } // Adopted from outside Macster, or found on at launch.
            if watchdog == nil {
                do { try armWatchdog() } catch { show(error) }
            }
            if autoOffTask == nil, !effectiveAutoOff.isNever { scheduleAutoOff() }
            powerSources.start { [weak self] in self?.evaluateSafety() }
            startSafetyPoll()
            if hasLid, let isClosed = rootDomain.isLidClosed,
               !lidMonitor.start(isClosed: isClosed, onChange: { [weak self] isClosed in self?.lidChanged(isClosed: isClosed) }) {
                log.error("Couldn't watch the lid, so the screen may stay on when it closes")
            }
            defaults.set(true, forKey: Keys.sessionActive)
            evaluateSafety()
        case .off:
            watchdog?.disarm()
            watchdog = nil
            autoOffTask?.cancel()
            autoOffTask = nil
            autoOffDeadline = nil
            safetyPoll?.cancel()
            safetyPoll = nil
            powerSources.stop()
            lidMonitor.stop()
            turnedScreensOff = false
            for source in processWatchers.values { source.cancel() }
            processWatchers = [:]
            owner = nil
            sessionAutoOff = nil
            defaults.set(false, forKey: Keys.sessionActive)
        case .on, .turningOn, .turningOff:
            break // Mid-change, or on without permission: nothing Macster can manage yet.
        }
    }

    private func armWatchdog() throws {
        guard watchdog == nil else { return }
        watchdog = try Watchdog.arm { [weak self] in
            self?.watchdogExitedUnexpectedly()
        }
    }

    private func watchdogExitedUnexpectedly() {
        watchdog = nil
        syncWithSystem() // It may have turned sleep back on before exiting.
        guard phase == .on else { return }

        // Re-arm once. If it keeps dying, stop rather than relaunch it in a loop: keeping the Mac awake without
        // the safety net isn't worth it.
        let now = ContinuousClock.now
        if let last = lastWatchdogFailure, now - last < .seconds(30) {
            log.error("Watchdog keeps exiting; turning off")
            Task { await turnOff(reason: .helperKeptStopping) }
            return
        }
        lastWatchdogFailure = now
        reconcile()
    }

    private func scheduleAutoOff() {
        autoOffTask?.cancel()
        autoOffTask = nil
        autoOffDeadline = nil
        let timer = effectiveAutoOff
        guard phase == .on, let duration = timer.duration else { return }

        autoOffDeadline = Date.now.addingTimeInterval(TimeInterval(timer.minutes * 60))
        autoOffTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration, tolerance: .seconds(5))
            } catch {
                return
            }
            await self?.turnOff(reason: .timerEnded(timer))
        }
    }

    // MARK: - Programs

    private static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func watch(_ pid: Int32) {
        guard processWatchers[pid] == nil else { return }
        // kqueue reports the exit; no polling.
        let source = DispatchSource.makeProcessSource(identifier: pid_t(pid), eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            self?.processExited(pid)
        }
        processWatchers[pid] = source
        source.resume()
        // It may have exited before the watch started.
        if !Self.isRunning(pid) { processExited(pid) }
    }

    private func processExited(_ pid: Int32) {
        guard let source = processWatchers.removeValue(forKey: pid) else { return }
        source.cancel()
        guard var current = owner else { return }
        let wasLast = current.processExited(pid)
        owner = current
        guard wasLast else { return }

        log.notice("Process \(pid, privacy: .public) exited; it was the last one Macster was waiting for")
        Task {
            guard await settled() else { return }
            // Someone may have taken the session over in the meantime.
            guard owner == .processes([]) else { return }
            if phase == .on {
                await turnOff(reason: .commandsFinished)
            } else {
                owner = nil
            }
        }
    }

    // MARK: - Lid

    private func lidChanged(isClosed: Bool) {
        log.notice("Lid \(isClosed ? "closed" : "opened", privacy: .public)")
        if isClosed {
            Task {
                // Give macOS a moment to finish its own lid handling, such as switching to an external display.
                try? await Task.sleep(for: .seconds(1))
                guard rootDomain.isLidClosed == true,
                      Clamshell.shouldTurnOffScreens(
                          isKeepingAwake: phase == .on,
                          isEnabled: screenOffWhenClosed,
                          hasOtherDisplay: Screens.hasOtherDisplay
                      )
                else { return }
                do {
                    try await Screens.turnOff()
                    turnedScreensOff = true
                    log.notice("Turned the screens off for the closed lid")
                } catch {
                    log.error("Couldn't turn the screens off: \(error.localizedDescription, privacy: .public)")
                }
            }
        } else if turnedScreensOff {
            // macOS wakes the screen when the lid opens; this makes sure it does.
            turnedScreensOff = false
            Screens.turnOn()
        }
    }

    // MARK: - Safety

    /// The reason it isn't safe to keep the Mac awake right now, if there is one.
    private func safetyStop() -> TurnOffReason? {
        Safety.stopReason(
            battery: PowerSourceMonitor.currentReading(),
            cutoff: batteryCutoff,
            heatGuard: heatGuard,
            isOverheating: ProcessInfo.processInfo.thermalState == .critical
        )
    }

    private func evaluateSafety() {
        guard phase == .on, access == .ready, let reason = safetyStop() else { return }
        Task { await turnOff(reason: reason) }
    }

    /// Battery temperature has no change notification, so it's read once a minute while Macster keeps the Mac awake.
    private func startSafetyPoll() {
        guard safetyPoll == nil else { return }
        safetyPoll = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60), tolerance: .seconds(15))
                } catch {
                    return
                }
                self?.evaluateSafety()
            }
        }
    }

    // MARK: - Setup

    private func completeSetUp() async {
        do {
            let rule = try SudoRule(userName: NSUserName())
            let plan = SetupPlan(
                rule: rule,
                userID: getuid(),
                legacy: legacy,
                currentSettings: await LegacyScanner.currentSettings()
            )
            log.notice("Running setup: \(plan.steps.joined(separator: "; "), privacy: .public)")
            let warnings = try await SleepControl.runPrivileged(plan.privilegedScript)
            if plan.turnSleepBackOn {
                // The kernel flag trails `pmset` by a moment; don't mistake the old state for the new one.
                _ = await waitForSystem(sleepDisabled: false)
            }
            await LegacyScanner.removeUserLeftovers()
            await refreshAccess()
            guard access == .ready else {
                throw SleepControlError.setupFailed("macOS still asks for a password to change sleep.")
            }
            log.notice("Setup finished")
            phase = rootDomain.isSleepDisabled ? .on : .off
            reconcile()
            if !warnings.isEmpty {
                notice = .info("Set up, but some old settings couldn't be restored: \(warnings.joined(separator: "; ")).")
            }
        } catch {
            log.error("Setup failed: \(String(describing: error), privacy: .public)")
            if access == .settingUp { access = .needsSetup }
            show(error)
        }
        // The password prompt took focus and closed the panel; bring it back to show the result.
        showPanel?()
    }

    private func refreshAccess() async {
        legacy = await LegacyScanner.scan()
        if legacy.isPresent {
            access = .needsSetup
        } else {
            let granted = await SleepControl.hasPasswordlessAccess(probe: rootDomain.isSleepDisabled)
            access = granted ? .ready : .needsSetup
        }
        log.notice("Permission: \(self.access == .ready ? "ready" : "needs setup", privacy: .public); Macster 0.1 leftovers: \(self.legacy.isPresent, privacy: .public)")
    }

    // MARK: - Helpers

    private func show(_ error: any Error) {
        switch error {
        case let error as SleepControlError where error == .setupCanceled:
            notice = .info(error.localizedDescription)
            return
        case let error as SleepControlError where error == .permissionMissing:
            access = .needsSetup
            notice = .error(error.localizedDescription)
        case let problem as SudoRule.Problem:
            notice = .error(problem.description)
        default:
            notice = .error(error.localizedDescription)
        }
        if let notice {
            notifyIfHidden(title: "Macster couldn’t change sleep", body: notice.message)
        }
    }

    /// With the panel open, its notice already says it.
    private func notifyIfHidden(title: String, body: String) {
        guard !isPanelVisible else { return }
        notifier.post(title: title, body: body)
    }

    private func refreshLoginItem() {
        let status = LoginItem.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        loginItemNeedsApproval = status == .requiresApproval
    }

    private func observeSystem() {
        guard systemObservers.isEmpty else { return }
        // powerd posts this whenever power settings change, `pmset disablesleep` included.
        if let observer = NotifyObserver("com.apple.system.powermanagement.prefschange", handler: { [weak self] in
            self?.syncSoon()
        }) {
            systemObservers.append(observer)
        }
        systemObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncSoon() }
            }
        )
        systemObservers.append(
            NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluateSafety() }
            }
        )
    }
}
