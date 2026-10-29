import SwiftUI

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject var api: API
    @EnvironmentObject var device: DeviceStore
    @State private var all: [Manga] = []
    @State private var cats: [Category] = []
    @State private var cat: Int = -1
    @State private var filter = ""
    @State private var sort = UserDefaults.standard.string(forKey: "lib.sort") ?? "title"
    @State private var only = ""
    @State private var error = ""
    @State private var loading = true
    @State private var showCats = false

    var list: [Manga] {
        var l = all.filter { cat < 0 || ($0.categories?.nodes.contains { $0.id == cat } ?? false) }
        if !filter.isEmpty { l = l.filter { ($0.title + " " + ($0.author ?? "")).localizedCaseInsensitiveContains(filter) } }
        if only == "unread" { l = l.filter { ($0.unreadCount ?? 0) > 0 } }
        if only == "server" { l = l.filter { ($0.downloadCount ?? 0) > 0 } }
        if only == "device" { l = l.filter { device.mangaCount($0.id) > 0 } }
        switch sort {
        case "unread": l.sort { ($0.unreadCount ?? 0) > ($1.unreadCount ?? 0) }
        case "latest": l.sort { (Double($0.latestUploadedChapter?.uploadDate ?? "0") ?? 0) > (Double($1.latestUploadedChapter?.uploadDate ?? "0") ?? 0) }
        default: l.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return l
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Chip(text: "All (\(all.count))", on: cat < 0) { cat = -1 }
                        ForEach(cats) { c in Chip(text: "\(c.name) (\(c.mangas?.totalCount ?? 0))", on: cat == c.id) { cat = c.id } }
                    }.padding(.horizontal, 12)
                }
                if !error.isEmpty { ErrorBanner(text: error) }
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                else if list.isEmpty { Text(all.isEmpty ? "Your library is empty. Browse a source and tap “Add to library”." : "Nothing matches.").foregroundStyle(.secondary).padding() }
                MangaGrid(mangas: list, device: device)
            }.padding(.vertical, 8)
        }
        .kumoDestinations()
        .navigationTitle("Library")
        .searchable(text: $filter, prompt: "Filter library")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) { Text("Title").tag("title"); Text("Unread").tag("unread"); Text("Latest chapter").tag("latest") }
                    Picker("Show", selection: $only) { Text("All").tag(""); Text("Unread").tag("unread"); Text("On server").tag("server"); Text("On this device").tag("device") }
                    Button { showCats = true } label: { Label("Categories…", systemImage: "folder") }
                    Button { Task { try? await api.updateLibrary() } } label: { Label("Update library now", systemImage: "arrow.triangle.2.circlepath") }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
        }
        .onChange(of: sort) { _, v in UserDefaults.standard.set(v, forKey: "lib.sort") }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showCats) { CategoriesSheet(cats: cats) { Task { await load() } } }
    }
    func load() async {
        do { async let a = api.library(); async let c = api.categories(); all = try await a; cats = try await c; error = "" } catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct Chip: View {
    let text: String; let on: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) { Text(text).font(.footnote).padding(.horizontal, 10).padding(.vertical, 5).background(on ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground), in: Capsule()).overlay(Capsule().stroke(on ? Color.accentColor : .clear)) }.buttonStyle(.plain)
    }
}

struct CategoriesSheet: View {
    @EnvironmentObject var api: API
    @Environment(\.dismiss) var dismiss
    @State var cats: [Category]
    let done: () -> Void
    @State private var name = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(cats) { c in
                    HStack { Text(c.name); Spacer(); Text("\(c.mangas?.totalCount ?? 0)").foregroundStyle(.secondary) }
                        .swipeActions { if !c.default { Button(role: .destructive) { Task { try? await api.deleteCategory(c.id); cats = (try? await api.categories()) ?? cats } } label: { Label("Delete", systemImage: "trash") } } }
                }
                HStack { TextField("New category", text: $name); Button("Add") { Task { try? await api.createCategory(name); name = ""; cats = (try? await api.categories()) ?? cats } }.disabled(name.isEmpty) }
            }
            .navigationTitle("Categories").toolbar { Button("Done") { done(); dismiss() } }
        }
    }
}

// MARK: - Browse: global search + sources

struct BrowseView: View {
    @EnvironmentObject var api: API
    @State private var sources: [Source] = []
    @State private var query = ""
    @State private var results: [(Source, [Manga])] = []
    @State private var searching = false
    @State private var error = ""
    var body: some View {
        List {
            if searching { ProgressView("Searching every source…") }
            ForEach(results, id: \.0.id) { (src, mangas) in
                Section(src.displayName) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(mangas.prefix(10)) { m in NavigationLink(value: m) { Cover(manga: m).frame(width: 100) }.buttonStyle(.plain) } }
                    }.listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                }
            }
            Section("Sources (\(api.visible(sources).count))") {
                if !error.isEmpty { ErrorBanner(text: error) }
                ForEach(api.visible(sources)) { s in
                    NavigationLink(value: s) {
                        HStack {
                            AsyncImage(url: api.img(s.iconUrl)) { $0.resizable() } placeholder: { Color(.secondarySystemBackground) }.frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) { Text(s.displayName); Text(s.isLocal ? "files on the server (local/)" : s.lang + (s.contentWarning == "NSFW" ? " · 18+" : s.contentWarning == "MIXED" ? " · may contain 18+" : "")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if sources.isEmpty { Text("No sources yet. Install extensions under More → Extensions.").foregroundStyle(.secondary) }
            }
        }
        .kumoDestinations()
        .navigationTitle("Browse")
        .searchable(text: $query, prompt: "Search every source")
        .onSubmit(of: .search) { Task { await search() } }
        .task { await load() }
        .refreshable { await load() }
    }
    func load() async { do { sources = try await api.sources(); error = "" } catch { self.error = error.localizedDescription } }
    func search() async {
        let q = query.trimmingCharacters(in: .whitespaces); guard !q.isEmpty else { return }
        searching = true; results = []
        await withTaskGroup(of: (Source, [Manga])?.self) { g in
            for s in api.visible(sources) where !s.isLocal { g.addTask { if let r = try? await api.sourceManga(s.id, type: "SEARCH", page: 1, query: q), !r.mangas.isEmpty { return (s, r.mangas) }; return nil } }
            for await r in g { if let r = r { results.append(r) } }
        }
        results.sort { $0.0.displayName < $1.0.displayName }
        searching = false
    }
}

// MARK: - One source

struct SourceView: View {
    @EnvironmentObject var api: API
    let source: Source
    @State private var type = "POPULAR"
    @State private var query = ""
    @State private var page = 1
    @State private var items: [Manga] = []
    @State private var more = false
    @State private var loading = false
    @State private var error = ""
    @State private var detail: SourceDetail?
    @State private var filters: [FilterChange]? = nil
    @State private var showFilters = false
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Picker("", selection: $type) { Text("Popular").tag("POPULAR"); if source.supportsLatest { Text("Latest").tag("LATEST") }; if !query.isEmpty || filters != nil { Text("Search").tag("SEARCH") } }.pickerStyle(.segmented)
                    if !(detail?.filters.isEmpty ?? true) { Button { showFilters = true } label: { Image(systemName: filters == nil ? "slider.horizontal.3" : "slider.horizontal.3").foregroundStyle(filters == nil ? Color.primary : Color.accentColor) } }
                }.padding(.horizontal, 12)
                if !error.isEmpty { ErrorBanner(text: error) }
                MangaGrid(mangas: items) { if more && !loading { page += 1; Task { await load(reset: false) } } }
                if loading { ProgressView().padding() }
                if !loading && items.isEmpty && !error.isEmpty == false { Text("Nothing here.").foregroundStyle(.secondary).padding() }
            }.padding(.vertical, 8)
        }
        .kumoDestinations()
        .navigationTitle(source.displayName).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search \(source.displayName)")
        .onSubmit(of: .search) { type = "SEARCH"; Task { await load(reset: true) } }
        .onChange(of: type) { _, _ in Task { await load(reset: true) } }
        .task { type = source.supportsLatest ? "LATEST" : "POPULAR"; detail = try? await api.source(source.id); if items.isEmpty { await load(reset: true) } }
        .sheet(isPresented: $showFilters) { if let d = detail { FilterSheet(filters: d.filters) { f in filters = f; type = "SEARCH"; Task { await load(reset: true) } } } }
    }
    func load(reset: Bool) async {
        if loading { return }
        loading = true
        if reset { page = 1; items = [] }
        do {
            let r = try await api.sourceManga(source.id, type: type, page: page, query: type == "SEARCH" ? query : nil, filters: type == "SEARCH" ? filters : nil)
            items.append(contentsOf: r.mangas.filter { m in !items.contains(where: { $0.id == m.id }) }); more = r.hasNextPage; error = ""
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

/// Builds FilterChangeInput values from the source's filter tree. Position = index in the list.
struct FilterSheet: View {
    @Environment(\.dismiss) var dismiss
    let filters: [SourceFilter]
    let apply: ([FilterChange]?) -> Void
    @State private var state: [String: Any] = [:]   // key "p" or "p.c" -> value
    var body: some View {
        NavigationStack {
            Form {
                ForEach(Array(filters.enumerated()), id: \.offset) { i, f in
                    if f.__typename == "GroupFilter" {
                        Section(f.name) { ForEach(Array((f.filters ?? []).enumerated()), id: \.offset) { j, g in row(g, key: "\(i).\(j)") } }
                    } else if f.__typename == "HeaderFilter" { Section(f.name) {} }
                    else if f.__typename != "SeparatorFilter" { row(f, key: "\(i)") }
                }
            }
            .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Reset") { apply(nil); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { apply(build()); dismiss() } }
            }
        }
    }
    @ViewBuilder func row(_ f: SourceFilter, key: String) -> some View {
        switch f.__typename {
        case "CheckBoxFilter": Toggle(f.name, isOn: Binding(get: { (state[key] as? Bool) ?? (f.cbDefault ?? false) }, set: { state[key] = $0 }))
        case "TriStateFilter": Picker(f.name, selection: Binding(get: { (state[key] as? String) ?? (f.triDefault ?? "IGNORE") }, set: { state[key] = $0 })) { Text("—").tag("IGNORE"); Text("Include").tag("INCLUDE"); Text("Exclude").tag("EXCLUDE") }
        case "SelectFilter": Picker(f.name, selection: Binding(get: { (state[key] as? Int) ?? (f.selDefault ?? 0) }, set: { state[key] = $0 })) { ForEach(Array((f.values ?? []).enumerated()), id: \.offset) { j, v in Text(v).tag(j) } }
        case "TextFilter": TextField(f.name, text: Binding(get: { (state[key] as? String) ?? (f.textDefault ?? "") }, set: { state[key] = $0 }))
        case "SortFilter":
            Picker(f.name, selection: Binding(get: { (state[key] as? Int) ?? (f.sortDefault?.index ?? 0) }, set: { state[key] = $0 })) { ForEach(Array((f.values ?? []).enumerated()), id: \.offset) { j, v in Text(v).tag(j) } }
            Toggle("Ascending", isOn: Binding(get: { (state[key + "asc"] as? Bool) ?? (f.sortDefault?.ascending ?? true) }, set: { state[key + "asc"] = $0 }))
        default: EmptyView()
        }
    }
    func build() -> [FilterChange]? {
        var out: [FilterChange] = []
        func change(_ f: SourceFilter, key: String) -> [String: Any]? {
            switch f.__typename {
            case "CheckBoxFilter": if let v = state[key] as? Bool { return ["checkBoxState": v] }
            case "TriStateFilter": if let v = state[key] as? String, v != "IGNORE" { return ["triState": v] }
            case "SelectFilter": if let v = state[key] as? Int { return ["selectState": v] }
            case "TextFilter": if let v = state[key] as? String, !v.isEmpty { return ["textState": v] }
            case "SortFilter": if state[key] != nil || state[key + "asc"] != nil { return ["sortState": ["index": (state[key] as? Int) ?? (f.sortDefault?.index ?? 0), "ascending": (state[key + "asc"] as? Bool) ?? (f.sortDefault?.ascending ?? true)]] }
            default: break
            }
            return nil
        }
        for (i, f) in filters.enumerated() {
            if f.__typename == "GroupFilter" {
                for (j, g) in (f.filters ?? []).enumerated() { if let c = change(g, key: "\(i).\(j)") { var gc: [String: Any] = ["position": j]; gc.merge(c) { a, _ in a }; out.append(["position": i, "groupChange": gc]) } }
            } else if let c = change(f, key: "\(i)") { var d: [String: Any] = ["position": i]; d.merge(c) { a, _ in a }; out.append(d) }
        }
        return out.isEmpty ? nil : out
    }
}
