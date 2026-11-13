/// The lid, as the kernel's power management reports it.
public enum Clamshell {
    /// `kIOPMMessageClamshellStateChange`, `iokit_family_msg(sub_iokit_powermanagement, 0x100)` in IOPM.h: sent as a
    /// general interest notification on IOPMrootDomain whenever the lid opens or closes. Swift can't import the macro.
    public static let stateChangeMessage: UInt32 = (0x38 << 26) | (13 << 14) | 0x100

    /// The message's argument is a bitfield. Bit 0 (`kClamshellStateBit`) is set while the lid is closed.
    public static func isClosed(messageArgument: UInt) -> Bool {
        messageArgument & 1 != 0
    }

    /// Whether to turn the screens off as the lid closes. With sleep disabled, macOS can leave the built-in screen lit
    /// behind the lid. Never with another display active: then the Mac is in clamshell mode on purpose, and that's the
    /// display you're looking at.
    public static func shouldTurnOffScreens(isKeepingAwake: Bool, isEnabled: Bool, hasOtherDisplay: Bool) -> Bool {
        isKeepingAwake && isEnabled && !hasOtherDisplay
    }
}
