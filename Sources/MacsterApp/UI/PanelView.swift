import AppKit
import MacsterCore
import SwiftUI

/// The panel under the menu bar icon.
struct PanelView: View {
    let state: PanelState
    let actions: PanelActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 10) {
                mainCard
                if let notice = state.notice {
                    NoticeView(notice: notice)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .animation(.easeOut(duration: 0.2), value: state.notice)

            options
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 2) {
                OptionRow("Open at login", systemImage: "power") {
                    MiniSwitch(title: "Open at login", isOn: state.launchAtLogin, set: actions.setLaunchAtLogin)
                }
                if state.loginItemNeedsApproval {
                    Button("Allow Macster in System Settings…", action: actions.openLoginItemSettings)
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .padding(.leading, 26)
                        .padding(.bottom, 4)
                }
                OptionRow("Keyboard shortcut", systemImage: "command") {
                    ShortcutField(
                        shortcut: state.shortcut,
                        isRecording: state.isRecordingShortcut,
                        record: actions.recordShortcut,
                        clear: actions.clearShortcut
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()
                .padding(.horizontal, 16)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text("Macster")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Menu {
                Button("About Macster", action: actions.showAbout)
                if state.setup == .ready {
                    Button("Remove Macster’s Permission…", action: actions.removeAccess)
                }
                Divider()
                Button("Quit Macster", action: actions.quit)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More")
        }
    }

    @ViewBuilder
    private var mainCard: some View {
        switch state.setup {
        case .needed(let updatingOldVersion):
            SetupCard(updatingOldVersion: updatingOldVersion, inProgress: false, setUp: actions.setUp)
        case .inProgress(let updatingOldVersion):
            SetupCard(updatingOldVersion: updatingOldVersion, inProgress: true, setUp: actions.setUp)
        case .checking, .ready:
            PowerCard(power: state.power, isEnabled: state.setup == .ready, setOn: actions.setOn)
        }
    }

    private var options: some View {
        VStack(spacing: 2) {
            OptionRow("Turn off after", systemImage: "timer") {
                Picker("Turn off after", selection: Binding(get: { state.autoOff }, set: { actions.setAutoOff($0) })) {
                    ForEach(AutoOff.choices(including: state.autoOff)) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }
            if state.showsBatteryCutoff {
                OptionRow("Turn off at", systemImage: "battery.25") {
                    Picker("Turn off at battery level", selection: Binding(get: { state.batteryCutoff }, set: { actions.setBatteryCutoff($0) })) {
                        ForEach(BatteryCutoff.choices(including: state.batteryCutoff)) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            OptionRow("Turn off if your Mac overheats", systemImage: "thermometer.high") {
                MiniSwitch(title: "Turn off if your Mac overheats", isOn: state.heatGuard, set: actions.setHeatGuard)
            }
            if state.showsLidOptions {
                OptionRow("Screen off with lid closed", systemImage: "display") {
                    MiniSwitch(
                        title: "Screen off with lid closed",
                        isOn: state.screenOffWhenClosed,
                        set: actions.setScreenOffWhenClosed
                    )
                }
                .help("Turns the screen off when you close the lid and back on when you open it. Your Mac locks, as it does whenever the screen turns off.")
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(state.setup == .ready && state.power.keepsMacAwake ? "Quitting Macster turns this off." : "Macster \(state.version)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit", action: actions.quit)
                .controlSize(.small)
                .accessibilityLabel("Quit Macster")
        }
    }
}

/// The model-backed panel the status item shows.
struct LivePanel: View {
    let model: AppModel
    let actions: PanelActions

    var body: some View {
        PanelView(state: model.panelState, actions: actions)
    }
}

// MARK: - Cards

private struct PowerCard: View {
    let power: PanelState.Power
    let isEnabled: Bool
    let setOn: @MainActor (Bool) -> Void

    private var isOn: Bool { power.isOnOrTurningOn }
    private var canToggle: Bool { isEnabled && !power.isChanging }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(isOn: isOn, isChanging: power.isChanging)
                    .onTapGesture(perform: toggle)
                Spacer()
                Toggle("Stay awake with lid closed", isOn: Binding(get: { isOn }, set: { setOn($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Theme.accent)
                    .disabled(!canToggle)
                    // labelsHidden() also hides the label from VoiceOver on macOS.
                    .accessibilityLabel("Stay awake with lid closed")
                    .accessibilityHint(subtitle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Stay awake with lid closed")
                    .font(.system(size: 13.5, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
        }
        .padding(12)
        .card(highlighted: isOn)
        .animation(.easeOut(duration: 0.2), value: power)
    }

    private func toggle() {
        if canToggle { setOn(!isOn) }
    }

    private var subtitle: String {
        switch power {
        case .off: "Your Mac sleeps normally when you close the lid."
        case .turningOn: "Turning on…"
        case .on(until: .none): "Your Mac won’t sleep, even with the lid closed."
        case .on(until: let date?): "Your Mac won’t sleep until \(date.formatted(date: .omitted, time: .shortened)), even with the lid closed."
        case .turningOff: "Turning off…"
        }
    }
}

private struct SetupCard: View {
    let updatingOldVersion: Bool
    let inProgress: Bool
    let setUp: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent)
                    Image(systemName: "key.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(updatingOldVersion ? "Finish updating Macster" : "One-time setup")
                        .font(.system(size: 13, weight: .semibold))
                    Text(description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: setUp) {
                HStack(spacing: 6) {
                    if inProgress {
                        ProgressView().controlSize(.mini)
                    }
                    Text(inProgress ? "Waiting for your password…" : "Set Up…")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(inProgress)
        }
        .padding(12)
        .card(highlighted: false)
    }

    private var description: String {
        if updatingOldVersion {
            "Enter your password once. Macster puts back the power settings its old version changed, turns normal sleep back on, and removes the old helper."
        } else {
            "Enter your password once so Macster can turn lid-close sleep on and off. It won’t ask again."
        }
    }
}

// MARK: - Pieces

private struct StatusBadge: View {
    let isOn: Bool
    let isChanging: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Theme.accent : Color.primary.opacity(0.08))
            if isChanging {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: isOn ? "sun.max.fill" : "moon.zzz.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.onAccent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }
}

private struct NoticeView: View {
    let notice: Notice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: notice.kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(notice.kind == .error ? Color.orange : Color.secondary)
                .accessibilityHidden(true)
            Text(notice.message)
                .foregroundStyle(notice.kind == .error ? Color.primary : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OptionRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    let accessory: Accessory

    init(_ title: String, systemImage: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12.5))
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            accessory
        }
        .frame(minHeight: 28)
    }
}

private struct MiniSwitch: View {
    let title: String
    let isOn: Bool
    let set: @MainActor (Bool) -> Void

    var body: some View {
        Toggle(title, isOn: Binding(get: { isOn }, set: { set($0) }))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .tint(Theme.accent)
            .accessibilityLabel(title)
    }
}

/// Shows the shortcut and records a new one: click, then press the keys. Escape cancels; Delete removes it.
private struct ShortcutField: View {
    let shortcut: String?
    let isRecording: Bool
    let record: @MainActor () -> Void
    let clear: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if shortcut != nil, !isRecording {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help("Remove the shortcut")
                .accessibilityLabel("Remove keyboard shortcut")
            }
            Button(action: record) {
                Text(label)
                    .font(.system(size: 11.5, weight: shortcut != nil && !isRecording ? .medium : .regular))
                    .foregroundStyle(isRecording ? Color.secondary : Color.primary)
                    .frame(minWidth: 64)
            }
            .controlSize(.small)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                    .opacity(isRecording ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .help(isRecording ? "Press Escape to cancel, Delete to remove the shortcut" : "Turns Macster on and off from any app")
            .accessibilityLabel(accessibilityLabel)
        }
        .animation(.easeOut(duration: 0.15), value: isRecording)
    }

    private var label: String {
        if isRecording { return "Type shortcut…" }
        return shortcut ?? "Record"
    }

    private var accessibilityLabel: String {
        if isRecording { return "Recording keyboard shortcut. Press the keys, or Escape to cancel." }
        return shortcut.map { "Keyboard shortcut \($0). Change" } ?? "Record keyboard shortcut"
    }
}

private struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.vertical, 7)
            .background(shape.fill(Theme.accent).opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.6))
            .contentShape(shape)
    }
}

private extension View {
    func card(highlighted: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return background(shape.fill(highlighted ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.045)))
            .overlay(shape.strokeBorder(highlighted ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1))
    }
}
