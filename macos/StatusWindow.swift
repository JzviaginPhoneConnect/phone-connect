// PhoneConnect Status: the small window that shows, in plain words, what PhoneConnect
// is doing until the phone's picture appears (macOS). The Windows version is the
// --status mode of windows/Launcher.cs.
//
//   PhoneConnect Status.app/Contents/MacOS/PhoneConnectStatus <status file>
//
// PhoneConnect.sh appends one line per step to the status file. The window shows the
// newest line large, with a spinner, and the few before it small. It only reads and
// writes files (no process handling, which antivirus scanners distrust):
//   <status file>         a line "__done__" closes the window
//   <status file>.alive   PhoneConnect.sh refreshes it; when it goes stale, it's gone
//   <status file>.cancel  Cancel creates it; PhoneConnect.sh then stops itself
// Built by build/build-macos.sh (swiftc, Apple Silicon + Intel).

import Cocoa

final class StatusController: NSObject, NSApplicationDelegate {
    private let statusPath: String
    private let started = Date()
    private var window: NSWindow!
    private let current = NSTextField(wrappingLabelWithString: "Starting…")
    private let earlier = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private var shownLines = -1

    init(statusPath: String) {
        self.statusPath = statusPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 150),
                          styleMask: [.titled, .miniaturizable], backing: .buffered, defer: false)
        window.title = "PhoneConnect"
        window.isReleasedWhenClosed = false

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        current.font = .systemFont(ofSize: 15, weight: .semibold)
        current.preferredMaxLayoutWidth = 292
        current.translatesAutoresizingMaskIntoConstraints = false
        current.widthAnchor.constraint(equalToConstant: 292).isActive = true
        earlier.font = .systemFont(ofSize: 11)
        earlier.textColor = .secondaryLabelColor
        earlier.preferredMaxLayoutWidth = 316
        earlier.translatesAutoresizingMaskIntoConstraints = false
        earlier.widthAnchor.constraint(equalToConstant: 316).isActive = true
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.keyEquivalent = "\u{1b}"   // Esc

        let headline = NSStackView(views: [spinner, current])
        headline.alignment = .firstBaseline
        headline.spacing = 8
        let text = NSStackView(views: [headline, earlier])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        let top = NSStackView(views: [icon, text])
        top.alignment = .top
        top.spacing = 16
        let buttons = NSStackView(views: [NSView(), cancel])
        let all = NSStackView(views: [top, buttons])
        all.orientation = .vertical
        all.alignment = .trailing
        all.spacing = 12
        top.widthAnchor.constraint(equalToConstant: 400).isActive = true
        buttons.widthAnchor.constraint(equalTo: top.widthAnchor).isActive = true
        // margins around everything
        let container = NSView()
        all.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(all)
        NSLayoutConstraint.activate([
            all.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            all.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            all.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            all.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])
        window.contentView = container
        window.setContentSize(container.fittingSize)

        // Low on the screen, so the app's own dialogs (in the middle) stay clear of it
        if let screen = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.minY + screen.height * 0.18))
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        poll()
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        // PhoneConnect.sh is gone (finished, crashed or stopped): nothing left to show
        if !phoneConnectRunning() { NSApp.terminate(nil); return }
        guard let data = FileManager.default.contents(atPath: statusPath),
              let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if lines.contains("__done__") { NSApp.terminate(nil); return }
        guard lines.count != shownLines, let last = lines.last else { return }
        shownLines = lines.count
        current.stringValue = last
        earlier.stringValue = lines.dropLast().suffix(5).joined(separator: "\n")
    }

    // PhoneConnect.sh refreshes <status file>.alive every 0.5 s while it runs
    private func phoneConnectRunning() -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: statusPath + ".alive")
        guard let changed = attributes?[.modificationDate] as? Date else {
            return Date().timeIntervalSince(started) < 5     // not there (yet)
        }
        return Date().timeIntervalSince(changed) < 5
    }

    @objc private func cancelPressed() {
        FileManager.default.createFile(atPath: statusPath + ".cancel", contents: Data())
        NSApp.terminate(nil)
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: PhoneConnectStatus <status file>\n".data(using: .utf8)!)
    exit(2)
}
let app = NSApplication.shared
let controller = StatusController(statusPath: arguments[1])
app.delegate = controller
app.setActivationPolicy(.regular)
app.run()
