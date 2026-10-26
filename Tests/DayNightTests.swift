// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Sunrise/sunset (NOAA) and the day/night schedule. Every clock is injected; no test reads the real time.
// Reference times: api.sunrise-sunset.org (fetched 2026-10-26), tolerance ±2 minutes.
import Foundation

private func utc(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
private func tz(_ id: String) -> TimeZone { TimeZone(identifier: id)! }
private let bangkok = (lat: 13.7563, lon: 100.5018)
private let newYork = (lat: 40.7128, lon: -74.0060)
private let london = (lat: 51.5074, lon: -0.1278)
private let tromso = (lat: 69.6492, lon: 18.9553)

private func times(_ r: SunEvent) -> (Date, Date)? { if case .normal(let a, let b) = r { return (a, b) }; return nil }
private func localHM(_ d: Date, _ z: TimeZone) -> String {
    var c = Calendar(identifier: .gregorian); c.timeZone = z
    let x = c.dateComponents([.hour, .minute], from: d)
    return String(format: "%02d:%02d", x.hour!, x.minute!)
}

func registerDayNightTests() {
    test("Sun: Bangkok 2026-10-26 sunrise 06:10:46, sunset 17:53:11 local") {
        let r = SunTimes.calculate(year: 2026, month: 10, day: 26, latitude: bangkok.lat, longitude: bangkok.lon, timeZone: tz("Asia/Bangkok"))
        guard let (rise, set) = times(r) else { expect(false, "expected normal day, got \(r)"); return }
        expectNear(rise.timeIntervalSince(utc("2026-10-25T23:10:46Z")), 0, 120, "sunrise falls on the previous UTC day")
        expectNear(set.timeIntervalSince(utc("2026-10-26T10:53:11Z")), 0, 120)
    }
    test("Sun: New York across the DST switch (2026-03-07 EST vs 2026-03-08 EDT)") {
        let z = tz("America/New_York")
        let a = times(SunTimes.calculate(year: 2026, month: 3, day: 7, latitude: newYork.lat, longitude: newYork.lon, timeZone: z))!
        let b = times(SunTimes.calculate(year: 2026, month: 3, day: 8, latitude: newYork.lat, longitude: newYork.lon, timeZone: z))!
        expectNear(a.0.timeIntervalSince(utc("2026-03-07T11:19:59Z")), 0, 120)
        expectNear(b.0.timeIntervalSince(utc("2026-03-08T11:18:24Z")), 0, 120)
        expectNear(b.1.timeIntervalSince(utc("2026-03-08T22:55:03Z")), 0, 120)
        expectEqual(localHM(a.0, z).prefix(3), "06:", "EST: ~06:20")
        expectEqual(localHM(b.0, z).prefix(3), "07:", "EDT: ~07:18, the wall clock jumps an hour, the sun does not")
    }
    test("Sun: London on the BST start day 2026-03-29") {
        let r = times(SunTimes.calculate(year: 2026, month: 3, day: 29, latitude: london.lat, longitude: london.lon, timeZone: tz("Europe/London")))!
        expectNear(r.0.timeIntervalSince(utc("2026-03-29T05:42:09Z")), 0, 120)
        expectNear(r.1.timeIntervalSince(utc("2026-03-29T18:28:22Z")), 0, 120)
    }
    test("Sun: polar day and polar night in Tromsø") {
        let z = tz("Europe/Oslo")
        expectEqual(SunTimes.calculate(year: 2026, month: 6, day: 21, latitude: tromso.lat, longitude: tromso.lon, timeZone: z), .polarDay)
        expectEqual(SunTimes.calculate(year: 2026, month: 12, day: 21, latitude: tromso.lat, longitude: tromso.lon, timeZone: z), .polarNight)
    }

    let bkk = tz("Asia/Bangkok")
    let auto = DayNightSchedule(mode: .sun(latitude: bangkok.lat, longitude: bangkok.lon), timeZone: bkk)
    test("Schedule: Bangkok phases through a day (sunrise ~06:10, sunset ~17:53)") {
        expectEqual(auto.phase(at: utc("2026-10-26T05:00:00Z")), .day, "12:00 local")
        expectEqual(auto.phase(at: utc("2026-10-26T15:00:00Z")), .night, "22:00 local")
        expectEqual(auto.phase(at: utc("2026-10-25T22:00:00Z")), .night, "05:00 local, before sunrise")
    }
    test("Schedule: clock set to exactly sunrise is day; one second before is night") {
        let (rise, set) = times(SunTimes.calculate(year: 2026, month: 10, day: 26, latitude: bangkok.lat, longitude: bangkok.lon, timeZone: bkk))!
        expectEqual(auto.phase(at: rise), .day)
        expectEqual(auto.phase(at: rise.addingTimeInterval(-1)), .night)
        expectEqual(auto.phase(at: set), .night, "exactly sunset is night")
        expectEqual(auto.nextChange(after: rise.addingTimeInterval(-1)), rise)
        expectEqual(auto.nextChange(after: rise), set)
    }
    test("Schedule: midnight crossover, next change after 23:30 is tomorrow's sunrise") {
        let lateNight = utc("2026-10-26T16:30:00Z")   // 23:30 Bangkok
        let next = auto.nextChange(after: lateNight)!
        let tomorrow = times(SunTimes.calculate(year: 2026, month: 10, day: 27, latitude: bangkok.lat, longitude: bangkok.lon, timeZone: bkk))!.0
        expectEqual(next, tomorrow)
        expectEqual(auto.phase(at: utc("2026-10-26T17:00:30Z")), .night, "00:00:30 local")
    }
    test("Schedule: manual times that wrap midnight (night 19:00 → day 07:00)") {
        let m = DayNightSchedule(mode: .manual(dayStartMinute: 7 * 60, nightStartMinute: 19 * 60), timeZone: bkk)
        expectEqual(m.phase(at: utc("2026-10-26T16:59:00Z")), .night, "23:59")
        expectEqual(m.phase(at: utc("2026-10-26T17:01:00Z")), .night, "00:01")
        expectEqual(m.phase(at: utc("2026-10-26T23:59:59Z")), .night, "06:59:59")
        expectEqual(m.phase(at: utc("2026-10-27T00:00:00Z")), .day, "07:00:00 exactly")
        expectEqual(m.phase(at: utc("2026-10-27T11:59:59Z")), .day, "18:59:59")
        expectEqual(m.phase(at: utc("2026-10-27T12:00:00Z")), .night, "19:00 exactly")
        expectEqual(m.nextChange(after: utc("2026-10-26T16:00:00Z")), utc("2026-10-27T00:00:00Z"), "23:00 -> 07:00 tomorrow")
        let inverted = DayNightSchedule(mode: .manual(dayStartMinute: 20 * 60, nightStartMinute: 4 * 60), timeZone: bkk)
        expectEqual(inverted.phase(at: utc("2026-10-26T17:00:00Z")), .day, "day window that itself wraps midnight")
    }
    test("Schedule: manual times follow the wall clock across a DST change") {
        let ny = tz("America/New_York")
        let m = DayNightSchedule(mode: .manual(dayStartMinute: 7 * 60, nightStartMinute: 19 * 60), timeZone: ny)
        expectEqual(m.nextChange(after: utc("2026-03-08T04:00:00Z")), utc("2026-03-08T11:00:00Z"), "07:00 EDT on the switch day")
        expectEqual(m.phase(at: utc("2026-03-08T11:30:00Z")), .day)
    }
    test("Schedule: timezone change re-evaluates the same instant") {
        let instant = utc("2026-10-26T12:00:00Z")   // 19:00 Bangkok, 08:00 New York (EDT)
        let m1 = DayNightSchedule(mode: .manual(dayStartMinute: 7 * 60, nightStartMinute: 19 * 60), timeZone: bkk)
        let m2 = DayNightSchedule(mode: .manual(dayStartMinute: 7 * 60, nightStartMinute: 19 * 60), timeZone: tz("America/New_York"))
        expectEqual(m1.phase(at: instant), .night)
        expectEqual(m2.phase(at: instant), .day)
    }
    test("Schedule: polar day/night is constant and re-checks at the next local midnight") {
        let oslo = tz("Europe/Oslo")
        let s = DayNightSchedule(mode: .sun(latitude: tromso.lat, longitude: tromso.lon), timeZone: oslo)
        expectEqual(s.phase(at: utc("2026-06-21T22:00:00Z")), .day, "midnight sun")
        expectEqual(s.phase(at: utc("2026-12-21T11:00:00Z")), .night, "polar night at noon")
        expectEqual(s.nextChange(after: utc("2026-06-21T10:00:00Z")), utc("2026-06-21T22:00:00Z"), "next local midnight (CEST)")
    }
    test("Coordinates: zone.tab ISO 6709 parsing (minutes and seconds forms)") {
        let tab = """
        # comment
        TH\t+1345+10031\tAsia/Bangkok
        US\t+404251-0740023\tAmerica/New_York\tEastern (most areas)
        """
        let c = TimeZoneCoordinates.parse(zoneTab: tab)
        expectNear(c["Asia/Bangkok"]!.latitude, 13.75, 0.01); expectNear(c["Asia/Bangkok"]!.longitude, 100.5167, 0.01)
        expectNear(c["America/New_York"]!.latitude, 40.7142, 0.001); expectNear(c["America/New_York"]!.longitude, -74.0064, 0.001)
        expectEqual(c.count, 2)
    }
    test("Coordinates: Bangkok from the timezone, offset fallback for unknown zones") {
        let tab = "TH\t+1345+10031\tAsia/Bangkok\n"
        let b = TimeZoneCoordinates.coordinates(for: tz("Asia/Bangkok"), zoneTab: tab)
        expectNear(b.latitude, 13.75, 0.01); expectEqual(b.approximate, false)
        let f = TimeZoneCoordinates.coordinates(for: TimeZone(secondsFromGMT: 7 * 3600)!, zoneTab: tab)
        expectNear(f.longitude, 105, 0.001); expectEqual(f.approximate, true)
    }
}
