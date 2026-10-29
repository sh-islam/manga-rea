import Foundation
import Network

/// Panels-style "Web Server": a tiny HTTP server on the phone. Open the shown address in a computer's browser
/// and drop CBZ/ZIP files; they land in Documents/Kumo/Local/<Manga>/ and show up under Files → On this device.
@MainActor
final class WebServer: ObservableObject {
    static let shared = WebServer()
    @Published var running = false
    @Published var address: String = ""
    @Published var log: [String] = []
    let port: UInt16 = 8787
    private var listener: NWListener?

    func start() {
        guard listener == nil else { return }
        do {
            let l = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { [weak self] c in Task { @MainActor in self?.handle(c) } }
            l.stateUpdateHandler = { [weak self] st in Task { @MainActor in if case .failed(let e) = st { self?.log.append("listener failed: \(e)"); self?.stop() } } }
            l.start(queue: .global(qos: .userInitiated))
            listener = l; running = true
            address = "http://\(WebServer.wifiIP() ?? "<this device's Wi‑Fi IP>"):\(port)/"
            log.append("started on \(address)")
        } catch { log.append("could not start: \(error.localizedDescription)") }
    }
    func stop() { listener?.cancel(); listener = nil; running = false; log.append("stopped") }

    private func handle(_ c: NWConnection) {
        let conn = HTTPConn(c, root: DeviceStore.local) { [weak self] line in Task { @MainActor in self?.log.append(line); if (self?.log.count ?? 0) > 60 { self?.log.removeFirst() } } }
        conn.start()
    }

    static func wifiIP() -> String? {
        var addr: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(p.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0, let sa = p.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard name == "en0" || name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { addr = String(cString: host); if name == "en0" { break } }
        }
        return addr
    }
}

/// One HTTP/1.1 connection: parses the request head, streams PUT bodies straight to disk.
final class HTTPConn {
    let c: NWConnection; let root: URL; let log: (String) -> Void
    private var buf = Data()
    init(_ c: NWConnection, root: URL, log: @escaping (String) -> Void) { self.c = c; self.root = root; self.log = log }
    func start() { c.start(queue: .global(qos: .userInitiated)); readHead() }

    private func readHead() {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, done, err in
            if let d = data { buf.append(d) }
            if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[buf.startIndex..<r.lowerBound], as: UTF8.self)
                let body0 = buf.subdata(in: r.upperBound..<buf.endIndex)
                buf = Data()
                route(head: head, firstBody: body0)
            } else if done || err != nil || buf.count > 1 << 20 { c.cancel() } else { readHead() }
        }
    }
    private func route(head: String, firstBody: Data) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.components(separatedBy: " ") ?? []
        guard parts.count >= 2 else { return c.cancel() }
        let method = parts[0]; let target = parts[1]
        var headers: [String: String] = [:]
        for l in lines.dropFirst() { if let i = l.firstIndex(of: ":") { headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
        let comps = URLComponents(string: target)
        let path = comps?.path ?? "/"
        let q = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let len = Int(headers["content-length"] ?? "0") ?? 0
        switch (method, path) {
        case ("GET", "/"): send(200, "text/html; charset=utf-8", Data(HTTPConn.page.utf8))
        case ("GET", "/api/list"): send(200, "application/json", list())
        case ("PUT", "/api/upload"):
            guard let rel = q["path"], let dest = safe(rel), !rel.hasSuffix("/") else { return send(400, "text/plain", Data("bad path".utf8)) }
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = dest.appendingPathExtension("part")
            FileManager.default.createFile(atPath: tmp.path, contents: nil)
            guard let h = try? FileHandle(forWritingTo: tmp) else { return send(500, "text/plain", Data("cannot write".utf8)) }
            var left = len
            let first = firstBody.prefix(left); h.write(first); left -= first.count
            func pump() {
                if left <= 0 {
                    try? h.close(); try? FileManager.default.removeItem(at: dest); try? FileManager.default.moveItem(at: tmp, to: dest)
                    log("received \(rel) (\(fmtBytes(len)))"); send(200, "application/json", Data("{\"ok\":true}".utf8)); return
                }
                c.receive(minimumIncompleteLength: 1, maximumLength: min(left, 1 << 20)) { [self] d, _, done, err in
                    if let d = d { h.write(d); left -= d.count }
                    if err != nil || (done && left > 0) { try? h.close(); try? FileManager.default.removeItem(at: tmp); c.cancel(); return }
                    pump()
                }
            }
            pump()
        case ("POST", "/api/mkdir"), ("POST", "/api/delete"):
            readBody(len, firstBody) { [self] body in
                let j = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
                guard let rel = j["path"] as? String, let u = safe(rel), u != root else { return send(400, "text/plain", Data("bad path".utf8)) }
                if path == "/api/mkdir" { try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true) } else { try? FileManager.default.removeItem(at: u) }
                send(200, "application/json", Data("{\"ok\":true}".utf8))
            }
        default: send(404, "text/plain", Data("not found".utf8))
        }
    }
    private func readBody(_ len: Int, _ first: Data, _ done: @escaping (Data) -> Void) {
        var body = first
        func more() {
            if body.count >= len { return done(body.prefix(len)) }
            c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [self] d, _, eof, err in
                if let d = d { body.append(d) }
                if err != nil || eof && body.count < len { c.cancel(); return }
                more()
            }
        }
        more()
    }
    private func safe(_ rel: String) -> URL? {
        let clean = rel.removingPercentEncoding ?? rel
        guard !clean.contains("..") else { return nil }
        let u = root.appendingPathComponent(clean.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        return u.path.hasPrefix(root.standardizedFileURL.path) ? u : nil
    }
    private func list() -> Data {
        var out: [[String: Any]] = []
        let fm = FileManager.default
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let u as URL in e {
                let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                out.append(["path": String(u.path.dropFirst(root.path.count + 1)), "dir": v?.isDirectory ?? false, "size": v?.fileSize ?? 0])
            }
        }
        return (try? JSONSerialization.data(withJSONObject: out)) ?? Data("[]".utf8)
    }
    private func send(_ code: Int, _ type: String, _ body: Data) {
        let reason = code == 200 ? "OK" : code == 400 ? "Bad Request" : code == 404 ? "Not Found" : "Error"
        var head = "HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\n\r\n"
        if body.isEmpty { head += "" }
        var d = Data(head.utf8); d.append(body)
        c.send(content: d, completion: .contentProcessed { [self] _ in c.cancel() })
    }

    static let page = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Kumo on this device</title>
    <style>body{font:15px -apple-system,Segoe UI,Roboto,sans-serif;background:#12141b;color:#e8eaf0;margin:0;padding:20px;max-width:760px;margin:auto}h1{font-size:22px}
    .drop{border:2px dashed #3a3f55;border-radius:12px;padding:40px;text-align:center;color:#9aa0b4;margin:14px 0}.drop.over{border-color:#8ab4ff;color:#fff}
    input,button{font:inherit;background:#242838;color:#e8eaf0;border:0;border-radius:8px;padding:8px 12px}button.p{background:#3b6fd6;color:#fff}
    .row{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin:8px 0}.it{display:flex;gap:10px;align-items:center;padding:7px 0;border-bottom:1px solid #242838}.it span{flex:1}
    .bar{height:6px;background:#242838;border-radius:4px;overflow:hidden}.bar i{display:block;height:100%;background:#8ab4ff;width:0}.muted{color:#9aa0b4;font-size:13px}</style></head><body>
    <h1>Kumo — drop comics onto this device</h1><p class="muted">Files go into a folder named after the manga (one folder per title, one CBZ/ZIP per chapter).</p>
    <div class="row"><label>Folder (manga title) <input id="folder" placeholder="e.g. One Piece" style="min-width:220px"></label><label class="p" style="padding:8px 12px;border-radius:8px;background:#3b6fd6;cursor:pointer">Choose files <input type="file" multiple hidden id="f"></label></div>
    <div class="drop" id="drop">…or drop CBZ / ZIP files here</div><div id="prog"></div><h3>On the device</h3><div id="list"></div>
    <script>
    const $=s=>document.querySelector(s);const list=async()=>{const r=await (await fetch('/api/list')).json();$('#list').innerHTML=r.filter(x=>!x.dir).sort((a,b)=>a.path.localeCompare(b.path)).map(x=>`<div class="it"><span>${x.path}</span><em class="muted">${(x.size/1048576).toFixed(1)} MB</em><button data-p="${x.path.replace(/"/g,'&quot;')}">Delete</button></div>`).join('')||'<p class="muted">Nothing yet.</p>'};
    $('#list').onclick=async e=>{const p=e.target.dataset.p;if(p&&confirm('Delete '+p+'?')){await fetch('/api/delete',{method:'POST',body:JSON.stringify({path:p})});list()}};
    async function up(files){const folder=$('#folder').value.trim();if(!folder)return alert('Type the manga title (folder) first');for(const f of files){const row=document.createElement('div');row.innerHTML=`<div class="muted">${f.name}</div><div class="bar"><i></i></div>`;$('#prog').appendChild(row);
    await new Promise(res=>{const x=new XMLHttpRequest();x.open('PUT','/api/upload?path='+encodeURIComponent(folder+'/'+f.name));x.upload.onprogress=e=>row.querySelector('i').style.width=Math.round(e.loaded/e.total*100)+'%';x.onload=x.onerror=res;x.send(f)})}list()}
    $('#f').onchange=e=>up([...e.target.files]);const d=$('#drop');d.ondragover=e=>{e.preventDefault();d.classList.add('over')};d.ondragleave=()=>d.classList.remove('over');d.ondrop=e=>{e.preventDefault();d.classList.remove('over');up([...e.dataTransfer.files])};list();
    </script></body></html>
    """
}
