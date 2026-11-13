import Foundation
import Testing
@testable import MacsterCore

struct AutoOffTests {
    @Test(arguments: zip(
        [0, 1, 30, 60, 90, 120, 480],
        ["Never", "1 minute", "30 minutes", "1 hour", "90 minutes", "2 hours", "8 hours"]
    ))
    func `titles read naturally`(minutes: Int, title: String) {
        #expect(AutoOff(minutes: minutes).title == title)
    }

    @Test func `never has no duration`() {
        #expect(AutoOff.never.duration == nil)
        #expect(AutoOff(minutes: -5) == .never)
        #expect(AutoOff(minutes: 2).duration == .seconds(120))
    }

    @Test func `a custom value joins the presets in order`() {
        #expect(AutoOff.choices(including: AutoOff(minutes: 60)) == AutoOff.presets)
        #expect(AutoOff.choices(including: AutoOff(minutes: 1)).map(\.minutes) == [0, 1, 30, 60, 120, 240, 480])
    }
}

struct SafetyTests {
    @Test(arguments: [
        (BatteryReading(percent: 10, isOnBatteryPower: true), true),
        (BatteryReading(percent: 3, isOnBatteryPower: true), true),
        (BatteryReading(percent: 11, isOnBatteryPower: true), false),
        (BatteryReading(percent: 5, isOnBatteryPower: false), false),
    ])
    func `turns off only when low on battery power`(reading: BatteryReading, tooLow: Bool) {
        #expect(Safety.isBatteryTooLow(reading, cutoff: .standard) == tooLow)
    }

    @Test func `the cutoff is adjustable and can be turned off`() {
        let reading = BatteryReading(percent: 18, isOnBatteryPower: true)
        #expect(Safety.isBatteryTooLow(reading, cutoff: BatteryCutoff(percent: 20)))
        #expect(!Safety.isBatteryTooLow(reading, cutoff: BatteryCutoff(percent: 15)))
        #expect(!Safety.isBatteryTooLow(BatteryReading(percent: 1, isOnBatteryPower: true), cutoff: .never))
    }

    @Test func `Macs without a battery are never too low or too hot`() {
        #expect(!Safety.isBatteryTooLow(nil, cutoff: BatteryCutoff(percent: 30)))
        #expect(!Safety.isBatteryTooHot(nil))
        #expect(!Safety.isBatteryTooHot(BatteryReading(percent: 50, isOnBatteryPower: true)))
    }

    @Test(arguments: [(44.9, false), (45.0, true), (52.3, true), (30.6, false)])
    func `turns off when the battery gets hot`(celsius: Double, tooHot: Bool) {
        let reading = BatteryReading(percent: 80, isOnBatteryPower: false, temperatureCelsius: celsius)
        #expect(Safety.isBatteryTooHot(reading) == tooHot)
    }

    @Test func `battery temperature comes in hundredths of a degree`() {
        #expect(Safety.celsius(fromBatteryTemperature: 3064) == 30.64)
        #expect(Safety.celsius(fromBatteryTemperature: 65_535) == nil)
        #expect(Safety.celsius(fromBatteryTemperature: -27_315) == nil)
    }

    @Test func `picks the reason to stop`() {
        let fine = BatteryReading(percent: 80, isOnBatteryPower: true, temperatureCelsius: 31)
        let low = BatteryReading(percent: 8, isOnBatteryPower: true, temperatureCelsius: 47.6)
        let hot = BatteryReading(percent: 80, isOnBatteryPower: false, temperatureCelsius: 47.6)
        func reason(_ battery: BatteryReading?, heat: Bool = true, overheating: Bool = false) -> TurnOffReason? {
            Safety.stopReason(battery: battery, cutoff: .standard, heatGuard: heat, isOverheating: overheating)
        }
        #expect(reason(fine) == nil)
        #expect(reason(nil) == nil)
        #expect(reason(low) == .lowBattery(percent: 8)) // The battery comes first: it can't wait.
        #expect(reason(hot) == .batteryHot(celsius: 48))
        #expect(reason(fine, overheating: true) == .overheating)
        #expect(reason(nil, overheating: true) == .overheating) // Desktop Macs can overheat too.
        // With the heat safety off, only the battery level counts.
        #expect(reason(hot, heat: false, overheating: true) == nil)
        #expect(reason(low, heat: false) == .lowBattery(percent: 8))
    }

    @Test func `cutoff choices`() {
        #expect(BatteryCutoff.presets.map(\.title) == ["Never", "5% battery", "10% battery", "15% battery", "20% battery", "30% battery"])
        #expect(BatteryCutoff.choices(including: BatteryCutoff(percent: 25)).map(\.percent) == [0, 5, 10, 15, 20, 25, 30])
        #expect(BatteryCutoff(percent: -3) == .never)
        #expect(BatteryCutoff(percent: 400).percent == 95)
    }

    @Test func `every automatic turn-off explains itself`() {
        let reasons: [TurnOffReason] = [
            .timerEnded(AutoOff(minutes: 60)), .lowBattery(percent: 9), .batteryHot(celsius: 46), .overheating,
            .helperKeptStopping, .leftOverSession, .commandsFinished,
        ]
        for reason in reasons {
            #expect(reason.message.hasPrefix("Turned off"))
        }
        #expect(TurnOffReason.timerEnded(AutoOff(minutes: 60)).message == "Turned off after 1 hour.")
        // Finishing the command it was asked to wait for is expected; everything else is worth a notification.
        #expect(reasons.filter { $0.notificationBody == nil } == [.commandsFinished])
    }
}

struct ProcessRunnerTests {
    @Test func `captures output and exit status`() async throws {
        let output = try await ProcessRunner.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        #expect(output.status == 3)
        #expect(output.stdout == "out\n")
        #expect(output.stderr == "err\n")
        #expect(!output.succeeded)
    }

    @Test func `drains large output without deadlocking`() async throws {
        let output = try await ProcessRunner.run("/bin/sh", ["-c", "head -c 1000000 /dev/zero | tr '\\0' a; head -c 200000 /dev/zero | tr '\\0' b >&2"])
        #expect(output.succeeded)
        #expect(output.stdout.count == 1_000_000)
        #expect(output.stderr.count == 200_000)
    }

    @Test func `stops programs that run too long`() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let output = try await ProcessRunner.run("/bin/sleep", ["10"], timeout: .milliseconds(300))
        #expect(output.timedOut)
        #expect(!output.succeeded)
        #expect(clock.now - start < .seconds(5))
    }

    @Test func `a missing program throws`() async {
        await #expect(throws: (any Error).self) {
            try await ProcessRunner.run("/nonexistent/program")
        }
    }
}
