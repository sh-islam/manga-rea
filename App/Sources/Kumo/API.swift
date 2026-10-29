import Foundation

// MARK: - Models (shapes mirror web/js/api.js)

struct Nodes<T: Decodable>: Decodable { var nodes: [T] }
struct Ref: Decodable, Hashable { var id: Int; var name: String? }
struct SourceRef: Decodable, Hashable { var displayName: String; var lang: String }

struct Manga: Decodable, Identifiable, Hashable {
    var id: Int
    var title: String
    var thumbnailUrl: String?
    var inLibrary: Bool
    var unreadCount: Int?
    var downloadCount: Int?
    var author: String?
    var artist: String?
    var status: String?
    var description: String?
    var genre: [String]?
    var sourceId: String?
    var realUrl: String?
    var source: SourceRef?
    var lastReadChapter: Ref?
    var latestUploadedChapter: UploadRef?
    var categories: Nodes<Ref>?
    struct UploadRef: Decodable, Hashable { var uploadDate: String }
    static func == (a: Manga, b: Manga) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

extension Manga {
    /// Minimal manga for navigation from a chapter reference (Updates / History / Reading now).
    init(id: Int, title: String, thumbnailUrl: String?, inLibrary: Bool) {
        self.id = id; self.title = title; self.thumbnailUrl = thumbnailUrl; self.inLibrary = inLibrary
    }
}

struct Chapter: Decodable, Identifiable, Hashable {
    var id: Int
    var name: String
    var chapterNumber: Double
    var scanlator: String?
    var uploadDate: String
    var isRead: Bool
    var isDownloaded: Bool
    var isBookmarked: Bool
    var pageCount: Int
    var lastPageRead: Int
    var sourceOrder: Int
    var fetchedAt: String?
    var lastReadAt: String?
    var manga: MangaRef?
    struct MangaRef: Decodable, Hashable { var id: Int; var title: String; var thumbnailUrl: String?; var inLibrary: Bool? }
    static func == (a: Chapter, b: Chapter) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Source: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var displayName: String
    var lang: String
    var iconUrl: String?
    var contentWarning: String?
    var supportsLatest: Bool
    var isConfigurable: Bool?
    var isLocal: Bool { lang == "localsourcelang" }
}

struct Category: Decodable, Identifiable, Hashable {
    var id: Int; var name: String; var order: Int; var `default`: Bool
    var mangas: Count?
    struct Count: Decodable, Hashable { var totalCount: Int }
}

struct Extension: Decodable, Identifiable, Hashable {
    var pkgName: String; var name: String; var lang: String; var versionName: String
    var isInstalled: Bool; var hasUpdate: Bool; var isObsolete: Bool; var contentWarning: String?; var iconUrl: String?
    var id: String { pkgName }
}
struct ExtensionStore: Decodable, Identifiable, Hashable { var indexUrl: String; var name: String; var id: String { indexUrl } }

struct DownloadItem: Decodable, Identifiable {
    var position: Int; var progress: Double; var state: String; var tries: Int
    var chapter: Ref; var manga: Ref2
    struct Ref2: Decodable { var id: Int; var title: String }
    var id: Int { chapter.id }
}
struct DownloadStatus: Decodable { var state: String; var queue: [DownloadItem] }

// Source filters (union) decoded loosely.
struct SourceFilter: Decodable, Identifiable {
    var __typename: String; var name: String
    var cbDefault: Bool?; var triDefault: String?; var selDefault: Int?; var textDefault: String?
    var values: [String]?; var sortDefault: SortDefault?; var filters: [SourceFilter]?
    struct SortDefault: Decodable { var index: Int; var ascending: Bool }
    var id: String { __typename + name }
}
struct SourceDetail: Decodable { var id: String; var displayName: String; var lang: String; var supportsLatest: Bool; var filters: [SourceFilter] }

/// FilterChangeInput as a JSON-able dictionary.
typealias FilterChange = [String: Any]

enum APIError: LocalizedError {
    case unauthorized, server(String), http(Int)
    var errorDescription: String? {
        switch self { case .unauthorized: return "Sign in again"; case .server(let m): return m; case .http(let c): return "HTTP \(c)" }
    }
}

// MARK: - Client

@MainActor
final class API: ObservableObject {
    static let shared = API()
    private let d = UserDefaults.standard
    @Published var loggedIn: Bool = false

    var base: String {
        get { d.string(forKey: "api") ?? "https://shad-server.elf-tarpon.ts.net:8443/manga" }
        set { d.set(newValue.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")), forKey: "api") }
    }
    var filesBase: String { d.string(forKey: "files") ?? (base + "/files") }
    var user: String { d.string(forKey: "user") ?? "" }
    private(set) var token: String { get { d.string(forKey: "token") ?? "" } set { d.set(newValue, forKey: "token") } }
    private var refresh: String { get { d.string(forKey: "refresh") ?? "" } set { d.set(newValue, forKey: "refresh") } }
    private(set) var filesToken: String { get { d.string(forKey: "filesToken") ?? "" } set { d.set(newValue, forKey: "filesToken") } }
    var nsfw: Bool { get { d.bool(forKey: "nsfw") } set { d.set(newValue, forKey: "nsfw") } }
    var langs: Set<String> { get { Set(d.stringArray(forKey: "langs") ?? ["en", "all"]) } set { d.set(Array(newValue), forKey: "langs") } }

    init() { loggedIn = !(d.string(forKey: "token") ?? "").isEmpty }

    /// Image/page URL with the JWT as a query parameter (Suwayomi accepts it on /api/v1 image routes).
    func img(_ path: String?) -> URL? {
        guard let p = path, !p.isEmpty else { return nil }
        let abs = p.hasPrefix("http") ? p : base + p
        return URL(string: abs + (abs.contains("?") ? "&" : "?") + "token=" + (token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
    }

    private struct RefreshResp: Decodable { struct P: Decodable { var accessToken: String }; var refreshToken: P }
    private struct GQLResponse<T: Decodable>: Decodable { var data: T?; var errors: [GQLErr]? }
    private struct GQLErr: Decodable { var message: String }

    private func raw<T: Decodable>(_ query: String, _ vars: [String: Any] = [:], auth: String?, as: T.Type) async throws -> T {
        var req = URLRequest(url: URL(string: base + "/api/graphql")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let a = auth, !a.isEmpty { req.setValue("Bearer " + a, forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": vars])
        req.timeoutInterval = 60
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        guard code == 200 else { throw APIError.http(code) }
        let r = try JSONDecoder().decode(GQLResponse<T>.self, from: data)
        if let e = r.errors, !e.isEmpty {
            let msg = e.map { $0.message.components(separatedBy: "\n").first ?? "" }.joined(separator: "; ")
            if msg.range(of: "token|unauthori|authenticat|forbidden", options: [.regularExpression, .caseInsensitive]) != nil { throw APIError.unauthorized }
            throw APIError.server(msg)
        }
        guard let d = r.data else { throw APIError.server("empty response") }
        return d
    }

    func gql<T: Decodable>(_ query: String, _ vars: [String: Any] = [:], as: T.Type = T.self) async throws -> T {
        do { return try await raw(query, vars, auth: token, as: T.self) }
        catch APIError.unauthorized {
            if !refresh.isEmpty, let r: RefreshResp = try? await raw("mutation($t:String!){ refreshToken(input:{refreshToken:$t}) { accessToken } }", ["t": refresh], auth: nil, as: RefreshResp.self) {
                token = r.refreshToken.accessToken
                return try await raw(query, vars, auth: token, as: T.self)
            }
            // refresh token rejected too (server restarted with a new secret): sign in again with the built-in login
            if !BuiltIn.server.isEmpty {
                do { try await login(server: BuiltIn.server, user: BuiltIn.user, pass: BuiltIn.pass); return try await raw(query, vars, auth: token, as: T.self) }
                catch { logout(); throw APIError.unauthorized }
            }
            logout(); throw APIError.unauthorized
        }
    }

    func login(server: String, user: String, pass: String) async throws {
        base = server
        d.set(server.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/files", forKey: "files")
        struct R: Decodable { struct L: Decodable { var accessToken: String; var refreshToken: String }; var login: L }
        let r: R = try await raw("mutation($u:String!,$p:String!){ login(input:{username:$u,password:$p}) { accessToken refreshToken } }", ["u": user, "p": pass], auth: nil, as: R.self)
        token = r.login.accessToken; refresh = r.login.refreshToken; d.set(user, forKey: "user")
        loggedIn = true
        // file service (optional)
        if var req = URL(string: filesBase + "/auth/login").map({ URLRequest(url: $0) }) {
            req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["username": user, "password": pass])
            if let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let t = j["token"] as? String { filesToken = t }
        }
    }
    func logout() { token = ""; refresh = ""; filesToken = ""; loggedIn = false }

    // MARK: queries
    static let MANGA = "id title thumbnailUrl inLibrary unreadCount downloadCount author status sourceId source { displayName lang } latestUploadedChapter { uploadDate } lastReadChapter { id name }"
    static let CHAPTER = "id name chapterNumber scanlator uploadDate isRead isDownloaded isBookmarked pageCount lastPageRead sourceOrder"

    func library() async throws -> [Manga] {
        struct R: Decodable { var mangas: Nodes<Manga> }
        let r: R = try await gql("query($f:MangaFilterInput){ mangas(filter:$f, order:[{by:TITLE}]) { nodes { \(API.MANGA) categories { nodes { id name } } } } }", ["f": ["inLibrary": ["equalTo": true]]])
        return r.mangas.nodes
    }
    struct MangaState: Decodable { var id: Int; var inLibrary: Bool; var downloadCount: Int?; var unreadCount: Int? }
    /// Current library / server-download state for some manga (after coming back from a manga page).
    func states(_ ids: [Int]) async throws -> [Int: MangaState] {
        guard !ids.isEmpty else { return [:] }
        struct R: Decodable { var mangas: Nodes<MangaState> }
        let r: R = try await gql("query($ids:[Int!]!){ mangas(filter:{id:{in:$ids}}) { nodes { id inLibrary downloadCount unreadCount } } }", ["ids": ids])
        return Dictionary(uniqueKeysWithValues: r.mangas.nodes.map { ($0.id, $0) })
    }
    func categories() async throws -> [Category] {
        struct R: Decodable { var categories: Nodes<Category> }
        let r: R = try await gql("{ categories(order:[{by:ORDER}]) { nodes { id name order default mangas { totalCount } } } }")
        return r.categories.nodes
    }
    func sources() async throws -> [Source] {
        struct R: Decodable { var sources: Nodes<Source> }
        let r: R = try await gql("{ sources { nodes { id name displayName lang iconUrl contentWarning supportsLatest isConfigurable } } }")
        return r.sources.nodes
    }
    func visible(_ s: [Source]) -> [Source] { s.filter { (nsfw || $0.contentWarning != "NSFW") && ($0.isLocal || langs.contains($0.lang) || langs.contains("*")) } }
    func source(_ id: String) async throws -> SourceDetail {
        struct R: Decodable { var source: SourceDetail }
        let f = "__typename ... on CheckBoxFilter { name cbDefault: default } ... on TriStateFilter { name triDefault: default } ... on SelectFilter { name selDefault: default values } ... on SortFilter { name values sortDefault: default { index ascending } } ... on TextFilter { name textDefault: default } ... on HeaderFilter { name } ... on SeparatorFilter { name }"
        let r: R = try await gql("query($id:LongString!){ source(id:$id) { id displayName lang supportsLatest filters { \(f) ... on GroupFilter { name filters { \(f) } } } } }", ["id": id])
        return r.source
    }
    struct SourcePage: Decodable { var hasNextPage: Bool; var mangas: [Manga] }
    func sourceManga(_ source: String, type: String, page: Int, query: String? = nil, filters: [FilterChange]? = nil) async throws -> SourcePage {
        struct R: Decodable { var fetchSourceManga: SourcePage }
        var input: [String: Any] = ["source": source, "type": type, "page": page]
        if let q = query, !q.isEmpty { input["query"] = q }
        if let f = filters { input["filters"] = f }
        let r: R = try await gql("mutation($i:FetchSourceMangaInput!){ fetchSourceManga(input:$i) { hasNextPage mangas { \(API.MANGA) } } }", ["i": input])
        return r.fetchSourceManga
    }
    struct MangaDetail { var manga: Manga; var chapters: [Chapter] }
    func manga(_ id: Int, refresh: Bool) async throws -> MangaDetail {
        if refresh {
            struct R: Decodable { struct P: Decodable { var manga: Manga; var chapters: [Chapter] }; var fetchMangaAndChapters: P }
            let r: R = try await gql("mutation($id:Int!){ fetchMangaAndChapters(input:{id:$id, fetchManga:true, fetchChapters:true}) { manga { \(API.MANGA) description genre artist realUrl categories { nodes { id name } } } chapters { \(API.CHAPTER) } } }", ["id": id])
            return MangaDetail(manga: r.fetchMangaAndChapters.manga, chapters: r.fetchMangaAndChapters.chapters)
        }
        struct R: Decodable { struct M: Decodable { var manga: Manga; var chapters: Nodes<Chapter> } }
        struct Q: Decodable { var manga: MangaWithChapters }
        struct MangaWithChapters: Decodable { var chapters: Nodes<Chapter>; var rest: Manga
            init(from dec: Decoder) throws { rest = try Manga(from: dec); let c = try dec.container(keyedBy: K.self); chapters = try c.decode(Nodes<Chapter>.self, forKey: .chapters) }
            enum K: String, CodingKey { case chapters } }
        let r: Q = try await gql("query($id:Int!){ manga(id:$id) { \(API.MANGA) description genre artist realUrl categories { nodes { id name } } chapters { nodes { \(API.CHAPTER) } } } }", ["id": id])
        let d = MangaDetail(manga: r.manga.rest, chapters: r.manga.chapters.nodes)
        return d.chapters.isEmpty ? try await manga(id, refresh: true) : d
    }
    func pages(_ chapterId: Int) async throws -> [String] {
        struct R: Decodable { struct P: Decodable { var pages: [String] }; var fetchChapterPages: P }
        let r: R = try await gql("mutation($id:Int!){ fetchChapterPages(input:{chapterId:$id}) { pages } }", ["id": chapterId])
        return r.fetchChapterPages.pages
    }
    struct Ok: Decodable {}
    func setLibrary(_ id: Int, _ v: Bool) async throws { let _: Ok = try await gql("mutation($id:Int!,$v:Boolean!){ updateManga(input:{id:$id, patch:{inLibrary:$v}}) { manga { id } } }", ["id": id, "v": v]) }
    func setCategories(_ id: Int, add: [Int], remove: [Int]) async throws { let _: Ok = try await gql("mutation($id:Int!,$a:[Int!],$r:[Int!]){ updateMangaCategories(input:{id:$id, patch:{addToCategories:$a, removeFromCategories:$r}}) { manga { id } } }", ["id": id, "a": add, "r": remove]) }
    func createCategory(_ name: String) async throws { let _: Ok = try await gql("mutation($n:String!){ createCategory(input:{name:$n}) { category { id } } }", ["n": name]) }
    func deleteCategory(_ id: Int) async throws { let _: Ok = try await gql("mutation($id:Int!){ deleteCategory(input:{categoryId:$id}) { category { id } } }", ["id": id]) }
    /// A download implies "keep this": the manga goes into the library first (categories untouched).
    func ensureLibrary(_ mangaId: Int) async throws {
        struct R: Decodable { struct M: Decodable { var inLibrary: Bool }; var manga: M }
        let r: R = try await gql("query($id:Int!){ manga(id:$id) { inLibrary } }", ["id": mangaId])
        if !r.manga.inLibrary { try await setLibrary(mangaId, true) }
    }
    func download(_ ids: [Int], mangaId: Int? = nil) async throws { if let m = mangaId { try await ensureLibrary(m) }; let _: Ok = try await gql("mutation($ids:[Int!]!){ enqueueChapterDownloads(input:{ids:$ids}) { downloadStatus { state } } }", ["ids": ids]); try? await downloader(start: true) }
    func deleteDownloads(_ ids: [Int]) async throws { let _: Ok = try await gql("mutation($ids:[Int!]!){ deleteDownloadedChapters(input:{ids:$ids}) { chapters { id } } }", ["ids": ids]) }
    func dequeue(_ ids: [Int]) async throws { let _: Ok = try await gql("mutation($ids:[Int!]!){ dequeueChapterDownloads(input:{ids:$ids}) { downloadStatus { state } } }", ["ids": ids]) }
    func downloadStatus() async throws -> DownloadStatus {
        struct R: Decodable { var downloadStatus: DownloadStatus }
        let r: R = try await gql("{ downloadStatus { state queue { position progress state tries chapter { id name } manga { id title } } } }")
        return r.downloadStatus
    }
    func downloader(start: Bool) async throws { let _: Ok = try await gql(start ? "mutation{ startDownloader(input:{}) { downloadStatus { state } } }" : "mutation{ stopDownloader(input:{}) { downloadStatus { state } } }") }
    func markRead(_ ids: [Int], read: Bool?, lastPage: Int? = nil) async throws {
        var p: [String: Any] = [:]
        if let r = read { p["isRead"] = r }
        if let l = lastPage { p["lastPageRead"] = l }
        let _: Ok = try await gql("mutation($ids:[Int!]!,$p:UpdateChapterPatchInput!){ updateChapters(input:{ids:$ids, patch:$p}) { chapters { id } } }", ["ids": ids, "p": p])
    }
    func bookmark(_ ids: [Int], _ v: Bool) async throws { let _: Ok = try await gql("mutation($ids:[Int!]!,$v:Boolean!){ updateChapters(input:{ids:$ids, patch:{isBookmarked:$v}}) { chapters { id } } }", ["ids": ids, "v": v]) }
    func updates() async throws -> [Chapter] {
        struct R: Decodable { var chapters: Nodes<Chapter> }
        let r: R = try await gql("{ chapters(filter:{inLibrary:{equalTo:true}}, order:[{by:FETCHED_AT, byType:DESC}], first:100) { nodes { \(API.CHAPTER) fetchedAt manga { id title thumbnailUrl } } } }")
        return r.chapters.nodes
    }
    func history() async throws -> [Chapter] {
        struct R: Decodable { var chapters: Nodes<Chapter> }
        let r: R = try await gql("{ chapters(filter:{lastReadAt:{greaterThan:\"0\"}}, order:[{by:LAST_READ_AT, byType:DESC}], first:60) { nodes { \(API.CHAPTER) lastReadAt manga { id title thumbnailUrl inLibrary } } } }")
        return r.chapters.nodes
    }
    func updateLibrary() async throws { let _: Ok = try await gql("mutation{ updateLibrary(input:{}) { updateStatus { isRunning } } }") }
    func extensions() async throws -> [Extension] {
        struct R: Decodable { var extensions: Nodes<Extension> }
        let r: R = try await gql("{ extensions { nodes { pkgName name lang versionName isInstalled hasUpdate isObsolete contentWarning iconUrl } } }")
        return r.extensions.nodes
    }
    func fetchExtensions() async throws { let _: Ok = try await gql("mutation{ fetchExtensions(input:{}) { extensions { pkgName } } }") }
    func extensionAction(_ pkg: String, install: Bool? = nil, uninstall: Bool? = nil, update: Bool? = nil) async throws {
        var p: [String: Any] = [:]
        if let v = install { p["install"] = v }; if let v = uninstall { p["uninstall"] = v }; if let v = update { p["update"] = v }
        let _: Ok = try await gql("mutation($id:String!,$p:UpdateExtensionPatchInput!){ updateExtension(input:{id:$id, patch:$p}) { extension { pkgName } } }", ["id": pkg, "p": p])
    }
    func stores() async throws -> [ExtensionStore] {
        struct R: Decodable { var extensionStores: Nodes<ExtensionStore> }
        let r: R = try await gql("{ extensionStores { nodes { indexUrl name } } }")
        return r.extensionStores.nodes
    }
    func addStore(_ url: String) async throws { let _: Ok = try await gql("mutation($u:String!){ addExtensionStore(input:{indexUrl:$u}) { extensionStore { name } } }", ["u": url]) }
    func removeStore(_ url: String) async throws { let _: Ok = try await gql("mutation($u:String!){ removeExtensionStore(input:{indexUrl:$u}) { extensionStore { name } } }", ["u": url]) }
    struct About: Decodable { struct S: Decodable { var name: String; var version: String }; struct T: Decodable { var downloadsPath: String; var localSourcePath: String; var downloadAsCbz: Bool; var globalUpdateInterval: Double; var autoDownloadNewChapters: Bool }
        var aboutServer: S; var settings: T }
    func about() async throws -> About { try await gql("{ aboutServer { name version } settings { downloadsPath localSourcePath downloadAsCbz globalUpdateInterval autoDownloadNewChapters } }") }
    func setSettings(_ s: [String: Any]) async throws { let _: Ok = try await gql("mutation($s:PartialSettingsTypeInput!){ setSettings(input:{settings:$s}) { settings { downloadAsCbz } } }", ["s": s]) }

    // MARK: file service
    struct FSEntry: Decodable, Identifiable { var name: String; var dir: Bool; var size: Int; var mtime: Int; var writable: Bool?; var id: String { name } }
    struct FSList: Decodable { var entries: [FSEntry]; var writable: Bool? }
    private func filesReq(_ path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
        guard let u = URL(string: filesBase + path) else { throw APIError.server("bad file service URL") }
        var req = URLRequest(url: u); req.httpMethod = method
        req.setValue("Bearer " + filesToken, forHTTPHeaderField: "Authorization")
        if let j = json { req.setValue("application/json", forHTTPHeaderField: "content-type"); req.httpBody = try JSONSerialization.data(withJSONObject: j) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.server("File service: sign in again (Settings)") }
        guard code < 300 else { throw APIError.server(String(data: data, encoding: .utf8) ?? "HTTP \(code)") }
        return data
    }
    func fsList(_ path: String) async throws -> FSList { try JSONDecoder().decode(FSList.self, from: try await filesReq("/fs?path=" + (path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))) }
    func fsMkdir(_ path: String) async throws { _ = try await filesReq("/fs/mkdir", method: "POST", json: ["path": path]) }
    func fsMove(_ from: String, _ to: String) async throws { _ = try await filesReq("/fs/move", method: "POST", json: ["from": from, "to": to]) }
    func fsDelete(_ path: String) async throws { _ = try await filesReq("/fs/delete", method: "POST", json: ["path": path]) }
    func fsFileURL(_ path: String) -> URL? { URL(string: filesBase + "/fs/file?path=" + (path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") + "&token=" + (filesToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) }
    func fsUpload(_ path: String, fileURL: URL) async throws {
        guard let u = URL(string: filesBase + "/fs/upload?path=" + (path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) else { throw APIError.server("bad URL") }
        var req = URLRequest(url: u); req.httpMethod = "PUT"
        req.setValue("Bearer " + filesToken, forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "content-type")
        let (_, resp) = try await URLSession.shared.upload(for: req, fromFile: fileURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.server("upload failed") }
    }
}

// MARK: - helpers

/// Retries a request a few times (the server answers errors for a few seconds while it restarts and loads extensions).
func withRetry<T>(_ attempts: Int = 3, delay: UInt64 = 2_000_000_000, _ op: () async throws -> T) async throws -> T {
    var last: Error?
    for i in 0..<attempts {
        do { return try await op() } catch { last = error; if isCancellation(error) { throw error }; if i + 1 < attempts { try? await Task.sleep(nanoseconds: delay) } }
    }
    throw last!
}

func fmtDate(_ s: String?) -> String {
    guard let s = s, var n = Double(s), n > 0 else { return "" }
    if n < 1e11 { n *= 1000 }
    let d = Date(timeIntervalSince1970: n / 1000)
    let days = Date().timeIntervalSince(d) / 86400
    if days < 1 { return "today" }
    if days < 2 { return "yesterday" }
    if days < 7 { return "\(Int(days)) days ago" }
    let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: d)
}
func fmtBytes(_ n: Int) -> String {
    if n < 1024 { return "\(n) B" }
    if n < 1 << 20 { return "\(n / 1024) KB" }
    if n < 1 << 30 { return String(format: "%.1f MB", Double(n) / 1048576) }
    return String(format: "%.2f GB", Double(n) / 1073741824)
}
