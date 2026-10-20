import Foundation
import Testing
@testable import FanKitCore

@Suite("SMC codec")
struct SMCCodecTests {
    @Test func decodesFloatRPM() {
        let rpm: Double = 2400
        let bytes = SMCCodec.rpmBytes(rpm, type: .flt)!
        #expect(SMCCodec.rpm(from: bytes, type: .flt) == rpm)
    }

    @Test func decodesFPE2RPM() {
        // 2000 rpm is 8000 in fpe2 fixed point.
        let bytes: [UInt8] = [0x1f, 0x40]
        #expect(SMCCodec.rpm(from: bytes, type: .fpe2) == 2000)
    }

    @Test func encodesFPE2RPM() {
        #expect(SMCCodec.rpmBytes(2000, type: .fpe2) == [0x1f, 0x40])
    }

    @Test func rejectsShortPayload() {
        #expect(SMCCodec.rpm(from: [0xff], type: .flt) == nil)
    }

    @Test func decodesSP78Temperature() {
        // 0x3a80 is 58.5 °C in signed 8.8 fixed point.
        #expect(SMCCodec.temperature(from: [0x3a, 0x80], type: .sp78) == 58.5)
    }
}

@Suite("SMC keys")
struct SMCKeyTests {
    @Test func packsBigEndian() {
        #expect(SMCKey("F0Ac").rawValue == 0x4630_4163)
    }

    @Test func roundTripsThroughString() {
        for name in ["FNum", "F0Md", "FS! ", "#KEY"] {
            #expect(SMCKey(name).string == name)
        }
    }

    @Test func decodesDataTypeFromMemoryOrder() {
        // The kernel hands the four type characters back in reversed memory
        // order, so `flt ` arrives with the bytes reading ` tlf`.
        let raw: UInt32 = 0x666c_7420
        #expect(SMCDataType(rawValue: raw).string == "flt ")
        #expect(SMCDataType("flt ").rawValue == raw)
    }
}

@Suite("Fan control resolution")
struct FanControlTests {
    private let fan = FanSnapshot(id: 0, name: "Fan 1", actualRPM: 1500,
                                  minimumRPM: 1000, maximumRPM: 5000,
                                  targetRPM: 1500, isForced: false)

    private let temperatures = [
        TemperatureReading(id: "hid:PMU tdie1", name: "PMU tdie1", celsius: 60, group: .cpu),
        TemperatureReading(id: "hid:PMU tdie2", name: "PMU tdie2", celsius: 80, group: .cpu),
        TemperatureReading(id: "hid:NAND", name: "NAND CH0 temp", celsius: 45, group: .storage),
    ]

    @Test func automaticProducesRelease() {
        let resolver = FanControlResolver()
        let command = resolver.command(for: fan, mode: .automatic, temperatures: temperatures)
        #expect(command?.forced == false)
    }

    @Test func constantClampsToRange() {
        let resolver = FanControlResolver()
        let low = resolver.command(for: fan, mode: .constant(rpm: 200), temperatures: [])
        let high = resolver.command(for: fan, mode: .constant(rpm: 99_000), temperatures: [])
        #expect(low?.rpm == 1000)
        #expect(high?.rpm == 5000)
    }

    @Test func sensorMapsBandToRange() {
        let resolver = FanControlResolver()
        let curve = FanControlMode.SensorCurve(sensorID: "cpu_average",
                                               startCelsius: 50,
                                               maxCelsius: 90)
        // CPU average is 70 °C, exactly halfway through the band.
        let command = resolver.command(for: fan, mode: .sensor(curve), temperatures: temperatures)
        #expect(command?.rpm == 3000)
        #expect(command?.forced == true)
    }

    @Test func sensorClampsOutsideBand() {
        let resolver = FanControlResolver()
        let curve = FanControlMode.SensorCurve(sensorID: "cpu_average",
                                               startCelsius: 90,
                                               maxCelsius: 100)
        let command = resolver.command(for: fan, mode: .sensor(curve), temperatures: temperatures)
        #expect(command?.rpm == 1000)
    }

    @Test func cpuAverageSkipsNonCPU() {
        #expect(TemperatureReader.cpuAverage(from: temperatures) == 70)
    }

    @Test func sensorLookupSupportsAliases() {
        #expect(TemperatureReader.value(forSensor: "cpu_average", readings: temperatures) == 70)
        #expect(TemperatureReader.value(forSensor: "hottest", readings: temperatures) == 80)
        #expect(TemperatureReader.value(forSensor: "NAND CH0 temp", readings: temperatures) == 45)
    }
}

@Suite("Preset persistence")
struct PresetTests {
    @Test func serializesToTheWireFormat() {
        let preset = FanPreset(name: "UNSAVED",
                               modes: [.sensor(.init(sensorID: "cpu_core_average",
                                                     startCelsius: 58,
                                                     maxCelsius: 80))])
        #expect(preset.serialized == "VU5TQVZFRHwyLGNwdV9jb3JlX2F2ZXJhZ2UsNTgsODA=")
    }

    @Test func parsesTheWireFormat() {
        let preset = FanPreset(serialized: "VU5TQVZFRHwyLGNwdV9jb3JlX2F2ZXJhZ2UsNTgsODA=")
        #expect(preset?.name == "UNSAVED")
        #expect(preset?.modes.count == 1)
        if case .sensor(let curve) = preset?.modes.first {
            #expect(curve.sensorID == "cpu_core_average")
            #expect(curve.startCelsius == 58)
            #expect(curve.maxCelsius == 80)
        } else {
            Issue.record("expected a sensor mode")
        }
    }

    @Test func handlesMixedModes() {
        let preset = FanPreset(name: "Mixed", modes: [.automatic, .constant(rpm: 1800),
                                                     .sensor(.init(sensorID: "hottest",
                                                                   startCelsius: 60,
                                                                   maxCelsius: 90))])
        let decoded = FanPreset(serialized: preset.serialized)
        #expect(decoded?.modes == preset.modes)
    }

    @Test func resizesToFanCount() {
        let preset = FanPreset.automatic(fanCount: 1)
        #expect(preset.resized(to: 3).modes.count == 3)
        #expect(preset.resized(to: 0).modes.isEmpty)
    }
}

@Suite("Control engine")
struct ControlEngineTests {
    private let fan = FanSnapshot(id: 0, name: "Fan 1", actualRPM: 1000,
                                  minimumRPM: 1000, maximumRPM: 5000,
                                  targetRPM: 1000, isForced: false)

    private func temperatures(_ celsius: Double) -> [TemperatureReading] {
        [TemperatureReading(id: "hid:cpu", name: "cpu", celsius: celsius, group: .cpu)]
    }

    @Test func emitsOnFirstEvaluation() {
        let engine = ControlEngine()
        let preset = FanPreset(name: "t", modes: [.constant(rpm: 2000)])
        let commands = engine.evaluate(preset: preset, fans: [fan], temperatures: [])
        #expect(commands.count == 1)
        #expect(commands.first?.rpm == 2000)
    }

    @Test func rateLimitsRepeatedWrites() {
        let engine = ControlEngine()
        let preset = FanPreset(name: "t", modes: [.constant(rpm: 2000)])
        let now = Date()
        _ = engine.evaluate(preset: preset, fans: [fan], temperatures: [], now: now)
        let repeated = engine.evaluate(preset: preset, fans: [fan], temperatures: [])
        #expect(repeated.isEmpty)
    }

    @Test func riseIsFasterThanFall() {
        let engine = ControlEngine()
        let curve = FanControlMode.SensorCurve(sensorID: "cpu_average",
                                               startCelsius: 40,
                                               maxCelsius: 90)
        let preset = FanPreset(name: "t", modes: [.sensor(curve)])
        let start = Date()

        // Prime at a cold reading so the first write lands at the minimum.
        _ = engine.evaluate(preset: preset, fans: [fan], temperatures: temperatures(30), now: start)

        let hot = engine.evaluate(preset: preset, fans: [fan],
                                  temperatures: temperatures(90), now: start.addingTimeInterval(2))
        #expect(hot.isEmpty == false)
        #expect((hot.first?.rpm ?? 0) > 1000)
    }

    @Test func automaticReleasesTheFan() {
        let engine = ControlEngine()
        let preset = FanPreset(name: "t", modes: [.automatic])
        let commands = engine.evaluate(preset: preset, fans: [fan], temperatures: [])
        #expect(commands.first?.forced == false)
    }
}
