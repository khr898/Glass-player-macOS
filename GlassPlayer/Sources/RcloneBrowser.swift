import Cocoa

// ---------------------------------------------------------------------------
// RcloneBrowser – browse and play files from an rclone serve HTTP instance
// Apple-style design, follows system theme, regular NSWindow (movable to Spaces)
// ---------------------------------------------------------------------------

class RcloneBrowser: NSWindowController, NSTableViewDelegate, NSTableViewDataSource {

    // MARK: - Data Model

    struct FileEntry {
        let name: String        // Display name (decoded)
        let href: String        // URL-encoded path component from rclone
        let isDirectory: Bool
        let sizeInfo: String    // Size text from listing
    }

    // MARK: - State

    private var baseUrl: String = ""
    private var currentPath: String = "/"
    private var pathHistory: [String] = []
    private var entries: [FileEntry] = []
    private var isConnected = false
    private var keyMonitor: Any?
    private var currentTask: URLSessionDataTask?

    // Cached regex for HTML parsing (compiled once)
    private static let linkRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"<a\s+href="([^"]+)"\s*>([^<]+)</a>\s*(.*)"#,
            options: []
        )
    }()

    // MARK: - UI Elements

    private let urlField = NSTextField()
    private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
    private let backButton = NSButton()
    private let upButton = NSButton()
    private let refreshButton = NSButton()
    private let pathLabel = NSTextField(labelWithString: "/")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "Enter an rclone serve URL and press Connect")
    private let placeholderLabel = NSTextField(labelWithString: "Connect to an rclone HTTP server to browse files")

    weak var playerWindow: PlayerWindow?
    var onFileSelected: ((String) -> Void)?

    // MARK: - Media Extensions

    private static let mediaExtensions: Set<String> = [
        "mp4", "mkv", "avi", "mov", "wmv", "webm", "flv", "m4v", "ts",
        "mpg", "mpeg", "3gp", "ogv", "vob", "asf", "rm", "rmvb",
        "mp3", "m4a", "flac", "wav", "ogg", "aac", "wma", "opus"
    ]

    // MARK: - Cached Icons

    private static let folderIcon = NSImage(systemSymbolName: "folder.fill",
        accessibilityDescription: nil)
    private static let filmIcon = NSImage(systemSymbolName: "film",
        accessibilityDescription: nil)
    private static let docIcon = NSImage(systemSymbolName: "doc",
        accessibilityDescription: nil)

    // MARK: - Init

    init() {
        // Use regular NSWindow instead of NSPanel so it can move across Spaces
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "rclone Browser"
        window.minSize = NSSize(width: 400, height: 300)
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = .moveToActiveSpace
        // Follow system theme — do NOT force darkAqua

        super.init(window: window)
        setupUI()
        setupKeyHandler()

        // Restore last URL
        if let savedUrl = UserDefaults.standard.string(forKey: "rcloneBaseUrl"),
           !savedUrl.isEmpty {
            urlField.stringValue = savedUrl
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // Background visual effect for unified look
        let bgEffect = NSVisualEffectView(frame: contentView.bounds)
        bgEffect.material = .sidebar
        bgEffect.blendingMode = .behindWindow
        bgEffect.state = .active
        bgEffect.autoresizingMask = [.width, .height]
        contentView.addSubview(bgEffect)

        // ── Connection bar ──
        let connectionBar = NSView()
        connectionBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(connectionBar)

        urlField.placeholderString = "http://localhost:8080"
        urlField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlField.target = self
        urlField.action = #selector(connectAction)
        urlField.focusRingType = .default
        urlField.bezelStyle = .roundedBezel
        connectionBar.addSubview(urlField)

        connectButton.bezelStyle = .rounded
        connectButton.font = .systemFont(ofSize: 12, weight: .medium)
        connectButton.target = self
        connectButton.action = #selector(connectAction)
        connectButton.translatesAutoresizingMaskIntoConstraints = false
        connectionBar.addSubview(connectButton)

        // ── Navigation bar ──
        let navBar = NSView()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(navBar)

        configureNavButton(backButton, symbol: "chevron.left", action: #selector(goBack))
        backButton.isEnabled = false
        navBar.addSubview(backButton)

        configureNavButton(upButton, symbol: "chevron.up", action: #selector(goUp))
        upButton.isEnabled = false
        navBar.addSubview(upButton)

        configureNavButton(refreshButton, symbol: "arrow.clockwise", action: #selector(refreshAction))
        refreshButton.isEnabled = false
        navBar.addSubview(refreshButton)

        pathLabel.font = .systemFont(ofSize: 12, weight: .medium)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        navBar.addSubview(pathLabel)

        // ── Separator ──
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        // ── Table view ──
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "Name"
        nameColumn.resizingMask = .autoresizingMask
        nameColumn.minWidth = 200
        tableView.addTableColumn(nameColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 80
        sizeColumn.minWidth = 60
        sizeColumn.maxWidth = 120
        tableView.addTableColumn(sizeColumn)

        tableView.delegate = self
        tableView.dataSource = self
        tableView.doubleAction = #selector(tableDoubleClick)
        tableView.target = self
        tableView.rowHeight = 32
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.style = .plain
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .regular

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        // ── Placeholder ──
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(placeholderLabel)

        // ── Status bar ──
        let statusSeparator = NSBox()
        statusSeparator.boxType = .separator
        statusSeparator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusSeparator)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        // ── Layout ──
        NSLayoutConstraint.activate([
            // Connection bar
            connectionBar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            connectionBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            connectionBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            connectionBar.heightAnchor.constraint(equalToConstant: 28),

            urlField.leadingAnchor.constraint(equalTo: connectionBar.leadingAnchor),
            urlField.centerYAnchor.constraint(equalTo: connectionBar.centerYAnchor),
            urlField.trailingAnchor.constraint(equalTo: connectButton.leadingAnchor, constant: -8),

            connectButton.trailingAnchor.constraint(equalTo: connectionBar.trailingAnchor),
            connectButton.centerYAnchor.constraint(equalTo: connectionBar.centerYAnchor),
            connectButton.widthAnchor.constraint(equalToConstant: 86),

            // Nav bar
            navBar.topAnchor.constraint(equalTo: connectionBar.bottomAnchor, constant: 10),
            navBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            navBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            navBar.heightAnchor.constraint(equalToConstant: 24),

            backButton.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 22),
            backButton.heightAnchor.constraint(equalToConstant: 22),

            upButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 2),
            upButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            upButton.widthAnchor.constraint(equalToConstant: 22),
            upButton.heightAnchor.constraint(equalToConstant: 22),

            refreshButton.leadingAnchor.constraint(equalTo: upButton.trailingAnchor, constant: 2),
            refreshButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),
            refreshButton.widthAnchor.constraint(equalToConstant: 22),
            refreshButton.heightAnchor.constraint(equalToConstant: 22),

            pathLabel.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: navBar.trailingAnchor),
            pathLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            // Separator
            separator.topAnchor.constraint(equalTo: navBar.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            // Scroll view (table)
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusSeparator.topAnchor),

            // Placeholder (centered in scroll area)
            placeholderLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            // Status separator
            statusSeparator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusSeparator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusSeparator.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -4),

            // Status bar
            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    private func configureNavButton(_ button: NSButton, symbol: String, action: Selector) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Key Handling

    private func setupKeyHandler() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, event.window == self.window else { return event }
            // Don't intercept when typing in the URL field
            if self.window?.firstResponder is NSTextView,
               let fieldEditor = self.window?.fieldEditor(false, for: self.urlField),
               self.window?.firstResponder == fieldEditor {
                return event
            }

            switch event.keyCode {
            case 36: // Return/Enter → open selected entry
                let row = self.tableView.selectedRow
                if row >= 0, row < self.entries.count {
                    self.openEntry(self.entries[row])
                    return nil
                }
            case 51: // Delete/Backspace → go back
                self.goBack()
                return nil
            case 53: // Escape → close
                self.close()
                return nil
            case 125: // Down arrow → select next row
                break  // let table handle it
            case 126: // Up arrow → select prev row
                break  // let table handle it
            default:
                break
            }
            return event
        }
    }

    // MARK: - Actions

    @objc private func connectAction() {
        var url = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { return }

        // Add http:// if missing
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "http://" + url
        }
        // Remove trailing slash
        while url.hasSuffix("/") { url.removeLast() }

        baseUrl = url
        currentPath = "/"
        pathHistory = []
        isConnected = true

        UserDefaults.standard.set(url, forKey: "rcloneBaseUrl")

        connectButton.title = "Reconnect"
        refreshButton.isEnabled = true
        fetchDirectory()
    }

    @objc private func goBack() {
        guard !pathHistory.isEmpty else { return }
        currentPath = pathHistory.removeLast()
        fetchDirectory()
    }

    @objc private func goUp() {
        guard currentPath != "/" else { return }
        pathHistory.append(currentPath)
        var components = currentPath.split(separator: "/")
        components.removeLast()
        currentPath = components.isEmpty ? "/" : "/" + components.joined(separator: "/") + "/"
        fetchDirectory()
    }

    @objc private func refreshAction() {
        guard isConnected else { return }
        fetchDirectory()
    }

    @objc private func tableDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0, row < entries.count else { return }
        openEntry(entries[row])
    }

    private func openEntry(_ entry: FileEntry) {
        if entry.isDirectory {
            pathHistory.append(currentPath)
            currentPath = currentPath + entry.href
            fetchDirectory()
        } else {
            // Build full URL and play
            let fullUrl = baseUrl + currentPath + entry.href
            if let callback = onFileSelected {
                callback(fullUrl)
            } else {
                playerWindow?.loadUrl(fullUrl)
            }
            statusLabel.stringValue = "Playing: \(entry.name)"
        }
    }

    // MARK: - Fetch Directory Listing

    private func fetchDirectory() {
        let urlString = baseUrl + currentPath
        guard let url = URL(string: urlString) else {
            statusLabel.stringValue = "Invalid URL"
            return
        }

        // Cancel any in-flight request to avoid stale responses
        currentTask?.cancel()

        statusLabel.stringValue = "Loading..."
        pathLabel.stringValue = currentPath
        backButton.isEnabled = !pathHistory.isEmpty
        upButton.isEnabled = currentPath != "/"
        placeholderLabel.isHidden = true

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                if let error = error {
                    // Ignore cancelled requests (from rapid navigation)
                    if (error as NSError).code == NSURLErrorCancelled { return }
                    self.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                    self.entries = []
                    self.tableView.reloadData()
                    self.placeholderLabel.stringValue = "Connection failed"
                    self.placeholderLabel.isHidden = false
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode != 200 {
                    self.statusLabel.stringValue = "HTTP \(httpResponse.statusCode)"
                    self.entries = []
                    self.tableView.reloadData()
                    self.placeholderLabel.stringValue = "Server returned \(httpResponse.statusCode)"
                    self.placeholderLabel.isHidden = false
                    return
                }

                guard let data = data, let html = String(data: data, encoding: .utf8) else {
                    self.statusLabel.stringValue = "Invalid response"
                    return
                }

                UniversalSiliconQoS.maintenance.async { [weak self] in
                    guard let self = self else { return }
                    let parsed = self.parseDirectoryListing(html)
                    DispatchQueue.main.async {
                        self.entries = parsed
                        self.tableView.reloadData()
                        self.statusLabel.stringValue = "\(self.entries.count) items"

                        if self.entries.isEmpty {
                            self.placeholderLabel.stringValue = "Empty directory"
                            self.placeholderLabel.isHidden = false
                        }
                    }
                }
            }
        }
        currentTask = task
        task.resume()
    }

    // MARK: - HTML Parsing

    private func parseDirectoryListing(_ html: String) -> [FileEntry] {
        // rclone serve http format:
        //   <a href="encoded_name">display_name</a>  optional_size  optional_date
        guard let regex = Self.linkRegex else { return [] }

        let nsHtml = html as NSString
        let matches = regex.matches(in: html, options: [],
            range: NSRange(location: 0, length: nsHtml.length))

        var result: [FileEntry] = []

        for match in matches {
            let href = nsHtml.substring(with: match.range(at: 1))
            let displayName = nsHtml.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespaces)
            let rawExtra = match.range(at: 3).location != NSNotFound
                ? nsHtml.substring(with: match.range(at: 3))
                    .trimmingCharacters(in: .whitespaces)
                : ""
            // Strip HTML tags (e.g. <span>...</span>) from the extra text
            let extra = rawExtra.replacingOccurrences(of: "<[^>]+>", with: "",
                options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)

            // Skip parent directory link
            if href == "../" || href == ".." || href == "/" { continue }
            // Skip the heading link (rclone sometimes includes the path itself)
            if href == "./" { continue }

            let isDir = href.hasSuffix("/")
            let name: String
            if isDir {
                // Remove trailing slash from display
                let trimmed = displayName.hasSuffix("/")
                    ? String(displayName.dropLast())
                    : displayName
                name = trimmed.removingPercentEncoding ?? trimmed
            } else {
                name = displayName.removingPercentEncoding ?? displayName
            }

            let sizeInfo = isDir ? "—" : extractSize(from: extra)

            result.append(FileEntry(
                name: name,
                href: href,
                isDirectory: isDir,
                sizeInfo: sizeInfo
            ))
        }

        // Sort: directories first, then alphabetically
        result.sort { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return result
    }

    private func extractSize(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        // rclone outputs size as first token: could be raw bytes or human-readable
        let parts = trimmed.components(separatedBy: CharacterSet.whitespaces)
            .filter { !$0.isEmpty }
        guard let first = parts.first else { return "" }
        // Try parsing as raw byte count
        if let bytes = Int64(first) {
            return formatFileSize(bytes)
        }
        return first
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let kb: Int64 = 1024
        let mb = kb * 1024
        let gb = mb * 1024
        if bytes >= gb {
            return String(format: "%.1f GB", Double(bytes) / Double(gb))
        } else if bytes >= mb {
            return String(format: "%.1f MB", Double(bytes) / Double(mb))
        } else if bytes >= kb {
            return String(format: "%.0f KB", Double(bytes) / Double(kb))
        } else {
            return "\(bytes) B"
        }
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return entries.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < entries.count else { return nil }
        let entry = entries[row]
        let colID = tableColumn?.identifier.rawValue ?? "name"

        if colID == "name" {
            let cellID = NSUserInterfaceItemIdentifier("NameCell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil)
                as? NSTableCellView {
                cell = reused
                cell.textField?.stringValue = entry.name
                cell.imageView?.image = iconForEntry(entry)
                cell.imageView?.contentTintColor = tintForEntry(entry)
                return cell
            }

            cell = NSTableCellView()
            cell.identifier = cellID

            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.image = iconForEntry(entry)
            iv.contentTintColor = tintForEntry(entry)
            cell.imageView = iv
            cell.addSubview(iv)

            let tf = NSTextField(labelWithString: entry.name)
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            tf.font = .systemFont(ofSize: 13)
            cell.textField = tf
            cell.addSubview(tf)

            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 16),
                iv.heightAnchor.constraint(equalToConstant: 16),
                tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])

            return cell
        } else {
            // Size column
            let cellID = NSUserInterfaceItemIdentifier("SizeCell")
            let cell: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: cellID, owner: nil)
                as? NSTableCellView {
                cell = reused
                cell.textField?.stringValue = entry.sizeInfo
                return cell
            }

            cell = NSTableCellView()
            cell.identifier = cellID

            let tf = NSTextField(labelWithString: entry.sizeInfo)
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.font = .systemFont(ofSize: 11)
            tf.textColor = .secondaryLabelColor
            tf.alignment = .right
            cell.textField = tf
            cell.addSubview(tf)

            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])

            return cell
        }
    }

    private func iconForEntry(_ entry: FileEntry) -> NSImage? {
        if entry.isDirectory {
            return Self.folderIcon
        }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        return Self.mediaExtensions.contains(ext) ? Self.filmIcon : Self.docIcon
    }

    private func tintForEntry(_ entry: FileEntry) -> NSColor {
        if entry.isDirectory { return .controlAccentColor }
        let ext = (entry.name as NSString).pathExtension.lowercased()
        return Self.mediaExtensions.contains(ext) ? .systemOrange : .secondaryLabelColor
    }

    // MARK: - Show

    func showBrowser() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Position next to main player window if possible
        if let mainFrame = playerWindow?.window?.frame,
           let browserWindow = window {
            let screen = NSScreen.main?.visibleFrame ?? NSRect.zero
            var x = mainFrame.maxX + 12
            let y = mainFrame.midY - browserWindow.frame.height / 2
            // If it would go off-screen, place to the left
            if x + browserWindow.frame.width > screen.maxX {
                x = mainFrame.minX - browserWindow.frame.width - 12
            }
            browserWindow.setFrameOrigin(NSPoint(x: max(screen.minX, x),
                                                  y: max(screen.minY, y)))
        } else {
            window?.center()
        }
    }
}
