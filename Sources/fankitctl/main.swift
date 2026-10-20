import FanKitCore
import Foundation

// Smoke test: prove the SMC and HID paths work on this machine.
do {
    let connection = try SMCConnection()
    let reader = FanReader(connection: connection)

    let count = try reader.fanCount()
    print("fanCount=\(count)")

    for fan in try reader.snapshots() {
        print(String(format: "fan %d %@ actual=%.0f min=%.0f max=%.0f target=%.0f forced=%@",
                     fan.id, fan.name, fan.actualRPM, fan.minimumRPM,
                     fan.maximumRPM, fan.targetRPM, fan.isForced ? "yes" : "no"))
    }

    let temps = TemperatureReader.readHID()
    print("temperatures=\(temps.count)")
    for reading in temps.sorted(by: { $0.celsius > $1.celsius }).prefix(8) {
        print(String(format: "  %-28@ %6.2f °C  [%@]",
                     reading.name as NSString, reading.celsius,
                     reading.group.displayName as NSString))
    }
} catch {
    print("error: \(error)")
    exit(1)
}
