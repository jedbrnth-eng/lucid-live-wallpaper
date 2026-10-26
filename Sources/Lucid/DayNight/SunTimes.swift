// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Sunrise/sunset (NOAA solar calculator equations) and the day/night schedule used by Day/Night wallpapers.
// Pure: the caller passes the date, location and time zone, so it is fully unit-tested with a fake clock.
// Equations: NOAA Global Monitoring Laboratory solar calculator, https://gml.noaa.gov/grad/solcalc/ (public domain).
import Foundation

enum SunEvent: Equatable {
    case normal(sunrise: Date, sunset: Date)
    case polarDay     // sun never sets on this date
    case polarNight   // sun never rises on this date
}

enum SunTimes {
    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = Double(year), m = Double(month)
        if m <= 2 { y -= 1; m += 12 }
        let a = floor(y / 100), b = 2 - a + floor(a / 4)
        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + Double(day) + b - 1524.5
    }

    /// Declination (degrees) and equation of time (minutes) at Julian century `t`.
    private static func solar(_ t: Double) -> (decl: Double, eqTime: Double) {
        let l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(rad(2 * m)) * (0.019993 - 0.000101 * t) + sin(rad(3 * m)) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let lambda = l0 + c - 0.00569 - 0.00478 * sin(rad(omega))
        let e0 = 23 + (26 + (21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = e0 + 0.00256 * cos(rad(omega))
        let decl = deg(asin(sin(rad(eps)) * sin(rad(lambda))))
        let y = pow(tan(rad(eps) / 2), 2)
        let eq = y * sin(2 * rad(l0)) - 2 * e * sin(rad(m)) + 4 * e * y * sin(rad(m)) * cos(2 * rad(l0))
            - 0.5 * y * y * sin(4 * rad(l0)) - 1.25 * e * e * sin(2 * rad(m))
        return (decl, deg(eq) * 4)
    }

    /// cos(hour angle) of sunrise; > 1 means no sunrise (polar night), < -1 means no sunset (polar day).
    private static func cosHourAngle(_ lat: Double, _ decl: Double) -> Double {
        cos(rad(90.833)) / (cos(rad(lat)) * cos(rad(decl))) - tan(rad(lat)) * tan(rad(decl))
    }

    /// Minutes after 00:00 UTC of the given calendar date (may be negative or > 1440).
    private static func eventMinutes(rise: Bool, jd: Double, lat: Double, lon: Double) -> Double? {
        func once(_ jdAt: Double) -> Double? {
            let t = (jdAt - 2451545.0) / 36525
            let s = solar(t)
            let c = cosHourAngle(lat, s.decl)
            guard c >= -1, c <= 1 else { return nil }
            let ha = deg(acos(c)) * (rise ? 1 : -1)
            return 720 - 4 * (lon + ha) - s.eqTime
        }
        guard let first = once(jd + 0.5) else { return nil }
        return once(jd + first / 1440) ?? first   // refine at the event time itself
    }

    /// Sunrise and sunset for a local calendar date. `longitude` is positive east (Bangkok ≈ +100.5).
    static func calculate(year: Int, month: Int, day: Int, latitude: Double, longitude: Double, timeZone: TimeZone) -> SunEvent {
        let lat = min(89.8, max(-89.8, latitude))
        let jd = julianDay(year: year, month: month, day: day)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        guard let midnightUTC = utc.date(from: DateComponents(year: year, month: month, day: day)) else { return .polarNight }
        if let r = eventMinutes(rise: true, jd: jd, lat: lat, lon: longitude),
           let s = eventMinutes(rise: false, jd: jd, lat: lat, lon: longitude) {
            return .normal(sunrise: midnightUTC.addingTimeInterval(r * 60), sunset: midnightUTC.addingTimeInterval(s * 60))
        }
        let noon = solar((jd + 0.5 - 2451545.0) / 36525)
        return cosHourAngle(lat, noon.decl) < -1 ? .polarDay : .polarNight
    }
}

enum DayPhase: String, Codable { case day, night }

struct DayNightSchedule {
    enum Mode: Equatable {
        case sun(latitude: Double, longitude: Double)
        case manual(dayStartMinute: Int, nightStartMinute: Int)   // minutes after local midnight
    }
    var mode: Mode
    var timeZone: TimeZone

    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }

    func sunEvent(onLocalDayOf d: Date) -> SunEvent? {
        guard case .sun(let lat, let lon) = mode else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return SunTimes.calculate(year: c.year!, month: c.month!, day: c.day!, latitude: lat, longitude: lon, timeZone: timeZone)
    }

    func phase(at d: Date) -> DayPhase {
        switch mode {
        case .sun:
            switch sunEvent(onLocalDayOf: d)! {
            case .normal(let rise, let set): return rise <= d && d < set ? .day : .night
            case .polarDay: return .day
            case .polarNight: return .night
            }
        case .manual(let dayStart, let nightStart):
            let c = calendar.dateComponents([.hour, .minute, .second], from: d)
            let m = Double(c.hour! * 60 + c.minute!) + Double(c.second!) / 60
            let ds = Double(dayStart), ns = Double(nightStart)
            if ds == ns { return .day }
            return ds < ns ? (m >= ds && m < ns ? .day : .night) : (m >= ds || m < ns ? .day : .night)
        }
    }

    /// The next instant strictly after `d` at which the phase may change.
    func nextChange(after d: Date) -> Date? {
        let cal = calendar
        let today = cal.startOfDay(for: d)
        var candidates: [Date] = []
        for offset in 0...2 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            switch mode {
            case .sun:
                switch sunEvent(onLocalDayOf: day.addingTimeInterval(12 * 3600))! {
                case .normal(let r, let s): candidates += [r, s]
                case .polarDay, .polarNight: if offset <= 1, let next = cal.date(byAdding: .day, value: 1, to: day) { candidates.append(next) }
                }
            case .manual(let ds, let ns):
                for m in [ds, ns] {
                    if let t = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day) { candidates.append(t) }
                }
            }
        }
        return candidates.filter { $0 > d }.min() ?? cal.date(byAdding: .day, value: 1, to: today)
    }
}

/// Approximate coordinates for a time zone from the system's zone.tab (no location permission needed).
enum TimeZoneCoordinates {
    struct Coord: Equatable { var latitude: Double; var longitude: Double; var approximate: Bool }

    static func parseISO6709(_ s: String) -> (Double, Double)? {
        let chars = Array(s)
        guard chars.count > 2, let split = chars.indices.dropFirst().first(where: { chars[$0] == "+" || chars[$0] == "-" }) else { return nil }
        func dms(_ part: ArraySlice<Character>, degDigits: Int) -> Double? {
            guard let sign = part.first, sign == "+" || sign == "-" else { return nil }
            let digits = String(part.dropFirst())
            guard digits.allSatisfy(\.isNumber), digits.count == degDigits + 2 || digits.count == degDigits + 4 else { return nil }
            let a = Array(digits)
            let d = Double(String(a[0..<degDigits]))!, m = Double(String(a[degDigits..<degDigits + 2]))!
            let s = a.count > degDigits + 2 ? Double(String(a[(degDigits + 2)...]))! : 0
            return (sign == "-" ? -1 : 1) * (d + m / 60 + s / 3600)
        }
        guard let lat = dms(chars[..<split], degDigits: 2), let lon = dms(chars[split...], degDigits: 3) else { return nil }
        return (lat, lon)
    }

    /// zone.tab lines: `CC<TAB>±DDMM±DDDMM[SS]<TAB>Zone/Name[<TAB>comment]`.
    static func parse(zoneTab: String) -> [String: Coord] {
        var out: [String: Coord] = [:]
        for line in zoneTab.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let f = line.split(separator: "\t")
            guard f.count >= 3, let c = parseISO6709(String(f[1])) else { continue }
            out[String(f[2])] = Coord(latitude: c.0, longitude: c.1, approximate: false)
        }
        return out
    }

    static let systemZoneTab = "/usr/share/zoneinfo/zone.tab"

    /// Known zone -> its reference city. Unknown -> longitude from the UTC offset (15° per hour), latitude 0, marked approximate.
    static func coordinates(for tz: TimeZone, zoneTab: String?) -> Coord {
        if let tab = zoneTab, let c = parse(zoneTab: tab)[tz.identifier] { return c }
        return Coord(latitude: 0, longitude: Double(tz.secondsFromGMT()) / 240, approximate: true)
    }
}
