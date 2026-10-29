import SwiftUI
import UniformTypeIdentifiers

// MARK: - Updates / History

struct UpdatesView: View {
    @EnvironmentObject var api: API
    @State private var list: [Chapter] = []
    @State private var error = ""
    @State private var loading = true
    var body: some View {
        List {
            if !error.isEmpty { ErrorBanner(text: error) }
            if loading { ProgressView() }
            else if list.isEmpty { Text("No new chapters yet. Add manga to your library and update.").foregroundStyle(.secondary) }
            ForEach(groups, id: \.0) { day, chs in
                Section(day) { ForEach(chs) { c in ChapterRow(c: c) } }
            }
        }
        .kumoDestinations()
        .navigationTitle("Updates")
        .toolbar { Button { Task { try? await api.updateLibrary() } } label: { Image(systemName: "arrow.triangle.2.circlepath") } }
        .task { await load() }.refreshable { await load() }
    }
    var groups: [(String, [Chapter])] {
        var out: [(String, [Chapter])] = []
        for c in list { let d = fmtDate(c.fetchedAt); if out.last?.0 == d { out[out.count - 1].1.append(c) } else { out.append((d, [c])) } }
        return out
    }
    func load() async { do { list = try await api.updates(); error = "" } catch { self.error = error.localizedDescription }; loading = false }
}

struct HistoryView: View {
    @EnvironmentObject var api: API
    @State private var list: [Chapter] = []
    @State private var error = ""
    var body: some View {
        List {
            if !error.isEmpty { ErrorBanner(text: error) }
            if list.isEmpty { Text("Nothing read yet.").foregroundStyle(.secondary) }
            ForEach(list) { c in ChapterRow(c: c, sub: [c.name, fmtDate(c.lastReadAt), c.isRead ? nil : "page \(c.lastPageRead + 1)"].compactMap { $0 }.joined(separator: " · ")) }
        }
        .kumoDestinations().navigationTitle("History").task { do { list = try await api.history() } catch { self.error = error.localizedDescription } }
    }
}

/// A chapter row that opens the reader; needs the manga's chapter list, so it fetches it on tap.
struct ChapterRow: View {
    @EnvironmentObject var api: API
    let c: Chapter
    var sub: String? = nil
    @State private var target: ReaderTarget?
    @State private var busy = false
    var body: some View {
        Button {
            guard let m = c.manga else { return }
            busy = true
            Task { if let d = try? await api.manga(m.id, refresh: false) { target = ReaderTarget(manga: d.manga, chapters: d.chapters, chapterId: c.id) }; busy = false }
        } label: {
            HStack {
                AsyncImage(url: api.img(c.manga?.thumbnailUrl)) { $0.resizable().scaledToFill() } placeholder: { Color(.secondarySystemBackground) }.frame(width: 44, height: 62).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading) { Text(c.manga?.title ?? "").lineLimit(1); Text(sub ?? c.name + (c.isDownloaded ? " · on server" : "")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer(); if busy { ProgressView() }
            }.foregroundStyle(c.isRead ? .secondary : .primary)
        }
        .navigationDestination(item: $target) { ReaderView(target: $0) }
    }
}

// MARK: - Downloads (server queue + device)

struct DownloadsView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var device: DeviceStore
    @State private var status: DownloadStatus?
    @State private var error = ""
    @State private var timer: Timer?
    var body: some View {
        List {
            Section {
                if let e = device.lastError { Text(e).font(.caption).foregroundStyle(.red) }
                if device.queue.isEmpty && device.chapters.isEmpty { Text("Nothing on this device. Use “Download to this device” on a chapter.").foregroundStyle(.secondary) }
                ForEach(device.queue, id: \.chapter.id) { job in
                    HStack { VStack(alignment: .leading) { Text(job.manga.title).lineLimit(1); Text(job.chapter.name).font(.caption).foregroundStyle(.secondary) }; Spacer(); ProgressView(value: device.progress[job.chapter.id] ?? 0).frame(width: 60); Button { device.remove(job.chapter.id) } label: { Image(systemName: "xmark") } }
                }
                ForEach(device.byManga, id: \.id) { m in
                    DisclosureGroup { ForEach(m.chapters) { c in HStack { Text(c.chapterName); Spacer(); Text(fmtBytes(c.bytes)).font(.caption).foregroundStyle(.secondary) }.swipeActions { Button(role: .destructive) { device.remove(c.chapterId) } label: { Label("Remove", systemImage: "trash") } } } } label: {
                        HStack { Text(m.title).lineLimit(1); Spacer(); Text("\(m.chapters.count) ch · \(fmtBytes(m.chapters.reduce(0) { $0 + $1.bytes }))").font(.caption).foregroundStyle(.secondary) }
                    }.swipeActions { Button(role: .destructive) { device.removeManga(m.id) } label: { Label("Remove all", systemImage: "trash") } }
                }
            } header: { Text("On this device · \(fmtBytes(device.totalBytes))") }
            Section {
                if !error.isEmpty { ErrorBanner(text: error) }
                if let s = status {
                    if s.queue.isEmpty { Text("Server queue is empty.").foregroundStyle(.secondary) }
                    ForEach(s.queue) { d in
                        HStack { VStack(alignment: .leading) { Text(d.manga.title).lineLimit(1); Text("\(d.chapter.name ?? "") · \(d.state.lowercased())").font(.caption).foregroundStyle(.secondary); ProgressView(value: d.progress) }; Button { Task { try? await api.dequeue([d.chapter.id]); await load() } } label: { Image(systemName: "xmark") } }
                    }
                }
            } header: {
                HStack { Text("Server queue · \(status?.state.lowercased() ?? "")"); Spacer()
                    Button(status?.state == "STARTED" ? "Pause" : "Resume") { Task { try? await api.downloader(start: status?.state != "STARTED"); await load() } }.font(.caption)
                    Button("Clear") { Task { try? await api.dequeue(status?.queue.map { $0.chapter.id } ?? []); await load() } }.font(.caption).disabled(status?.queue.isEmpty ?? true) }
            }
        }
        .navigationTitle("Downloads")
        .task { await load() }
        .onAppear { timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in Task { await load() } } }
        .onDisappear { timer?.invalidate() }
    }
    func load() async { do { status = try await api.downloadStatus(); error = "" } catch { self.error = error.localizedDescription } }
}

// MARK: - More

struct MoreView: View {
    @EnvironmentObject var web: WebServer
    var body: some View {
        List {
            NavigationLink { HistoryView() } label: { Label("History", systemImage: "clock") }
            NavigationLink { ServerFilesView(path: "") } label: { Label("Files on the server", systemImage: "externaldrive") }
            NavigationLink { DeviceFilesView() } label: { Label("Files on this device", systemImage: "iphone") }
            NavigationLink { WebServerView() } label: { HStack { Label("Web Server", systemImage: "wifi"); Spacer(); if web.running { Text("on").foregroundStyle(.green) } } }
            NavigationLink { ExtensionsView() } label: { Label("Extensions & repos", systemImage: "puzzlepiece.extension") }
            NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gear") }
        }.kumoDestinations().navigationTitle("More")
    }
}

// MARK: - Files on the server (file service)

struct ServerFilesView: View {
    @EnvironmentObject var api: API
    let path: String
    @State private var list: API.FSList?
    @State private var error = ""
    @State private var newFolder = false
    @State private var folderName = ""
    @State private var rename: API.FSEntry?
    @State private var renameTo = ""
    @State private var importing = false
    @State private var uploading = ""
    var body: some View {
        List {
            if path.isEmpty { Text("local/ is yours: CBZ/ZIP files in local/<Manga>/ appear in Browse → Local source. manga/ is what the server downloaded (read-only here).").font(.caption).foregroundStyle(.secondary) }
            if !error.isEmpty { ErrorBanner(text: error) }
            if !uploading.isEmpty { Label(uploading, systemImage: "arrow.up.circle") }
            ForEach(list?.entries ?? []) { e in
                let p = (path.isEmpty ? "" : path + "/") + e.name
                if e.dir { NavigationLink { ServerFilesView(path: p) } label: { Label(e.name, systemImage: "folder") } }
                else { Link(destination: api.fsFileURL(p) ?? URL(string: "about:blank")!) { HStack { Label(e.name, systemImage: "doc"); Spacer(); Text(fmtBytes(e.size)).font(.caption).foregroundStyle(.secondary) } } }
            }
            .onDelete { idx in if list?.writable == true, !path.isEmpty { for i in idx { let e = list!.entries[i]; Task { try? await api.fsDelete((path.isEmpty ? "" : path + "/") + e.name); await load() } } } }
            if (list?.writable ?? false) && !path.isEmpty {
                Section {
                    Button { newFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    Button { importing = true } label: { Label("Upload files from this device", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .navigationTitle(path.isEmpty ? "Server files" : (path as NSString).lastPathComponent)
        .task { await load() }.refreshable { await load() }
        .alert("New folder", isPresented: $newFolder) { TextField("Manga title", text: $folderName); Button("Create") { Task { try? await api.fsMkdir(path + "/" + folderName); folderName = ""; await load() } }; Button("Cancel", role: .cancel) {} }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, UTType(filenameExtension: "cbz") ?? .zip, .data], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            Task {
                for u in urls {
                    let ok = u.startAccessingSecurityScopedResource(); defer { if ok { u.stopAccessingSecurityScopedResource() } }
                    uploading = "Uploading \(u.lastPathComponent)…"
                    do { try await api.fsUpload(path + "/" + u.lastPathComponent, fileURL: u) } catch { self.error = error.localizedDescription }
                }
                uploading = ""; await load()
            }
        }
    }
    func load() async { do { list = try await api.fsList(path); error = "" } catch { self.error = error.localizedDescription } }
}

// MARK: - Files on this device (CBZ library) + Web Server

struct DeviceFilesView: View {
    @EnvironmentObject var device: DeviceStore
    @State private var books: [DeviceStore.LocalBook] = []
    @State private var importing = false
    var body: some View {
        List {
            Text("Drop CBZ/ZIP here through More → Web Server, the Files app (On My iPhone → Kumo → Local), or Import.").font(.caption).foregroundStyle(.secondary)
            ForEach(books) { b in
                DisclosureGroup {
                    ForEach(Array(b.files.enumerated()), id: \.offset) { i, f in
                        NavigationLink(value: LocalBookTarget(title: b.folder, files: b.files, index: i)) { Text(f.deletingPathExtension().lastPathComponent) }
                            .swipeActions { Button(role: .destructive) { try? FileManager.default.removeItem(at: f); books = device.localBooks() } label: { Label("Delete", systemImage: "trash") } }
                    }
                } label: { HStack { Label(b.folder, systemImage: "books.vertical"); Spacer(); Text("\(b.files.count)").foregroundStyle(.secondary) } }
            }
            Button { importing = true } label: { Label("Import CBZ/ZIP…", systemImage: "square.and.arrow.down") }
        }
        .kumoDestinations().navigationTitle("On this device")
        .onAppear { books = device.localBooks() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, UTType(filenameExtension: "cbz") ?? .zip, .data], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            for u in urls {
                let ok = u.startAccessingSecurityScopedResource(); defer { if ok { u.stopAccessingSecurityScopedResource() } }
                let folder = DeviceStore.local.appendingPathComponent(u.deletingPathExtension().lastPathComponent, isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: u, to: folder.appendingPathComponent(u.lastPathComponent))
            }
            books = device.localBooks()
        }
    }
}

struct WebServerView: View {
    @EnvironmentObject var web: WebServer
    var body: some View {
        List {
            Section {
                Toggle("Web Server", isOn: Binding(get: { web.running }, set: { $0 ? web.start() : web.stop() }))
                if web.running { Text(web.address).font(.title3.monospaced()).textSelection(.enabled); Text("Open that address in a browser on a computer on the same Wi‑Fi and drop CBZ/ZIP files. Keep this screen open while uploading.").font(.caption).foregroundStyle(.secondary) }
                else { Text("Turns this device into a drop target for comics, like Panels: no cable, no cloud.").font(.caption).foregroundStyle(.secondary) }
            }
            Section("Activity") { ForEach(Array(web.log.suffix(20).reversed().enumerated()), id: \.offset) { Text($0.element).font(.caption) } }
        }.navigationTitle("Web Server")
    }
}

// MARK: - Extensions & repos

struct ExtensionsView: View {
    @EnvironmentObject var api: API
    @State private var exts: [Extension] = []
    @State private var stores: [ExtensionStore] = []
    @State private var tab = 0
    @State private var q = ""
    @State private var error = ""
    @State private var busyPkg = ""
    @State private var newRepo = ""
    @State private var nsfw = API.shared.nsfw
    @State private var langs = API.shared.langs
    var shown: [Extension] {
        var l = exts.filter { tab == 0 ? $0.isInstalled : tab == 1 ? $0.hasUpdate : !$0.isInstalled }
        if tab != 0 { l = l.filter { (nsfw || $0.contentWarning != "NSFW") && (langs.contains("*") || langs.contains($0.lang)) } }
        if !q.isEmpty { l = l.filter { ($0.name + $0.pkgName).localizedCaseInsensitiveContains(q) } }
        return l.sorted { ($0.lang, $0.name) < ($1.lang, $1.name) }
    }
    var allLangs: [String] { Array(Set(exts.map { $0.lang })).sorted() }
    var body: some View {
        List {
            Section("Repositories") {
                ForEach(stores) { s in VStack(alignment: .leading) { Text(s.name); Text(s.indexUrl).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }.swipeActions { Button(role: .destructive) { Task { try? await api.removeStore(s.indexUrl); await load() } } label: { Label("Remove", systemImage: "trash") } } }
                HStack { TextField("https://…/index.pb", text: $newRepo).autocapitalization(.none).keyboardType(.URL); Button("Add") { Task { do { try await api.addStore(newRepo); try await api.fetchExtensions(); newRepo = ""; await load() } catch { self.error = error.localizedDescription } } }.disabled(newRepo.isEmpty) }
                Button("Refresh extension list") { Task { try? await api.fetchExtensions(); await load() } }
            }
            Section {
                Picker("", selection: $tab) { Text("Installed").tag(0); Text("Updates").tag(1); Text("Available").tag(2) }.pickerStyle(.segmented)
                if tab != 0 {
                    Toggle("Show 18+", isOn: $nsfw).onChange(of: nsfw) { _, v in api.nsfw = v }
                    ScrollView(.horizontal, showsIndicators: false) { HStack { Chip(text: "any", on: langs.contains("*")) { toggleLang("*") }; ForEach(allLangs, id: \.self) { l in Chip(text: l, on: langs.contains(l)) { toggleLang(l) } } } }
                }
                if !error.isEmpty { ErrorBanner(text: error) }
                ForEach(shown.prefix(300)) { e in
                    HStack {
                        AsyncImage(url: api.img(e.iconUrl)) { $0.resizable() } placeholder: { Color(.secondarySystemBackground) }.frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading) { Text(e.name); Text("\(e.lang) · \(e.versionName)\(e.contentWarning == "NSFW" ? " · 18+" : e.contentWarning == "MIXED" ? " · mixed" : "")\(e.isObsolete ? " · obsolete" : "")").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if busyPkg == e.pkgName { ProgressView() }
                        else if e.hasUpdate { Button("Update") { act(e.pkgName, update: true) }.buttonStyle(.borderedProminent).font(.caption) }
                        else if e.isInstalled { Button("Remove") { act(e.pkgName, uninstall: true) }.buttonStyle(.bordered).font(.caption) }
                        else { Button("Install") { act(e.pkgName, install: true) }.buttonStyle(.borderedProminent).font(.caption) }
                    }
                }
                if shown.count > 300 { Text("\(shown.count - 300) more — narrow the search.").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Extensions").searchable(text: $q)
        .task { await load() }
    }
    func toggleLang(_ l: String) { if langs.contains(l) { langs.remove(l) } else { langs.insert(l) }; api.langs = langs }
    func act(_ pkg: String, install: Bool? = nil, uninstall: Bool? = nil, update: Bool? = nil) {
        busyPkg = pkg
        Task { do { try await api.extensionAction(pkg, install: install, uninstall: uninstall, update: update); await load() } catch { self.error = error.localizedDescription }; busyPkg = "" }
    }
    func load() async { do { async let e = api.extensions(); async let s = api.stores(); exts = try await e; stores = try await s; error = "" } catch { self.error = error.localizedDescription } }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var api: API
    @State private var about: API.About?
    @State private var cbz = true
    @State private var auto = false
    @State private var interval = 12.0
    @State private var error = ""
    @State private var server = ""
    var body: some View {
        Form {
            Section("Server") {
                TextField("https://server:8443", text: $server).autocapitalization(.none).keyboardType(.URL).onSubmit { api.base = server }
                if let a = about { Text("\(a.aboutServer.name) \(a.aboutServer.version)\ndownloads: \(a.settings.downloadsPath)\nuploads: \(a.settings.localSourcePath)").font(.caption).foregroundStyle(.secondary) }
                if !error.isEmpty { ErrorBanner(text: error) }
                Button("Sign out (\(api.user))", role: .destructive) { api.logout() }
            }
            Section("Server downloads & updates") {
                Toggle("Save chapters as CBZ", isOn: $cbz)
                Toggle("Auto-download new chapters", isOn: $auto)
                Stepper("Check for new chapters every \(Int(interval)) h", value: $interval, in: 0...48, step: 6)
                Button("Apply") { Task { do { try await api.setSettings(["downloadAsCbz": cbz, "autoDownloadNewChapters": auto, "globalUpdateInterval": interval]) } catch { self.error = error.localizedDescription } } }
            }
            Section("About") { Text("Panels Rea: Tachiyomi-style sources through your own server (the server runs the extensions), Panels-style files and web server on the device. Same account and library as the web app.").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Settings")
        .task { server = api.base; do { about = try await api.about(); cbz = about!.settings.downloadAsCbz; auto = about!.settings.autoDownloadNewChapters; interval = about!.settings.globalUpdateInterval } catch { self.error = error.localizedDescription } }
    }
}
