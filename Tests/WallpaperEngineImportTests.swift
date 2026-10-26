// Copyright (c) 2026 Jed Brown
// SPDX-License-Identifier: GPL-3.0-only
// Part of Lucid: https://github.com/jedbrnth-eng/lucid-live-wallpaper

// Wallpaper Engine importer: project.json parsing, folder scanning, de-dupe, removal and Steam detection.
import Foundation

private var fixtures: URL {
    URL(fileURLWithPath: ProcessInfo.processInfo.environment["LUCID_FIXTURES"] ?? "Tests/Fixtures")
        .appendingPathComponent("wallpaper-engine", isDirectory: true)
}
private var workshop: URL { fixtures.appendingPathComponent("workshop/content/431960", isDirectory: true) }
private var myprojects: URL { fixtures.appendingPathComponent("myprojects", isDirectory: true) }

private func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("lucid-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

func registerWallpaperEngineImportTests() {
    test("WE.parse: video project.json with string workshop id") {
        let p = try WEProject.parse(Data(contentsOf: workshop.appendingPathComponent("1001/project.json")))
        expectEqual(p.title, "Neon Rain")
        expectEqual(p.type, .video)
        expectEqual(p.file, "neon-rain.mp4")
        expectEqual(p.preview, "preview.jpg")
        expectEqual(p.tags, ["Landscape", "Relaxing"])
        expectEqual(p.workshopID, "1001")
        expectEqual(p.description, "Rain on a neon street, 4K loop")
    }
    test("WE.parse: capitalised type and numeric workshop id") {
        let p = try WEProject.parse(Data(contentsOf: workshop.appendingPathComponent("1002/project.json")))
        expectEqual(p.type, .video)
        expectEqual(p.workshopID, "1002")
        expectEqual(p.description, nil, "empty description becomes nil")
    }
    test("WE.parse: web item keeps user property defaults as {name: {value}} JSON") {
        let p = try WEProject.parse(Data(contentsOf: workshop.appendingPathComponent("861750235/project.json")))
        expectEqual(p.type, .web)
        expectEqual(p.workshopID, "861750235")
        let props = try JSONSerialization.jsonObject(with: Data((p.userPropertiesJSON ?? "").utf8)) as? [String: Any]
        expectEqual((props?["customint"] as? [String: Any])?["value"] as? Int, 20)
        expectEqual((props?["showclock"] as? [String: Any])?["value"] as? Bool, true)
        expectEqual((props?["schemecolor"] as? [String: Any])?["value"] as? String, "0.56 0.31 0.58")
    }
    test("WE.parse: malformed JSON throws") {
        var threw = false
        do { _ = try WEProject.parse(Data(contentsOf: workshop.appendingPathComponent("1006/project.json"))) } catch { threw = true }
        expect(threw)
    }
    test("WE.parse: unknown type maps to .unknown and keeps raw value") {
        let p = try WEProject.parse(Data(#"{"type":"preset","title":"x"}"#.utf8))
        expectEqual(p.type, .unknown)
        expectEqual(p.rawType, "preset")
    }

    test("WE.scan: workshop folder classifies every item honestly") {
        let r = WEScanner.scan(roots: [workshop])
        let byID = Dictionary(uniqueKeysWithValues: r.entries.map { ($0.workshopID ?? $0.id, $0) })
        expectEqual(r.entries.count, 7, "1001 1002 861750235 1004 1005 1008 1009; 1006 malformed, 1007 has no project.json")
        expectEqual(r.errors.count, 1, "the malformed project.json is reported")
        expectEqual(byID["1001"]?.support, .video)
        expectEqual(byID["1001"]?.needsConversion, false)
        expect(byID["1001"]?.mainFile?.hasSuffix("1001/neon-rain.mp4") ?? false)
        expect(byID["1001"]?.previewFile?.hasSuffix("1001/preview.jpg") ?? false)
        expectEqual(byID["1002"]?.support, .video)
        expectEqual(byID["1002"]?.needsConversion, true, "WebM needs HEVC conversion")
        expectEqual(byID["861750235"]?.support, .web)
        expect(byID["861750235"]?.mainFile?.hasSuffix("index.html") ?? false)
        expectEqual(byID["1004"]?.support, .unsupported)
        expectEqual(byID["1004"]?.type, .scene)
        expect(byID["1004"]?.fallbackPreview?.hasSuffix("preview.gif") ?? false, "animated scene preview kept as a labelled fallback")
        expectEqual(byID["1004"]?.mainFile, nil, "a scene never gets a playable main file")
        expectEqual(byID["1005"]?.support, .unsupported)
        expectEqual(byID["1005"]?.type, .application)
        expectEqual(byID["1008"]?.support, .unsupported, "video whose file is missing")
        expect(byID["1008"]?.note.localizedCaseInsensitiveContains("missing") ?? false)
        expectEqual(byID["1009"]?.support, .unsupported)
        let c = r.counts
        expectEqual(c.video, 2); expectEqual(c.web, 1); expectEqual(c.unsupported, 4)
    }
    test("WE.scan: ids are stable and namespaced by workshop id") {
        let r = WEScanner.scan(roots: [workshop])
        expect(r.entries.contains { $0.id == "we:1001" })
        expect(r.entries.allSatisfy { $0.id.hasPrefix("we:") })
        let again = WEScanner.scan(roots: [workshop])
        expectEqual(r.entries.map(\.id), again.entries.map(\.id))
    }
    test("WE.scan: myprojects folder without workshop id gets a path-based id and a folder title") {
        let r = WEScanner.scan(roots: [myprojects])
        let loop = r.entries.first { $0.folder.hasSuffix("my-loop") }
        expect(loop != nil)
        expectEqual(loop?.title, "My Loop", "empty title falls back to the folder name")
        expect(loop?.id.hasPrefix("we:local:") ?? false)
        expectEqual(loop?.support, .video)
    }
    test("WE.scan: de-dupes by workshop id across folders (first root wins)") {
        let r = WEScanner.scan(roots: [workshop, myprojects])
        expectEqual(r.entries.filter { $0.workshopID == "1001" }.count, 1)
        expectEqual(r.entries.first { $0.workshopID == "1001" }?.title, "Neon Rain")
        expectEqual(r.entries.count, 8)
    }
    test("WE.scan: accepts a parent folder, a single item folder, and the same root twice") {
        expectEqual(WEScanner.scan(roots: [fixtures]).entries.count, 8, "parent holding workshop/content/431960 and myprojects")
        expectEqual(WEScanner.scan(roots: [workshop.appendingPathComponent("1001")]).entries.map(\.id), ["we:1001"])
        expectEqual(WEScanner.scan(roots: [workshop, workshop]).entries.count, 7)
    }
    test("WE.scan: missing root yields nothing, no crash") {
        let r = WEScanner.scan(roots: [URL(fileURLWithPath: "/nonexistent/lucid/431960")])
        expectEqual(r.entries.count, 0)
    }
    test("WE.sync: a vanished folder is removed on rescan, and the diff reports it") {
        let tmp = tempDir(); defer { try? FileManager.default.removeItem(at: tmp) }
        let root = tmp.appendingPathComponent("431960")
        try FileManager.default.copyItem(at: workshop, to: root)
        let before = WEScanner.scan(roots: [root]).entries
        try FileManager.default.removeItem(at: root.appendingPathComponent("1001"))
        let after = WEScanner.scan(roots: [root]).entries
        expectEqual(after.count, before.count - 1)
        let d = WESync.diff(old: before, new: after)
        expectEqual(d.removed.map(\.id), ["we:1001"])
        expectEqual(d.added.count, 0)
        let d2 = WESync.diff(old: after, new: before)
        expectEqual(d2.added.map(\.id), ["we:1001"])
    }
    test("WE.steam: parses libraryfolders.vdf paths, including escaped Windows paths") {
        let vdf = """
        "libraryfolders"
        {
        \t"0"
        \t{
        \t\t"path"\t\t"/Users/demo/Library/Application Support/Steam"
        \t\t"label"\t\t""
        \t\t"apps" { "431960" "123" }
        \t}
        \t"1"
        \t{
        \t\t"path"\t\t"D:\\\\SteamLibrary"
        \t}
        }
        """
        expectEqual(WEScanner.parseLibraryFolders(vdf), ["/Users/demo/Library/Application Support/Steam", "D:\\SteamLibrary"])
    }
    test("WE.steam: auto-detects the Mac Steam default path and extra library folders") {
        let home = tempDir(); defer { try? FileManager.default.removeItem(at: home) }
        let fm = FileManager.default
        let steam = home.appendingPathComponent("Library/Application Support/Steam")
        let extra = home.appendingPathComponent("ExternalLibrary")
        let item = extra.appendingPathComponent("steamapps/workshop/content/431960/2001")
        try fm.createDirectory(at: item, withIntermediateDirectories: true)
        try Data(#"{"type":"video","file":"a.mp4","title":"Ext","workshopid":"2001"}"#.utf8).write(to: item.appendingPathComponent("project.json"))
        try Data("x".utf8).write(to: item.appendingPathComponent("a.mp4"))
        try fm.createDirectory(at: steam.appendingPathComponent("steamapps"), withIntermediateDirectories: true)
        try Data("\"libraryfolders\" { \"1\" { \"path\" \"\(extra.path)\" } }".utf8)
            .write(to: steam.appendingPathComponent("steamapps/libraryfolders.vdf"))
        expectEqual(WEScanner.detectSteamFolders(home: home).map(\.standardizedFileURL.path),
                    [extra.appendingPathComponent("steamapps/workshop/content/431960").standardizedFileURL.path])
        let empty = tempDir(); defer { try? FileManager.default.removeItem(at: empty) }
        expectEqual(WEScanner.detectSteamFolders(home: empty).count, 0, "no Steam, no folders")
    }
}
