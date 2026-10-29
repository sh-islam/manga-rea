import SwiftUI

struct ReaderTarget: Hashable { let manga: Manga; let chapters: [Chapter]; let chapterId: Int
    static func == (a: ReaderTarget, b: ReaderTarget) -> Bool { a.chapterId == b.chapterId && a.manga.id == b.manga.id }
    func hash(into h: inout Hasher) { h.combine(manga.id); h.combine(chapterId) } }

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

    var sorted: [Chapter] { ascending ? chapters.sorted { $0.sourceOrder > $1.sourceOrder } : chapters.sorted { $0.sourceOrder < $1.sourceOrder } }   // source order 0 = latest
    var unread: [Chapter] { chapters.filter { !$0.isRead } }
    var resume: Chapter? {
        if let l = manga?.lastReadChapter, let c = chapters.first(where: { $0.id == l.id }) { return c }
        return unread.max(by: { $0.sourceOrder < $1.sourceOrder }) ?? chapters.max(by: { $0.sourceOrder < $1.sourceOrder })
    }

    var body: some View {
        List {
            if let m = manga ?? seed {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Cover(manga: m).frame(width: 110)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(m.title).font(.headline)
                            if let a = m.author, !a.isEmpty { Text(a).font(.subheadline).foregroundStyle(.secondary) }
                            Text([m.status?.capitalized, m.source?.displayName].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button { Task { try? await api.setLibrary(m.id, !m.inLibrary); await load(refresh: false) } } label: { Label(m.inLibrary ? "In library" : "Add", systemImage: m.inLibrary ? "checkmark" : "plus") }.buttonStyle(.borderedProminent).tint(m.inLibrary ? .gray : .accentColor)
                                if m.inLibrary { Button { Task { cats = (try? await api.categories()) ?? []; showCats = true } } label: { Image(systemName: "folder") }.buttonStyle(.bordered) }
                                Button { Task { await load(refresh: true) } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
                            }.padding(.top, 4)
                        }
                    }.listRowSeparator(.hidden)
                    if let d = m.description, !d.isEmpty {
                        Text(d).font(.subheadline).lineLimit(showDesc ? nil : 4).onTapGesture { showDesc.toggle() }
                    }
                    if let g = m.genre, !g.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(g, id: \.self) { Chip(text: $0, on: false) {} } } }.listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    if let r = resume {
                        NavigationLink(value: ReaderTarget(manga: m, chapters: chapters, chapterId: r.id)) {
                            Label(m.lastReadChapter == nil ? "Start reading: \(r.name)" : "Resume: \(r.name)", systemImage: "play.fill").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                Section {
                    if !error.isEmpty { ErrorBanner(text: error) }
                    if loading && chapters.isEmpty { ProgressView() }
                    ForEach(sorted) { c in chapterRow(c, m) }
                } header: {
                    HStack {
                        Text("\(chapters.count) chapters · \(unread.count) unread")
                        Spacer()
                        Menu { downloadMenu(m) } label: { Label("Download", systemImage: "arrow.down.circle") }
                        Button(selecting ? "Done" : "Select") { selecting.toggle(); sel.removeAll() }
                        Button { ascending.toggle() } label: { Image(systemName: ascending ? "arrow.up" : "arrow.down") }.help(ascending ? "Oldest first" : "Newest first")
                    }.textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .kumoDestinations()
        .navigationTitle(manga?.title ?? seed?.title ?? "").navigationBarTitleDisplayMode(.inline)
        .task { await load(refresh: false) }
        .refreshable { await load(refresh: true) }
        .sheet(isPresented: $showCats) { if let m = manga { MangaCategoriesSheet(manga: m, cats: cats) { Task { await load(refresh: false) } } } }
        .overlay(alignment: .bottom) { if !toast.isEmpty { Text(toast).padding(10).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, selecting ? 70 : 20) } }
        .safeAreaInset(edge: .bottom) { if selecting, let m = manga { selectionBar(m) } }
    }

    @ViewBuilder func chapterRow(_ c: Chapter, _ m: Manga) -> some View {
        let onDevice = device.has(c.id)
        HStack {
            if selecting { Image(systemName: sel.contains(c.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.accentColor).onTapGesture { toggle(c.id) } }
            NavigationLink(value: ReaderTarget(manga: m, chapters: chapters, chapterId: c.id)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((c.isBookmarked ? "🔖 " : "") + c.name).foregroundStyle(c.isRead ? .secondary : .primary)
                    Text([fmtDate(c.uploadDate), c.scanlator, (!c.isRead && c.lastPageRead > 0) ? "page \(c.lastPageRead + 1)" : nil].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(selecting)
            Spacer()
            if let p = device.progress[c.id] { ProgressView(value: p).frame(width: 40) }
            if onDevice { Image(systemName: "iphone").foregroundStyle(.orange) }
            if c.isDownloaded { Image(systemName: "checkmark.icloud").foregroundStyle(.green) }
            Menu {
                Button { device.enqueue(m, [c]) } label: { Label(onDevice ? "On this device" : "Download to this device", systemImage: "iphone.and.arrow.down") }.disabled(onDevice)
                if onDevice { Button(role: .destructive) { device.remove(c.id) } label: { Label("Remove from device", systemImage: "iphone.slash") } }
                if c.isDownloaded { Button(role: .destructive) { Task { try? await api.deleteDownloads([c.id]); await load(refresh: false) } } label: { Label("Delete from server", systemImage: "icloud.slash") } }
                else { Button { Task { try? await api.download([c.id], mangaId: m.id); flash("Queued on server") } } label: { Label("Download to server", systemImage: "icloud.and.arrow.down") } }
                Divider()
                Button { Task { try? await api.markRead([c.id], read: !c.isRead, lastPage: c.isRead ? 0 : nil); await load(refresh: false) } } label: { Label(c.isRead ? "Mark unread" : "Mark read", systemImage: c.isRead ? "eye.slash" : "eye") }
                Button { Task { let ids = chapters.filter { $0.sourceOrder > c.sourceOrder }.map { $0.id }; if !ids.isEmpty { try? await api.markRead(ids, read: true) }; await load(refresh: false) } } label: { Label("Mark previous as read", systemImage: "eye.fill") }
                Button { Task { try? await api.bookmark([c.id], !c.isBookmarked); await load(refresh: false) } } label: { Label(c.isBookmarked ? "Remove bookmark" : "Bookmark", systemImage: "bookmark") }
            } label: { Image(systemName: "ellipsis.circle").padding(.leading, 4) }
        }
        .contentShape(Rectangle())
        .onTapGesture { if selecting { toggle(c.id) } }
    }
    func toggle(_ id: Int) { if sel.contains(id) { sel.remove(id) } else { sel.insert(id) } }

    @ViewBuilder func downloadMenu(_ m: Manga) -> some View {
        let notOnServer = chapters.filter { !$0.isDownloaded }
        let unreadNext = unread.sorted { $0.sourceOrder > $1.sourceOrder }   // oldest unread first
        Section("To the server") {
            ForEach([1, 5, 10, 25], id: \.self) { n in Button("Next \(n) unread") { Task { let ids = Array(unreadNext.filter { !$0.isDownloaded }.prefix(n)).map { $0.id }; try? await api.download(ids, mangaId: m.id); flash("\(ids.count) queued on server") } } }
            Button("All unread (\(unread.count))") { Task { let ids = unread.filter { !$0.isDownloaded }.map { $0.id }; try? await api.download(ids, mangaId: m.id); flash("\(ids.count) queued on server") } }
            Button("Everything (\(notOnServer.count))") { Task { try? await api.download(notOnServer.map { $0.id }, mangaId: m.id); flash("\(notOnServer.count) queued on server") } }
        }
        Section("To this device") {
            ForEach([1, 5, 10], id: \.self) { n in Button("Next \(n) unread") { device.enqueue(m, Array(unreadNext.prefix(n))); flash("Downloading to device") } }
            Button("All unread (\(unread.count))") { device.enqueue(m, unreadNext); flash("Downloading to device") }
            Button("Everything (\(chapters.count))") { device.enqueue(m, chapters.sorted { $0.sourceOrder > $1.sourceOrder }); flash("Downloading to device") }
        }
    }
    @ViewBuilder func selectionBar(_ m: Manga) -> some View {
        HStack {
            Text("\(sel.count) selected").font(.footnote)
            Spacer()
            Button("All") { sel = Set(chapters.map { $0.id }) }
            Menu("Actions") {
                Button { Task { try? await api.download(Array(sel), mangaId: m.id); flash("Queued on server"); selecting = false } } label: { Label("Download to server", systemImage: "icloud.and.arrow.down") }
                Button { device.enqueue(m, chapters.filter { sel.contains($0.id) }.sorted { $0.sourceOrder > $1.sourceOrder }); selecting = false } label: { Label("Download to this device", systemImage: "iphone.and.arrow.down") }
                Button { Task { try? await api.markRead(Array(sel), read: true); await load(refresh: false); selecting = false } } label: { Label("Mark read", systemImage: "eye") }
                Button { Task { try? await api.markRead(Array(sel), read: false, lastPage: 0); await load(refresh: false); selecting = false } } label: { Label("Mark unread", systemImage: "eye.slash") }
                Button(role: .destructive) { Task { try? await api.deleteDownloads(Array(sel)); await load(refresh: false); selecting = false } } label: { Label("Delete from server", systemImage: "icloud.slash") }
                Button(role: .destructive) { for id in sel { device.remove(id) }; selecting = false } label: { Label("Remove from device", systemImage: "iphone.slash") }
            }.disabled(sel.isEmpty)
        }.padding(.horizontal).padding(.vertical, 8).background(.bar)
    }
    func flash(_ s: String) { toast = s; Task { try? await Task.sleep(nanoseconds: 1_800_000_000); toast = "" } }
    func load(refresh: Bool) async {
        loading = true
        do { let d = try await api.manga(mangaId, refresh: refresh); manga = d.manga; chapters = d.chapters; error = "" } catch { self.error = error.localizedDescription }
        loading = false
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

// MARK: - Reader (server pages or device pages)

struct ReaderView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var device: DeviceStore
    @Environment(\.dismiss) var dismiss
    let target: ReaderTarget
    @State private var pages: [URL] = []
    @State private var page = 0
    @State private var error = ""
    @State private var hud = false
    @AppStorage("reader.mode") private var mode = "webtoon"   // webtoon | paged | pagedRTL
    @AppStorage("reader.fitWidth") private var fitWidth = true
    @State private var saveTask: Task<Void, Never>?
    @State private var current: Int = 0

    var ordered: [Chapter] { target.chapters.sorted { $0.sourceOrder > $1.sourceOrder } }   // reading order
    var idx: Int { ordered.firstIndex { $0.id == current } ?? 0 }
    var chapter: Chapter? { ordered.indices.contains(idx) ? ordered[idx] : nil }
    var prev: Chapter? { idx > 0 ? ordered[idx - 1] : nil }
    var next: Chapter? { idx + 1 < ordered.count ? ordered[idx + 1] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !error.isEmpty { VStack { Text(error).foregroundStyle(.red).padding(); Button("Back") { dismiss() } } }
            else if pages.isEmpty { ProgressView().tint(.white) }
            else if mode == "webtoon" { webtoon }
            else { paged }
            if hud { hudView }
        }
        .navigationBarHidden(true).statusBarHidden(!hud).toolbar(.hidden, for: .tabBar)
        .task(id: current) { await loadPages() }
        .onAppear { current = target.chapterId }
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
                ZoomableImage(url: u).tag(mode == "pagedRTL" ? pages.count - 1 - i : i)
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
    func go(_ c: Chapter) { Task { await save(final: false) }; page = 0; pages = []; current = c.id }
    func touched() {
        saveTask?.cancel()
        let final = page >= pages.count - 1
        saveTask = Task { try? await Task.sleep(nanoseconds: final ? 0 : 1_500_000_000); if !Task.isCancelled { await save(final: final) } }
    }
    func save(final: Bool) async {
        guard let c = chapter, !pages.isEmpty else { return }
        try? await api.markRead([c.id], read: final ? true : nil, lastPage: page)
    }
    func loadPages() async {
        guard let c = chapter else { return }
        pages = []; error = ""
        let local = device.pages(c.id)
        if !local.isEmpty { pages = local }
        else {
            do { pages = try await api.pages(c.id).compactMap { api.img($0) } } catch { self.error = error.localizedDescription; return }
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
