import Foundation
import Testing
@testable import MacsterCore

struct MacsterCommandTests {
    private func command(_ string: String) -> MacsterCommand? {
        URL(string: string).flatMap(MacsterCommand.init(url:))
    }

    @Test func `reads every command`() {
        #expect(command("macster://on") == .on(minutes: nil, pid: nil))
        #expect(command("macster://off") == .off)
        #expect(command("macster://toggle") == .toggle)
        #expect(command("macster://open") == .open)
        #expect(command("macster://") == .open)
    }

    @Test func `accepts the forms Shortcuts and Terminal produce`() {
        #expect(command("MACSTER://ON") == .on(minutes: nil, pid: nil))
        #expect(command("macster:on") == .on(minutes: nil, pid: nil))
        #expect(command("macster:///off") == .off)
        #expect(command("macster://on/") == .on(minutes: nil, pid: nil))
    }

    @Test func `reads durations and processes`() {
        #expect(command("macster://on?minutes=90") == .on(minutes: 90, pid: nil))
        #expect(command("macster://on?hours=2") == .on(minutes: 120, pid: nil))
        #expect(command("macster://on?hours=1&minutes=30") == .on(minutes: 90, pid: nil))
        #expect(command("macster://on?minutes=0") == .on(minutes: 0, pid: nil))
        #expect(command("macster://on?pid=4242") == .on(minutes: nil, pid: 4242))
        #expect(command("macster://on?minutes=5&pid=7") == .on(minutes: 5, pid: 7))
    }

    @Test(arguments: [
        "https://on", "macster://sleep", "macster://on?minutes=abc", "macster://on?minutes=-5",
        "macster://on?minutes=99999", "macster://on?hours=999", "macster://on?pid=0", "macster://on?pid=-1",
        "macster://on?pid=99999999999",
    ])
    func `rejects anything else`(string: String) {
        #expect(command(string) == nil)
    }

    @Test(arguments: [
        MacsterCommand.on(minutes: nil, pid: nil), .on(minutes: 45, pid: nil), .on(minutes: nil, pid: 99),
        .on(minutes: 0, pid: 12), .off, .toggle, .open,
    ])
    func `round-trips through its URL`(original: MacsterCommand) {
        #expect(MacsterCommand(url: original.url) == original)
    }
}

struct CommandLineRequestTests {
    private func parse(_ arguments: String...) throws -> CommandLineRequest? {
        try CommandLineRequest.parse(arguments)
    }

    @Test func `no command starts the app`() throws {
        #expect(try parse() == nil)
        #expect(try parse("-psn_0_12345") == nil)
        #expect(try parse("-NSDocumentRevisionsDebugMode", "YES") == nil)
    }

    @Test func `reads commands`() throws {
        #expect(try parse("on") == .send(.on(minutes: nil, pid: nil)))
        #expect(try parse("on", "2h") == .send(.on(minutes: 120, pid: nil)))
        #expect(try parse("on", "never") == .send(.on(minutes: 0, pid: nil)))
        #expect(try parse("off") == .send(.off))
        #expect(try parse("toggle") == .send(.toggle))
        #expect(try parse("open") == .send(.open))
        #expect(try parse("status") == .status)
        #expect(try parse("--diagnose") == .diagnose)
        #expect(try parse("diagnose") == .diagnose)
        #expect(try parse("-h") == .help)
        #expect(try parse("version") == .version)
    }

    @Test func `run keeps the command's own arguments`() throws {
        #expect(try parse("run", "--", "make", "-j8", "--keep-going") == .run(["make", "-j8", "--keep-going"]))
        #expect(try parse("run", "sleep", "10") == .run(["sleep", "10"]))
        #expect(try parse("run", "--", "--") == .run(["--"]))
    }

    @Test(arguments: [["onn"], ["on", "soon"], ["on", "1h", "2h"], ["off", "now"], ["run"], ["run", "--"], ["on", "200h"]])
    func `explains mistakes`(arguments: [String]) {
        #expect(throws: CommandLineRequest.UsageError.self) {
            try CommandLineRequest.parse(arguments)
        }
    }

    @Test(arguments: zip(
        ["90", "90m", "2h", "1h30m", "1h30", "0", "never", "Forever", "45M", "8H"],
        [90, 90, 120, 90, 90, 0, 0, 0, 45, 480]
    ))
    func `reads durations`(text: String, minutes: Int) {
        #expect(CommandLineRequest.minutes(from: text) == minutes)
    }

    @Test(arguments: ["", "h", "m", "2x", "1.5h", "30m2h", "2h2h", "1m30", "-5", "1234567", "۳m"])
    func `rejects malformed durations`(text: String) {
        #expect(CommandLineRequest.minutes(from: text) == nil)
    }
}

struct KeyboardShortcutTests {
    private let l: UInt16 = 37 // kVK_ANSI_L

    @Test func `needs two modifiers including command or control`() {
        #expect(KeyboardShortcut(keyCode: l, modifiers: [.control, .option, .command]).problem == nil)
        #expect(KeyboardShortcut(keyCode: l, modifiers: [.shift, .command]).problem == nil)
        #expect(KeyboardShortcut(keyCode: l, modifiers: [.control, .option]).problem == nil)
        // ⌘L is an app shortcut, ⌃L is Terminal's clear screen, ⌥L types ¬, ⇧⌥L types a character too.
        #expect(KeyboardShortcut(keyCode: l, modifiers: [.command]).problem == .needsMoreModifiers)
        #expect(KeyboardShortcut(keyCode: l, modifiers: [.control]).problem == .needsMoreModifiers)
        #expect(KeyboardShortcut(keyCode: l, modifiers: [.option]).problem == .needsMoreModifiers)
        #expect(KeyboardShortcut(keyCode: l, modifiers: [.shift, .option]).problem == .needsMoreModifiers)
        #expect(KeyboardShortcut(keyCode: l, modifiers: []).problem == .needsMoreModifiers)
    }

    @Test func `function keys work on their own`() {
        #expect(KeyboardShortcut(keyCode: 105, modifiers: []).problem == nil) // F13
        #expect(KeyboardShortcut(keyCode: 105, modifiers: []).isFunctionKey)
    }

    @Test func `shows modifiers in the order macOS uses`() {
        let shortcut = KeyboardShortcut(keyCode: l, modifiers: [.command, .shift, .option, .control])
        #expect(shortcut.displayName(character: "l") == "⌃⌥⇧⌘L")
        #expect(KeyboardShortcut(keyCode: 49, modifiers: [.option, .command]).displayName(character: " ") == "⌥⌘Space")
        #expect(KeyboardShortcut(keyCode: 122, modifiers: []).displayName(character: nil) == "F1")
        #expect(KeyboardShortcut(keyCode: 126, modifiers: [.control, .command]).displayName(character: nil) == "⌃⌘↑")
        #expect(KeyboardShortcut(keyCode: 200, modifiers: [.control, .command]).displayName(character: nil) == "⌃⌘Key 200")
    }

    @Test func `maps modifiers to Carbon flags`() {
        #expect(KeyboardShortcut(keyCode: l, modifiers: [.command]).carbonModifiers == 0x0100)
        #expect(KeyboardShortcut(keyCode: l, modifiers: [.control, .option, .shift, .command]).carbonModifiers == 0x1B00)
    }

    @Test func `survives a trip through the defaults`() throws {
        let shortcut = KeyboardShortcut(keyCode: l, modifiers: [.control, .command])
        let data = try JSONEncoder().encode(shortcut)
        #expect(try JSONDecoder().decode(KeyboardShortcut.self, from: data) == shortcut)
    }
}

struct ClamshellTests {
    @Test func `matches the IOKit message number`() {
        // iokit_family_msg(sub_iokit_powermanagement, 0x100) = err_system(0x38) | err_sub(13) | 0x100
        #expect(Clamshell.stateChangeMessage == 0xE003_4100)
    }

    @Test func `reads the lid from the message's bits`() {
        #expect(Clamshell.isClosed(messageArgument: 0b01))
        #expect(Clamshell.isClosed(messageArgument: 0b11))
        #expect(!Clamshell.isClosed(messageArgument: 0b10)) // Bit 1 only says whether closing would sleep.
        #expect(!Clamshell.isClosed(messageArgument: 0))
    }

    @Test func `turns screens off only when it helps`() {
        #expect(Clamshell.shouldTurnOffScreens(isKeepingAwake: true, isEnabled: true, hasOtherDisplay: false))
        // Asleep anyway, or the option is off.
        #expect(!Clamshell.shouldTurnOffScreens(isKeepingAwake: false, isEnabled: true, hasOtherDisplay: false))
        #expect(!Clamshell.shouldTurnOffScreens(isKeepingAwake: true, isEnabled: false, hasOtherDisplay: false))
        // Closed on a desk with a monitor: that monitor is in use.
        #expect(!Clamshell.shouldTurnOffScreens(isKeepingAwake: true, isEnabled: true, hasOtherDisplay: true))
    }
}

struct SessionOwnerTests {
    @Test func `turning on with nothing running`() {
        #expect(SessionOwner.afterTurningOn(current: nil, pid: nil) == .user)
        #expect(SessionOwner.afterTurningOn(current: nil, pid: 10) == .processes([10]))
    }

    @Test func `programs join a session programs started`() {
        #expect(SessionOwner.afterTurningOn(current: .processes([10]), pid: 11) == .processes([10, 11]))
    }

    @Test func `programs don't take over the user's session, and the user takes over theirs`() {
        #expect(SessionOwner.afterTurningOn(current: .user, pid: 10) == .user)
        #expect(SessionOwner.afterTurningOn(current: .processes([10]), pid: nil) == .user)
    }

    @Test func `ends when the last program exits`() {
        var owner = SessionOwner.processes([10, 11])
        #expect(owner.isWaiting(for: 10))
        let results = [
            owner.processExited(10),
            owner.processExited(10), // Already gone.
            owner.processExited(99), // Never waited for it.
            owner.processExited(11),
        ]
        #expect(results == [false, false, false, true])
        #expect(owner == .processes([]))
    }

    @Test func `the user's session ignores programs`() {
        var owner = SessionOwner.user
        #expect(!owner.isWaiting(for: 10))
        let wasLast = owner.processExited(10)
        #expect(!wasLast)
        #expect(owner == .user)
    }
}
