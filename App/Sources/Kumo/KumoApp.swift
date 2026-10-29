import SwiftUI
import UIKit

@main
struct KumoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var api = API.shared
    @StateObject private var device = DeviceStore.shared
    @StateObject private var web = WebServer.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if api.loggedIn { RootView() } else { LoginView() }
            }
            .environmentObject(api).environmentObject(device).environmentObject(web)
            .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SignatureReminder.scheduleIfNeeded()
        return true
    }
}

struct RootView: View {
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { LibraryView() }.tabItem { Label("Library", systemImage: "books.vertical") }.tag(0)
            NavigationStack { BrowseView() }.tabItem { Label("Browse", systemImage: "magnifyingglass") }.tag(1)
            NavigationStack { UpdatesView() }.tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }.tag(2)
            NavigationStack { DownloadsView() }.tabItem { Label("Downloads", systemImage: "arrow.down.circle") }.tag(3)
            NavigationStack { MoreView() }.tabItem { Label("More", systemImage: "ellipsis") }.tag(4)
        }
    }
}

struct LoginView: View {
    @EnvironmentObject var api: API
    @State private var server = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var error = ""
    @State private var busy = false
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cloud.fill").font(.system(size: 56)).foregroundStyle(Color.accentColor)
            Text("Panels Rea").font(.largeTitle.bold())
            Text("Sign in to your server").foregroundStyle(.secondary)
            TextField("https://server:8443", text: $server).textContentType(.URL).keyboardType(.URL).autocapitalization(.none).textFieldStyle(.roundedBorder)
            TextField("username", text: $user).textContentType(.username).autocapitalization(.none).textFieldStyle(.roundedBorder)
            SecureField("password", text: $pass).textContentType(.password).textFieldStyle(.roundedBorder)
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.footnote) }
            Button { Task { busy = true; defer { busy = false }; do { try await api.login(server: server, user: user, pass: pass) } catch { self.error = "Sign-in failed: \(error.localizedDescription)" } } } label: {
                Text(busy ? "Signing in…" : "Sign in").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).disabled(busy || server.isEmpty || user.isEmpty)
            Spacer(); Spacer()
        }
        .padding(24)
        .onAppear {
            server = api.base; user = api.user
            // baked-in login (Secrets.swift, generated at build time, never in git): sign in without any setup
            if !BuiltIn.server.isEmpty && !busy { server = BuiltIn.server; user = BuiltIn.user; pass = BuiltIn.pass
                Task { busy = true; defer { busy = false }; do { try await api.login(server: server, user: user, pass: pass) } catch { self.error = "Auto sign-in failed: \(error.localizedDescription)" } } }
        }
    }
}

// MARK: - shared small views

struct Cover: View {
    let manga: Manga
    var badgeUnread: Int? = nil
    var badgeDevice: Int? = nil
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(.secondarySystemBackground)
            AsyncImage(url: API.shared.img(manga.thumbnailUrl)) { img in img.resizable().scaledToFill() } placeholder: { Color(.secondarySystemBackground) }
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            Text(manga.title).font(.caption.bold()).foregroundStyle(.white).lineLimit(2).padding(7).shadow(radius: 2)
            HStack(spacing: 3) {
                if let u = badgeUnread, u > 0 { Badge(text: "\(u)", color: .accentColor) }
                if let d = manga.downloadCount, d > 0 { Badge(text: "\(d)", color: .green) }
                if let d = badgeDevice, d > 0 { Badge(text: "📱\(d)", color: .orange) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(5)
            if manga.inLibrary { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).background(Circle().fill(.black)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(5) }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
struct Badge: View {
    let text: String; let color: Color
    var body: some View { Text(text).font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 2).background(color, in: RoundedRectangle(cornerRadius: 5)) }
}

struct MangaGrid: View {
    let mangas: [Manga]
    var device: DeviceStore? = nil
    var onEnd: (() -> Void)? = nil
    private let cols = [GridItem(.adaptive(minimum: 105), spacing: 10)]
    var body: some View {
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(mangas) { m in
                NavigationLink(value: m) { Cover(manga: m, badgeUnread: m.unreadCount, badgeDevice: device?.mangaCount(m.id)) }
                    .buttonStyle(.plain)
                    .onAppear { if m.id == mangas.last?.id { onEnd?() } }
            }
        }
        .padding(.horizontal, 12)
    }
}

struct ErrorBanner: View {
    let text: String
    var body: some View { Text(text).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
}

extension View {
    /// Push MangaView for Manga values and ReaderView for ReaderTarget values.
    func kumoDestinations() -> some View {
        self.navigationDestination(for: Manga.self) { MangaView(mangaId: $0.id, seed: $0) }
            .navigationDestination(for: ReaderTarget.self) { ReaderView(target: $0) }
            .navigationDestination(for: Source.self) { SourceView(source: $0) }
            .navigationDestination(for: LocalBookTarget.self) { LocalReaderView(book: $0) }
    }
}
