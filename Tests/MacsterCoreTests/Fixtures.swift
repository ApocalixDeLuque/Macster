import Foundation
@testable import MacsterCore

/// Real outputs captured on a MacBook Pro running Macster 0.1.2 with keep-awake on (macOS 26.4), with the user and
/// computer names replaced.
enum Fixtures {
    static let pmsetCustomWithLegacyOn = """
    Battery Power:
     Sleep On Power Button 1
     powermode            0
     standby              0
     ttyskeepawake        1
     hibernatemode        3
     powernap             0
     hibernatefile        /var/vm/sleepimage
     displaysleep         0
     womp                 0
     networkoversleep     0
     sleep                0
     lessbright           1
     tcpkeepalive         1
     disksleep            0
     SleepServices        0
    AC Power:
     Sleep On Power Button 1
     powermode            0
     standby              0
     ttyskeepawake        1
     hibernatemode        3
     powernap             0
     hibernatefile        /var/vm/sleepimage
     displaysleep         0
     womp                 1
     networkoversleep     0
     sleep                0
     tcpkeepalive         1
     disksleep            0
     SleepServices        0
    """

    static let legacyBackupJSON = """
    {
      "ac" : {
        "disksleep" : "10",
        "displaysleep" : "0",
        "powernap" : "1",
        "sleep" : "1",
        "standby" : "1"
      },
      "battery" : {
        "disksleep" : "10",
        "displaysleep" : "0",
        "powernap" : "1",
        "sleep" : "1",
        "standby" : "1"
      },
      "createdAt" : "2026-11-05T21:51:30Z",
      "version" : 1
    }
    """

    static let sudoListingWithOldRule = """
    Matching Defaults entries for jappleseed on Johnnys-MacBook-Pro:
        env_reset, env_keep+=BLOCKSIZE, env_keep+="COLORFGBG COLORTERM", lecture_file=/etc/sudo_lecture, !log_allowed

    User jappleseed may run the following commands on Johnnys-MacBook-Pro:
        (ALL) ALL
        (root) NOPASSWD: /usr/local/libexec/macsterctl enable, /usr/local/libexec/macsterctl disable
    """

    static let sudoListingWithRule = """
    Matching Defaults entries for jappleseed on Johnnys-MacBook-Pro:
        env_reset, env_keep+=BLOCKSIZE, lecture_file=/etc/sudo_lecture, !log_allowed

    User jappleseed may run the following commands on Johnnys-MacBook-Pro:
        (ALL) ALL
        (root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
    """

    static let legacySettingsProfile = PowerProfile([.sleep: 0, .disksleep: 0, .displaysleep: 0, .standby: 0, .powernap: 0])
    static let backupProfile = PowerProfile([.sleep: 1, .disksleep: 10, .displaysleep: 0, .standby: 1, .powernap: 1])

    static func rule() throws -> SudoRule {
        try SudoRule(userName: "jappleseed")
    }
}
