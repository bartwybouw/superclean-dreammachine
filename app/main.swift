// Superclean Dreammachine — native Mac-wrapper rond hans-prisma-shuffle.html
// AppKit + WKWebView, gebouwd met swiftc (geen Xcode-project).
//
// De webview laadt de HTML LIVE uit de projectmap via loadFileURL(_:allowingReadAccessTo:),
// zodat updates aan de HTML meteen zichtbaar zijn (Cmd+R) zonder opnieuw te bouwen.
//
// Extra's:
//  - Het Dock-icoon toont de afspeelstatus (play-driehoek / pauze-streepjes, halftransparant).
//  - Rechtsklik op het Dock-icoon geeft Afspelen / Pauze.
//  - De status wordt uit de Mixcloud-widget gelezen via een geïnjecteerd scriptje,
//    zonder de HTML zelf te moeten aanpassen.

import Cocoa
import WebKit
import MediaPlayer
import Sparkle

// --- Configuratie ------------------------------------------------------------

let kHtmlFilename = "hans-prisma-shuffle.html"

let kAppName = "Superclean Dreammachine"
let kFrameAutosaveName = "SCDMainWindow"

/// Projectmap met de HTML. build.sh schrijft het echte pad in Info.plist (sleutel
/// HPSProjectDir); valt dat weg, dan proberen we een map met de repo-naam in de homefolder.
func projectDirURL() -> URL {
    if let dir = Bundle.main.object(forInfoDictionaryKey: "HPSProjectDir") as? String,
       !dir.isEmpty {
        return URL(fileURLWithPath: dir, isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("superclean-dreammachine", isDirectory: true)
}

func htmlURL() -> URL {
    // Dev: live uit de projectmap, zodat HTML-wijzigingen meteen zichtbaar zijn.
    let dev = projectDirURL().appendingPathComponent(kHtmlFilename)
    if FileManager.default.fileExists(atPath: dev.path) { return dev }
    // Distributie (DMG): kopie die in de app zelf zit (Contents/Resources).
    if let bundled = Bundle.main.url(forResource: "hans-prisma-shuffle", withExtension: "html") {
        return bundled
    }
    return dev
}

func appVersion() -> String {
    (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?"
}

let kRepoURL = "https://github.com/bartwybouw/superclean-dreammachine"

enum PlayState { case idle, playing, paused }

// --- Hoofdcontroller ---------------------------------------------------------

final class Controller: NSObject, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate,
                        WKScriptMessageHandler {
    var window: NSWindow!
    var webView: WKWebView!
    var updaterController: SPUStandardUpdaterController?   // Sparkle (gezet door AppDelegate)
    var baseIcon: NSImage = NSImage()        // het statische app-icoon (3D-knop)
    var state: PlayState = .idle

    // Scriptje dat Mixcloud.PlayerWidget omwikkelt en play/pause/ended naar native stuurt.
    // Raakt de HTML niet aan; werkt in een gewone browser gewoon niet (webkit ontbreekt daar).
    static let hookJS = """
    (function(){
      function post(s){ try{ window.webkit.messageHandlers.scd.postMessage(s); }catch(e){} }
      function attach(w){
        try{ w.ready.then(function(){
          w.events.play.on(function(){ post('playing'); });
          w.events.pause.on(function(){ post('paused'); });
          w.events.ended.on(function(){ post('paused'); });
        }); }catch(e){}
      }
      function hook(){
        if(!window.Mixcloud || typeof window.Mixcloud.PlayerWidget!=='function') return false;
        if(window.Mixcloud.__scdHooked) return true;
        var orig = window.Mixcloud.PlayerWidget;
        window.Mixcloud.PlayerWidget = function(){
          var w = orig.apply(this, arguments);
          attach(w);
          return w;
        };
        window.Mixcloud.__scdHooked = true;
        return true;
      }
      if(!hook()){
        var t = setInterval(function(){ if(hook()) clearInterval(t); }, 300);
        setTimeout(function(){ clearInterval(t); }, 60000);
      }
    })();
    """

    func start() {
        baseIcon = NSApp.applicationIconImage ?? NSImage()
        buildMenu()
        setupRemoteCommands()
        makeWindow()
        loadPage()
    }

    // --- Media-toetsen van het toetsenbord (play/pause/stop) -----------------
    // Via MPRemoteCommandCenter ontvangt de app de hardware-mediatoetsen en de
    // Control Center-/Now Playing-bediening; we vertalen ze naar de widget.
    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in self?.dockPlay(); return .success }
        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in self?.dockPause(); return .success }
        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        cc.stopCommand.isEnabled = true
        cc.stopCommand.addTarget { [weak self] _ in self?.dockPause(); return .success }
        // Sommige toetsenborden sturen vorige/volgende → volgende = willekeurige show.
        cc.nextTrackCommand.isEnabled = true
        cc.nextTrackCommand.addTarget { [weak self] _ in self?.dockNext(); return .success }
        cc.previousTrackCommand.isEnabled = true
        cc.previousTrackCommand.addTarget { [weak self] _ in self?.dockNext(); return .success }
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    @objc func toggle() {
        if state == .playing { dockPause() } else { dockPlay() }
    }

    @objc func dockNext() {
        webView?.evaluateJavaScript(
            "try { var b = document.getElementById('shuffleBtn'); if (b) b.click(); } catch(e) {}")
    }

    /// Houdt de systeem-\"Now Playing\"-status in sync met de widget.
    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        switch state {
        case .playing: center.playbackState = .playing
        case .paused:  center.playbackState = .paused
        case .idle:    center.playbackState = .stopped; return
        }
        webView?.evaluateJavaScript(
            "(function(){var t=document.getElementById('nowTitle');return t?t.textContent:'';})()"
        ) { result, _ in
            var info = center.nowPlayingInfo ?? [:]
            let title = (result as? String).flatMap { $0.isEmpty ? nil : $0 } ?? kAppName
            info[MPMediaItemPropertyTitle] = title
            info[MPMediaItemPropertyArtist] = "Hans Prisma · Superclean Dreammachine"
            center.nowPlayingInfo = info
        }
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        // Automatisch afspelen toelaten (ook na herstart) — geen klik vereist.
        config.mediaTypesRequiringUserActionForPlayback = []
        // Persistente datastore: localStorage (gespeelde shows, positie, volume, bewaarde
        // nummers) blijft bewaard tussen app-starts.
        config.websiteDataStore = WKWebsiteDataStore.default()

        // Statushook injecteren + berichtenkanaal "scd".
        let ucc = WKUserContentController()
        ucc.add(self, name: "scd")
        ucc.addUserScript(WKUserScript(source: Self.hookJS,
                                       injectionTime: .atDocumentEnd,
                                       forMainFrameOnly: true))
        config.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.uiDelegate = self
        wv.navigationDelegate = self
        // Media (Mixcloud-widget) blijft spelen als het venster naar de achtergrond gaat:
        // dat is standaardgedrag van WKWebView, er is geen extra instelling voor nodig.
        return wv
    }

    private func makeWindow() {
        webView = makeWebView()

        let rect = NSRect(x: 0, y: 0, width: 1100, height: 840)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = kAppName
        window.delegate = self
        window.contentView = webView
        window.minSize = NSSize(width: 480, height: 480)

        // Venstergrootte en -positie onthouden tussen sessies.
        window.setFrameAutosaveName(kFrameAutosaveName)
        if !window.setFrameUsingName(kFrameAutosaveName) {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadPage() {
        setState(.idle)   // verse pagina: nog niets aan het spelen
        let html = htmlURL()
        let dir = html.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: html.path) else {
            let alert = NSAlert()
            alert.messageText = "Pagina niet gevonden"
            alert.informativeText = """
            De pagina werd niet gevonden:
            \(html.path)

            Controleer dat 'hans-prisma-shuffle.html' in de projectmap staat, of herbouw
            de app met build.sh zodat het juiste pad in Info.plist (HPSProjectDir) komt.
            """
            alert.alertStyle = .critical
            alert.runModal()
            return
        }
        // allowingReadAccessTo = de volledige projectmap, zodat relatieve assets mogen laden.
        webView.loadFileURL(html, allowingReadAccessTo: dir)
    }

    // --- Afspeelstatus → Dock-icoon -----------------------------------------

    private func setState(_ s: PlayState) {
        state = s
        NSApp.applicationIconImage = dockIcon(for: s)
        updateNowPlaying()
    }

    /// Tekent de play/pause-glyph halftransparant over het basis-icoon.
    private func dockIcon(for s: PlayState) -> NSImage {
        guard s != .idle else { return baseIcon }

        let size = NSSize(width: 512, height: 512)
        let img = NSImage(size: size)
        img.lockFocus()
        baseIcon.draw(in: NSRect(origin: .zero, size: size),
                      from: .zero, operation: .copy, fraction: 1.0)

        let c = NSPoint(x: size.width / 2, y: size.height / 2)
        let r: CGFloat = 150

        // Zachte, halftransparante schijf als achtergrond voor leesbaarheid.
        let disc = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        NSColor(white: 0, alpha: 0.38).setFill()
        disc.fill()
        NSColor(white: 1, alpha: 0.22).setStroke()
        disc.lineWidth = 4
        disc.stroke()

        NSColor(white: 1, alpha: 0.9).setFill()
        if s == .playing {
            // play-driehoek (optisch gecentreerd, iets naar rechts)
            let tr: CGFloat = 78
            let dx: CGFloat = 16
            let tri = NSBezierPath()
            tri.move(to: NSPoint(x: c.x - tr * 0.5 + dx, y: c.y - tr))
            tri.line(to: NSPoint(x: c.x - tr * 0.5 + dx, y: c.y + tr))
            tri.line(to: NSPoint(x: c.x + tr * 0.95 + dx, y: c.y))
            tri.close()
            tri.fill()
        } else {
            // pauze-streepjes
            let bw: CGFloat = 36, bh: CGFloat = 132, gap: CGFloat = 36
            NSBezierPath(roundedRect: NSRect(x: c.x - gap / 2 - bw, y: c.y - bh / 2,
                                             width: bw, height: bh),
                         xRadius: 9, yRadius: 9).fill()
            NSBezierPath(roundedRect: NSRect(x: c.x + gap / 2, y: c.y - bh / 2,
                                             width: bw, height: bh),
                         xRadius: 9, yRadius: 9).fill()
        }

        img.unlockFocus()
        return img
    }

    // --- Widget aansturen vanuit Dock-menu -----------------------------------

    @objc func dockPlay() {
        // Speelt de huidige show, of start een willekeurige als er nog niets geladen is.
        webView?.evaluateJavaScript("""
        try {
          if (typeof widget !== 'undefined' && widget) { widget.play(); }
          else { var b = document.getElementById('shuffleBtn'); if (b) b.click(); }
        } catch(e) {}
        """)
    }

    @objc func dockPause() {
        webView?.evaluateJavaScript(
            "try { if (typeof widget !== 'undefined' && widget) { widget.pause(); } } catch(e) {}")
    }

    func makeDockMenu() -> NSMenu {
        let m = NSMenu()
        let play = m.addItem(withTitle: "Afspelen", action: #selector(dockPlay), keyEquivalent: "")
        play.target = self
        let pause = m.addItem(withTitle: "Pauze", action: #selector(dockPause), keyEquivalent: "")
        pause.target = self
        return m
    }

    // --- WKScriptMessageHandler ----------------------------------------------

    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "scd", let s = message.body as? String else { return }
        switch s {
        case "playing": setState(.playing)
        case "paused":  setState(.paused)
        default: break
        }
    }

    // --- Menu ----------------------------------------------------------------

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App-menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let about = appMenu.addItem(
            withTitle: "Over \(kAppName)", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        let updates = appMenu.addItem(
            withTitle: "Zoek naar updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updates.target = updaterController
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Verberg \(kAppName)",
            action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Verberg andere",
            action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Stop \(kAppName)",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Weergave-menu
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "Weergave")
        viewItem.submenu = viewMenu
        let reload = viewMenu.addItem(
            withTitle: "Herlaad pagina", action: #selector(reloadPage), keyEquivalent: "r")
        reload.target = self

        // Venster-menu
        let winItem = NSMenuItem()
        mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: "Venster")
        winItem.submenu = winMenu
        winMenu.addItem(
            withTitle: "Minimaliseer",
            action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = winMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.applicationName: kAppName,
            NSApplication.AboutPanelOptionKey.applicationVersion: appVersion(),
            // Lege build-versie: geen "(5)" achter het versienummer. Het buildnummer
            // (CFBundleVersion) blijft in Info.plist, Sparkle heeft het nodig.
            NSApplication.AboutPanelOptionKey.version: "",
            NSApplication.AboutPanelOptionKey.credits: aboutCredits(),
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"):
                "Mixcloud-archief van Hans Prisma · Superclean Dreammachine",
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Credits in het Over-venster: maker, eerbetoon en een klikbare link naar het project.
    private func aboutCredits() -> NSAttributedString {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: centered,
        ]
        var bold = base
        bold[.font] = NSFont.boldSystemFont(ofSize: 11)
        var muted = base
        muted[.foregroundColor] = NSColor.secondaryLabelColor
        var link = base
        link[.link] = URL(string: kRepoURL)

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "Gemaakt door ", attributes: base))
        s.append(NSAttributedString(string: "Bart Wybouw", attributes: bold))
        s.append(NSAttributedString(string: "\nTer nagedachtenis aan Hans Prisma\n\n", attributes: muted))
        s.append(NSAttributedString(string: "github.com/bartwybouw/superclean-dreammachine", attributes: link))
        return s
    }

    @objc private func reloadPage() {
        loadPage()   // vers van schijf → HTML-wijzigingen meteen zichtbaar
    }

    // --- WKUIDelegate: target="_blank" en window.open → standaardbrowser --------

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = message; a.runModal(); completionHandler()
    }
}

// --- App-delegate ------------------------------------------------------------

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    // Sparkle: controleert dagelijks de appcast (SUFeedURL in Info.plist) en installeert
    // updates die met de EdDSA-sleutel (SUPublicEDKey) ondertekend zijn.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.updaterController = updaterController
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller.window?.makeKeyAndOrderFront(nil) }
        return true
    }

    // Rechtsklik-menu op het Dock-icoon: Afspelen / Pauze.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        controller.makeDockMenu()
    }
}

// --- Entrypoint --------------------------------------------------------------

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
