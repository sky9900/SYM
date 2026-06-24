// The MIT License (MIT)
//
// Copyright (c) 2017 - present zqqf16
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Cocoa

extension NSPopUpButton {
    func reloadItemsWithApps(_ apps: [MDAppInfo]) {
        removeAllItems()
        apps.forEach { app in
            self.addItem(withTitle: "\(app.name)(\(app.identifier))")
        }
    }
}

class FileBrowserViewController: NSViewController, LoadingAble {
    @IBOutlet var exportButton: NSButton!
    @IBOutlet var exportIndicator: NSProgressIndicator!
    @IBOutlet var outlineView: NSOutlineView!

    var loadingIndicator: NSProgressIndicator!

    private var deviceID: String?
    private var appID: String?

    private var rootDir: MDDeviceFile!
    private var afcClient: MDAfcClient!

    private var searchText: String = ""
    private var searchResults: [MDDeviceFile] = []
    private var searchPathMap: [MDDeviceFile: String] = [:]
    private var isSearchMode: Bool {
        return !searchText.isEmpty
    }

    private var savedExpandedPaths: Set<String> = []
    private var savedScrollPosition: CGFloat = 0
    private var shouldRestoreState = false

    private var searchField: NSSearchField!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSearchField()
    }

    private func setupSearchField() {
        let searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "搜索文件或文件夹"
        searchField.sendsWholeSearchString = false
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldDidChange(_:))
        self.searchField = searchField

        view.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchField.widthAnchor.constraint(equalToConstant: 200),
        ])
    }

    @objc @IBAction func searchFieldDidChange(_ sender: NSSearchField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespaces)
        searchText = text
        if !text.isEmpty {
            performSearch(text)
        } else {
            searchResults.removeAll()
            searchPathMap.removeAll()
            outlineView.reloadData()
        }
    }

    func reloadData(withDeviceID deviceID: String?, appID: String?) {
        if deviceID == self.deviceID && appID == self.appID {
            return
        }

        self.deviceID = deviceID
        self.appID = appID

        if deviceID == nil || appID == nil {
            rootDir = nil
            outlineView.reloadData()
            return
        }

        showLoading()
        DispatchQueue.global().async {
            let lockdown = MDLockdown(udid: deviceID!)
            let houseArrest = MDHouseArrest(lockdown: lockdown, appID: appID!)
            let afcClient = MDAfcClient.fileClient(with: houseArrest)
            let rootDir = MDDeviceFile(afcClient: afcClient)
            rootDir.path = "."
            rootDir.isDirectory = true
            _ = rootDir.children

            DispatchQueue.main.async {
                self.afcClient = afcClient
                self.rootDir = rootDir
                self.outlineView.reloadData()
                self.restoreState()
                self.hideLoading()
            }
        }
    }

    private func performSearch(_ text: String) {
        guard let root = rootDir else {
            searchResults.removeAll()
            searchPathMap.removeAll()
            outlineView.reloadData()
            return
        }
        showLoading()
        let lowercased = text.lowercased()
        DispatchQueue.global().async {
            var results: [MDDeviceFile] = []
            var pathMap: [MDDeviceFile: String] = [:]
            self.collectMatchingFiles(in: root, parentPath: "", searchText: lowercased, results: &results, pathMap: &pathMap)
            DispatchQueue.main.async {
                self.searchResults = results
                self.searchPathMap = pathMap
                self.outlineView.reloadData()
                self.hideLoading()
            }
        }
    }

    private func collectMatchingFiles(in dir: MDDeviceFile, parentPath: String, searchText: String, results: inout [MDDeviceFile], pathMap: inout [MDDeviceFile: String]) {
        guard let children = dir.children else { return }
        let currentPath = dir.path == "." ? "" : (parentPath.isEmpty ? dir.name : "\(parentPath)/\(dir.name)")
        for file in children {
            if file.lowercaseName.contains(searchText) {
                results.append(file)
                pathMap[file] = currentPath
            }
            if file.isDirectory {
                collectMatchingFiles(in: file, parentPath: currentPath, searchText: searchText, results: &results, pathMap: &pathMap)
            }
        }
    }

    @IBAction func didClickExportButton(_: NSButton) {
        exportSelectedFiles()
    }

    @IBAction func openFile(_: AnyObject?) {
        exportSelectedFiles()
    }

    private func exportSelectedFiles() {
        let selectedRows = outlineView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        var files: [MDDeviceFile] = []
        for row in selectedRows {
            if let file = outlineView.item(atRow: row) as? MDDeviceFile {
                files.append(file)
            }
        }
        guard !files.isEmpty else { return }

        if files.count == 1 {
            exportFile(atIndex: outlineView.selectedRow)
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.message = "选择导出目录"
        openPanel.beginSheetModal(for: view.window!) { [weak self] result in
            guard result == .OK, let self = self, let url = openPanel.url else { return }
            self.showLoading()
            DispatchQueue.global().async {
                for file in files {
                    let dest = url.appendingPathComponent(file.name)
                    file.copy(dest.path)
                }
                DispatchQueue.main.async {
                    self.hideLoading()
                }
            }
        }
    }

    @IBAction func didDoubleClickCell(_: AnyObject?) {
        let row = outlineView.clickedRow
        openFile(atIndex: row)
    }

    @IBAction func reloadFiles(_: AnyObject?) {
        saveState()
        let deviceID = self.deviceID
        let appID = self.appID
        self.deviceID = nil
        self.appID = nil
        searchText = ""
        searchResults.removeAll()
        searchPathMap.removeAll()
        reloadData(withDeviceID: deviceID, appID: appID)
    }

    private func saveState() {
        guard !isSearchMode, rootDir != nil else { return }

        var expanded: Set<String> = []
        for row in 0..<outlineView.numberOfRows {
            if let file = outlineView.item(atRow: row) as? MDDeviceFile,
               file.isDirectory,
               outlineView.isItemExpanded(file) {
                expanded.insert(file.path)
            }
        }
        savedExpandedPaths = expanded
        savedScrollPosition = outlineView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
        shouldRestoreState = !expanded.isEmpty
    }

    private func restoreState() {
        guard shouldRestoreState else { return }
        shouldRestoreState = false

        var didExpand = true
        while didExpand {
            didExpand = false
            for row in 0..<outlineView.numberOfRows {
                if let file = outlineView.item(atRow: row) as? MDDeviceFile,
                   file.isDirectory,
                   !outlineView.isItemExpanded(file),
                   savedExpandedPaths.contains(file.path) {
                    outlineView.expandItem(file)
                    didExpand = true
                }
            }
        }

        if let scrollView = outlineView.enclosingScrollView {
            let contentHeight = scrollView.contentView.bounds.height
            let documentHeight = scrollView.documentView?.bounds.height ?? 0
            let maxY = max(0, documentHeight - contentHeight)
            let restoredY = min(savedScrollPosition, maxY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: restoredY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    @IBAction func removeFile(_: AnyObject?) {
        let selectedRows = outlineView.selectedRowIndexes
        guard !selectedRows.isEmpty else { return }

        struct ItemInfo {
            let file: MDDeviceFile
            let parent: MDDeviceFile
            let indexInParent: Int
        }

        if isSearchMode {
            var items: [MDDeviceFile] = []
            for row in selectedRows {
                if let file = outlineView.item(atRow: row) as? MDDeviceFile {
                    items.append(file)
                }
            }
            guard !items.isEmpty else { return }

            showLoading()
            DispatchQueue.global().async {
                for item in items {
                    _ = item.remove()
                }
                DispatchQueue.main.async {
                    self.performSearch(self.searchText)
                    self.hideLoading()
                }
            }
            return
        }

        var items: [ItemInfo] = []
        for row in selectedRows {
            guard let file = outlineView.item(atRow: row) as? MDDeviceFile,
                  let parent = outlineView.parent(forItem: file) as? MDDeviceFile
            else { continue }
            items.append(ItemInfo(file: file, parent: parent, indexInParent: outlineView.childIndex(forItem: file)))
        }
        guard !items.isEmpty else { return }

        showLoading()
        DispatchQueue.global().async {
            for item in items {
                _ = item.parent.removeChild(item.file)
            }
            DispatchQueue.main.async {
                self.outlineView.reloadData()
                self.hideLoading()
            }
        }
    }

    @IBAction func didClickImportButton(_: NSButton) {
        importFiles()
    }

    private func importFiles() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true
        openPanel.beginSheetModal(for: view.window!) { [weak self] result in
            guard result == .OK, let self = self else { return }
            let urls = openPanel.urls
            guard !urls.isEmpty else { return }

            var targetDir: MDDeviceFile?
            let row = self.outlineView.selectedRow
            if row >= 0, let file = self.outlineView.item(atRow: row) as? MDDeviceFile {
                targetDir = file.isDirectory ? file : (self.outlineView.parent(forItem: file) as? MDDeviceFile)
            }
            if targetDir == nil {
                targetDir = self.rootDir
            }

            guard let dir = targetDir else { return }
            self.showLoading()
            DispatchQueue.global().async {
                for url in urls {
                    _ = dir.upload(fromLocalPath: url.path)
                }
                DispatchQueue.main.async {
                    self.hideLoading()
                    self.reloadFiles(nil)
                }
            }
        }
    }

    private func exportFile(atIndex index: Int) {
        guard index >= 0, let file = outlineView.item(atRow: index) as? MDDeviceFile else {
            return
        }

        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = file.name
        savePanel.beginSheetModal(for: view.window!) { [weak savePanel] result in
            guard result == .OK, let url = savePanel?.url else {
                return
            }
            var name = savePanel?.nameFieldStringValue ?? ""
            if name.isEmpty {
                name = file.name
            }
            let dest = URL(fileURLWithPath: name, relativeTo: url)
            self.exportFile(file, toURL: dest)
        }
    }

    private func exportFile(_ file: MDDeviceFile, toURL url: URL) {
        // self.exportIndicator.startAnimation(nil)
        // self.exportIndicator.isHidden = false
        // self.exportButton.isEnabled = false
        DispatchQueue.global().async {
            file.copy(url.path)
            /*
             DispatchQueue.main.async {
                 self.exportIndicator.stopAnimation(nil)
                 self.exportIndicator.isHidden = true
                 self.exportButton.isEnabled = true
             }
              */
        }
    }

    private func openFile(atIndex index: Int) {
        guard index >= 0, let file = outlineView.item(atRow: index) as? MDDeviceFile else {
            return
        }
        if file.isDirectory {
            exportFile(atIndex: index)
            return
        }
        showLoading()
        DispatchQueue.global().async {
            guard let udid = self.deviceID else {
                self.hideLoading()
                return
            }

            let path = FileManager.default.localCrashDirectory(udid) + "/\(file.name)"
            let url = URL(fileURLWithPath: path)
            file.copy(url.path)
            DispatchQueue.main.async {
                self.hideLoading()
                NSWorkspace.shared.open(url)
            }
        }
    }
}

extension FileBrowserViewController: NSOutlineViewDelegate, NSOutlineViewDataSource {
    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if isSearchMode {
            return item == nil ? searchResults.count : 0
        }

        if let file = item as? MDDeviceFile, file.isDirectory, let children = file.children {
            return children.count
        }

        return rootDir?.children?.count ?? 0
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if isSearchMode {
            return searchResults[index]
        }

        if let file = item as? MDDeviceFile, file.isDirectory, let children = file.children {
            return children[index]
        }

        return rootDir!.children![index]
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if isSearchMode {
            return false
        }

        if let file = item as? MDDeviceFile, file.isDirectory, let children = file.children {
            return children.count > 0
        }

        return false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        guard let file = item as? MDDeviceFile else {
            return view
        }

        view = outlineView.makeView(withIdentifier: tableColumn!.identifier, owner: nil) as? NSTableCellView
        if tableColumn == outlineView.tableColumns[0] {
            view?.textField?.stringValue = file.name
            if file.isDirectory {
                view?.imageView?.image = NSImage(named: NSImage.folderName as NSImage.Name)
            } else {
                view?.imageView?.image = NSWorkspace.shared.icon(forFileType: file.extension)
            }
        } else if tableColumn == outlineView.tableColumns[1] {
            view?.textField?.stringValue = file.date.formattedString
        } else if outlineView.tableColumns.count > 3, tableColumn == outlineView.tableColumns[3] {
            if isSearchMode {
                view?.textField?.stringValue = searchPathMap[file] ?? ""
            } else {
                view?.textField?.stringValue = ""
            }
        } else {
            view?.textField?.stringValue = "\(file.size.readableSize)"
        }

        return view
    }

    func outlineViewSelectionDidChange(_: Notification) {}
}
