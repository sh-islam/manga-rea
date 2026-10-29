import SwiftUI

/// What the reader opens. `chapters` may be empty (e.g. from Updates/History); the reader then loads them.
struct ReaderTarget: Hashable {
    let manga: Manga; let chapters: [Chapter]; let chapterId: Int
    static func == (a: ReaderTarget, b: ReaderTarget) -> Bool { a.chapterId == b.chapterId && a.manga.id == b.manga.id }
    func hash(into h: inout Hasher) { h.combine(manga.id); h.combine(chapterId) }
}

func isCancellation(_ e: Error) -> Bool { e is CancellationError || (e as? URLError)?.code == .cancelled }

// MARK: - Manga details + chapters

struct MangaView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var device: DeviceStore
    let mangaId: Int
    var seed: Manga?
    @State private var manga: Manga?
    @State private var chapters: [Chapter] = []
    @State private var error = ""
    @State private var loading = true
    @State private var selecting = false
    @State private var sel: Set<Int> = []
    @State private var showDesc = false
    @State private var showCats = false
    @State private var cats: [Category] = []
    @State private var toast = ""
    @AppStorage("chapters.asc") private var ascending = false
    @State private var queue: [Int: DownloadItem] = [:]   // server queue by chapter id

    var sorted: [Chapter] { ascending ? chapters.sorted { $0.sourceOrder > $1.sourceOrder } : chapters.sorted { $0.sourceOrder < $1.sourceOrder } }   // source order 0 = latest
    var unread: [Chapter] { chapters.filter { !$0.isRead } }
    var oldestFirstUnread: [Chapter] { unread.sorted { $0.sourceOrder > $1.sourceOrder } }
    var resume: Chapter? {
        if let l = manga?.lastReadChapter, let c = chapters.first(where: { $0.id == l.id }), !c.isRead || c.lastPageRead < c.pageCount - 1 { return c }
        return oldestFirstUnread.first ?? chapters.max(by: { $0.sourceOrder < $1.sourceOrder })
    }
    var onServer: Int { chapters.filter { $0.isDownloaded }.count }
    var onDevice: Int { chapters.filter { device.has($0.id) }.count }

    var body: some View {
        List {
            if let m = manga ?? seed {
                Section {
                    header(m)
                    actionRow(m)
                    if let d = m.description, !d.isEmpty {
                        Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(showDesc ? nil : 3)
                            .contentShape(Rectangle()).onTapGesture { withAnimation { showDesc.toggle() } }
                    }
                    if let g = m.genre, !g.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { ForEach(g, id: \.self) { Chip(text: $0, on: false) {} } } }
                            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16))
                    }
                    if let r = resume {
                        NavigationLink(value: ReaderTarget(manga: m, chapters: chapters, chapterId: r.id)) {
                            HStack { Image(systemName: "play.fill"); Text(m.lastReadChapter == nil || r.lastPageRead == 0 ? "Start reading" : "Continue reading").bold(); Spacer(); Text(r.name).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        .listRowBackground(Color.accentColor.opacity(0.15))
                    }
                }
                .listRowSeparator(.hidden)

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(chapters.count) chapters").font(.headline)
                            Text("\(unread.count) unread · \(onServer) on server · \(onDevice) on this phone").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { withAnimation { ascending.toggle() } } label: { Image(systemName: ascending ? "arrow.up" : "arrow.down").frame(width: 32, height: 32) }.buttonStyle(.bordered).help(ascending ? "Oldest first" : "Newest first")
                        Button(selecting ? "Done" : "Select") { withAnimation { selecting.toggle(); sel.removeAll() } }.buttonStyle(.bordered)
                    }
                    .listRowSeparator(.hidden)
                    if !error.isEmpty { ErrorBanner(text: error) }
                    if loading && chapters.isEmpty { HStack { Spacer(); ProgressView(); Spacer() } }
                    if !loading && chapters.isEmpty && error.isEmpty { Text("No chapters from this source.").foregroundStyle(.secondary) }
                    ForEach(sorted) { c in chapterRow(c, m) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(manga?.title ?? seed?.title ?? "").navigationBarTitleDisplayMode(.inline)
        .task { await load(refresh: false) }
        .task {   // live server-queue state for this manga's chapters
            while !Task.isCancelled {
                if let s = try? await api.downloadStatus() {
                    let next = Dictionary(uniqueKeysWithValues: s.queue.map { ($0.chapter.id, $0) })
                    for i in chapters.indices where queue[chapters[i].id] != nil && next[chapters[i].id] == nil { chapters[i].isDownloaded = true }
                    queue = next
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .refreshable { await load(refresh: true) }
        .sheet(isPresented: $showCats) { if let m = manga { MangaCategoriesSheet(manga: m, cats: cats) { Task { await load(refresh: false) } } } }
        .overlay(alignment: .bottom) { if !toast.isEmpty { Text(toast).font(.footnote).padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, selecting ? 70 : 20) } }
        .safeAreaInset(edge: .bottom) { if selecting, let m = manga ?? seed { selectionBar(m) } }
    }

    // MARK: header + actions
    @ViewBuilder func header(_ m: Manga) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Cover(manga: m).frame(width: 118)
            VStack(alignment: .leading, spacing: 6) {
                Text(m.title).font(.title3.bold()).lineLimit(4)
                if let a = m.author, !a.isEmpty { Label(a, systemImage: "person").font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                if let s = m.status, s != "UNKNOWN" { Label(s.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: "clock").font(.subheadline).foregroundStyle(.secondary) }
                if let src = m.source { Label(src.displayName, systemImage: "globe").font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder func actionRow(_ m: Manga) -> some View {
        HStack(spacing: 8) {
            Button { Task { try? await api.setLibrary(m.id, !m.inLibrary); await load(refresh: false); flash(m.inLibrary ? "Removed from library" : "Added to library") } } label: {
                ActionLabel(icon: m.inLibrary ? "heart.fill" : "heart", text: m.inLibrary ? "In library" : "Add to library", tint: m.inLibrary ? .pink : .primary)
            }
            Menu { downloadMenu(m) } label: { ActionLabel(icon: "arrow.down.circle", text: "Download", tint: .primary) }
            if m.inLibrary {
                Button { Task { cats = (try? await api.categories()) ?? []; showCats = true } } label: { ActionLabel(icon: "folder", text: "Category", tint: .primary) }
            } else if let u = m.realUrl, let url = URL(string: u) {
                Link(destination: url) { ActionLabel(icon: "safari", text: "Website", tint: .primary) }
            } else {
                Button { Task { await load(refresh: true) } } label: { ActionLabel(icon: "arrow.clockwise", text: "Refresh", tint: .primary) }
            }
        }
        .buttonStyle(.bordered)
        .padding(.top, 4)
    }

    // MARK: chapter row
    @ViewBuilder func chapterRow(_ c: Chapter, _ m: Manga) -> some View {
        let onDevice = device.has(c.id)
        HStack(spacing: 10) {
            if selecting {
                Image(systemName: sel.contains(c.id) ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(Color.accentColor)
            }
            NavigationLink(value: ReaderTarget(manga: m, chapters: chapters, chapterId: c.id)) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if c.isBookmarked { Image(systemName: "bookmark.fill").font(.caption).foregroundStyle(Color.accentColor) }
                        Text(c.name).foregroundStyle(c.isRead ? .secondary : .primary).lineLimit(1)
                    }
                    Text([fmtDate(c.uploadDate), c.scanlator, (!c.isRead && c.lastPageRead > 0) ? "page \(c.lastPageRead + 1)" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .disabled(selecting)
            Spacer(minLength: 4)
            if let p = device.progress[c.id] {
                VStack(alignment: .trailing, spacing: 2) { Text("to phone \(Int(p * 100))%").font(.caption2).foregroundStyle(.orange); ProgressView(value: p).frame(width: 56).tint(.orange) }
            } else if let d = queue[c.id] {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(d.state == "DOWNLOADING" ? "server \(Int(d.progress * 100))%" : d.state == "ERROR" ? "retrying" : "queued").font(.caption2).foregroundStyle(.secondary)
                    ProgressView(value: d.progress).frame(width: 56)
                }
            } else {
                HStack(spacing: 6) {
                    if onDevice { Image(systemName: "iphone").foregroundStyle(.orange).help("On this phone") }
                    if c.isDownloaded { Image(systemName: "checkmark.icloud").foregroundStyle(.green).help("On the server") }
                }
            }
            if !selecting {
                Menu {
                    Section("This phone") {
                        if onDevice { Button(role: .destructive) { device.remove(c.id) } label: { Label("Remove from this phone", systemImage: "iphone.slash") } }
                        else { Button { device.enqueue(m, [c]); flash("Downloading to this phone") } label: { Label("Download to this phone", systemImage: "iphone.and.arrow.down") } }
                    }
                    Section("Server") {
                        if queue[c.id] != nil { Button(role: .destructive) { Task { try? await api.dequeue([c.id]); queue[c.id] = nil } } label: { Label("Remove from server queue", systemImage: "xmark.circle") } }
                        else if c.isDownloaded { Button(role: .destructive) { Task { try? await api.deleteDownloads([c.id]); await load(refresh: false) } } label: { Label("Delete from server", systemImage: "icloud.slash") } }
                        else { Button { Task { try? await api.download([c.id], mangaId: m.id); queue[c.id] = DownloadItem(position: 0, progress: 0, state: "QUEUED", tries: 0, chapter: Ref(id: c.id, name: c.name), manga: DownloadItem.Ref2(id: m.id, title: m.title)); flash("Queued on server") } } label: { Label("Download to server", systemImage: "icloud.and.arrow.down") } }
                    }
                    Section("Reading") {
                        Button { Task { try? await api.markRead([c.id], read: !c.isRead, lastPage: c.isRead ? 0 : nil); await load(refresh: false) } } label: { Label(c.isRead ? "Mark unread" : "Mark read", systemImage: c.isRead ? "eye.slash" : "eye") }
                        Button { Task { let ids = chapters.filter { $0.sourceOrder > c.sourceOrder }.map { $0.id }; if !ids.isEmpty { try? await api.markRead(ids, read: true) }; await load(refresh: false) } } label: { Label("Mark previous as read", systemImage: "eye.fill") }
                        Button { Task { try? await api.bookmark([c.id], !c.isBookmarked); await load(refresh: false) } } label: { Label(c.isBookmarked ? "Remove bookmark" : "Bookmark", systemImage: "bookmark") }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if selecting { toggle(c.id) } }
    }
    func toggle(_ id: Int) { if sel.contains(id) { sel.remove(id) } else { sel.insert(id) } }

    // MARK: download menu: two explicit destinations
    @ViewBuilder func downloadMenu(_ m: Manga) -> some View {
        let notOnServer = chapters.filter { !$0.isDownloaded }
        let unreadNotOnServer = oldestFirstUnread.filter { !$0.isDownloaded }
        let unreadNotOnDevice = oldestFirstUnread.filter { !device.has($0.id) }
        let allOldestFirst = chapters.sorted { $0.sourceOrder > $1.sourceOrder }
        Menu {
            ForEach([1, 5, 10, 25], id: \.self) { n in Button("Next \(n) unread") { Task { let ids = Array(unreadNotOnServer.prefix(n)).map { $0.id }; try? await api.download(ids, mangaId: m.id); flash("\(ids.count) queued on server") } } }
            Button("All unread (\(unreadNotOnServer.count))") { Task { let ids = unreadNotOnServer.map { $0.id }; try? await api.download(ids, mangaId: m.id); flash("\(ids.count) queued on server") } }
            Button("Everything (\(notOnServer.count))") { Task { try? await api.download(notOnServer.map { $0.id }, mangaId: m.id); flash("\(notOnServer.count) queued on server") } }
        } label: { Label("To the server (stays there, read anywhere)", systemImage: "icloud.and.arrow.down") }
        Menu {
            ForEach([1, 5, 10, 25], id: \.self) { n in Button("Next \(n) unread") { device.enqueue(m, Array(unreadNotOnDevice.prefix(n))); flash("Downloading to this phone") } }
            Button("All unread (\(unreadNotOnDevice.count))") { device.enqueue(m, unreadNotOnDevice); flash("Downloading to this phone") }
            Button("Everything (\(chapters.count))") { device.enqueue(m, allOldestFirst); flash("Downloading to this phone") }
        } label: { Label("To this phone (offline copy)", systemImage: "iphone.and.arrow.down") }
    }

    @ViewBuilder func selectionBar(_ m: Manga) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(sel.count) selected").font(.footnote.bold())
                Spacer()
                Button("All") { sel = Set(chapters.map { $0.id }) }.font(.footnote)
                Button("Unread") { sel = Set(unread.map { $0.id }) }.font(.footnote)
                Button("None") { sel.removeAll() }.font(.footnote)
            }
            HStack(spacing: 8) {
                Button { Task { try? await api.download(Array(sel), mangaId: m.id); flash("\(sel.count) queued on server"); selecting = false } } label: { ActionLabel(icon: "icloud.and.arrow.down", text: "To server", tint: .primary) }
                Button { device.enqueue(m, chapters.filter { sel.contains($0.id) }.sorted { $0.sourceOrder > $1.sourceOrder }); flash("Downloading to this phone"); selecting = false } label: { ActionLabel(icon: "iphone.and.arrow.down", text: "To phone", tint: .primary) }
                Button { Task { try? await api.markRead(Array(sel), read: true); await load(refresh: false); selecting = false } } label: { ActionLabel(icon: "eye", text: "Read", tint: .primary) }
                Menu {
                    Button { Task { try? await api.markRead(Array(sel), read: false, lastPage: 0); await load(refresh: false); selecting = false } } label: { Label("Mark unread", systemImage: "eye.slash") }
                    Button { Task { try? await api.bookmark(Array(sel), true); await load(refresh: false); selecting = false } } label: { Label("Bookmark", systemImage: "bookmark") }
                    Button(role: .destructive) { Task { try? await api.deleteDownloads(Array(sel)); await load(refresh: false); selecting = false } } label: { Label("Delete from server", systemImage: "icloud.slash") }
                    Button(role: .destructive) { for id in sel { device.remove(id) }; selecting = false } label: { Label("Remove from this phone", systemImage: "iphone.slash") }
                } label: { ActionLabel(icon: "ellipsis", text: "More", tint: .primary) }
            }
            .buttonStyle(.bordered)
            .disabled(sel.isEmpty)
        }
        .padding(.horizontal).padding(.vertical, 8).background(.bar)
    }

    func flash(_ s: String) { toast = s; Task { try? await Task.sleep(nanoseconds: 1_800_000_000); toast = "" } }

    /// Loads in a detached task so SwiftUI re-creating the view (which cancels `.task`) never surfaces as "cancelled".
    func load(refresh: Bool) async {
        loading = true
        let id = mangaId
        let result = await Task.detached { () -> Result<API.MangaDetail, Error> in
            do { return .success(try await API.shared.manga(id, refresh: refresh)) } catch { return .failure(error) }
        }.value
        switch result {
        case .success(let d): manga = d.manga; chapters = d.chapters; error = ""
        case .failure(let e): if !isCancellation(e) { error = e.localizedDescription }
        }
        loading = false
    }
}

/// Centered icon-over-text label for the equal-width action buttons.
struct ActionLabel: View {
    let icon: String; let text: String; let tint: Color
    var body: some View {
        VStack(spacing: 4) { Image(systemName: icon).font(.title3); Text(text).font(.caption2).lineLimit(1).minimumScaleFactor(0.8) }
            .foregroundStyle(tint).frame(maxWidth: .infinity).padding(.vertical, 4)
    }
}

struct MangaCategoriesSheet: View {
    @EnvironmentObject var api: API
    @Environment(\.dismiss) var dismiss
    let manga: Manga; let cats: [Category]; let done: () -> Void
    @State private var on: Set<Int> = []
    var body: some View {
        NavigationStack {
            List(cats) { c in Toggle(c.name, isOn: Binding(get: { on.contains(c.id) }, set: { if $0 { on.insert(c.id) } else { on.remove(c.id) } })) }
                .navigationTitle("Categories").toolbar {
                    Button("Save") { Task { let mine = Set(manga.categories?.nodes.map { $0.id } ?? []); try? await api.setCategories(manga.id, add: Array(on.subtracting(mine)), remove: Array(mine.subtracting(on))); done(); dismiss() } }
                }
        }.onAppear { on = Set(manga.categories?.nodes.map { $0.id } ?? []) }
    }
}

// MARK: - Reader (streams pages from the server; uses the phone copy when there is one)

struct ReaderView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var device: DeviceStore
    @Environment(\.dismiss) var dismiss
    let target: ReaderTarget
    @State private var chapters: [Chapter] = []
    @State private var pages: [URL] = []
    @State private var page = 0
    @State private var error = ""
    @State private var hud = false
    @AppStorage("reader.mode") private var mode = "webtoon"   // webtoon | paged | pagedRTL
    @AppStorage("reader.fitWidth") private var fitWidth = true
    @State private var saveTask: Task<Void, Never>?
    @State private var current: Int = 0

    var ordered: [Chapter] { chapters.sorted { $0.sourceOrder > $1.sourceOrder } }   // reading order
    var idx: Int { ordered.firstIndex { $0.id == current } ?? 0 }
    var chapter: Chapter? { ordered.indices.contains(idx) ? ordered[idx] : nil }
    var prev: Chapter? { idx > 0 ? ordered[idx - 1] : nil }
    var next: Chapter? { idx + 1 < ordered.count ? ordered[idx + 1] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !error.isEmpty { VStack(spacing: 12) { Text(error).foregroundStyle(.red).multilineTextAlignment(.center).padding(); Button("Try again") { Task { await loadPages() } }.buttonStyle(.borderedProminent); Button("Back") { dismiss() } } }
            else if pages.isEmpty { ProgressView().tint(.white) }
            else if mode == "webtoon" { webtoon }
            else { paged }
            if hud { hudView }
        }
        .navigationBarHidden(true).statusBarHidden(!hud).toolbar(.hidden, for: .tabBar)
        .task { chapters = target.chapters; current = target.chapterId; await loadPages() }
        .onDisappear { saveTask?.cancel(); Task { await save(final: false) } }
    }

    var webtoon: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, u in
                        PageImage(url: u).id(i)
                            .onAppear { if i > page || i == 0 { page = i; touched() } }
                    }
                    chapterEnd
                }
            }
            .onTapGesture { withAnimation { hud.toggle() } }
            .onAppear { if page > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo(page, anchor: .top) } } }
        }
    }
    var paged: some View {
        TabView(selection: $page) {
            ForEach(Array(pages.enumerated()), id: \.offset) { i, u in
                ZoomableImage(url: u).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .environment(\.layoutDirection, mode == "pagedRTL" ? .rightToLeft : .leftToRight)
        .onChange(of: page) { _, _ in touched() }
        .onTapGesture { withAnimation { hud.toggle() } }
        .ignoresSafeArea()
    }
    var chapterEnd: some View {
        VStack(spacing: 12) {
            Text("End of \(chapter?.name ?? "")").foregroundStyle(.white)
            if let n = next { Button("Next: \(n.name)") { go(n) }.buttonStyle(.borderedProminent) }
            else { Button("Back to manga") { dismiss() }.buttonStyle(.bordered) }
        }.padding(30)
    }
    var hudView: some View {
        VStack {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").padding(8) }
                VStack(alignment: .leading) { Text(target.manga.title).lineLimit(1).font(.subheadline.bold()); Text(chapter?.name ?? "").font(.caption).lineLimit(1) }
                Spacer()
                Menu {
                    Picker("Mode", selection: $mode) { Label("Webtoon (scroll)", systemImage: "arrow.down").tag("webtoon"); Label("Paged, left to right", systemImage: "arrow.right").tag("paged"); Label("Paged, right to left (manga)", systemImage: "arrow.left").tag("pagedRTL") }
                    Toggle("Fit width", isOn: $fitWidth)
                } label: { Image(systemName: "textformat.size").padding(8) }
            }.padding(.horizontal, 8).padding(.top, 44).background(.black.opacity(0.75)).foregroundStyle(.white)
            Spacer()
            HStack {
                Button { if let p = prev { go(p) } } label: { Image(systemName: "backward.end") }.disabled(prev == nil)
                Slider(value: Binding(get: { Double(page) }, set: { page = Int($0) }), in: 0...Double(max(1, pages.count - 1)), step: 1)
                Text("\(page + 1)/\(pages.count)").font(.caption.monospacedDigit())
                Button { if let n = next { go(n) } } label: { Image(systemName: "forward.end") }.disabled(next == nil)
            }.padding().background(.black.opacity(0.75)).foregroundStyle(.white)
        }.ignoresSafeArea()
    }
    func go(_ c: Chapter) { Task { await save(final: false); page = 0; pages = []; current = c.id; await loadPages() } }
    func touched() {
        saveTask?.cancel()
        let final = page >= pages.count - 1
        saveTask = Task { try? await Task.sleep(nanoseconds: final ? 0 : 1_500_000_000); if !Task.isCancelled { await save(final: final) } }
    }
    func save(final: Bool) async {
        guard let c = chapter, !pages.isEmpty else { return }
        let id = c.id, p = page
        _ = await Task.detached { try? await API.shared.markRead([id], read: final ? true : nil, lastPage: p) }.value
    }
    func loadPages() async {
        error = ""; pages = []
        let mid = target.manga.id
        if chapters.isEmpty {   // opened from Updates/History: fetch the chapter list first
            let r = await Task.detached { () -> [Chapter]? in (try? await API.shared.manga(mid, refresh: false))?.chapters }.value
            chapters = r ?? []
            if chapters.isEmpty { error = "Could not load the chapter list"; return }
        }
        guard let c = chapter else { error = "Chapter not found"; return }
        let local = device.pages(c.id)
        if !local.isEmpty { pages = local }
        else {
            let cid = c.id
            let r = await Task.detached { () -> Result<[String], Error> in do { return .success(try await API.shared.pages(cid)) } catch { return .failure(error) } }.value
            switch r {
            case .success(let p): pages = p.compactMap { api.img($0) }
            case .failure(let e): if !isCancellation(e) { error = e.localizedDescription }; return
            }
            if pages.isEmpty { error = "This chapter has no pages on its source (it may be hosted elsewhere)."; return }
        }
        page = min(c.lastPageRead, max(0, pages.count - 1))
        if c.isRead && page >= pages.count - 1 { page = 0 }
    }
}

struct PageImage: View {
    @AppStorage("reader.fitWidth") private var fitWidth = true
    let url: URL
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img): img.resizable().scaledToFit().frame(maxWidth: fitWidth ? .infinity : 900)
            case .failure: VStack { Image(systemName: "exclamationmark.triangle"); Text("page failed").font(.caption) }.foregroundStyle(.gray).frame(height: 200)
            default: Rectangle().fill(.gray.opacity(0.15)).frame(height: 400).overlay(ProgressView().tint(.white))
            }
        }
    }
}

struct ZoomableImage: View {
    let url: URL
    @State private var scale: CGFloat = 1
    @State private var last: CGFloat = 1
    var body: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image { img.resizable().scaledToFit() } else if phase.error != nil { Text("page failed").foregroundStyle(.gray) } else { ProgressView().tint(.white) }
                }
                .frame(width: geo.size.width * scale, height: geo.size.height * scale)
            }
            .gesture(MagnificationGesture().onChanged { v in scale = max(1, min(4, last * v)) }.onEnded { _ in last = scale })
            .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2.5; last = scale } }
        }.background(.black)
    }
}

// MARK: - Local CBZ reader (files dropped onto the device)

struct LocalBookTarget: Hashable { let title: String; let files: [URL]; let index: Int }

struct LocalReaderView: View {
    @Environment(\.dismiss) var dismiss
    let book: LocalBookTarget
    @State private var cbz: CBZ?
    @State private var page = 0
    @State private var hud = false
    @State private var images: [Int: UIImage] = [:]
    @AppStorage("reader.mode") private var mode = "webtoon"
    var file: URL { book.files[book.index] }
    var key: String { "local.\(file.lastPathComponent).\(file.path.hashValue)" }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let z = cbz {
                if mode == "webtoon" {
                    ScrollView { LazyVStack(spacing: 4) { ForEach(0..<z.entries.count, id: \.self) { i in localPage(z, i).onAppear { page = i; UserDefaults.standard.set(i, forKey: key) } }
                        if book.index + 1 < book.files.count { NavigationLink("Next: \(book.files[book.index + 1].deletingPathExtension().lastPathComponent)", value: LocalBookTarget(title: book.title, files: book.files, index: book.index + 1)).buttonStyle(.borderedProminent).padding(30) } } }
                } else {
                    TabView(selection: $page) { ForEach(0..<z.entries.count, id: \.self) { i in localPage(z, i).tag(i) } }.tabViewStyle(.page(indexDisplayMode: .never)).environment(\.layoutDirection, mode == "pagedRTL" ? .rightToLeft : .leftToRight)
                        .onChange(of: page) { _, p in UserDefaults.standard.set(p, forKey: key) }
                }
            } else { Text("Could not open this file").foregroundStyle(.gray) }
            if hud {
                VStack { HStack { Button { dismiss() } label: { Image(systemName: "chevron.left").padding(8) }; Text(file.deletingPathExtension().lastPathComponent).lineLimit(1); Spacer()
                    Menu { Picker("Mode", selection: $mode) { Text("Webtoon").tag("webtoon"); Text("Paged").tag("paged"); Text("Paged RTL").tag("pagedRTL") } } label: { Image(systemName: "textformat.size").padding(8) } }
                    .padding(.horizontal, 8).padding(.top, 44).background(.black.opacity(0.75)).foregroundStyle(.white); Spacer()
                    Text("\(page + 1)/\(cbz?.entries.count ?? 0)").font(.caption).foregroundStyle(.white).padding(8).background(.black.opacity(0.75)) }.ignoresSafeArea()
            }
        }
        .onTapGesture { withAnimation { hud.toggle() } }
        .navigationBarHidden(true).statusBarHidden(!hud).toolbar(.hidden, for: .tabBar)
        .onAppear { cbz = CBZ(url: file); page = UserDefaults.standard.integer(forKey: key) }
    }
    @ViewBuilder func localPage(_ z: CBZ, _ i: Int) -> some View {
        if let img = images[i] { Image(uiImage: img).resizable().scaledToFit() }
        else { Rectangle().fill(.gray.opacity(0.15)).frame(height: 400).overlay(ProgressView().tint(.white)).task { if let d = z.page(i), let u = UIImage(data: d) { images[i] = u } } }
    }
}
