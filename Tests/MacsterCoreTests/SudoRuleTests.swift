import Foundation
import Testing
@testable import MacsterCore

struct SudoRuleTests {
    @Test(arguments: ["jappleseed", "j.appleseed", "john-doe", "_mbsetupuser", "a1", "UPPER"])
    func `accepts macOS short names`(name: String) {
        #expect(SudoRule.isValidUserName(name))
    }

    @Test(arguments: [
        "", "-n", ".hidden", "john doe", "a,b", "root\nALL", "user=ALL", "jöhn", "x:y", #"a"b"#, "a'b", "(root)",
        String(repeating: "a", count: 65),
    ])
    func `refuses names that could change the meaning of the rule`(name: String) {
        #expect(!SudoRule.isValidUserName(name))
        #expect(throws: SudoRule.Problem.invalidUserName(name)) {
            try SudoRule(userName: name)
        }
    }

    @Test func `the rule allows exactly the two pmset commands`() throws {
        let lines = try Fixtures.rule().contents.split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(lines == [
            "jappleseed ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0",
        ])
    }

    @Test func `visudo accepts the rule`() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("macster-rule-\(UUID().uuidString)")
        try Fixtures.rule().contents.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let output = try await ProcessRunner.run("/usr/sbin/visudo", ["-cqf", file.path])
        #expect(output.succeeded, "\(output.stderr)")
    }

    @Test func `the commands Macster runs match the rule`() {
        #expect(SleepCommand.sudoArguments(sleepDisabled: true) == ["-n", "/usr/bin/pmset", "-a", "disablesleep", "1"])
        #expect(SleepCommand.sudoArguments(sleepDisabled: false) == ["-n", "/usr/bin/pmset", "-a", "disablesleep", "0"])
    }
}

struct SudoListingTests {
    @Test func `finds Macster's rule`() {
        #expect(SudoRule.listingGrantsAccess(Fixtures.sudoListingWithRule))
    }

    @Test func `the Macster 0.1 rule doesn't count`() {
        #expect(!SudoRule.listingGrantsAccess(Fixtures.sudoListingWithOldRule))
    }

    @Test func `NOPASSWD ALL counts`() {
        #expect(SudoRule.listingGrantsAccess("    (ALL : ALL) NOPASSWD: ALL"))
    }

    @Test func `password-protected rules don't count`() {
        #expect(!SudoRule.listingGrantsAccess("    (ALL) ALL"))
        #expect(!SudoRule.listingGrantsAccess("    (root) /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"))
    }

    @Test func `the two commands may come from separate lines`() {
        let listing = """
            (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
            (root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
        """
        #expect(SudoRule.listingGrantsAccess(listing))
    }

    @Test func `both commands are required`() {
        #expect(!SudoRule.listingGrantsAccess("    (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1"))
    }

    @Test func `a PASSWD tag applies to the commands after it`() {
        let listing = "    (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, PASSWD: /usr/bin/pmset -a disablesleep 0"
        #expect(!SudoRule.listingGrantsAccess(listing))
    }

    @Test func `rules that run as another user don't count`() {
        let listing = "    (nobody) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
        #expect(!SudoRule.listingGrantsAccess(listing))
    }

    @Test func `other tags are skipped`() {
        let listing = "    (root) NOPASSWD: SETENV: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
        #expect(SudoRule.listingGrantsAccess(listing))
    }
}
