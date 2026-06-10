import Foundation
import Combine

class ZoneSettingsManager: ObservableObject {
    @Published var z1Enabled: Bool  { didSet { UserDefaults.standard.set(z1Enabled,         forKey: "z1Enabled") } }
    @Published var z1Name: String   { didSet { UserDefaults.standard.set(z1Name,             forKey: "z1Name") } }
    @Published var z1Start: Int     { didSet { UserDefaults.standard.set(z1Start,            forKey: "z1Start") } }
    @Published var z1End: Int       { didSet { UserDefaults.standard.set(z1End,              forKey: "z1End") } }
    @Published var z2Enabled: Bool  { didSet { UserDefaults.standard.set(z2Enabled,         forKey: "z2Enabled") } }
    @Published var z2Name: String   { didSet { UserDefaults.standard.set(z2Name,             forKey: "z2Name") } }
    @Published var z2Start: Int     { didSet { UserDefaults.standard.set(z2Start,            forKey: "z2Start") } }
    @Published var z2End: Int       { didSet { UserDefaults.standard.set(z2End,              forKey: "z2End") } }
    @Published var z3Enabled: Bool  { didSet { UserDefaults.standard.set(z3Enabled,         forKey: "z3Enabled") } }
    @Published var z3Name: String   { didSet { UserDefaults.standard.set(z3Name,             forKey: "z3Name") } }
    @Published var z3Start: Int     { didSet { UserDefaults.standard.set(z3Start,            forKey: "z3Start") } }
    @Published var z3End: Int       { didSet { UserDefaults.standard.set(z3End,              forKey: "z3End") } }
    @Published var zoneGapEnabled: Bool     { didSet { UserDefaults.standard.set(zoneGapEnabled,     forKey: "zoneGapEnabled") } }
    @Published var showZoneWatermarks: Bool { didSet { UserDefaults.standard.set(showZoneWatermarks, forKey: "showZoneWatermarks") } }

    init() {
        let ud = UserDefaults.standard
        z1Enabled          = ud.object(forKey: "z1Enabled")          as? Bool   ?? true
        z1Name             = ud.string(forKey: "z1Name")                         ?? "Zone 1"
        z1Start            = ud.object(forKey: "z1Start")            as? Int    ?? 7
        z1End              = ud.object(forKey: "z1End")              as? Int    ?? 11
        z2Enabled          = ud.object(forKey: "z2Enabled")          as? Bool   ?? true
        z2Name             = ud.string(forKey: "z2Name")                         ?? "Zone 2"
        z2Start            = ud.object(forKey: "z2Start")            as? Int    ?? 13
        z2End              = ud.object(forKey: "z2End")              as? Int    ?? 17
        z3Enabled          = ud.object(forKey: "z3Enabled")          as? Bool   ?? true
        z3Name             = ud.string(forKey: "z3Name")                         ?? "Zone 3"
        z3Start            = ud.object(forKey: "z3Start")            as? Int    ?? 19
        z3End              = ud.object(forKey: "z3End")              as? Int    ?? 23
        zoneGapEnabled     = ud.object(forKey: "zoneGapEnabled")     as? Bool   ?? false
        showZoneWatermarks = ud.object(forKey: "showZoneWatermarks") as? Bool   ?? true
    }
}
