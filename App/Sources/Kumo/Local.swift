import Foundation
import Compression

// MARK: - Device downloads (chapters saved as page images under Documents/Kumo/downloads/<mangaId>/<chapterId>/)

struct LocalChapter: Codable, Identifiable, Hashable {
    var mangaId: Int; var mangaTitle: String; var thumbnailUrl: String?
    var chapterId: Int; var chapterName: String; var chapterNumber: Double; var sourceOrder: Int
    var pageCount: Int; var bytes: Int; var date: Date
    var id: Int { chapterId }
}

@MainActor
final class DeviceStore: ObservableObject {
    static let shared = DeviceStore()
    @Published private(set) var chapters: [Int: LocalChapter] = [:]
    @Published var queue: [(manga: Manga, chapter: Chapter)] = []
    @Published var progress: [Int: Double] = [:]
    @Published var lastError: String?
    private var running = false

    static let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let root = docs.appendingPathComponent("Kumo", isDirectory: true)
    static let downloads = root.appendingPathComponent("downloads", isDirectory: true)
    static let local = root.appendingPathComponent("Local", isDirectory: true)   // CBZ/ZIP dropped in via the web server / Files app
    private let index = root.appendingPathComponent("downloads.json")

    init() {
        try? FileManager.default.createDirectory(at: DeviceStore.downloads, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: DeviceStore.local, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: index), let l = try? JSONDecoder().decode([LocalChapter].self, from: d) { chapters = Dictionary(uniqueKeysWithValues: l.map { ($0.chapterId, $0) }) }
    }
    private func save() { if let d = try? JSONEncoder().encode(Array(chapters.values)) { try? d.write(to: index) } }

    func dir(_ mangaId: Int, _ chapterId: Int) -> URL { DeviceStore.downloads.appendingPathComponent("\(mangaId)/\(chapterId)", isDirectory: true) }
    func has(_ chapterId: Int) -> Bool { chapters[chapterId] != nil }
    func pages(_ chapterId: Int) -> [URL] {
        guard let c = chapters[chapterId] else { return [] }
        let d = dir(c.mangaId, chapterId)
        return ((try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("p") }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func mangaCount(_ mangaId: Int) -> Int { chapters.values.filter { $0.mangaId == mangaId }.count }
    var totalBytes: Int { chapters.values.reduce(0) { $0 + $1.bytes } }
    var byManga: [(id: Int, title: String, thumb: String?, chapters: [LocalChapter])] {
        Dictionary(grouping: chapters.values, by: { $0.mangaId }).map { (id: $0.key, title: $0.value[0].mangaTitle, thumb: $0.value[0].thumbnailUrl, chapters: $0.value.sorted { $0.sourceOrder > $1.sourceOrder }) }.sorted { $0.title < $1.title }
    }

    func enqueue(_ manga: Manga, _ chs: [Chapter]) {
        for c in chs where !has(c.id) && !queue.contains(where: { $0.chapter.id == c.id }) { queue.append((manga, c)) }
        run()
    }
    func remove(_ chapterId: Int) {
        queue.removeAll { $0.chapter.id == chapterId }
        if let c = chapters[chapterId] { try? FileManager.default.removeItem(at: dir(c.mangaId, chapterId)); chapters[chapterId] = nil; save() }
    }
    func removeManga(_ mangaId: Int) { for c in chapters.values where c.mangaId == mangaId { remove(c.chapterId) } }

    private func run() {
        guard !running, let job = queue.first else { return }
        running = true
        Task {
            do {
                let api = API.shared
                let paths = try await api.pages(job.chapter.id)
                let d = dir(job.manga.id, job.chapter.id)
                try? FileManager.default.removeItem(at: d)
                try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
                var bytes = 0
                let urls = paths.map { api.img($0) }
                try await withThrowingTaskGroup(of: (Int, Int).self) { group in
                    var i = 0
                    func add(_ idx: Int) {
                        guard idx < urls.count, let u = urls[idx] else { return }
                        group.addTask {
                            let (tmp, resp) = try await URLSession.shared.download(from: u)
                            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.http((resp as? HTTPURLResponse)?.statusCode ?? 0) }
                            let ext = (resp.mimeType ?? "").contains("png") ? "png" : (resp.mimeType ?? "").contains("webp") ? "webp" : (resp.mimeType ?? "").contains("gif") ? "gif" : "jpg"
                            let dest = d.appendingPathComponent(String(format: "p%04d.%@", idx, ext))
                            try? FileManager.default.removeItem(at: dest)
                            try FileManager.default.moveItem(at: tmp, to: dest)
                            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
                            return (idx, size)
                        }
                    }
                    while i < min(3, paths.count) { add(i); i += 1 }
                    var done = 0
                    for try await (_, size) in group {
                        bytes += size; done += 1
                        progress[job.chapter.id] = Double(done) / Double(max(1, paths.count))
                        if i < paths.count { add(i); i += 1 }
                    }
                }
                chapters[job.chapter.id] = LocalChapter(mangaId: job.manga.id, mangaTitle: job.manga.title, thumbnailUrl: job.manga.thumbnailUrl, chapterId: job.chapter.id, chapterName: job.chapter.name, chapterNumber: job.chapter.chapterNumber, sourceOrder: job.chapter.sourceOrder, pageCount: paths.count, bytes: bytes, date: Date())
                save()
            } catch {
                lastError = "\(job.chapter.name): \(error.localizedDescription)"
            }
            progress[job.chapter.id] = nil
            queue.removeAll { $0.chapter.id == job.chapter.id }
            running = false
            run()
        }
    }

    // MARK: Local (CBZ) library on the device: Local/<Manga>/<file>.cbz
    struct LocalBook: Identifiable, Hashable { var folder: String; var files: [URL]; var id: String { folder } }
    func localBooks() -> [LocalBook] {
        let fm = FileManager.default
        let dirs = ((try? fm.contentsOfDirectory(at: DeviceStore.local, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
        var out: [LocalBook] = []
        for d in dirs {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: d.path, isDirectory: &isDir), isDir.boolValue {
                let files = ((try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []).filter { ["cbz", "zip"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                out.append(LocalBook(folder: d.lastPathComponent, files: files))
            } else if ["cbz", "zip"].contains(d.pathExtension.lowercased()) {
                out.append(LocalBook(folder: d.deletingPathExtension().lastPathComponent, files: [d]))
            }
        }
        return out
    }
}

// MARK: - Minimal ZIP (CBZ) reader: central directory + stored/deflate entries, images only.

struct ZipEntry { let name: String; let method: UInt16; let compressed: Int; let uncompressed: Int; let localHeaderOffset: Int }

final class CBZ {
    let url: URL
    let data: Data
    private(set) var entries: [ZipEntry] = []
    init?(url: URL) {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.url = url; self.data = d
        guard parse() else { return nil }
    }
    private func u16(_ o: Int) -> UInt16 { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) } }
    private func u32(_ o: Int) -> UInt32 { data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) } }
    private func parse() -> Bool {
        let n = data.count; guard n > 22 else { return false }
        var eocd = -1
        var i = n - 22
        while i >= max(0, n - 66000) { if u32(i) == 0x06054b50 { eocd = i; break }; i -= 1 }
        guard eocd >= 0 else { return false }
        let count = Int(u16(eocd + 10)); var off = Int(u32(eocd + 16))
        let imgExt: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "heic", "avif"]
        for _ in 0..<count {
            guard off + 46 <= n, u32(off) == 0x02014b50 else { break }
            let method = u16(off + 10), csize = Int(u32(off + 20)), usize = Int(u32(off + 24))
            let nlen = Int(u16(off + 28)), elen = Int(u16(off + 30)), clen = Int(u16(off + 32))
            let lho = Int(u32(off + 42))
            let name = String(data: data.subdata(in: (off + 46)..<(off + 46 + nlen)), encoding: .utf8) ?? ""
            off += 46 + nlen + elen + clen
            let ext = (name as NSString).pathExtension.lowercased()
            if imgExt.contains(ext), !name.hasPrefix("__MACOSX"), !(name as NSString).lastPathComponent.hasPrefix(".") {
                entries.append(ZipEntry(name: name, method: method, compressed: csize, uncompressed: usize, localHeaderOffset: lho))
            }
        }
        entries.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return !entries.isEmpty
    }
    func page(_ i: Int) -> Data? {
        guard i < entries.count else { return nil }
        let e = entries[i]; let lho = e.localHeaderOffset
        guard lho + 30 <= data.count, u32(lho) == 0x04034b50 else { return nil }
        let start = lho + 30 + Int(u16(lho + 26)) + Int(u16(lho + 28))
        guard start + e.compressed <= data.count else { return nil }
        let raw = data.subdata(in: start..<(start + e.compressed))
        if e.method == 0 { return raw }
        guard e.method == 8 else { return nil }
        var out = Data(count: max(e.uncompressed, 1))
        let n = out.withUnsafeMutableBytes { dst -> Int in
            raw.withUnsafeBytes { src -> Int in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, dst.count, src.bindMemory(to: UInt8.self).baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        return n > 0 ? out.prefix(n) : nil
    }
}
