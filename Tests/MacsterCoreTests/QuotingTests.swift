import Foundation
import Testing
@testable import MacsterCore

/// These run the real interpreters, so the quoting is checked against what `/bin/sh` and AppleScript actually do.
struct QuotingTests {
    static let tricky = [
        "plain", "it's", "'leading and trailing'", #""double""#, #"back\slash"#, #"\\two"#, "$HOME `id` $(whoami)",
        "new\nline", "tab\there", "semi; colon && pipe | done", "🌙 lid", "",
    ]

    @Test(arguments: tricky)
    func `shell quoting reads back exactly`(text: String) async throws {
        let output = try await ProcessRunner.run("/bin/sh", ["-c", "printf '%s' \(Quoting.shell(text))"])
        #expect(output.stdout == text)
    }

    @Test(arguments: tricky)
    func `AppleScript quoting reads back exactly`(text: String) async throws {
        let output = try await ProcessRunner.run("/usr/bin/osascript", ["-e", "return \(Quoting.appleScript(text))"])
        #expect(output.succeeded, "\(output.stderr)")
        #expect(output.stdout == text + "\n")
    }

    @Test func `a script survives both layers unchanged`() async throws {
        let marker = #"it's "quoted" \back\slash $HOME `id`"#
        let script = "cat <<'END'\n\(marker)\nEND\n"
        let source = PrivilegedScript(script: script, prompt: "unused").appleScript(withAdministratorPrivileges: false)
        let output = try await ProcessRunner.run("/usr/bin/osascript", ["-e", source])
        #expect(output.succeeded, "\(output.stderr)")
        #expect(output.stdout == marker + "\n")
    }

    @Test func `the privileged form asks for an administrator with Macster's prompt`() {
        let source = PrivilegedScript(script: "true", prompt: "Macster needs your password.").appleScript()
        #expect(source.hasPrefix("do shell script "))
        #expect(source.hasSuffix(#" with prompt "Macster needs your password." with administrator privileges"#))
    }

    @Test func `osascript errors are reduced to their message`() {
        #expect(PrivilegedScript.message(fromOsascriptError: "0:312: execution error: the new sudo rule failed validation (1)\n")
            == "the new sudo rule failed validation")
        #expect(PrivilegedScript.message(fromOsascriptError: "something odd") == "something odd")
        #expect(PrivilegedScript.message(fromOsascriptError: "  ") == "The administrator command failed.")
        #expect(PrivilegedScript.message(fromOsascriptError: "execution error: Failed (see log) (2)") == "Failed (see log)")
    }

    @Test func `cancelling the password prompt is recognized`() {
        #expect(PrivilegedScript.isCancellation("0:93: execution error: User canceled. (-128)"))
        #expect(!PrivilegedScript.isCancellation("0:93: execution error: The administrator user name or password was incorrect. (-60007)"))
    }
}
